import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../providers/session.dart';
import '../services/api.dart';
import '../services/location.dart';
import '../widgets/common.dart';
import 'records.dart';

class CheckFlowScreen extends StatefulWidget {
  final Json shift;
  final bool checkout;
  const CheckFlowScreen({
    super.key,
    required this.shift,
    required this.checkout,
  });
  @override
  State<CheckFlowScreen> createState() => _CheckFlowScreenState();
}

class _CheckFlowScreenState extends State<CheckFlowScreen> {
  Position? position;
  String? qrToken, error, sensorError;
  int step = 0, seconds = 30, peaks = 0;
  bool busy = false, finished = false;
  Json? result;
  Timer? timer;
  StreamSubscription<UserAccelerometerEvent>? sensor;
  DateTime? lastPeak;
  double get distance => position == null
      ? double.infinity
      : Geolocator.distanceBetween(
          position!.latitude,
          position!.longitude,
          (widget.shift['latitude'] as num).toDouble(),
          (widget.shift['longitude'] as num).toDouble(),
        );
  @override
  void dispose() {
    timer?.cancel();
    sensor?.cancel();
    super.dispose();
  }

  Future<void> locate() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final p = await currentLocation();
      if (!mounted) return;
      setState(() => position = p);
      if (distance > (widget.shift['allowed_radius'] as num)) {
        throw ApiException(
          'Bạn cách địa điểm ${distance.round()}m, ngoài bán kính cho phép ${widget.shift['allowed_radius']}m.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> scan() async {
    final code = await openPage<String>(context, const QrScannerScreen());
    if (code == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await context.read<Session>().api.post('/qr/verify', {
        'qrToken': code,
        'workplaceId': widget.shift['workplace_id'],
      });
      if (!mounted) return;
      setState(() {
        qrToken = code;
        step = 2;
      });
      startMotion();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void startMotion() {
    timer?.cancel();
    sensor?.cancel();
    seconds = 30;
    peaks = 0;
    lastPeak = null;
    sensorError = null;
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || finished) {
        t.cancel();
        return;
      }
      if (busy) return;
      setState(() => seconds = max(0, seconds - 1));
      if (seconds == 0) {
        t.cancel();
        sensor?.cancel();
        setState(
          () => sensorError =
              'Hết thời gian xác nhận. Bắt đầu lại hoặc dùng nút thay thế.',
        );
      }
    });
    try {
      sensor =
          userAccelerometerEventStream(
            samplingPeriod: SensorInterval.gameInterval,
          ).listen(
            (event) {
              if (!mounted || busy || finished || seconds <= 0 || step != 2) {
                return;
              }
              final magnitude = sqrt(
                event.x * event.x + event.y * event.y + event.z * event.z,
              );
              final now = DateTime.now();
              if (magnitude > 14 &&
                  (lastPeak == null ||
                      now.difference(lastPeak!).inMilliseconds > 250)) {
                if (lastPeak != null &&
                    now.difference(lastPeak!).inSeconds > 3) {
                  peaks = 0;
                }
                lastPeak = now;
                peaks++;
                if (peaks >= 2) submit('shake');
              }
            },
            onError: (Object e) {
              if (mounted) {
                setState(
                  () => sensorError =
                      'Không đọc được cảm biến. Dùng nút xác nhận bên dưới.',
                );
              }
            },
            cancelOnError: true,
          );
    } catch (_) {
      sensorError = 'Thiết bị không hỗ trợ cảm biến. Dùng nút xác nhận.';
    }
  }

