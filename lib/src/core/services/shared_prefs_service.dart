import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPrefsService {
  SharedPrefsService._();

  static final SharedPrefsService _instance = SharedPrefsService._();
  static SharedPrefsService get instance => _instance;

  SharedPreferences? _prefs;
  static const _secure = MethodChannel('steadylink/credentials');
  final Map<String, Object?> _credentials = {};
  bool _secureReady = false;
  bool _secureRequired = false;
  Future<void> _writeTail = Future<void>.value();
  bool _sensitive(String key) =>
      key == 'paired_devices' ||
      key.startsWith('wristbox.account.') ||
      key.startsWith('mi.account.') ||
      key.startsWith('mi_account.');

  /// Load before constructing the device manager, which reads synchronously.
  /// No plaintext fallback is used if the platform keystore is unavailable.
  Future<void> initializeSecureStorage() async {
    _secureRequired = true;
    _secureReady = false;
    _credentials.clear();
    final raw = await _secure.invokeMethod<String>('read');
    _credentials.addAll(
      (jsonDecode(raw ?? '{}') as Map).cast<String, Object?>(),
    );
    _secureReady = true;
  }

  Future<bool> _saveCredential(String key, Object? value) async {
    if (!_secureReady) throw StateError('安全凭据存储尚未初始化');
    final next = _writeTail.then((_) async {
      final updated = Map<String, Object?>.of(_credentials);
      if (value == null) {
        updated.remove(key);
      } else {
        updated[key] = value;
      }
      await _secure.invokeMethod<void>('write', jsonEncode(updated));
      _credentials
        ..clear()
        ..addAll(updated);
    });
    _writeTail = next.catchError((Object _) {});
    await next;
    return true;
  }

  bool get isInitialized => _prefs != null;
  bool get isSecureStorageReady => _secureReady;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Refresh the in-memory cache from disk when another OronBox process may
  /// have changed preferences, such as the desktop daemon after OAuth.
  Future<void> reload() => _safePrefs.reload();

  SharedPreferences get _safePrefs {
    if (_prefs == null) {
      throw StateError(
        'SharedPrefsService not initialized. Call init() first.',
      );
    }
    return _prefs!;
  }

  String? getString(String key) => _secureRequired && _sensitive(key)
      ? _credentials[key] as String?
      : _safePrefs.getString(key);
  Future<bool> setString(String key, String value) =>
      _secureRequired && _sensitive(key)
      ? _saveCredential(key, value)
      : _safePrefs.setString(key, value);
  Future<bool> remove(String key) => _secureRequired && _sensitive(key)
      ? _saveCredential(key, null)
      : _safePrefs.remove(key);

  bool? getBool(String key) => _safePrefs.getBool(key);
  Future<bool> setBool(String key, bool value) =>
      _safePrefs.setBool(key, value);

  int? getInt(String key) => _safePrefs.getInt(key);
  Future<bool> setInt(String key, int value) => _safePrefs.setInt(key, value);

  double? getDouble(String key) => _safePrefs.getDouble(key);
  Future<bool> setDouble(String key, double value) =>
      _safePrefs.setDouble(key, value);

  List<String>? getStringList(String key) => _secureRequired && _sensitive(key)
      ? (_credentials[key] as List?)?.cast<String>()
      : _safePrefs.getStringList(key);
  Future<bool> setStringList(String key, List<String> value) =>
      _secureRequired && _sensitive(key)
      ? _saveCredential(key, value)
      : _safePrefs.setStringList(key, value);
}
