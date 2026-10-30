import 'dart:async';
import 'dart:io';

import 'filter_plan.dart';
import 'models.dart';
import 'router_client.dart';
import 'secure_store.dart';

/// Adds addresses that an active filter lists but the router has no entry for,
/// so a manually added device can still be seen and removed.
List<Host> withListedHosts(List<Host> hosts, List<WlanFilter> filters) {
  final known = {for (final host in hosts) host.mac};
  return [
    ...hosts,
    for (final filter in filters)
      if (filter.enabled)
        for (final mac in filter.macs)
          if (known.add(mac)) Host.listed(mac, filter.name),
  ];
}

class RouterSnapshot {
  const RouterSnapshot({
    required this.hosts,
    required this.filters,
    required this.traffic,
    required this.selfMac,
  });

  final List<Host> hosts;
  final List<WlanFilter> filters;
  final Traffic? traffic;
  final String? selfMac;

  WlanFilter? get mainFilter => filters.firstOrNull;

  WlanFilter? filterFor(Host host) {
    for (final filter in filters) {
      if (filter.name == host.interface) {
        return filter;
      }
    }
    return null;
  }

  bool isBlocked(Host host) => filterFor(host)?.blocks(host.mac) ?? false;
}

class RouterRepository {
  RouterRepository({RouterClient? client, this.store = const SecureStore()})
    : _client = client ?? RouterClient();

  final RouterClient _client;
  final SecureStore store;
  Credentials? _credentials;

  // ntwk/*_host, app/qosclass_host and ntwk/wlanpin hang the router's web
  // server and drop the session. Never call them.

  Future<void> login(Credentials credentials, {required bool remember}) async {
    await _client.login(credentials.username, credentials.password);
    _credentials = credentials;
    if (remember) {
      await store.saveCredentials(credentials);
    } else {
      await store.clearCredentials();
    }
  }

  Future<void> logout() async {
    final credentials = _credentials;
    _credentials = null;
    await store.clearCredentials();
    if (credentials != null) {
      try {
        await _client.logout();
      } on Exception {
        // The session expires by itself on the router.
      }
    }
  }

  Future<RouterSnapshot> load() => _read(() async {
    final hostsJson = await _client.get('system/HostInfo') as List;
    final filters = await _readFilters();
    final hosts = withListedHosts([
      for (final item in hostsJson) Host.fromJson(item as Map<String, dynamic>),
    ], filters);
    final wifi = await _client.get('ntwk/wifi_info');
    return RouterSnapshot(
      hosts: hosts,
      filters: filters,
      traffic: _parseTraffic(wifi),
      selfMac: await _findSelfMac(hosts),
    );
  });

  /// Sends the new filter, then re-reads it from the router. Wi-Fi may restart
  /// while the change applies, so connection errors are expected here.
  Future<void> applyFilter(WlanFilter current, FilterPlan plan) async {
    if (plan.next == current) {
      return;
    }
    if (plan.replacesStoredList) {
      await store.backupFilterOnce(current);
    }
    try {
      await _withSession(
        () => _client.post('ntwk/wlanfilterone', plan.next.toSubmitJson()),
      );
    } on RouterException {
      rethrow;
    } on Exception {
      // Handled by the verification below.
    }
    await _waitForEffect();
    await _verify(plan.next);
  }

  Future<void> renameHost(Host host, String name) => _withSession(
    () => _client.post(
      'system/HostInfo',
      host.toRenameJson(name),
      action: 'update',
    ),
  );

  Future<void> forgetHost(Host host) => _withSession(
    () =>
        _client.post('system/HostInfo', host.toForgetJson(), action: 'delete'),
  );

  Future<List<UrlRule>> loadUrlRules() => _read(() async {
    final json = await _client.get('ntwk/urlfilter') as List;
    return [
      for (final item in json) UrlRule.fromJson(item as Map<String, dynamic>),
    ];
  });

  Future<void> addUrlRule(String domain) => _withSession(
    () => _client.post('ntwk/urlfilter', {
      'ID': '',
      'URL': domain,
      'Status': 2,
      'Devices': <String>[],
      'DevManual': false,
    }, action: 'create'),
  );

  Future<void> deleteUrlRule(UrlRule rule) => _withSession(
    () => _client.post('ntwk/urlfilter', {'ID': rule.id}, action: 'delete'),
  );

  void close() => _client.close();

  Future<List<WlanFilter>> _readFilters() async {
    final json = await _client.get('ntwk/wlanfilterone') as List;
    return [
      for (final item in json)
        WlanFilter.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<void> _waitForEffect() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        final result = await _client.get('ntwk/wlaneffect');
        if (result is Map && result['haseffective'] == true) {
          return;
        }
      } on Exception {
        // Not reachable yet while Wi-Fi restarts.
      }
    }
  }

  Future<void> _verify(WlanFilter expected) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        final filters = await _withSession(_readFilters);
        final actual = filters.where((f) => f.id == expected.id).firstOrNull;
        if (actual != null &&
            actual.enabled == expected.enabled &&
            actual.policy == expected.policy &&
            actual.macs.toSet().containsAll(expected.macs) &&
            expected.macs.toSet().containsAll(actual.macs)) {
          return;
        }
        throw const RouterException('الراوتر ما طبقش التغيير');
      } on RouterException {
        rethrow;
      } on Exception {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
    throw const RouterException(
      'مش قادر أتأكد من التغيير، تأكد إنك متصل بالراوتر وحدث القائمة',
    );
  }

  /// For reads only: safe to send twice after a dropped connection.
  Future<T> _read<T>(Future<T> Function() action) async {
    try {
      return await _withSession(action);
    } on RouterException {
      rethrow;
    } on Exception {
      await Future<void>.delayed(const Duration(seconds: 1));
      return _withSession(action);
    }
  }

  Future<T> _withSession<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on SessionExpiredException {
      final credentials = _credentials;
      if (credentials == null) {
        rethrow;
      }
      await _client.login(credentials.username, credentials.password);
      return action();
    }
  }

  Traffic? _parseTraffic(dynamic json) {
    if (json is! List || json.isEmpty) {
      return null;
    }
    var downloaded = 0;
    var uploaded = 0;
    for (final item in json) {
      downloaded += (item['sendbytes'] as num?)?.toInt() ?? 0;
      uploaded += (item['receivebytes'] as num?)?.toInt() ?? 0;
    }
    return Traffic(downloaded: downloaded, uploaded: uploaded);
  }

  Future<String?> _findSelfMac(List<Host> hosts) async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final addresses = {
      for (final interface in interfaces)
        for (final address in interface.addresses) address.address,
    };
    for (final host in hosts) {
      if (host.active && addresses.contains(host.ip)) {
        return host.mac;
      }
    }
    return null;
  }
}
