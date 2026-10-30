import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../providers/session.dart';
import '../widgets/common.dart';
import 'settings.dart';
import 'management.dart';
import 'records.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final user = context.read<Session>().user!;
    final api = context.read<Session>().api;
    return LoadView<Json>(
      load: () async {
        final results = await Future.wait<dynamic>([
          api.get('/stats'),
          api.list('/attendance?limit=3&offset=0'),
        ]);
        return {'stats': results[0], 'recent': results[1]};
      },
      builder: (data, reload) {
        final stats = data['stats'] as Json;
        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: ListView(
            padding: const EdgeInsets.all(24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Row(
                children: [
                  const Icon(Icons.wb_sunny_outlined, size: 16, color: muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dateOnly(DateTime.now().toUtc().toIso8601String()),
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: navy,
                    child: Text(
                      user.initial,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Xin chào, ${user.fullName}',
                style: const TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Text(
                user.isAdmin
                    ? 'Nhịp làm việc,\ntrong tầm tay.'
                    : 'Mỗi ngày làm việc.\nMỗi dấu ấn riêng.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 24),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 450),
                builder: (context, v, child) => Opacity(
                  opacity: v,
                  child: Transform.translate(
                    offset: Offset(0, 16 * (1 - v)),
                    child: child,
                  ),
                ),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [navy, Color(0xFF174C85)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -42,
                        top: -65,
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .07),
                              width: 30,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TRANDUYTAN / ATTENDANCE',
                              style: TextStyle(
                                color: Color(0xFFA9C8F1),
                                fontSize: 10,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              user.isAdmin
                                  ? 'Một đội ngũ.\nCùng một nhịp.'
                                  : 'Vào ca an toàn.\nAn tâm làm việc.',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              user.isAdmin
                                  ? '${stats['working']} nhân viên đang trong ca.'
                                  : 'GPS · QR có thời hạn · Xác nhận chuyển động',
                              style: const TextStyle(
                                color: Color(0xFFBAD3F4),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 22),
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                await openPage(
                                  context,
                                  user.isAdmin
                                      ? const ManagementScreen(
                                          kind: ManagementKind.shifts,
                                        )
                                      : const ShiftScreen(),
                                );
                                if (context.mounted) reload();
                              },
                              icon: Icon(
                                user.isAdmin
                                    ? Icons.calendar_month_outlined
                                    : Icons.fingerprint,
                              ),
                              label: Text(
                                user.isAdmin
                                    ? 'Xem ca làm việc'
                                    : 'Chấm công ngay',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, c) => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final metric in [
                      ('Tổng lượt', stats['total'], Icons.fact_check_outlined),
                      ('Đi muộn', stats['late'], Icons.schedule),
                      ('Đã ra ca', stats['checked_out'], Icons.task_alt),
                      ('Chờ duyệt', stats['pending'], Icons.edit_note),
                    ])
                      SizedBox(
                        width: (c.maxWidth - 12) / 2,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(metric.$3, color: blue, size: 22),
                                const SizedBox(height: 14),
                                Text(
                                  '${metric.$2}',
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w600,
                                    color: navy,
                                  ),
                                ),
                                Text(
                                  metric.$1,
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Text(
                'Truy cập nhanh',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.edit_note_outlined,
                        color: blue,
                      ),
                      title: Text(
                        user.isAdmin
                            ? 'Duyệt giải trình đi muộn'
                            : 'Smart Late · Giải trình',
                      ),
                      subtitle: const Text(
                        'Theo dõi lý do và kết quả phê duyệt',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await openPage(context, const ExplanationScreen());
                        if (context.mounted) reload();
                      },
                    ),
                    if (user.isAdmin) ...[
                      const Divider(height: 1, indent: 18, endIndent: 18),
                      ListTile(
                        leading: const Icon(Icons.qr_code_2, color: blue),
                        title: const Text('Địa điểm & QR'),
                        subtitle: const Text('Quản lý khu vực chấm công'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => openPage(
                          context,
                          const ManagementScreen(
                            kind: ManagementKind.workplaces,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Text(
                'Hoạt động gần đây',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              if ((data['recent'] as List).isEmpty)
                const EmptyState('Chưa có dữ liệu chấm công.'),
              for (final row in data['recent'])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const Icon(Icons.fingerprint, color: blue),
                      title: Text(
                        row['full_name'],
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${row['shift_name']}\n${dateTime(row['check_in_at'])}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      isThreeLine: true,
                      trailing: StatusBadge(row['status']),
                      onTap: () => openPage(
                        context,
                        AttendanceDetailScreen(id: row['id']),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'NHÓM 08 · TRANDUYTAN',
                  style: TextStyle(
                    color: muted,
                    fontSize: 10,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool busy = false;
  Future<void> logout() async {
    setState(() => busy = true);
    try {
      await context.read<Session>().logout();
    } catch (e) {
      if (mounted) notice(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<Session>().user!;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SectionTitle('Hồ sơ cá nhân'),
        Center(
          child: CircleAvatar(
            radius: 44,
            backgroundColor: navy,
            child: Text(
              user.initial,
              style: const TextStyle(fontSize: 32, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          user.fullName,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Center(child: StatusBadge(user.isAdmin ? 'ADMIN' : 'EMPLOYEE')),
        const SizedBox(height: 26),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                InfoLine('Mã NV', user.employeeId),
                InfoLine('Username', user.values['username']),
                InfoLine('Email', user.values['email']),
                InfoLine('Điện thoại', user.values['phone']),
                InfoLine('Phòng ban', user.values['department']),
                InfoLine('Chức vụ', user.values['position']),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Cài đặt và hồ sơ'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openPage(context, const SettingsScreen()),
          ),
        ),
        const SizedBox(height: 24),
        BusyButton(
          busy: busy,
          onPressed: logout,
          label: 'Đăng xuất',
          icon: Icons.logout,
        ),
        const SizedBox(height: 24),
        const Text(
          'TRANDUYTAN · Nhóm 8\nỨng dụng chấm công nhân viên',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
  }
}
