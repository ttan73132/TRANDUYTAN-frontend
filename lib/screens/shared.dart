import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../providers/session.dart';
import '../services/face.dart';
import '../services/location.dart';
import '../widgets/common.dart';
import 'shared_management.dart';
import 'shared_attendance.dart';
import 'translation.dart';
import 'shared_handovers.dart';

class SharedAccountStatus extends StatefulWidget {
  const SharedAccountStatus({super.key});
  @override
  State<SharedAccountStatus> createState() => _SharedAccountStatusState();
}

class _SharedAccountStatusState extends State<SharedAccountStatus> {
  bool busy = false;
  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) notice(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final suspended = session.user!.values['status'] == 'suspended';
    return Scaffold(
      appBar: AppBar(title: const Text('TRANDUYTAN')),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const SizedBox(height: 50),
            Icon(
              suspended ? Icons.lock_outline : Icons.hourglass_top,
              size: 72,
              color: blue,
            ),
            const SizedBox(height: 28),
            SectionTitle(
              suspended ? 'Tài khoản tạm khóa' : 'Chờ quản trị viên duyệt',
              caption: 'Email: ${session.user!.values['email']}',
            ),
            const SizedBox(height: 24),
            Text(
              suspended
                  ? 'Liên hệ quản trị viên nhóm để kiểm tra trạng thái tài khoản.'
                  : 'Email đã xác minh chưa đồng nghĩa tài khoản đã được kích hoạt. Nhờ quản trị viên nhóm duyệt tài khoản và gán chi nhánh trước khi chấm công.',
            ),
            const SizedBox(height: 24),
            BusyButton(
              busy: busy,
              onPressed: () => run(session.reloadUser),
              label: 'Kiểm tra trạng thái',
            ),
            TextButton(
              onPressed: busy ? null : () => run(session.logout),
              child: const Text('Đăng xuất'),
            ),
            TextButton.icon(
              onPressed: () => openPage(context, const TranslationScreen()),
              icon: const Icon(Icons.translate),
              label: const Text('Dịch trực tiếp'),
            ),
          ],
        ),
      ),
    );
  }
}

class SharedHome extends StatefulWidget {
  const SharedHome({super.key});
  @override
  State<SharedHome> createState() => _SharedHomeState();
}

class _SharedHomeState extends State<SharedHome> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user!;
    final pages = [
      const SharedDashboard(),
      const SharedResourceScreen(kind: 'shifts', embedded: true),
      const SharedAttendanceScreen(embedded: true),
      const SharedProfile(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TRANDUYTAN',
          style: TextStyle(letterSpacing: 1.5, fontSize: 17),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: StatusBadge(user.values['role'] as String)),
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
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            label: 'Tổng quan',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Ca làm',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            label: 'Bảng công',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Cá nhân',
          ),
        ],
      ),
    );
  }
}

