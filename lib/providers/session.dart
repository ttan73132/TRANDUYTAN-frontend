import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../models/user.dart';
import '../services/api.dart';
import '../core/format.dart';
import '../core/navigation.dart';
import '../services/biometrics.dart';
import 'preferences.dart';

class Session extends ChangeNotifier {
  final ApiClient api;
  final FlutterSecureStorage storage;
  final DeviceBiometrics biometrics;
  late final AppPreferences preferences = AppPreferences(storage);
  bool biometricEnabled = false;
  Json? rememberedAccount;
  bool _unlocking = false;
  AppUser? user;
  bool loading = true;
  String? bootError;
  String? refreshToken;
  Future<bool>? _refreshing;
  int _generation = 0;
  Session({
    ApiClient? api,
    FlutterSecureStorage? storage,
    DeviceBiometrics? biometrics,
  }) : api = api ?? ApiClient(),
       storage = storage ?? const FlutterSecureStorage(),
       biometrics = biometrics ?? DeviceBiometrics() {
    this.api.onExpired = expire;
    this.api.onRefresh = refresh;
  }
  Future<void> initialize() async {
    loading = true;
    bootError = null;
    notifyListeners();
    try {
      await preferences.load();
      const buildUrl = String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: ApiClient.sharedBaseUrl,
      );
      final saved = await storage.read(key: 'api_url');
      if ((saved ?? buildUrl).isNotEmpty) {
        api.baseUrl = ApiClient.validateUrl(saved ?? buildUrl);
      }
      final remembered = await storage.read(key: 'biometric_account_v1');
      if (remembered != null) {
        try {
          final account = Map<String, dynamic>.from(
            jsonDecode(remembered) as Map,
          );
          if (account['origin'] == api.baseUrl &&
              account['id'] is String &&
              account['username'] is String &&
              api.isShared) {
            rememberedAccount = account;
            final namespace = account['vault'] as String?;
            if (namespace != null &&
                RegExp(r'^quick_login_[a-zA-Z0-9_-]+$').hasMatch(namespace)) {
              biometrics.useNamespace(namespace);
            }
            biometricEnabled = true;
          }
        } on FormatException {
          await storage.delete(key: 'biometric_account_v1');
        } on TypeError {
          await storage.delete(key: 'biometric_account_v1');
        }
      }
      if (biometricEnabled) {
        api.token = null;
        refreshToken = null;
        user = null;
        loading = false;
        notifyListeners();
        return;
      }
      api.token = await storage.read(key: 'access_token');
      refreshToken = await storage.read(key: 'refresh_token');
      if (api.token != null && api.baseUrl.isNotEmpty) {
        user = AppUser(await api.get(api.isShared ? '/me' : '/auth/me'));
        await preferences.loadProfile(api.baseUrl, user!.id);
      }
    } catch (e) {
      if (api.token != null) bootError = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> configure(String value) async {
    if (api.token != null) {
      throw const ApiException('Đăng xuất trước khi đổi máy chủ.');
    }
    final url = ApiClient.validateUrl(value);
    final previous = api.baseUrl;
    api.baseUrl = url;
    try {
      await api.get('/health');
      await storage.write(key: 'api_url', value: url);
    } catch (_) {
      api.baseUrl = previous;
      rethrow;
    }
    if (previous != url) await disableBiometrics();
    notifyListeners();
  }

  Future<void> accept(Json result, {bool freshLogin = false}) async {
    final generation = _generation;
    final value = result['accessToken'] as String;
    final nextUser = AppUser(Map<String, dynamic>.from(result['user'] as Map));
    final nextRefresh = api.isShared ? result['refreshToken'] as String : null;
    if (freshLogin && biometricEnabled) {
      await storage.delete(key: 'biometric_account_v1');
      biometricEnabled = false;
      rememberedAccount = null;
      await biometrics.clear().catchError((_) {});
    }
    if (biometricEnabled && nextUser.id != rememberedAccount?['id']) {
      await disableBiometrics();
    }
    if (api.isShared) {
      if (biometricEnabled) {
        await biometrics.save(nextRefresh!);
      } else {
        await storage.write(key: 'refresh_token', value: nextRefresh);
      }
    }
    if (!biometricEnabled) {
      await storage.write(key: 'access_token', value: value);
    }
    if (generation != _generation) return;
    refreshToken = nextRefresh;
    api.token = value;
    user = nextUser;
    await preferences.loadProfile(api.baseUrl, nextUser.id);
    if (generation != _generation) {
      preferences.profile = {};
      return;
    }
    bootError = null;
    notifyListeners();
  }

  Future<bool> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<bool> _refresh() async {
    final generation = _generation;
    final current = refreshToken;
    if (current == null) return false;
    try {
      final result = await api.post('/auth/refresh', {'refreshToken': current});
      if (generation != _generation) {
        // Locking must retain a token already rotated by the server, without
        // restoring protected screens. Logout clears the biometric marker.
        if (biometricEnabled &&
            (result['user'] as Map)['id'] == rememberedAccount?['id']) {
          await biometrics.save(result['refreshToken'] as String);
        }
        return false;
      }
      await accept(result);
      return generation == _generation && user != null;
    } catch (_) {
      if (generation == _generation) expire();
      return false;
    }
  }

  Future<void> reloadUser() async {
    final generation = _generation;
    final result = await api.get(api.isShared ? '/me' : '/auth/me');
    if (generation != _generation) return;
    user = AppUser(result);
    notifyListeners();
  }

  void expire() {
    _generation++;
    api.token = null;
    user = null;
    bootError = null;
    storage.delete(key: 'access_token');
    refreshToken = null;
    storage.delete(key: 'refresh_token');
    biometricEnabled = false;
    rememberedAccount = null;
    preferences.profile = {};
    storage.delete(key: 'biometric_account_v1');
    biometrics.clear().catchError((_) {});
    // Protected pages may sit above AppGate in the navigator stack.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    });
    notifyListeners();
  }

  Future<void> logout() async {
    await _refreshing;
    if (api.token == null) {
      expire();
      return;
    }
    // Keep logout retryable if server revocation fails.
    await api.post(
      '/auth/logout',
      api.isShared ? {'refreshToken': refreshToken} : {},
    );
    expire();
  }

  String get profileName => preferences.profile['fullName']?.isNotEmpty == true
      ? preferences.profile['fullName']!
      : user?.fullName ?? '';

  Future<void> setAppearance(double scale, int background) async {
    await preferences.appearance(scale, background);
    notifyListeners();
  }

  Future<void> updateLocalProfile(Map<String, String> values) async {
    final current = user;
    if (current == null) {
      throw const ApiException('Đăng nhập để cập nhật hồ sơ.');
    }
    await preferences.saveProfile(api.baseUrl, current.id, values);
    notifyListeners();
  }

  Future<void> enableBiometrics() async {
    await _refreshing;
    if (!api.isShared || user == null || refreshToken == null) {
      throw const ApiException(
        'Đăng nhập bằng mật khẩu và OTP trước khi bật sinh trắc học.',
      );
    }
    if (!await biometrics.available()) {
      throw const ApiException(
        'Chưa có sinh trắc học đủ điều kiện. Vào Cài đặt điện thoại để đăng ký vân tay hoặc khuôn mặt được Android hỗ trợ.',
      );
    }
    final namespace = 'quick_login_${const Uuid().v4()}';
    biometrics.useNamespace(namespace);
    await biometrics.save(refreshToken!);
    final account = <String, dynamic>{
      'id': user!.id,
      'username': user!.values['username'],
      'origin': api.baseUrl,
      'vault': namespace,
    };
    await storage.write(
      key: 'biometric_account_v1',
      value: jsonEncode(account),
    );
    biometricEnabled = true;
    rememberedAccount = account;
    // No second, unprotected copy may bypass the biometric vault on restart.
    await storage.delete(key: 'refresh_token');
    await storage.delete(key: 'access_token');
    notifyListeners();
  }

  Future<void> disableBiometrics() async {
    if (user != null && api.token != null) {
      await storage.write(key: 'access_token', value: api.token);
      if (refreshToken != null) {
        await storage.write(key: 'refresh_token', value: refreshToken);
      }
    }
    await storage.delete(key: 'biometric_account_v1');
    await biometrics.clear();
    biometricEnabled = false;
    rememberedAccount = null;
    notifyListeners();
  }

  Future<void> biometricLogin() async {
    if (_unlocking || !biometricEnabled) return;
    _unlocking = true;
    final generation = _generation;
    try {
      await _refreshing;
      final token = await biometrics.unlock();
      if (generation != _generation) return;
      if (token == null) {
        throw const ApiException(
          'Phiên đã mất. Đăng nhập lại bằng mật khẩu và OTP.',
        );
      }
      final result = await api.post('/auth/refresh', {'refreshToken': token});
      if (generation != _generation) return;
      if ((result['user'] as Map)['id'] != rememberedAccount?['id']) {
        throw const ApiException('Phiên không khớp tài khoản đã lưu.');
      }
      await accept(result);
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) expire();
      rethrow;
    } finally {
      _unlocking = false;
    }
  }

  void lock() {
    if (!biometricEnabled || user == null) return;
    _generation++;
    api.token = null;
    refreshToken = null;
    user = null;
    preferences.profile = {};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    });
    notifyListeners();
  }
}
