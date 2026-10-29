import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/user.dart';
import '../services/api.dart';
import '../core/format.dart';
import '../core/navigation.dart';

class Session extends ChangeNotifier {
  final ApiClient api;
  final FlutterSecureStorage storage;
  AppUser? user;
  bool loading = true;
  String? bootError;
  String? refreshToken;
  Future<bool>? _refreshing;
  int _generation = 0;
  Session({ApiClient? api, FlutterSecureStorage? storage})
    : api = api ?? ApiClient(),
      storage = storage ?? const FlutterSecureStorage() {
    this.api.onExpired = expire;
    this.api.onRefresh = refresh;
  }
  Future<void> initialize() async {
    loading = true;
    bootError = null;
    notifyListeners();
    try {
      const buildUrl = String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: ApiClient.sharedBaseUrl,
      );
      final saved = await storage.read(key: 'api_url');
      if ((saved ?? buildUrl).isNotEmpty) {
        api.baseUrl = ApiClient.validateUrl(saved ?? buildUrl);
      }
      api.token = await storage.read(key: 'access_token');
      refreshToken = await storage.read(key: 'refresh_token');
      if (api.token != null && api.baseUrl.isNotEmpty) {
        user = AppUser(await api.get(api.isShared ? '/me' : '/auth/me'));
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
    notifyListeners();
  }

  Future<void> accept(Json result) async {
    final value = result['accessToken'] as String;
    if (api.isShared) {
      refreshToken = result['refreshToken'] as String;
      await storage.write(key: 'refresh_token', value: refreshToken);
    }
    await storage.write(key: 'access_token', value: value);
    api.token = value;
    user = AppUser(Map<String, dynamic>.from(result['user'] as Map));
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
      if (generation != _generation) return false;
      await accept(result);
      return true;
    } catch (_) {
      if (generation == _generation) expire();
      return false;
    }
  }

  Future<void> reloadUser() async {
    user = AppUser(await api.get(api.isShared ? '/me' : '/auth/me'));
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
    // Protected pages may sit above AppGate in the navigator stack.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    });
    notifyListeners();
  }

  Future<void> logout() async {
    // Keep logout retryable if server revocation fails.
    await api.post(
      '/auth/logout',
      api.isShared ? {'refreshToken': refreshToken} : {},
    );
    expire();
  }
}
