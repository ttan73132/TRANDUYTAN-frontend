import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/local_face.dart';

class FaceScanScreen extends StatefulWidget {
  final LocalFaceAccess access;
  final List<double>? reference;
  const FaceScanScreen({super.key, required this.access, this.reference});
  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen>
    with WidgetsBindingObserver {
  CameraController? camera;
  late FaceChallenge challenge;
  bool running = false, starting = false;
  bool foreground = true;
  String message = 'Chuẩn bị nhận diện trên điện thoại…';
  double? progress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(start());
  }

  @override
  void dispose() {
    running = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(camera?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) foreground = true;
    if (state == AppLifecycleState.paused) {
      foreground = false;
      running = false;
      final previous = camera;
      camera = null;
      unawaited(previous?.dispose());
      if (mounted) {
        setState(() => message = 'Đã dừng camera. Bấm thử lại để tiếp tục.');
      }
    }
  }

  Future<void> start() async {
    if (starting || running) return;
    starting = true;
    challenge = FaceChallenge(reference: widget.reference);
    try {
      await camera?.dispose();
      camera = null;
      final model = await widget.access.prepare((value) {
        if (mounted) {
          setState(() {
            progress = value;
            message = 'Tải gói nhận diện mặt 39 MB · ${(value * 100).round()}%';
          });
        }
      });
      if (!mounted || !foreground) return;
      final devices = await availableCameras();
      final front = devices
          .where((d) => d.lensDirection == CameraLensDirection.front)
          .firstOrNull;
      if (front == null) throw StateError('Thiết bị chưa có camera trước.');
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      camera = controller;
      await controller.initialize();
      if (!mounted || camera != controller) {
        await controller.dispose();
        return;
      }
      running = true;
      setState(() {
        progress = null;
        message = challenge.instruction;
      });
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (mounted && running && DateTime.now().isBefore(deadline)) {
        XFile? shot;
        try {
          shot = await controller.takePicture();
          final sample = await LocalFaceAccess.channel
              .invokeMapMethod<String, dynamic>('features', {
                'image': shot.path,
                'model': model,
              });
          if (!mounted || !running) break;
          final vector = List<num>.from(sample!['embedding'] as List);
          final completed = challenge.observe(
            vector,
            (sample['yaw'] as num).toDouble(),
          );
          if (completed != null) {
            running = false;
            if (mounted) Navigator.pop(context, completed);
            return;
          }
          setState(() => message = challenge.instruction);
        } catch (_) {
          if (mounted && running) {
            setState(
              () =>
                  message = 'Giữ mặt rõ và đủ sáng. ${challenge.instruction}.',
            );
          }
        } finally {
          if (shot != null) {
            final file = File(shot.path);
            if (await file.exists()) await file.delete();
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      if (mounted && running) {
        setState(
          () => message =
              'Chưa quét được. Thử lại ở nơi đủ sáng hoặc dùng vân tay.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Không mở được camera hoặc gói nhận diện. Kiểm tra quyền camera, mạng lần tải đầu và thử lại.',
        );
      }
    } finally {
      running = false;
      starting = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.reference == null
            ? 'Đăng ký khuôn mặt trên máy'
            : 'Quét mặt để đăng nhập',
      ),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (camera?.value.isInitialized == true)
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: CameraPreview(camera!),
              ),
            )
          else
            const SizedBox(
              height: 260,
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 20),
          if (progress != null) LinearProgressIndicator(value: progress),
          if (running && challenge.stage == 1)
            Icon(
              challenge.direction > 0 ? Icons.arrow_back : Icons.arrow_forward,
              size: 48,
            ),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          const Text(
            'Giữ một người trong khung hình. Mẫu mặt xử lý trên máy; camera 2D không bảo đảm chống ảnh/video giả.',
            textAlign: TextAlign.center,
          ),
          if (!running && !starting)
            TextButton(onPressed: start, child: const Text('Thử lại')),
        ],
      ),
    ),
  );
}