class SharedDashboard extends StatelessWidget {
  const SharedDashboard({super.key});
  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    return LoadView<Json>(
      refreshInterval: const Duration(seconds: 15),
      load: () => session.api.get('/dashboard'),
      builder: (data, reload) => RefreshIndicator(
        onRefresh: () async => reload(),
        child: ListView(
          padding: const EdgeInsets.all(24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              dateOnly(DateTime.now().toUtc().toIso8601String()),
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 12),
            Text(
              'Xin chào, ${session.user!.fullName}',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 12),
            Text(
              'Mỗi ngày làm việc.\nMỗi dấu ấn riêng.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [navy, Color(0xFF174C85)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TRANDUYTAN / NHÓM 08',
                    style: TextStyle(
                      color: Color(0xFFA9C8F1),
                      letterSpacing: 1.5,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Vào ca an toàn.\nAn tâm làm việc.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Vị trí thực · Thời gian từ máy chủ',
                    style: TextStyle(color: Color(0xFFBAD3F4)),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.tonalIcon(
                    onPressed: () => openPage(
                      context,
                      const SharedResourceScreen(kind: 'shifts'),
                    ),
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Xem ca và chấm công'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, size) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final metric in [
                    ('Nhân viên', 'employeeCount'),
                    ('Chờ duyệt', 'pendingEmployeeCount'),
                    ('Tổng ca', 'shiftCount'),
                    ('Đang làm hôm nay', 'checkedInCount'),
                  ])
                    SizedBox(
                      width: (size.maxWidth - 12) / 2,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${data[metric.$2] ?? 0}',
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w600,
                                  color: navy,
                                ),
                              ),
                              Text(
                                metric.$1,
                                style: const TextStyle(color: muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _tile(
              context,
              Icons.translate,
              'Dịch trực tiếp',
              'Camera · Giọng nói · Việt, Anh, Trung, Nhật',
              const TranslationScreen(),
            ),
            _tile(
              context,
              Icons.forum_outlined,
              'Bàn giao song ngữ',
              'Bản dịch, thông tin quan trọng và xác nhận',
              const SharedHandovers(),
            ),
            const SectionTitle(
              'Không bỏ sót một ca',
              caption: 'Đối soát giờ gốc, ca thiếu chấm ra và đơn điều chỉnh trong một nơi.',
            ),
            const SizedBox(height: 14),
            _tile(
              context,
              Icons.rule,
              'Trợ lý đối soát ca',
              'Bảng công tháng và các ca cần kiểm tra',
              const SharedAttendanceScreen(),
            ),
            _tile(
              context,
              Icons.edit_note,
              'Đơn điều chỉnh',
              'Đề nghị giờ đúng; lưu bằng chứng trước và sau duyệt',
              const SharedCorrections(),
            ),
            _tile(
              context,
              Icons.location_on_outlined,
              'Chia sẻ vị trí',
              'Chỉ gửi khi bạn chọn, tự hết hạn sau 15 phút',
              const SharedLocations(),
            ),
            if (session.user!.canManage)
              _tile(
                context,
                Icons.people_outline,
                'Nhân viên',
                'Quản lý theo quyền tài khoản',
                const SharedResourceScreen(kind: 'employees'),
              ),
            _tile(
              context,
              Icons.business_outlined,
              'Chi nhánh',
              'Địa chỉ và bán kính chấm công',
              const SharedResourceScreen(kind: 'branches'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Widget page,
  ) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: Icon(icon, color: blue),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => openPage(context, page),
    ),
  );
}

class SharedProfile extends StatefulWidget {
  const SharedProfile({super.key});
  @override
  State<SharedProfile> createState() => _SharedProfileState();
}

class _SharedProfileState extends State<SharedProfile> {
  bool busy = false;
  int revision = 0;
  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
      if (mounted) setState(() => revision++);
    } catch (e) {
      if (mounted) notice(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> enroll() async {
    if (!await confirm(
      context,
      'Đăng ký khuôn mặt',
      'Ảnh sẽ được gửi tới máy chủ nhóm để tạo mẫu đối chiếu khuôn mặt của chính bạn. Đây là đối chiếu ảnh 2D; đăng nhập vẫn cần OTP email. Bạn đồng ý chụp và gửi ảnh?',
    )) {
      return;
    }
    if (!mounted) return;
    final api = context.read<Session>().api;
    await run(() async {
      final image = await captureFace();
      if (image != null) await api.post('/face/enroll', {'imageBase64': image});
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final user = session.user!;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SectionTitle('Hồ sơ cá nhân'),
        const SizedBox(height: 24),
        Center(
          child: CircleAvatar(
            radius: 42,
            backgroundColor: navy,
            child: Text(
              user.initial,
              style: const TextStyle(fontSize: 30, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          user.fullName,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                InfoLine('Username', user.values['username']),
                InfoLine('Email', user.values['email']),
                InfoLine('Quyền', statusLabel(user.values['role'] as String?)),
                InfoLine(
                  'Trạng thái',
                  statusLabel(user.values['status'] as String?),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        LoadView<Json>(
          key: ValueKey(revision),
          load: () => session.api.get('/face/status'),
          builder: (face, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Đăng nhập bằng khuôn mặt',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    face['enrolled'] == true
                        ? 'Đã đăng ký · ${dateTime(face['enrolledAt'])}'
                        : 'Chưa có mẫu khuôn mặt.',
                  ),
                  const SizedBox(height: 14),
                  BusyButton(
                    busy: busy,
                    onPressed: enroll,
                    label: face['enrolled'] == true
                        ? 'Chụp lại khuôn mặt'
                        : 'Đăng ký khuôn mặt',
                    icon: Icons.face,
                  ),
                  if (face['enrolled'] == true)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              if (await confirm(
                                context,
                                'Xóa mẫu khuôn mặt?',
                                'Bạn vẫn đăng nhập bằng mật khẩu và OTP.',
                              )) {
                                await run(
                                  () => session.api.delete('/face/enroll'),
                                );
                              }
                            },
                      child: const Text('Xóa mẫu của tôi'),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        BusyButton(
          busy: busy,
          onPressed: () => run(session.logout),
          label: 'Đăng xuất',
          icon: Icons.logout,
        ),
      ],
    );
  }
}

class SharedLocations extends StatefulWidget {
  const SharedLocations({super.key});
  @override
  State<SharedLocations> createState() => _SharedLocationsState();
}

class _SharedLocationsState extends State<SharedLocations> {
  bool busy = false;
  int revision = 0;
  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
      if (mounted) setState(() => revision++);
    } catch (e) {
      if (mounted) notice(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> share() async {
    if (!await confirm(
      context,
      'Chia sẻ trong 15 phút?',
      'Gửi một vị trí GPS hiện tại cho người quản lý có quyền xem. Không theo dõi nền hoặc tự cập nhật. Bạn có thể dừng trước khi hết hạn.',
    )) {
      return;
    }
    if (!mounted) return;
    final api = context.read<Session>().api;
    await run(() async {
      final p = await currentLocation();
      await api.post('/location-shares', {
        'latitude': p.latitude,
        'longitude': p.longitude,
        'accuracyMeters': p.accuracy,
        'ttlMinutes': 15,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    return Scaffold(
      appBar: AppBar(title: const Text('Chia sẻ vị trí')),
      body: LoadView<List<Json>>(
        refreshInterval: const Duration(seconds: 15),
        key: ValueKey(revision),
        load: () => session.api.list('/location-shares'),
        builder: (rows, reload) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SectionTitle(
              'Bạn quyết định chia sẻ',
              caption: 'Chỉ vị trí chưa hết hạn và trong phạm vi được server cho phép mới hiển thị.',
            ),
            const SizedBox(height: 20),
            BusyButton(
              busy: busy,
              onPressed: share,
              label: 'Chia sẻ vị trí hiện tại · 15 phút',
              icon: Icons.my_location,
            ),
            const SizedBox(height: 18),
            if (rows.isEmpty) const EmptyState('Chưa có vị trí đang chia sẻ.'),
            for (final row in rows)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row['fullName'] ?? 'Vị trí'}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      InfoLine(
                        'Tọa độ',
                        '${row['latitude'] ?? row['lat']}, ${row['longitude'] ?? row['lng']}',
                      ),
                      InfoLine('Hết hạn', dateTime(row['expiresAt'])),
                      if (row['userId'] == session.user!.id)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => run(
                                  () => session.api.delete(
                                    '/location-shares/${row['id']}',
                                  ),
                                ),
                          child: const Text('Dừng chia sẻ của tôi'),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
