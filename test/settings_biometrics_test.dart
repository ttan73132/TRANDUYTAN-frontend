import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:tranduytan/main.dart';
import 'package:tranduytan/models/user.dart';
import 'package:tranduytan/providers/preferences.dart';
import 'package:tranduytan/providers/session.dart';
import 'package:tranduytan/screens/settings.dart';
import 'package:tranduytan/services/api.dart';
import 'package:tranduytan/services/biometrics.dart';

const account = <String, dynamic>{
  'id': 'user-1',
  'fullName': 'Trần Duy Tân',
  'username': 'tantest',
  'email': 'tan@example.test',
  'role': 'employee',
  'status': 'pending',
  'emailVerified': true,
};
Map<String, dynamic> tokens(
  String suffix, [
  Map<String, dynamic> user = account,
]) => {
  'accessToken': 'access-$suffix',
  'refreshToken': 'refresh-$suffix',
  'user': user,
};
http.Response response(dynamic data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class FakeBiometrics extends DeviceBiometrics {
  final Map<String, String> secrets = {};
  String namespace = 'quick_login_v1';
  bool supported = true, canceled = false;
  int unlocks = 0;
  @override
  Future<bool> available() async => supported;
  @override
  void useNamespace(String value) {
    namespace = value;
  }

  @override
  Future<void> save(String token) async {
    secrets[namespace] = token;
  }

  @override
  Future<String?> unlock() async {
    unlocks++;
    if (canceled) throw const ApiException('Canceled');
    return secrets[namespace];
  }

  @override
  Future<void> clear() async {
    secrets.remove(namespace);
  }

  String? get token => secrets[namespace];
}

Session session(
  FakeBiometrics biometrics,
  Future<http.Response> Function(http.Request) handle,
) => Session(
  api: ApiClient(client: MockClient(handle))..baseUrl = ApiClient.sharedBaseUrl,
  biometrics: biometrics,
)..loading = false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'appearance persists, validates damaged settings and bounds font size',
    () async {
      const storage = FlutterSecureStorage();
      final preferences = AppPreferences(storage);
      await preferences.appearance(1.4, 3);
      final reopened = AppPreferences(storage);
      await reopened.load();
      expect(reopened.textScale, 1.4);
      expect(reopened.backgroundIndex, 3);
      await reopened.appearance(double.nan, 999);
      expect(reopened.textScale, 1);
      expect(reopened.backgroundIndex, backgroundChoices.length - 1);
      await storage.write(key: 'appearance_v1', value: '{broken');
      await AppPreferences(storage).load();
      await storage.write(key: 'appearance_v1', value: '{"textScale":"large"}');
      await AppPreferences(storage).load();
    },
  );

  test(
    'local profile isolates account and server and cannot change account role',
    () async {
      const storage = FlutterSecureStorage();
      final preferences = AppPreferences(storage);
      await preferences.saveProfile(ApiClient.sharedBaseUrl, 'user-1', {
        'fullName': '  Tân  ',
        'phone': '0901234567',
        'role': 'admin',
      });
      expect(preferences.profile, {'fullName': 'Tân', 'phone': '0901234567'});
      await preferences.loadProfile(ApiClient.sharedBaseUrl, 'user-2');
      expect(preferences.profile, isEmpty);
      await preferences.loadProfile('https://another.test/v1', 'user-1');
      expect(preferences.profile, isEmpty);
      final reopened = AppPreferences(storage);
      await reopened.loadProfile(ApiClient.sharedBaseUrl, 'user-1');
      expect(reopened.profile['fullName'], 'Tân');
    },
  );

  test(
    'enable requires verified session and enrolled strong biometrics',
    () async {
      final device = FakeBiometrics();
      final s = session(device, (_) async => response({}));
      await expectLater(s.enableBiometrics(), throwsA(isA<ApiException>()));
      await s.accept(tokens('otp'));
      device.supported = false;
      await expectLater(s.enableBiometrics(), throwsA(isA<ApiException>()));
      expect(s.biometricEnabled, false);
      expect(await s.storage.read(key: 'refresh_token'), 'refresh-otp');
    },
  );

  test(
    'enrollment removes ordinary tokens; cold start cannot bypass vault',
    () async {
      final device = FakeBiometrics();
      var requests = 0;
      final s = session(device, (_) async {
        requests++;
        return response(account);
      });
      await s.accept(tokens('otp'));
      await s.enableBiometrics();
      expect(await s.storage.read(key: 'access_token'), isNull);
      expect(await s.storage.read(key: 'refresh_token'), isNull);
      expect(device.token, 'refresh-otp');
      final restarted = session(device, (_) async {
        requests++;
        return response(account);
      });
      await restarted.initialize();
      expect(restarted.biometricEnabled, true);
      expect(restarted.user, isNull);
      expect(restarted.api.token, isNull);
      expect(restarted.refreshToken, isNull);
      expect(requests, 0);
    },
  );

  test(
    'cancel never contacts server; successful biometric login rotates secret',
    () async {
      final device = FakeBiometrics();
      var requests = 0;
      final s = session(device, (request) async {
        requests++;
        expect(request.url.path, '/v1/auth/refresh');
        expect(jsonDecode(request.body)['refreshToken'], 'refresh-otp');
        return response(tokens('rotated'));
      });
      await s.accept(tokens('otp'));
      await s.enableBiometrics();
      s.lock();
      device.canceled = true;
      await expectLater(s.biometricLogin(), throwsA(isA<ApiException>()));
      expect(requests, 0);
      expect(s.user, isNull);
      device.canceled = false;
      await s.biometricLogin();
      expect(s.user?.id, 'user-1');
      expect(device.token, 'refresh-rotated');
      expect(await s.storage.read(key: 'refresh_token'), isNull);
      expect(device.unlocks, 2);
    },
  );

  test(
    'server revocation clears quick login and does not restore account',
    () async {
      final device = FakeBiometrics();
      final s = session(
        device,
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 'REVOKED', 'message': 'Expired'},
          }),
          401,
        ),
      );
      await s.accept(tokens('otp'));
      await s.enableBiometrics();
      s.lock();
      await expectLater(s.biometricLogin(), throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);
      expect(s.user, isNull);
      expect(s.biometricEnabled, false);
      expect(device.token, isNull);
      expect(await s.storage.read(key: 'biometric_account_v1'), isNull);
    },
  );

  test(
    'locking during refresh preserves rotated token without opening account',
    () async {
      final device = FakeBiometrics();
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      final s = session(device, (_) {
        started.complete();
        return pending.future;
      });
      await s.accept(tokens('otp'));
      await s.enableBiometrics();
      final refreshing = s.refresh();
      await started.future;
      s.lock();
      pending.complete(response(tokens('rotated')));
      expect(await refreshing, false);
      expect(device.token, 'refresh-rotated');
      expect(s.user, isNull);
      expect(s.api.token, isNull);
    },
  );

  test('late profile reload cannot reopen locked session', () async {
    final device = FakeBiometrics();
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final s = session(device, (_) {
      started.complete();
      return pending.future;
    });
    await s.accept(tokens('otp'));
    await s.enableBiometrics();
    final reload = s.reloadUser();
    await started.future;
    s.lock();
    pending.complete(response(account));
    await reload;
    expect(s.user, isNull);
  });

  test(
    'logout revokes server session and removes remembered device login',
    () async {
      final device = FakeBiometrics();
      final s = session(device, (request) async {
        expect(request.url.path, '/v1/auth/logout');
        expect(jsonDecode(request.body)['refreshToken'], 'refresh-otp');
        return response({'loggedOut': true});
      });
      await s.accept(tokens('otp'));
      await s.enableBiometrics();
      await s.logout();
      await Future<void>.delayed(Duration.zero);
      expect(s.biometricEnabled, false);
      expect(s.user, isNull);
      expect(device.token, isNull);
    },
  );

  test('OTP fallback can change account without retaining old profile or quick login', () async {
    final device = FakeBiometrics();
    final s = session(device, (_) async => response({}));
    await s.accept(tokens('first'));
    await s.updateLocalProfile({'fullName': 'Local Name'});
    await s.enableBiometrics();
    s.lock();
    await s.accept(
      tokens('second', {...account, 'id': 'user-2'}),
      freshLogin: true,
    );
    expect(s.user?.id, 'user-2');
    expect(s.profileName, account['fullName']);
    expect(s.preferences.profile, isEmpty);
    expect(s.biometricEnabled, false);
    expect(await s.storage.read(key: 'refresh_token'), 'refresh-second');
  });

  test(
    'cached vault always requests fresh strong authentication after locking',
    () async {
      var prompts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DeviceBiometrics.channel, (call) async {
            if (call.method == 'available') return true;
            expect(call.method, 'authenticateStrong');
            prompts++;
            return prompts > 1;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(DeviceBiometrics.channel, null),
      );
      final device = DeviceBiometrics(vault: const FlutterSecureStorage());
      await device.save('secret');
      await expectLater(device.unlock(), throwsA(isA<ApiException>()));
      expect(await device.unlock(), 'secret');
      expect(prompts, 2);
    },
  );

  testWidgets(
    'settings and editable profile fit narrow screen at 140% font size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = session(FakeBiometrics(), (_) async => response(account))
        ..user = AppUser({...account});
      await s.setAppearance(1.4, 0);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(value: s, child: const TranduytanApp()),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Cài đặt và hồ sơ cá nhân'),
        180,
      );
      await tester.ensureVisible(find.text('Cài đặt và hồ sơ cá nhân'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cài đặt và hồ sơ cá nhân'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Cát ấm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cát ấm'));
      await tester.pumpAndSettle();
      expect(s.preferences.backgroundIndex, 3);
      await tester.scrollUntilVisible(find.text('Cập nhật hồ sơ cá nhân'), 180);
      await tester.ensureVisible(find.text('Cập nhật hồ sơ cá nhân'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cập nhật hồ sơ cá nhân'));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      final nameField = find.byKey(const ValueKey('profile-fullName'));
      final phoneField = find.byKey(const ValueKey('profile-phone'));
      await tester.scrollUntilVisible(
        nameField,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(nameField, 'Tân cập nhật');
      await tester.scrollUntilVisible(
        phoneField,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(phoneField, '0901234567');
      await tester.scrollUntilVisible(
        find.text('Lưu hồ sơ trên thiết bị'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Lưu hồ sơ trên thiết bị'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu hồ sơ trên thiết bị'));
      await tester.pumpAndSettle();
      expect(s.profileName, 'Tân cập nhật');
      expect(s.preferences.profile['phone'], '0901234567');
      expect(s.user?.values['email'], account['email']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
