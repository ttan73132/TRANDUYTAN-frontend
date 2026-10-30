import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tranduytan/providers/session.dart';
import 'package:tranduytan/services/api.dart';
import 'package:tranduytan/services/local_face.dart';

import 'settings_biometrics_test.dart' as fixtures;

List<double> vector(int index) => List.generate(128, (i) => i == index ? 1 : 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });
  test('face vectors reject NaN, zero norm and wrong dimensions', () {
    expect(() => normalizedFace([1, 2]), throwsFormatException);
    expect(() => normalizedFace(List.filled(128, 0)), throwsFormatException);
    expect(
      () => normalizedFace([...List.filled(127, 1), double.nan]),
      throwsFormatException,
    );
    expect(faceSimilarity(vector(0), vector(0)), closeTo(1, 1e-8));
    expect(faceSimilarity(vector(0), vector(1)), 0);
  });
  test('static face does not finish randomized motion challenge', () {
    final challenge = FaceChallenge(reference: vector(0), direction: -1);
    for (var i = 0; i < 10; i++) {
      expect(challenge.observe(vector(0), 0), isNull);
    }
    expect(challenge.stage, 1);
    expect(challenge.observe(vector(0), 18), isNull);
    expect(challenge.stage, 1);
    expect(challenge.observe(vector(0), -18), isNull);
    expect(challenge.observe(vector(0), 0), vector(0));
  });
  test('different person resets challenge and cannot unlock', () {
    final challenge = FaceChallenge(reference: vector(0), direction: 1);
    challenge.observe(vector(0), 0);
    expect(
      () => challenge.observe(vector(1), 18),
      throwsA(isA<ApiException>()),
    );
    expect(challenge.stage, 0);
  });
  test('face and fingerprint alternate using latest refresh token, never replay stale vault proof', () async {
    final device = fixtures.FakeBiometrics();
    var count = 0;
    final s = fixtures.session(device, (request) async {
      expect(request.url.path, '/v1/auth/refresh');
      final expected = count == 0 ? 'refresh-otp' : 'refresh-$count';
      expect(jsonDecode(request.body)['refreshToken'], expected);
      count++;
      return fixtures.response(fixtures.tokens('$count'));
    });
    await s.accept(fixtures.tokens('otp'));
    await s.enableBiometrics();
    await s.enableFace(vector(0));
    s.lock();
    await expectLater(s.faceLogin(vector(1)), throwsA(isA<ApiException>()));
    expect(count, 0);
    expect(s.user, isNull);
    await s.faceLogin(vector(0));
    expect(count, 1);
    expect(device.token, 'refresh-otp');
    s.lock();
    await s.biometricLogin();
    expect(count, 2);
    expect(await s.faceAccess.token(), 'refresh-2');
    await s.disableFace();
    expect(device.token, 'refresh-2');
    s.lock();
    await s.biometricLogin();
    expect(count, 3);
    expect(s.faceEnabled, false);
    expect(s.user?.id, fixtures.account['id']);
  });
  test('cold start with camera-only quick login remains locked', () async {
    var requests = 0;
    final device = fixtures.FakeBiometrics();
    final s = fixtures.session(device, (_) async {
      requests++;
      return fixtures.response({});
    });
    await s.accept(fixtures.tokens('otp'));
    await s.enableFace(vector(0));
    final restarted = Session(
      api: ApiClient(
        client: MockClient((_) async {
          requests++;
          return fixtures.response({});
        }),
      ),
    );
    await restarted.initialize();
    expect(restarted.faceEnabled, true);
    expect(restarted.user, isNull);
    expect(restarted.api.token, isNull);
    expect(requests, 0);
    expect(await s.storage.read(key: 'refresh_token'), isNull);
  });
  test(
    'disabling fingerprint preserves face login without ordinary token copy',
    () async {
      final s = fixtures.session(
        fixtures.FakeBiometrics(),
        (_) async => fixtures.response(fixtures.tokens('next')),
      );
      await s.accept(fixtures.tokens('otp'));
      await s.enableBiometrics();
      await s.enableFace(vector(0));
      await s.disableBiometrics();
      expect(s.biometricEnabled, false);
      expect(s.faceEnabled, true);
      expect(await s.storage.read(key: 'refresh_token'), isNull);
      s.lock();
      await s.faceLogin(vector(0));
      expect(s.user?.id, fixtures.account['id']);
    },
  );
  test(
    'revoked face session clears both quick login methods and template',
    () async {
      final s = fixtures.session(
        fixtures.FakeBiometrics(),
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 'EXPIRED', 'message': 'Expired'},
          }),
          401,
        ),
      );
      await s.accept(fixtures.tokens('otp'));
      await s.enableBiometrics();
      await s.enableFace(vector(0));
      s.lock();
      await expectLater(s.faceLogin(vector(0)), throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);
      expect(s.quickLoginEnabled, false);
      expect(s.user, isNull);
      expect(await s.faceAccess.token(), isNull);
    },
  );
}
