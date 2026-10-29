import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session.dart';
import '../core/theme.dart';
import '../screens/auth.dart';
import '../screens/dashboard.dart';
import '../screens/management.dart';
import '../screens/records.dart';
import '../widgets/common.dart';
import '../screens/shared.dart';

class AppGate extends StatelessWidget {
  const AppGate({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    if (s.loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fingerprint_rounded, size: 80, color: blue),
              SizedBox(height: 24),
              Text(
                'TRANDUYTAN',
                style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 32),
              CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }
    if (s.bootError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.bootError!, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: s.initialize,
                  child: const Text('Kết nối lại'),
                ),
                TextButton(
                  onPressed: s.expire,
                  child: const Text('Xóa phiên trên thiết bị'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (s.api.baseUrl.isEmpty) return const SetupScreen();
    if (s.user == null) return const LoginScreen();
    if (s.api.isShared) {
      return s.user!.isActive
          ? const SharedHome()
          : const SharedAccountStatus();
    }
    return const AppShell();
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final admin = context.watch<Session>().user!.isAdmin;
    final pages = [
      const DashboardScreen(),
      admin
          ? const ManagementScreen(
              kind: ManagementKind.employees,
              embedded: true,
            )
          : const ShiftScreen(embedded: true),
      admin ? const OperationsScreen() : const AttendanceScreen(embedded: true),
      const ProfileScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TRANDUYTAN',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: blue.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  admin ? 'ADMIN' : 'NHÂN VIÊN',
                  style: const TextStyle(
                    color: blue,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: PageBody(
          child: KeyedSubtree(key: ValueKey(index), child: pages[index]),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Tổng quan',
          ),
          NavigationDestination(
            icon: Icon(
              admin ? Icons.people_outline : Icons.calendar_month_outlined,
            ),
            label: admin ? 'Nhân viên' : 'Ca của tôi',
          ),
          NavigationDestination(
            icon: Icon(admin ? Icons.tune_rounded : Icons.history_rounded),
            label: admin ? 'Quản lý' : 'Lịch sử',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Cá nhân',
          ),
        ],
      ),
    );
  }
}

class OperationsScreen extends StatelessWidget {
  const OperationsScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const SectionTitle(
        'Điều hành',
        caption: 'Ca làm việc, địa điểm và dữ liệu chấm công.',
      ),
      for (final entry in [
        (
          Icons.calendar_month_outlined,
          'Quản lý ca làm việc',
          'Phân ca theo nhân viên và địa điểm',
          const ManagementScreen(kind: ManagementKind.shifts),
        ),
        (
          Icons.location_on_outlined,
          'Địa điểm & mã QR',
          'Bán kính chấm công và QR có thời hạn',
          const ManagementScreen(kind: ManagementKind.workplaces),
        ),
        (
          Icons.fact_check_outlined,
          'Dữ liệu chấm công',
          'Lịch sử, chi tiết và chỉnh sửa có nhật ký',
          const AttendanceScreen(),
        ),
        (
          Icons.edit_note_outlined,
          'Duyệt giải trình',
          'Xử lý đề xuất Smart Late Check-in',
          const ExplanationScreen(),
        ),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(18),
              leading: Icon(entry.$1, color: blue, size: 28),
              title: Text(
                entry.$2,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(entry.$3),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openPage(context, entry.$4),
            ),
          ),
        ),
    ],
  );
}
