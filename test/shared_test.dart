import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:tranduytan/core/theme.dart';
import 'package:tranduytan/main.dart';
import 'package:tranduytan/models/user.dart';
import 'package:tranduytan/providers/session.dart';
import 'package:tranduytan/screens/auth.dart';
import 'package:tranduytan/screens/shared.dart';
import 'package:tranduytan/screens/shared_attendance.dart';
import 'package:tranduytan/screens/shared_handovers.dart';
import 'package:tranduytan/screens/shared_management.dart';
import 'package:tranduytan/screens/translation.dart';
import 'package:tranduytan/services/api.dart';
import 'package:tranduytan/services/biometrics.dart';
import 'package:tranduytan/services/translation.dart';
import 'package:tranduytan/widgets/common.dart';

final testUser = <String, dynamic>{
  'id': '00000000-0000-4000-8000-000000000001',
  'fullName': 'Tran Duy Tan',
  'username': 'tantest',
  'email': 'tan@example.test',
  'role': 'employee',
  'status': 'active',
  'emailVerified': true,
  'branchId': 'branch-1',
};
final testShift = <String, dynamic>{
  'id': 'shift-1',
  'title': 'Ca sang',
  'employeeId': testUser['id'],
  'branchId': 'branch-1',
  'startsAt': '2026-10-29T01:00:00Z',
  'endsAt': '2026-10-29T10:00:00Z',
  'status': 'scheduled',
  'planLocked': true,
};
http.Response response(dynamic data, {int status = 200}) => http.Response(
  jsonEncode({'data': data}),
  status,
  headers: {'content-type': 'application/json'},
);
http.Response failure(int status) => http.Response(
  jsonEncode({
    'error': {
      'code': status == 409 ? 'VERSION_CONFLICT' : 'REJECTED',
      'message': 'Request rejected',
    },
  }),
  status,
);
Session sessionFor(
  Future<http.Response> Function(http.Request) handle, {
  String role = 'employee',
  String status = 'active',
}) =>
    Session(
        api: ApiClient(client: MockClient(handle))
          ..baseUrl = ApiClient.sharedBaseUrl
          ..token = 'old-access',
      )
      ..loading = false
      ..user = AppUser({...testUser, 'role': role, 'status': status});
Widget page(Session session, Widget child) => ChangeNotifierProvider.value(
  value: session,
  child: MaterialApp(theme: appTheme(), home: child),
);
Widget root(Session session) =>
    ChangeNotifierProvider.value(value: session, child: const TranduytanApp());

class FakeTranslation implements TranslationEngine {
  final calls = <String, Completer<String>>{};
  bool available = true;
  @override
  Future<bool> installed(String source, String target) async => available;
  @override
  Future<void> prepare(String source, String target) async {
    available = true;
  }