  Future<void> submit(String method) async {
    if (busy || finished || qrToken == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    timer?.cancel();
    await sensor?.cancel();
    if (!mounted) return;
    try {
      final api = context.read<Session>().api;
      final fresh = await currentLocation();
      final response = await api.post(
        '/attendance/${widget.checkout ? 'check-out' : 'check-in'}',
        {
          'shiftId': widget.shift['id'],
          'qrToken': qrToken,
          'latitude': fresh.latitude,
          'longitude': fresh.longitude,
          'accuracy': fresh.accuracy,
          'motionMethod': method,
          'isMocked': fresh.isMocked,
        },
      );
      if (!mounted) return;
      setState(() {
        position = fresh;
        result = response;
        finished = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          step = 0;
          qrToken = null;
          position = null;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> share() async {
    if (position == null) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              'Vị trí của tôi: https://maps.google.com/?q=${position!.latitude},${position!.longitude}',
        ),
      );
    } catch (e) {
      if (mounted) notice(context, e, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid =
        position != null &&
        distance <= (widget.shift['allowed_radius'] as num) &&
        error == null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.checkout ? 'Check-out' : 'Check-in')),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (finished) ...[
              const SizedBox(height: 40),
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF087E63),
                size: 86,
              ),
              const SizedBox(height: 24),
              Text(
                widget.checkout ? 'Đã kết thúc ca.' : 'Check-in thành công!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Text(
                dateTime(
                  result![widget.checkout ? 'check_out_at' : 'check_in_at'],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (!widget.checkout && (result!['late_minutes'] as num) > 0) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          'Bạn đã đi muộn ${result!['late_minutes']} phút.',
                          style: const TextStyle(
                            color: Color(0xFFB42338),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Bản nháp giải trình đã được tạo. Bổ sung lý do để quản trị viên xem xét.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: () =>
                              openPage(context, const ExplanationScreen()),
                          child: const Text('Viết giải trình'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hoàn tất'),
              ),
            ] else ...[
              SectionTitle(
                widget.shift['name'],
                caption:
                    '${widget.shift['workplace_name']} · ${timeOnly(widget.shift['start_at'])} – ${timeOnly(widget.shift['end_at'])}',
              ),
              Row(
                children: [
                  for (int i = 0; i < 3; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Column(
                          children: [
                            Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: i <= step
                                    ? blue
                                    : const Color(0xFFDCE4F0),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              ['01 · GPS', '02 · QR', '03 · Xác nhận'][i],
                              style: TextStyle(
                                color: i <= step ? blue : muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              if (step == 0) ...[
                const Icon(Icons.my_location_rounded, size: 72, color: blue),
                const SizedBox(height: 24),
                Text(
                  'Bạn đang ở đâu?',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Bật GPS và cấp quyền vị trí. Máy chủ sẽ kiểm tra khoảng cách đến nơi làm việc.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        InfoLine(
                          'Bán kính',
                          '${widget.shift['allowed_radius']} m',
                        ),
                        if (position != null) ...[
                          InfoLine(
                            'Tọa độ',
                            '${position!.latitude.toStringAsFixed(6)}, ${position!.longitude.toStringAsFixed(6)}',
                          ),
                          InfoLine(
                            'Độ chính xác',
                            '±${position!.accuracy.round()} m',
                          ),
                          InfoLine('Khoảng cách', '${distance.round()} m'),
                          InfoLine(
                            'Trạng thái',
                            valid
                                ? 'Trong khu vực'
                                : 'Ngoài khu vực / cần thử lại',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                BusyButton(
                  busy: busy,
                  onPressed: locate,
                  label: position == null
                      ? 'Lấy vị trí GPS'
                      : 'Cập nhật vị trí',
                  icon: Icons.my_location,
                ),
                if (position != null)
                  TextButton.icon(
                    onPressed: busy ? null : share,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share My Location'),
                  ),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: () => Geolocator.openLocationSettings(),
                      child: const Text('Cài đặt GPS'),
                    ),
                    TextButton(
                      onPressed: () => Geolocator.openAppSettings(),
                      child: const Text('Quyền ứng dụng'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: valid && !busy
                      ? () => setState(() => step = 1)
                      : null,
                  child: const Text('Tiếp tục quét QR'),
                ),
              ],
              if (step == 1) ...[
                const Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 80,
                  color: blue,
                ),
                const SizedBox(height: 24),
                Text(
                  'Quét mã tại nơi làm việc.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Yêu cầu quản trị viên hiển thị mã QR mới. Mã có thời hạn 90 giây và phải khớp địa điểm của ca.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 28),
                BusyButton(
                  busy: busy,
                  onPressed: scan,
                  label: 'Mở camera quét QR',
                  icon: Icons.camera_alt_outlined,
                ),
                TextButton(
                  onPressed: busy ? null : () => setState(() => step = 0),
                  child: const Text('Quay lại GPS'),
                ),
              ],
              if (step == 2) ...[
                const Icon(Icons.vibration_rounded, size: 90, color: blue),
                const SizedBox(height: 24),
                Text(
                  'Lắc nhẹ, xác nhận ca.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Lắc điện thoại hai lần để xác nhận thao tác. Giữ chắc thiết bị. App sẽ gửi chấm công một lần.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 22),
                Text(
                  '$seconds',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 64,
                    color: blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Text(
                  'GIÂY XÁC NHẬN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    letterSpacing: 2,
                    fontSize: 10,
                    color: muted,
                  ),
                ),
                if (sensorError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Text(sensorError!, textAlign: TextAlign.center),
                  ),
                const SizedBox(height: 24),
                BusyButton(
                  busy: busy,
                  onPressed: () => submit('manual'),
                  label: widget.checkout
                      ? 'Xác nhận check-out bằng nút'
                      : 'Xác nhận check-in bằng nút',
                  icon: Icons.touch_app_outlined,
                ),
                if (seconds == 0)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            setState(startMotion);
                          },
                    child: const Text('Thử lại cảm biến'),
                  ),
                const SizedBox(height: 14),
                const Text(
                  'Nút thay thế dành cho thiết bị không có cảm biến hoặc người dùng khó thực hiện thao tác lắc.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Color(0xFFB42338)),
                  ),
                ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: 18),
                  child: Text(
                    'Đang xác nhận, vui lòng chờ…',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});
  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with WidgetsBindingObserver {
  final controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool captured = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!controller.value.hasCameraPermission) return;
    if (state == AppLifecycleState.resumed && !captured) {
      controller.start();
    } else if (state == AppLifecycleState.inactive) {
      controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: navy,
    appBar: AppBar(
      title: const Text('Quét QR chấm công'),
      actions: [
        IconButton(
          onPressed: () => controller.toggleTorch(),
          tooltip: 'Đèn pin',
          icon: const Icon(Icons.flash_on),
        ),
        IconButton(
          onPressed: () => controller.switchCamera(),
          tooltip: 'Đổi camera',
          icon: const Icon(Icons.cameraswitch_outlined),
        ),
      ],
    ),
    body: Stack(
      children: [
        MobileScanner(
          controller: controller,
          onDetect: (capture) {
            if (captured) return;
            final codes = capture.barcodes.where((b) => b.rawValue != null);
            if (codes.isEmpty) return;
            captured = true;
            controller.stop();
            Navigator.pop(context, codes.first.rawValue);
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.no_photography_outlined,
                    size: 54,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Không mở được camera. Kiểm tra quyền camera trong cài đặt ứng dụng.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Geolocator.openAppSettings(),
                    child: const Text('Mở cài đặt'),
                  ),
                  TextButton(
                    onPressed: () {
                      controller.stop();
                      controller.start();
                    },
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
        const Positioned(
          bottom: 50,
          left: 24,
          right: 24,
          child: Text(
            'Đặt mã QR vào khung.\nỨng dụng sẽ tự nhận diện một lần.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, height: 1.8),
          ),
        ),
      ],
    ),
  );
}
