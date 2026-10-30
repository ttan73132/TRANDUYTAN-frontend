import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../providers/preferences.dart';
import '../providers/session.dart';
import '../widgets/common.dart';
import 'face_scan.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool busy = false;
  double? draftScale;
  Future<void> enrollFace() async {
    if (!await confirm(
      context,
      'Bật quét mặt vào thẳng?',
      'Camera 2D có mức bảo vệ thấp hơn vân tay, không bảo đảm chống ảnh/video giả. Mẫu khuôn mặt lưu mã hóa trên điện thoại, không gửi ảnh lên máy chủ. Cần tải gói nhận diện 39 MB một lần. Bạn đồng ý đăng ký?',
    )) {
      return;
    }
    if (!mounted) return;
    final session = context.read<Session>();
    await run(() async {
      final template = await openPage<List<double>>(
        context,
        FaceScanScreen(access: session.faceAccess),
      );
      if (template != null) {
        await session.enableFace(template);
        if (mounted) {
          notice(
            context,
            'Đã bật quét mặt. Khóa ứng dụng rồi chọn Quét mặt để đăng nhập.',
          );
        }
      }
    });
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) notice(context, 'Không lưu được cài đặt: $e', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final preferences = session.preferences;
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SectionTitle(
            'Giao diện',
            caption: 'Lưu trên thiết bị, giữ lại sau khi đóng app.',
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cỡ chữ · ${((draftScale ?? preferences.textScale) * 100).round()}%',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Slider(
                    value: draftScale ?? preferences.textScale,
                    min: .85,
                    max: 1.4,
                    divisions: 11,
                    label:
                        '${((draftScale ?? preferences.textScale) * 100).round()}%',
                    onChanged: busy
                        ? null
                        : (value) => setState(() => draftScale = value),
                    onChangeEnd: busy
                        ? null
                        : (value) async {
                            await run(
                              () => session.setAppearance(
                                value,
                                preferences.backgroundIndex,
                              ),
                            );
                            if (mounted) setState(() => draftScale = null);
                          },
                  ),
                  const Text(
                    'Xin chào! Đây là cỡ chữ hiển thị trong ứng dụng.',
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Màu nền',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var i = 0; i < backgroundChoices.length; i++)
                        ChoiceChip(
                          label: Text(backgroundChoices[i].$1),
                          avatar: CircleAvatar(
                            backgroundColor: backgroundChoices[i].$2,
                            radius: 10,
                          ),
                          selected: preferences.backgroundIndex == i,
                          onSelected: busy
                              ? null
                              : (_) => run(
                                  () => session.setAppearance(
                                    preferences.textScale,
                                    i,
                                  ),
                                ),
                        ),
                    ],
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => run(() => session.setAppearance(1, 0)),
                    child: const Text('Khôi phục giao diện mặc định'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const SectionTitle('Tài khoản'),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              leading: const Icon(Icons.manage_accounts_outlined, color: blue),
              title: const Text('Cập nhật hồ sơ cá nhân'),
              subtitle: const Text('Tên hiển thị, điện thoại và giới thiệu'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openPage(context, const EditProfileScreen()),
            ),
          ),
          if (session.api.isShared) ...[
            const SizedBox(height: 14),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Đăng nhập sinh trắc học'),
                    subtitle: const Text(
                      'Vân tay hoặc khuôn mặt được Android hỗ trợ. Bật sau khi đã xác thực OTP.',
                    ),
                    value: session.biometricEnabled,
                    onChanged: busy
                        ? null
                        : (enabled) => run(
                            enabled
                                ? session.enableBiometrics
                                : session.disableBiometrics,
                          ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 18),
                    child: Text(
                      'Sinh trắc học xử lý trên điện thoại (Android 11 trở lên). Mọi sinh trắc học đã đăng ký trên máy đều có thể mở app. Máy chỉ có khuôn mặt 2D có thể cần dùng vân tay. Phiên hết hạn hoặc bị thu hồi cần mật khẩu và OTP lại.',
                    ),
                  ),
                  if (session.quickLoginEnabled)
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('Khóa ứng dụng'),
                      subtitle: const Text(
                        'Lần mở sau dùng sinh trắc học; tự khóa khi rời app từ 30 giây.',
                      ),
                      onTap: busy ? null : session.lock,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.face_retouching_natural),
                    title: const Text('Quét mặt bằng camera'),
                    subtitle: Text(
                      session.faceEnabled
                          ? 'Đã đăng ký trên điện thoại · vào thẳng khi phiên còn hiệu lực'
                          : 'Đăng ký mẫu mặt để lần sau không cần OTP',
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Xử lý trên máy. Camera 2D có mức bảo vệ thấp hơn vân tay; không bảo đảm chống ảnh/video giả.',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: busy ? null : enrollFace,
                          icon: const Icon(Icons.camera_front),
                          label: Text(
                            session.faceEnabled
                                ? 'Đăng ký lại khuôn mặt'
                                : 'Đăng ký khuôn mặt trên máy',
                          ),
                        ),
                        if (session.faceEnabled)
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => run(session.disableFace),
                            child: const Text('Tắt và xóa mẫu mặt'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final form = GlobalKey<FormState>();
  final fields = {
    for (final key in ['fullName', 'phone', 'department', 'position', 'bio'])
      key: TextEditingController(),
  };
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final session = context.read<Session>();
    for (final entry in fields.entries) {
      entry.value.text =
          session.preferences.profile[entry.key] ??
          (entry.key == 'fullName'
              ? session.user!.fullName
              : session.user!.values[entry.key]?.toString() ?? '');
    }
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await context.read<Session>().updateLocalProfile({
        for (final entry in fields.entries) entry.key: entry.value.text,
      });
      if (mounted) {
        notice(context, 'Đã lưu hồ sơ trên thiết bị.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) notice(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Ứng dụng đã khóa.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Cập nhật hồ sơ')),
      body: Form(
        key: form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Hồ sơ này lưu riêng trên điện thoại, chưa đồng bộ máy chủ nhóm. Thay đổi tên hiển thị không sửa tên trong bảng công. Email, tên đăng nhập và quyền do máy chủ quản lý.',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              InfoLine('Tên đăng nhập', user.values['username']),
              InfoLine('Email', user.values['email']),
              const SizedBox(height: 16),
              for (final item in [
                ('fullName', 'Tên hiển thị', 120),
                ('phone', 'Số điện thoại', 24),
                ('department', 'Phòng ban (giới thiệu)', 120),
                ('position', 'Chức vụ (giới thiệu)', 120),
                ('bio', 'Giới thiệu bản thân', 500),
              ]) ...[
                TextFormField(
                  key: ValueKey('profile-${item.$1}'),
                  controller: fields[item.$1],
                  enabled: !busy,
                  decoration: InputDecoration(labelText: item.$2),
                  maxLength: item.$3,
                  maxLines: item.$1 == 'bio' ? 3 : 1,
                  keyboardType: item.$1 == 'phone'
                      ? TextInputType.phone
                      : TextInputType.text,
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (item.$1 == 'fullName' && text.length < 2) {
                      return 'Nhập tên từ 2 ký tự.';
                    }
                    if (item.$1 == 'phone' &&
                        text.isNotEmpty &&
                        !RegExp(r'^\+?[0-9 ()\-]{8,24}$').hasMatch(text)) {
                      return 'Số điện thoại không hợp lệ.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
              ],
              BusyButton(
                busy: busy,
                onPressed: save,
                label: 'Lưu hồ sơ trên thiết bị',
                icon: Icons.save_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
