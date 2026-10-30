import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

/// Tokens use an isolated, biometric-protected Android Keystore namespace.
class DeviceBiometrics {
  static const channel = MethodChannel('vn.nhom8.tranduytan/biometrics');
  FlutterSecureStorage vault;
  bool _opened = false;

  DeviceBiometrics({FlutterSecureStorage? vault})
    : vault = vault ?? _storage('quick_login_v1');

  static FlutterSecureStorage _storage(String namespace) =>
      FlutterSecureStorage(
        aOptions: AndroidOptions.biometric(
          storageNamespace: namespace,
          enforceBiometrics: true,
          biometricType: AndroidBiometricType.strongBiometricOnly,
          resetOnError: false,
          biometricPromptTitle: 'Mở khóa TRANDUYTAN',
          biometricPromptSubtitle:
              'Xác thực bằng vân tay hoặc khuôn mặt được thiết bị hỗ trợ',
          biometricPromptNegativeButton: 'Hủy',
        ),
      );

  void useNamespace(String namespace) {
    vault = _storage(namespace);
    _opened = false;
  }

  Future<bool> available() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await channel
              .invokeMethod<bool>('available')
              .timeout(const Duration(seconds: 3)) ==
          true;
    } catch (_) {
      return false;
    }
  }

  Future<void> save(String token) async {
    await vault.write(key: 'refresh_token', value: token);
    _opened = true;
  }

  Future<String?> unlock() async {
    // The plugin caches its unwrapped key in-process. Re-prompt on later locks.
    if (_opened &&
        await channel.invokeMethod<bool>('authenticateStrong') != true) {
      throw const ApiException('Đã hủy xác thực sinh trắc học.');
    }
    final token = await vault.read(key: 'refresh_token');
    _opened = token != null;
    return token;
  }

  Future<void> clear() async {
    await vault.delete(key: 'refresh_token');
    _opened = false;
  }
}