  @override
  Future<String> translate(String text, String source, String target) =>
      (calls[text] = Completer<String>()).future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DeviceBiometrics.channel, (_) async => false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('google_mlkit_on_device_translator'),
          (call) async =>
              call.method == 'nlp#manageLanguageModelModels' ? true : null,
        );
  });

  test('shared origin normalizes /v1 exactly once', () {
    final origin = ApiClient.sharedBaseUrl.replaceFirst('/v1', '');
    expect(ApiClient.validateUrl(origin), ApiClient.sharedBaseUrl);
    expect(ApiClient.validateUrl('$origin/'), ApiClient.sharedBaseUrl);
    expect(
      ApiClient.validateUrl('${ApiClient.sharedBaseUrl}/'),
      ApiClient.sharedBaseUrl,
    );
    expect(
      () => ApiClient.validateUrl('${ApiClient.sharedBaseUrl}/v1'),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'concurrent expired requests rotate one refresh token and replay once',
    () async {
      var refreshes = 0, requests = 0;
      final session = sessionFor((req) async {
        if (req.url.path == '/v1/auth/refresh') {
          refreshes++;
          expect(jsonDecode(req.body), {'refreshToken': 'old-refresh'});
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return response({
            'accessToken': 'new-access',
            'refreshToken': 'new-refresh',
            'user': testUser,
          });
        }
        requests++;
        return req.headers['Authorization'] == 'Bearer new-access'
            ? response({'ok': true})
            : failure(401);
      })..refreshToken = 'old-refresh';
      final result = await Future.wait([
        session.api.get('/dashboard'),
        session.api.get('/me'),
      ]);
      expect(result.every((row) => row['ok'] == true), true);
      expect(refreshes, 1);
      expect(requests, 4);
      expect(await session.storage.read(key: 'refresh_token'), 'new-refresh');
      expect(await session.storage.read(key: 'access_token'), 'new-access');
    },
  );

  test('failed refresh clears session and never loops', () async {
    var calls = 0;
    final session = sessionFor((req) async {
      calls++;
      return failure(401);
    })..refreshToken = 'invalid';
    await expectLater(session.api.get('/me'), throwsA(isA<ApiException>()));
    expect(calls, 2);
    expect(session.user, isNull);
    expect(session.api.token, isNull);
  });

  test('public logout does not rotate stale refresh body after 401', () async {
    var calls = 0, rotations = 0;
    final api =
        ApiClient(
            client: MockClient((req) async {
              calls++;
              return failure(401);
            }),
          )
          ..baseUrl = ApiClient.sharedBaseUrl
          ..token = 'access'
          ..onRefresh = () async {
            rotations++;
            return true;
          };
    await expectLater(
      api.post('/auth/logout', {'refreshToken': 'refresh'}),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 1);
    expect(rotations, 0);
  });

  test('role permissions and locked plan date validation', () {
    for (final role in ['employee', 'manager', 'admin']) {
      final session = sessionFor((req) async => response([]), role: role);
      expect(resourceWrite(session, 'employees'), role == 'admin');
      expect(resourceWrite(session, 'branches'), role == 'admin');
      expect(resourceWrite(session, 'shifts'), role != 'employee');
    }
    expect(parseVietnamInput('2026-10-29 08:00'), '2026-10-29T01:00:00.000Z');
    for (final value in [
      '2026-02-30 08:00',
      '2026-10-29 24:00',
      '29/10/2026 08:00',
    ]) {
      expect(() => parseVietnamInput(value), throwsFormatException);
    }
    expect(
      reviewHint({
        'timing': {'missingCheckOut': true},
      }),
      contains('Thiếu chấm ra'),
    );
    expect(
      reviewHint({
        'timing': {'late': true, 'arrivalDelayMinutes': 12},
      }),
      contains('12'),
    );
    expect(reviewHint({'timing': {}}), isEmpty);
    expect(canonicalFact('quantity', '0012.500'), '12.5');
    expect(() => canonicalFact('quantity', '1,000'), throwsFormatException);
    expect(
      () => canonicalFact('deadline', '2026-02-30 08:00'),
      throwsFormatException,
    );
  });

  testWidgets(
    'register uses shared schema, OTP stores both tokens then gates pending account',
    (tester) async {
      final session = sessionFor((req) async {
        final body = req.body.isEmpty ? null : jsonDecode(req.body);
        if (req.url.path == '/v1/auth/register') {
          expect((body as Map).keys.toSet(), {
            'fullName',
            'username',
            'email',
            'password',
          });
          return response({
            'challengeId': 'challenge',
            'maskedEmail': 't***@example.test',
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 10))
                .toUtc()
                .toIso8601String(),
            'retryAfterSeconds': 60,
          }, status: 202);
        }
        if (req.url.path == '/v1/auth/verify-otp') {
          expect(body, {'challengeId': 'challenge', 'code': '123456'});
          return response({
            'accessToken': 'verified-access',
            'refreshToken': 'verified-refresh',
            'user': {...testUser, 'status': 'pending'},
          });
        }
        throw StateError('Unexpected ${req.url}');
      })..user = null;
      session.api.token = null;
      await tester.pumpWidget(root(session));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Chưa có tài khoản? Đăng ký'));
      await tester.tap(find.text('Chưa có tài khoản? Đăng ký'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      for (final entry in [
        'Tran Duy Tan',
        'tantest',
        'tan@example.test',
        'Password12345',
        'Password12345',
      ].asMap().entries) {
        await tester.enterText(fields.at(entry.key), entry.value);
      }
      await tester.ensureVisible(find.text('Đăng ký tài khoản'));
      await tester.tap(find.text('Đăng ký tài khoản'));
      await tester.pumpAndSettle();
      expect(find.byType(OtpScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '123456');
      await tester.ensureVisible(find.text('Xác thực và đăng nhập'));
      await tester.tap(find.text('Xác thực và đăng nhập'));
      await tester.pumpAndSettle();
      expect(find.byType(SharedAccountStatus), findsOneWidget);
      expect(find.byType(SharedDashboard), findsNothing);
      expect(
        await session.storage.read(key: 'refresh_token'),
        'verified-refresh',
      );
      expect(
        await session.storage.read(key: 'access_token'),
        'verified-access',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pending account reload opens dashboard only after server approval',
    (tester) async {
      final session = sessionFor((req) async {
        if (req.url.path == '/v1/me') return response(testUser);
        if (req.url.path == '/v1/dashboard') return response({});
        throw StateError('Unexpected ${req.url}');
      }, status: 'pending');
      await tester.pumpWidget(root(session));
      await tester.pumpAndSettle();
      expect(find.byType(SharedAccountStatus), findsOneWidget);
      await tester.tap(find.text('Kiểm tra trạng thái'));
      await tester.pumpAndSettle();
      expect(find.byType(SharedHome), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('locked shift editor only sends title in PATCH', (tester) async {
    JsonMap? sent;
    final session = sessionFor((req) async {
      if (req.method == 'PATCH') {
        sent = Map<String, dynamic>.from(jsonDecode(req.body) as Map);
        return response(testShift);
      }
      return response([]);
    }, role: 'admin');
    await tester.pumpWidget(
      page(session, SharedEditor(kind: 'shifts', row: testShift)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Ca moi');
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(sent, {'title': 'Ca moi'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'polling preserves data during refresh, stops in background, retries without overlap',
    (tester) async {
      var calls = 0;
      Completer<int>? pending;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LoadView<int>(
              refreshInterval: const Duration(seconds: 15),
              load: () async {
                calls++;
                return pending == null ? calls : await pending.future;
              },
              builder: (value, reload) => Text('Data $value'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Data 1'), findsOneWidget);
      pending = Completer<int>();
      await tester.pump(const Duration(seconds: 15));
      expect(calls, 2);
      expect(find.text('Data 1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 2);
      pending.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Data 1'), findsOneWidget);
      expect(find.textContaining('Mất kết nối'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 2);
      pending = null;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, 3);
      expect(find.text('Data 3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'live translation debounces and rejects late results for old text',
    (tester) async {
      final engine = FakeTranslation();
      final live = LiveTranslation(engine: engine);
      await live.checkModels();
      live.update('old');
      await tester.pump(const Duration(milliseconds: 600));
      live.update('new');
      await tester.pump(const Duration(milliseconds: 600));
      engine.calls['new']!.complete('new result');
      await tester.pump();
      expect(live.result, 'new result');
      engine.calls['old']!.complete('old result');
      await tester.pump();
      expect(live.result, 'new result');
      live.update('discarded');
      live.dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(engine.calls.containsKey('discarded'), false);
    },
  );

  testWidgets('translation screen renders output from engine', (tester) async {
    final engine = FakeTranslation();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: TranslationScreen(engine: engine),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhập chữ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Xin chao');
    await tester.pump(const Duration(milliseconds: 600));
    engine.calls['Xin chao']!.complete('Hello');
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'translation keeps readable result during update and clears it on failure',
    (tester) async {
      final engine = FakeTranslation();
      final live = LiveTranslation(engine: engine);
      await live.checkModels();
      live.update('first');
      await tester.pump(const Duration(milliseconds: 600));
      engine.calls['first']!.complete('First result');
      await tester.pump();
      live.update('second');
      expect(live.result, 'First result');
      expect(live.busy, true);
      await tester.pump(const Duration(milliseconds: 600));
      expect(live.result, 'First result');
      engine.calls['second']!.complete('Second result');
      await tester.pump();
      expect(live.result, 'Second result');
      live.update('fails');
      await tester.pump(const Duration(milliseconds: 600));
      engine.calls['fails']!.completeError(StateError('failed'));
      await tester.pump();
      expect(live.result, isEmpty);
      expect(live.error, contains('failed'));
      live.update('');
      expect(live.result, isEmpty);
      live.dispose();
    },
  );

  test(
    'Japanese downloads ja model and uses native Japanese translator',
    () async {
      final downloaded = <String>[];
      final channels =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      channels.setMockMethodCallHandler(
        const MethodChannel('google_mlkit_on_device_translator'),
        (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          if (call.method == 'nlp#manageLanguageModelModels') {
            if (args['task'] == 'check') return args['model'] != 'ja';
            if (args['task'] == 'download') {
              downloaded.add(args['model'] as String);
              return 'success';
            }
          }
          if (call.method == 'nlp#startLanguageTranslator') {
            expect(args['source'], 'vi');
            expect(args['target'], 'ja');
            return 'こんにちは';
          }
          return null;
        },
      );
      final engine = DeviceTranslation();
      await engine.prepare('vi', 'ja');
      expect(downloaded, ['ja']);
      expect(await engine.translate('Xin chào', 'vi', 'ja'), 'こんにちは');
    },
  );

  testWidgets('Japanese selectable for direct translation', (tester) async {
    final engine = FakeTranslation();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: TranslationScreen(engine: engine),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhập chữ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本語').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Xin chào');
    await tester.pump(const Duration(milliseconds: 600));
    engine.calls['Xin chào']!.complete('こんにちは');
    await tester.pumpAndSettle();
    expect(find.text('こんにちは'), findsOneWidget);
    expect(handoverLanguageCodes, isNot(contains('ja')));
    await tester.pumpWidget(const SizedBox());
  });

  final handover = <String, dynamic>{
    'id': 'handover-1',
    'createdBy': 'sender-1',
    'recipientId': testUser['id'],
    'shiftId': 'shift-1',
    'shiftTitle': 'Ca sang',
    'status': 'submitted',
    'version': 4,
    'originalText': 'Ban giao EQ-12',
    'translatedText': 'Handover EQ-12',
    'sourceLanguage': 'vi',
    'targetLanguage': 'en',
    'items': [
      {
        'id': 'item-1',
        'text': 'Kiem tra',
        'translatedText': 'Check',
        'state': 'understood',
      },
    ],
    'criticalFacts': [
      {
        'id': 'fact-1',
        'kind': 'equipment',
        'label': 'Ma thiet bi',
        'value': 'eq-12',
      },
    ],
    'criticalFactConfirmation': null,
  };
  testWidgets(
    'recipient submits exact version and typed fact answers; stale version requires reload',
    (tester) async {
      JsonMap? sent;
      final session = sessionFor((req) async {
        if (req.method == 'GET') return response(handover);
        sent = Map<String, dynamic>.from(jsonDecode(req.body) as Map);
        return failure(409);
      });
      await tester.pumpWidget(
        page(session, const SharedHandoverDetail(id: 'handover-1')),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(TextField),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), 'EQ-12');
      final answerController = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      await tester.scrollUntilVisible(
        find.text('Xác nhận hoàn tất bàn giao'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Xác nhận hoàn tất bàn giao'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(sent?['version'], 4);
      expect(sent?['status'], 'acknowledged');
      expect(sent?['factAnswers'], [
        {'factId': 'fact-1', 'value': 'EQ-12'},
      ]);
      expect((sent?['items'] as List).single, {
        'id': 'item-1',
        'text': 'Kiem tra',
        'translatedText': 'Check',
        'state': 'understood',
      });
      expect(find.text('Tải phiên bản mới'), findsOneWidget);
      expect(find.text('Xác nhận hoàn tất bàn giao'), findsNothing);
      expect(answerController.text, 'EQ-12');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('admin author has no recipient confirmation controls', (
    tester,
  ) async {
    final session = sessionFor(
      (req) async => response({
        ...handover,
        'createdBy': testUser['id'],
        'recipientId': 'other',
      }),
      role: 'admin',
    );
    await tester.pumpWidget(
      page(session, const SharedHandoverDetail(id: 'handover-1')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Sửa nội dung bàn giao'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Sửa nội dung bàn giao'), findsOneWidget);
    expect(find.text('Xác nhận hoàn tất bàn giao'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed correction withdrawal keeps detail open', (tester) async {
    final session = sessionFor(
      (req) async => req.method == 'DELETE'
          ? failure(403)
          : response({
              'id': 'correction-1',
              'employeeId': testUser['id'],
              'shiftId': 'shift-1',
              'status': 'pending',
              'reason': 'Missing time',
            }),
    );
    await tester.pumpWidget(
      page(session, const SharedCorrectionDetail(id: 'correction-1')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Rút đơn'));
    await tester.tap(find.text('Rút đơn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(find.byType(SharedCorrectionDetail), findsOneWidget);
    expect(find.text('Request rejected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  final reportRow = {
    ...testShift,
    'shiftId': testShift['id'],
    'employeeName': 'Tran Duy Tan',
    'branchName': 'Van phong',
    'checkInAt': null,
    'checkOutAt': null,
    'recordedCheckInAt': null,
    'recordedCheckOutAt': null,
    'timing': {'state': 'missing_check_in'},
  };
  for (final entry in <String, Widget>{
    'home': const SharedHome(),
    'employees': const SharedResourceScreen(kind: 'employees'),
    'branches': const SharedResourceScreen(kind: 'branches'),
    'report': const SharedAttendanceScreen(),
    'corrections': const SharedCorrections(),
    'locations': const SharedLocations(),
    'handovers': const SharedHandovers(),
    'handover-editor': const SharedHandoverEditor(),
  }.entries) {
    testWidgets('shared ${entry.key} fits narrow phone', (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = sessionFor(
        (req) async => response(switch (req.url.path) {
          '/v1/dashboard' => {
            'employeeCount': 3,
            'pendingEmployeeCount': 1,
            'shiftCount': 2,
            'checkedInCount': 1,
          },
          '/v1/employees' => [testUser],
          '/v1/shifts' => [testShift],
          '/v1/branches' => [
            {
              'id': 'branch-1',
              'name': 'Van phong',
              'address': 'Thu Duc',
              'radiusMeters': 100,
            },
          ],
          '/v1/reports/monthly' => {
            'timeZone': 'Asia/Ho_Chi_Minh',
            'totals': {'shiftCount': 1},
            'rows': [reportRow],
          },
          '/v1/handover-recipients' => [
            {'id': 'recipient-1', 'fullName': 'Nguoi nhan'},
          ],
          _ => [],
        }),
        role: 'admin',
      );
      await tester.pumpWidget(page(session, entry.value));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

typedef JsonMap = Map<String, dynamic>;
