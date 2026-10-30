import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../core/format.dart';
import '../providers/session.dart';
import '../widgets/common.dart';
import '../services/face.dart';
import 'translation.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: blue,
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Icon(
          Icons.fingerprint_rounded,
          color: Colors.white,
          size: 29,
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Text(
          'TRANDUYTAN',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 1.8,
            color: navy,
            fontSize: 18,
          ),
        ),
      ),
    ],
  );
}

class AuthFrame extends StatelessWidget {
  final Widget child;
  const AuthFrame({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFE7EFFF),
            Theme.of(context).scaffoldBackgroundColor,
            const Color(0xFFEAF4F7),
          ],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

class SetupScreen extends StatefulWidget {
  final bool canPop;
  const SetupScreen({super.key, this.canPop = false});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final controller = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    controller.text = context.read<Session>().api.baseUrl;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await context.read<Session>().configure(controller.text);
      if (!mounted) return;
      if (widget.canPop) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BrandMark(),
        const SizedBox(height: 54),
        const Icon(Icons.cloud_done_outlined, size: 58, color: blue),
        const SizedBox(height: 24),
        Text(
          'Kết nối nơi\nlàm việc của bạn.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 16),
        const Text(
          'Nhập địa chỉ máy chủ HTTPS do quản trị viên cung cấp để bắt đầu chấm công.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Địa chỉ API HTTPS',
            hintText: 'https://your-service.onrender.com',
          ),
          onSubmitted: (_) => busy ? null : save(),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: BusyButton(
            busy: busy,
            onPressed: save,
            label: 'Kiểm tra và kết nối',
            icon: Icons.link,
          ),
        ),
        if (widget.canPop)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Quay lại'),
          ),
        const SizedBox(height: 40),
        const Text(
          'NHÓM 08 / CHẤM CÔNG NHÂN VIÊN',
          style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.5),
        ),
      ],
    ),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController();
  final password = TextEditingController();
  bool busy = false, obscure = true;
  String? error;
  @override
  void initState() {
    super.initState();
    username.text =
        context.read<Session>().rememberedAccount?['username']?.toString() ??
        '';
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await context.read<Session>().api.post('/auth/login', {
        'username': username.text.trim(),
        'password': password.text,
      });
      if (!mounted) return;
      password.clear();
      await openPage(context, OtpScreen(challenge: result));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> faceLogin() async {
    if (username.text.trim().isEmpty) {
      setState(() => error = 'Nhập tên đăng nhập trước khi chụp khuôn mặt.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final api = context.read<Session>().api;
      final image = await captureFace();
      if (image == null) return;
      final challenge = await api.post('/auth/face-login', {
        'username': username.text.trim(),
        'imageBase64': image,
      });
      if (mounted) await openPage(context, OtpScreen(challenge: challenge));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> biometricLogin() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await context.read<Session>().biometricLogin();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Chưa mở được bằng sinh trắc học. Thử lại hoặc đăng nhập bằng mật khẩu và OTP.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthFrame(
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandMark(),
          const SizedBox(height: 48),
          const Text(
            'MỖI NGÀY, ĐÚNG NHỊP.',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 2,
              color: blue,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Chào ngày mới.\nSẵn sàng vào ca?',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          const Text(
            'Đăng nhập an toàn với mật khẩu và mã xác thực qua email.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 32),
          if (context.watch<Session>().biometricEnabled) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : biometricLogin,
                icon: const Icon(Icons.fingerprint, size: 30),
                label: const Text('Đăng nhập bằng vân tay / khuôn mặt'),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Dùng tài khoản đã xác thực trên thiết bị này.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 24),
          ],
          TextFormField(
            controller: username,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(
              labelText: 'Tên đăng nhập',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Nhập tên đăng nhập' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: password,
            obscureText: obscure,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Mật khẩu',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () => setState(() => obscure = !obscure),
                tooltip: 'Hiện / ẩn mật khẩu',
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
            validator: (v) => v == null || v.isEmpty ? 'Nhập mật khẩu' : null,
            onFieldSubmitted: (_) => busy ? null : login(),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: BusyButton(
              busy: busy,
              onPressed: login,
              label: 'Tiếp tục với OTP',
            ),
          ),
          const SizedBox(height: 12),
          if (context.read<Session>().api.isShared)
            TextButton.icon(
              onPressed: busy ? null : faceLogin,
              icon: const Icon(Icons.face),
              label: const Text('Khuôn mặt và OTP'),
            ),
          Center(
            child: TextButton(
              onPressed: busy
                  ? null
                  : () => openPage(context, const RegisterScreen()),
              child: const Text('Chưa có tài khoản? Đăng ký'),
            ),
          ),
          if (context.read<Session>().api.isShared)
            Center(
              child: TextButton.icon(
                onPressed: () => openPage(context, const TranslationScreen()),
                icon: const Icon(Icons.translate),
                label: const Text('Dịch trực tiếp'),
              ),
            ),
          const SizedBox(height: 28),
          Center(
            child: TextButton.icon(
              onPressed: busy
                  ? null
                  : () => openPage(context, const SetupScreen(canPop: true)),
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text(
                'Cấu hình máy chủ',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final form = GlobalKey<FormState>();
  final fields = {
    for (final key in [
      'fullName',
      'username',
      'email',
      'password',
      'confirmPassword',
    ])
      key: TextEditingController(),
  };
  bool busy = false;
  String? error;
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final api = context.read<Session>().api;
      final body = fields.map(
        (k, v) => MapEntry(
          k,
          k.toLowerCase().contains('password') ? v.text : v.text.trim(),
        ),
      );
      if (api.isShared) body.remove('confirmPassword');
      final result = await api.post('/auth/register', body);
      if (!mounted) return;
      if (api.isShared) {
        await openPage(context, OtpScreen(challenge: result));
        return;
      }
      notice(context, 'Đăng ký thành công. Đăng nhập để nhận OTP.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tạo tài khoản')),
    body: PageBody(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle(
                'Bắt đầu cùng\nTRANDUYTAN',
                caption: 'Tài khoản mới được cấp quyền nhân viên.',
              ),
              for (final entry in const {
                'fullName': 'Họ và tên',
                'username': 'Tên đăng nhập',
                'email': 'Email',
                'password': 'Mật khẩu',
                'confirmPassword': 'Xác nhận mật khẩu',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                    controller: fields[entry.key],
                    obscureText: entry.key.toLowerCase().contains('password'),
                    keyboardType: entry.key == 'email'
                        ? TextInputType.emailAddress
                        : TextInputType.text,
                    decoration: InputDecoration(
                      labelText: entry.value,
                      helperText: entry.key == 'password'
                          ? (context.read<Session>().api.isShared
                                ? '10–128 ký tự'
                                : '10–72 byte, gồm chữ và số')
                          : null,
                    ),
                    validator: (value) {
                      final v = value ?? '';
                      if (v.trim().isEmpty) return 'Không được để trống';
                      if (entry.key == 'email' &&
                          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(v.trim())) {
                        return 'Email không hợp lệ';
                      }
                      if (entry.key == 'username' &&
                          !(context.read<Session>().api.isShared
                                  ? RegExp(r'^[a-z0-9][a-z0-9_.]{2,31}$')
                                  : RegExp(r'^[a-zA-Z0-9_.-]{3,50}$'))
                              .hasMatch(v)) {
                        return '3–32 ký tự thường, số, dấu _ hoặc .; bắt đầu bằng chữ hoặc số';
                      }
                      if (entry.key == 'password' &&
                          (v.length < 10 || v.length > 128)) {
                        return 'Mật khẩu cần 10–128 ký tự';
                      }
                      if (entry.key == 'confirmPassword' &&
                          v != fields['password']!.text) {
                        return 'Mật khẩu xác nhận không khớp';
                      }
                      return null;
                    },
                  ),
                ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              BusyButton(
                busy: busy,
                onPressed: submit,
                label: 'Đăng ký tài khoản',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class OtpScreen extends StatefulWidget {
  final Json challenge;
  const OtpScreen({super.key, required this.challenge});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final controller = TextEditingController();
  late Timer timer;
  late DateTime expires;
  late DateTime resendAt;
  int tick = 0, sends = 1;
  bool get shared => context.read<Session>().api.isShared;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    updateTiming(widget.challenge);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => tick++);
    });
  }

  void updateTiming(Json data) {
    expires =
        DateTime.tryParse(data['expiresAt']?.toString() ?? '') ??
        DateTime.now().add(
          Duration(seconds: (data['expiresIn'] as num?)?.toInt() ?? 300),
        );
    resendAt = DateTime.now().add(
      Duration(
        seconds:
            (data['retryAfterSeconds'] ?? data['resendAfter'] ?? 60) as int,
      ),
    );
  }

  @override
  void dispose() {
    timer.cancel();
    controller.dispose();
    super.dispose();
  }

  Future<void> verify() async {
    if (!RegExp(r'^\d{6}$').hasMatch(controller.text)) {
      setState(() => error = 'Nhập đủ 6 chữ số.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = context.read<Session>();
      final result = await session.api.post('/auth/verify-otp', {
        'challengeId': widget.challenge['challengeId'],
        shared ? 'code' : 'otp': controller.text,
      });
      await session.accept(result, freshLogin: true);
      if (mounted &&
          session.api.isShared &&
          !session.biometricEnabled &&
          await session.biometrics.available()) {
        if (!mounted) return;
        final enabled = await confirm(
          context,
          'Bật đăng nhập sinh trắc học?',
          'Lần sau mở app bằng vân tay hoặc khuôn mặt được Android hỗ trợ, không cần nhập lại OTP khi phiên còn hiệu lực. Mọi sinh trắc học đã đăng ký trên điện thoại đều có thể mở app.',
        );
        if (enabled) {
          try {
            await session.enableBiometrics();
          } catch (_) {
            if (mounted) {
              notice(
                context,
                'Chưa bật sinh trắc học. Bạn có thể bật lại trong Cài đặt.',
                error: true,
              );
            }
          }
        }
      }
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resend() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await context.read<Session>().api.post(
        '/auth/resend-otp',
        {'challengeId': widget.challenge['challengeId']},
      );
      if (mounted) {
        setState(() {
          sends++;
          controller.clear();
          updateTiming(result);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = expires
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, shared ? 600 : 300);
    final wait = resendAt.difference(DateTime.now()).inSeconds.clamp(0, 60);
    return Scaffold(
      appBar: AppBar(title: const Text('Xác thực email')),
      body: PageBody(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 30),
              const Icon(Icons.mark_email_read_outlined, size: 72, color: blue),
              const SizedBox(height: 28),
              const SectionTitle(
                'Một bước nữa thôi.',
                caption: 'Kiểm tra hộp thư và thư mục spam để lấy mã xác thực.',
              ),
              Text(
                widget.challenge['maskedEmail'].toString(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofillHints: const [AutofillHints.oneTimeCode],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 30, letterSpacing: 10),
                decoration: const InputDecoration(
                  labelText: 'Mã OTP',
                  counterText: '',
                ),
                onSubmitted: (_) => busy ? null : verify(),
              ),
              const SizedBox(height: 12),
              Text(
                'Mã còn hiệu lực ${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 26),
              BusyButton(
                busy: busy,
                onPressed: remaining > 0 ? verify : null,
                label: 'Xác thực và đăng nhập',
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: busy || wait > 0 || sends >= (shared ? 5 : 3)
                    ? null
                    : resend,
                child: Text(
                  sends >= (shared ? 5 : 3)
                      ? 'Đã hết lượt gửi lại'
                      : wait > 0
                      ? 'Gửi lại sau ${wait}s'
                      : 'Gửi lại OTP',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
