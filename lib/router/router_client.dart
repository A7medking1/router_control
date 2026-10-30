import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'password_cipher.dart';

class RouterException implements Exception {
  const RouterException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SessionExpiredException extends RouterException {
  const SessionExpiredException() : super('انتهت جلسة الراوتر');
}

class LoginFailedException extends RouterException {
  const LoginFailedException(super.message);
}

/// Thin client for the DG8045 web API. The router handles requests one at a
/// time, so callers must await each request before sending the next one.
class RouterClient {
  RouterClient({this.host = '192.168.1.1'})
    : _http = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8)
        ..badCertificateCallback = ((_, certHost, _) => certHost == host);

  final String host;
  final HttpClient _http;
  final Map<String, String> _cookies = {};
  Map<String, String>? _csrf;

  static const _jsonType = 'application/json;charset=UTF-8';
  static const _timeout = Duration(seconds: 20);

  Future<void> login(String username, String password) async {
    _cookies.clear();
    final page = await _send('GET', '/');
    final meta = {
      for (final match in RegExp(
        r'<meta name="([a-z_]+)" content="([^"]*)"',
      ).allMatches(page.body))
        match.group(1)!: match.group(2)!,
    };
    final modulus = meta['n'];
    final exponent = meta['e'];
    final csrfParam = meta['csrf_param'];
    final csrfToken = meta['csrf_token'];
    if (modulus == null ||
        exponent == null ||
        csrfParam == null ||
        csrfToken == null) {
      throw const RouterException('صفحة الراوتر غير متوقعة');
    }
    _csrf = {'csrf_param': csrfParam, 'csrf_token': csrfToken};

    final data = {
      'UserName': username,
      'Password': encryptPassword(password, modulus, exponent),
    };
    const loginType = '$_jsonType;enp';
    var result = await _postRaw('system/user_login', data, loginType);
    if (result['errcode'] == 1) {
      // Stale CSRF token; the router's own page resends once.
      result = await _postRaw('system/user_login', data, loginType);
    }
    if (result['errorCategory'] != 'ok') {
      throw LoginFailedException(_loginError(result));
    }
  }

  Future<void> logout() async {
    await _postRaw('system/user_logout', null, _jsonType);
    _cookies.clear();
  }

  Future<dynamic> get(String endpoint) async {
    final response = await _send('GET', '/api/$endpoint');
    if (response.status != 200) {
      throw const SessionExpiredException();
    }
    try {
      return jsonDecode(unwrapResponse(response.body));
    } on FormatException {
      throw const SessionExpiredException();
    }
  }

  Future<void> post(
    String endpoint,
    Map<String, dynamic> data, {
    String? action,
  }) async {
    final result = await _postRaw(endpoint, data, _jsonType, action: action);
    final errcode = result['errcode'];
    if (errcode != null && errcode != 0) {
      throw RouterException('الراوتر رفض الطلب (كود $errcode)');
    }
  }

  void close() => _http.close(force: true);

  Future<Map<String, dynamic>> _postRaw(
    String endpoint,
    Map<String, dynamic>? data,
    String contentType, {
    String? action,
  }) async {
    final body = jsonEncode({'csrf': _csrf, 'action': ?action, 'data': ?data});
    final response = await _send(
      'POST',
      '/api/$endpoint',
      body: body,
      contentType: contentType,
    );
    if (response.status != 200) {
      throw const SessionExpiredException();
    }
    final decoded = jsonDecode(unwrapResponse(response.body));
    if (decoded is! Map<String, dynamic>) {
      throw const RouterException('رد غير متوقع من الراوتر');
    }
    final token = decoded['csrf_token'];
    final param = decoded['csrf_param'];
    if (token is String && param is String) {
      _csrf = {'csrf_param': param, 'csrf_token': token};
    }
    return decoded;
  }

  Future<_Response> _send(
    String method,
    String path, {
    String? body,
    String? contentType,
  }) async {
    final request = await _http
        .openUrl(method, Uri.https(host, path))
        .timeout(_timeout);
    request.followRedirects = false;
    // The router drops idle connections without saying so, and reusing one
    // fails the next request.
    request.persistentConnection = false;
    request.headers
      ..set(HttpHeaders.acceptEncodingHeader, 'identity')
      ..set(HttpHeaders.refererHeader, 'https://$host/');
    if (_cookies.isNotEmpty) {
      request.headers.set(
        HttpHeaders.cookieHeader,
        _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      );
    }
    if (body != null) {
      final bytes = utf8.encode(body);
      request.headers.set(HttpHeaders.contentTypeHeader, contentType!);
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close().timeout(_timeout);
    for (final cookie in response.headers[HttpHeaders.setCookieHeader] ?? []) {
      final pair = cookie.split(';').first;
      final separator = pair.indexOf('=');
      if (separator > 0) {
        _cookies[pair.substring(0, separator)] = pair.substring(separator + 1);
      }
    }
    final text = await response
        .transform(const Utf8Decoder(allowMalformed: true))
        .join()
        .timeout(_timeout);
    return _Response(response.statusCode, text);
  }

  String _loginError(Map<String, dynamic> result) {
    final category = '${result['errorCategory']}';
    if (category.contains('Three_time_err')) {
      return 'الدخول مقفول مؤقتًا، جرب بعد ${result['waitTime'] ?? 'شوية'}';
    }
    return 'اسم المستخدم أو كلمة المرور غير صحيحة';
  }
}

String unwrapResponse(String text) {
  const prefix = 'while(1); /*';
  var body = text.trim();
  if (body.startsWith(prefix)) {
    body = body.substring(prefix.length);
  }
  if (body.endsWith('*/')) {
    body = body.substring(0, body.length - 2);
  }
  return body;
}

class _Response {
  const _Response(this.status, this.body);

  final int status;
  final String body;
}
