import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:tranduytan/main.dart';
import 'package:tranduytan/core/format.dart';
import 'package:tranduytan/providers/session.dart';
import 'package:tranduytan/services/api.dart';
import 'package:tranduytan/models/user.dart';
import 'package:tranduytan/screens/auth.dart';
import 'package:tranduytan/screens/dashboard.dart';
import 'package:tranduytan/core/navigation.dart';

final employee = <String, dynamic>{
  'id': 'user-id',
  'employee_id': 'employee-id',
  'full_name': 'Tran Duy Tan',
  'username': 'tantest',
  'email': 'test@example.test',
  'role': 'EMPLOYEE',
  'status': 'ACTIVE',
  'phone': '',
  'department': 'Nhom 8',
  'position': 'Nhan vien',
};
http.Response jsonResponse(dynamic data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json'},
);
Widget app(Session session) =>
    ChangeNotifierProvider.value(value: session, child: const TranduytanApp());
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('production URL rejects insecure, local, credential and path URLs', () {
    for (final value in [
      'http://example.com',
      'https://localhost',
      'https://127.0.0.1',
      'https://127.5.6.7',
      'https://name:password@example.com',
      'https://example.com/auth',
      'https://example.com?secret=x',
      'invalid',
    ]) {
      expect(() => ApiClient.validateUrl(value), throwsA(isA<ApiException>()));
    }
    expect(
      ApiClient.validateUrl('https://example.onrender.com/'),
      'https://example.onrender.com',
    );
  });
  test('401 expires session; bearer token attached', () async {
    var expired = false;
    final api =
        ApiClient(
            client: MockClient((req) async {
              expect(req.headers['Authorization'], 'Bearer temporary-token');
              return http.Response(
                '{"error":{"code":"SESSION_EXPIRED","message":"expired"}}',
                401,
              );
            }),
          )
          ..baseUrl = 'https://example.test'
          ..token = 'temporary-token'
          ..onExpired = () => expired = true;
    await expectLater(api.get('/auth/me'), throwsA(isA<ApiException>()));
    expect(expired, true);
  });
  test('Vietnam display time independent of device timezone', () {
    expect(timeOnly('2026-10-29T01:00:00Z'), '08:00');
    expect(dateOnly('2026-10-28T18:00:00Z'), '29/10/2026');
  });
  testWidgets('session expiry removes protected nested routes', (tester) async {
    final api =
        ApiClient(
            client: MockClient((req) async {
              if (req.url.path == '/stats') {
                return jsonResponse({
                  'total': 0,
                  'late': 0,
                  'working': 0,
                  'checked_out': 0,
                  'pending': 0,
                });
              }
              if (req.url.path == '/attendance') {
                return jsonResponse([]);
              }
              return http.Response(
                '{"error":{"code":"SESSION_EXPIRED","message":"expired"}}',
                401,
              );
            }),
          )
          ..baseUrl = 'https://example.test'
          ..token = 'expired-token';
    final session = Session(api: api)
      ..loading = false
      ..user = AppUser(employee);
    await tester.pumpWidget(app(session));
    await tester.pumpAndSettle();
    appNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Protected nested page')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Protected nested page'), findsOneWidget);
    await expectLater(api.get('/auth/me'), throwsA(isA<ApiException>()));
    await tester.pumpAndSettle();
    expect(find.text('Protected nested page'), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'login cannot reach dashboard before OTP; successful OTP opens employee dashboard',
    (tester) async {
      final calls = <String>[];
      final api = ApiClient(
        client: MockClient((req) async {
          calls.add(req.url.path);
          if (req.url.path == '/auth/login') {
            expect(jsonDecode(req.body)['username'], 'tantest');
            return jsonResponse({
              'challengeId': 'challenge-id',
              'maskedEmail': 't***@example.test',
              'expiresIn': 300,
              'resendAfter': 60,
            });
          }
          if (req.url.path == '/auth/verify-otp') {
            expect(jsonDecode(req.body)['otp'], '123456');
            return jsonResponse({
              'accessToken': 'temporary-token',
              'user': employee,
            });
          }
          if (req.url.path == '/stats') {
            return jsonResponse({
              'total': 1,
              'late': 1,
              'working': 1,
              'checked_out': 0,
              'pending': 0,
            });
          }
          if (req.url.path == '/attendance') return jsonResponse([]);
          throw StateError('Unexpected ${req.url}');
        }),
      )..baseUrl = 'https://example.test';
      final session = Session(api: api)..loading = false;
      await tester.pumpWidget(app(session));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);
      await tester.enterText(find.byType(TextFormField).at(0), 'tantest');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'TestPassword123',
      );
      await tester.ensureVisible(find.text('Tiếp tục với OTP'));
      await tester.tap(find.text('Tiếp tục với OTP'));
      await tester.pumpAndSettle();
      expect(find.byType(OtpScreen), findsOneWidget);
      expect(session.user, isNull);
      expect(calls.contains('/stats'), false);
      await tester.enterText(find.byType(TextField).first, '123456');
      await tester.ensureVisible(find.text('Xác thực và đăng nhập'));
      await tester.tap(find.text('Xác thực và đăng nhập'));
      await tester.pumpAndSettle();
      expect(session.user?.isAdmin, false);
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(
        await session.storage.read(key: 'access_token'),
        'temporary-token',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'setup and admin dashboard fit narrow screen with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ApiClient(
        client: MockClient(
          (req) async => req.url.path == '/stats'
              ? jsonResponse({
                  'total': 2,
                  'late': 1,
                  'working': 0,
                  'checked_out': 2,
                  'pending': 1,
                })
              : jsonResponse([]),
        ),
      );
      final session = Session(api: api)..loading = false;
      await tester.pumpWidget(app(session));
      await tester.pumpAndSettle();
      expect(find.byType(SetupScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      api.baseUrl = 'https://example.test';
      session.user = AppUser({...employee, 'role': 'ADMIN'});
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: session,
          child: MaterialApp(
            theme: ThemeData(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
