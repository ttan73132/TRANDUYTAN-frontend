import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../services/camera_text.dart';

class CameraTranslation extends StatefulWidget {
  final String language;
  final bool enabled;
  final ValueChanged<String> onText;
  const CameraTranslation({
    super.key,
    required this.language,
    required this.enabled,
    required this.onText,
  });

  @override
  State<CameraTranslation> createState() => _CameraTranslationState();
}

class _CameraTranslationState extends State<CameraTranslation>
    with WidgetsBindingObserver {
  CameraController? _camera;
  TextRecognizer? _recognizer;
  Future<void>? _recognizing;
  Future<void>? _stopping;
  bool _starting = false;
  bool _closed = false;
  int _generation = 0;
  String? _error;
  CameraTextStabilizer _stableText = CameraTextStabilizer();
  DateTime _lastFrame = DateTime(2000);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(CameraTranslation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language || !widget.enabled) {
      unawaited(_stop());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_stop());
    }
  }

  Future<void> _start() async {
    if (_starting || _stopping != null || _camera != null || !widget.enabled) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _starting = true;
      _error = null;
      _stableText = CameraTextStabilizer();
    });
    CameraController? camera;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('Máy không có camera.');
      if (!mounted || generation != _generation) return;
      final rear = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      camera = CameraController(
        rear.isEmpty ? cameras.first : rear.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await camera.initialize();
      if (!mounted || generation != _generation) {
        await camera.dispose();
        return;
      }
      _recognizer = TextRecognizer(script: textScript(widget.language));
      _camera = camera;
      await camera.startImageStream((image) {
        if (_recognizing != null ||
            generation != _generation ||
            DateTime.now().difference(_lastFrame).inMilliseconds < 900) {
          return;
        }
        _lastFrame = DateTime.now();
        _recognizing = _read(image, camera!, generation).whenComplete(() {
          _recognizing = null;
        });
      });
    } catch (e) {
      if (camera != _camera) await camera?.dispose();
      if (mounted && generation == _generation) {
        setState(
          () => _error = e is CameraException
              ? 'Không mở được camera. Cho phép Camera trong cài đặt ứng dụng rồi thử lại. (${e.code})'
              : e.toString(),
        );
        await _stop();
      }
    } finally {
      if (!_closed) {
        setState(() => _starting = false);
      }
    }
  }

  Future<void> _read(
    CameraImage image,
    CameraController camera,
    int generation,
  ) async {
    try {
      final result = await _recognizer!.processImage(
        cameraInput(image, camera),
      );
      if (!mounted || generation != _generation) return;
      if (_error != null && result.text.trim().isNotEmpty) {
        setState(() => _error = null);
      }
      final text = _stableText.add(result.text, DateTime.now());
      if (text != null) {
        widget.onText(text);
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = 'Chưa đọc được chữ. Giữ máy ổn định, đủ sáng. $e',
        );
      }
    }
  }

  Future<void> _stop() => _stopping ??= _release()
      .catchError((Object error) {
        if (!_closed) setState(() => _error = 'Đã ngừng camera: $error');
      })
      .whenComplete(() {
        _stopping = null;
        if (!_closed) setState(() {});
      });

  Future<void> _release() async {
    ++_generation;
    final camera = _camera;
    final recognizer = _recognizer;
    _camera = null;
    _recognizer = null;
    if (!_closed) setState(() {});
    try {
      if (camera?.value.isStreamingImages ?? false) {
        await camera!.stopImageStream();
      }
      await _recognizing;
    } finally {
      try {
        await camera?.dispose();
      } finally {
        await recognizer?.close();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 240,
          child: ColoredBox(
            color: const Color(0xFF102238),
            child: _camera != null && _camera!.value.isInitialized
                ? CameraPreview(_camera!)
                : const Center(
                    child: Icon(
                      Icons.document_scanner_outlined,
                      color: Colors.white70,
                      size: 64,
                    ),
                  ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: !widget.enabled || _starting || _stopping != null
            ? null
            : _camera == null
            ? _start
            : _stop,
        icon: Icon(
          _camera == null
              ? Icons.camera_alt_outlined
              : Icons.stop_circle_outlined,
        ),
        label: Text(
          _starting
              ? 'Đang mở camera…'
              : _camera == null
              ? 'Bật camera dịch chữ'
              : 'Dừng camera',
        ),
      ),
      if (_camera != null)
        OutlinedButton.icon(
          onPressed: _starting || _stopping != null
              ? null
              : () {
                  final text = _stableText.force(DateTime.now());
                  if (text == null) {
                    setState(
                      () => _error = 'Chưa đọc được chữ. Đưa máy gần hơn, đủ sáng và chọn đúng ngôn ngữ gốc.',
                    );
                  } else {
                    widget.onText(text);
                  }
                },
          icon: const Icon(Icons.translate),
          label: const Text('Dịch ngay chữ vừa đọc'),
        ),
      const Text(
        'Giữ máy 1–2 giây; app chọn chữ từ vài khung để dịch. Có thể bấm Dịch ngay chữ vừa đọc, hoặc Dừng camera để giữ kết quả. Ảnh không gửi lên mạng.',
      ),
      if (_error != null)
        Text(_error!, style: const TextStyle(color: Colors.red)),
    ],
  );
}
