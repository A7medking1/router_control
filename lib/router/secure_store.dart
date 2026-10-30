import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

class Credentials {
  const Credentials(this.username, this.password);

  final String username;
  final String password;
}

class SecureStore {
  const SecureStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const _usernameKey = 'router_username';
  static const _passwordKey = 'router_password';
  static const _backupPrefix = 'filter_backup_';

  Future<Credentials?> readCredentials() async {
    final username = await _storage.read(key: _usernameKey);
    final password = await _storage.read(key: _passwordKey);
    if (username == null || password == null) {
      return null;
    }
    return Credentials(username, password);
  }

  Future<void> saveCredentials(Credentials credentials) async {
    await _storage.write(key: _usernameKey, value: credentials.username);
    await _storage.write(key: _passwordKey, value: credentials.password);
  }

  Future<void> clearCredentials() async {
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _passwordKey);
  }

  /// Keeps the first list seen for an SSID, so later writes never overwrite
  /// the original copy.
  Future<void> backupFilterOnce(WlanFilter filter) async {
    final key = '$_backupPrefix${filter.name}';
    if (await _storage.read(key: key) == null) {
      await _storage.write(key: key, value: jsonEncode(filter.toBackupJson()));
    }
  }
}
