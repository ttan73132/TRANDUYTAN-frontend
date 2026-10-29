import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:tranduytan/core/theme.dart';
import 'package:tranduytan/models/user.dart';
import 'package:tranduytan/providers/session.dart';
import 'package:tranduytan/services/api.dart';
import 'package:tranduytan/screens/auth.dart';
import 'package:tranduytan/screens/dashboard.dart';
import 'package:tranduytan/screens/management.dart';
import 'package:tranduytan/screens/records.dart';

// Screenshots use test fixtures only; these records are never bundled into the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('BeVietnamPro')
      ..addFont(rootBundle.load('assets/fonts/BeVietnamPro-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/BeVietnamPro-SemiBold.ttf'));
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  final employee = <String, dynamic>{
    'id': 'employee-1',
    'user_id': 'user-1',
    'employee_id': 'employee-1',
    'full_name': 'Trần Duy Tân',
    'username': 'tantest',
    'email': 'tan@example.test',
    'role': 'EMPLOYEE',
    'status': 'ACTIVE',
    'phone': '',
    'department': 'Vận hành',
    'position': 'Nhân viên',
  };
  final record = <String, dynamic>{
    'id': 'record-1',
    'shift_name': 'Ca sáng · Văn phòng',
    'full_name': 'Trần Duy Tân',
    'workplace_name': 'Văn phòng Nhóm 8',
    'start_at': '2026-10-29T01:00:00Z',
    'end_at': '2026-10-29T10:00:00Z',
    'check_in_at': '2026-10-29T01:12:00Z',
    'check_out_at': null,
    'late_minutes': 12,
    'status': 'Late',
    'latitude': 10.77,
    'longitude': 106.69,
    'accuracy': 10,
    'distance_meters': 24,
    'motion_method': 'shake',
    'corrections': [],
  };
  final explanation = <String, dynamic>{
    'id': 'explanation-1',
    'full_name': 'Trần Duy Tân',
    'shift_name': 'Ca sáng · Văn phòng',
    'check_in_at': '2026-10-29T01:12:00Z',
    'late_minutes': 12,
    'reason': 'Kẹt xe trên đường đến văn phòng.',
    'status': 'Pending',
    'reviews': [],
    'reviewer_name': null,
  };
  final cases = <String, Widget>{
    'login': const LoginScreen(),
    'admin-dashboard': const DashboardScreen(),
    'employees': const ManagementScreen(kind: ManagementKind.employees),
    'attendance': const AttendanceScreen(),
    'explanations': const ExplanationScreen(),
    'attendance-detail': const AttendanceDetailScreen(id: 'record-1'),
  };
  for (final entry in cases.entries) {
    testWidgets('${entry.key} renders at phone width', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ApiClient(
        client: MockClient((req) async {
          final dynamic data = switch (req.url.path) {
            '/stats' => {
              'total': 24,
              'late': 3,
              'checked_out': 18,
              'working': 6,
              'pending': 2,
            },
            '/attendance' => [record],
            '/attendance/record-1' => record,
            '/employees' => [employee],
            '/explanations' => [explanation],
            _ => throw StateError('Unexpected ${req.url}'),
          };
          return http.Response(
            jsonEncode({'data': data}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..baseUrl = 'https://example.test';
      final session = Session(api: api)
        ..loading = false
        ..user = AppUser({
          ...employee,
          'id': 'admin-1',
          'employee_id': 'admin-employee',
          'role': 'ADMIN',
        });
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: session,
          child: RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: appTheme(),
              debugShowCheckedModeBanner: false,
              home: entry.value is DashboardScreen
                  ? Scaffold(
                      appBar: AppBar(title: const Text('TRANDUYTAN')),
                      body: entry.value,
                    )
                  : entry.value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('../output/ui-fixtures');
        await directory.create(recursive: true);
        await File('${directory.path}/${entry.key}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    });
  }
}
