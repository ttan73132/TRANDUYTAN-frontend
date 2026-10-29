import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

TextRecognitionScript textScript(String language) => switch (language) {
  'zh' => TextRecognitionScript.chinese,
  'ja' => TextRecognitionScript.japanese,
  _ => TextRecognitionScript.latin,
};

class CameraTextStabilizer {
  final _readings = <String>[];
  String _latest = '', _published = '';
  DateTime? _windowSince, _publishedAt;

  String? add(String text, DateTime now) {
    _latest = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (_latest.isNotEmpty) {
      _windowSince ??= now;
      _readings.add(_latest);
      if (_readings.length > 5) _readings.removeAt(0);
    }
    if (_readings.isEmpty) return null;
    final elapsed = now.difference(_windowSince!).inMilliseconds;
    // A bounded window always progresses, even when every OCR reading differs.
    if (elapsed < 800 ||
        (_readings.length < 2 && elapsed < 1800) ||
        (_publishedAt != null &&
            now.difference(_publishedAt!).inMilliseconds < 2500)) {
      return null;
    }
    final counts = <String, int>{};
    for (final reading in _readings) {
      final key = reading.toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    String best = '';
    var bestScore = -1;
    for (final reading in _readings) {
      final key = reading.toLowerCase();
      final score =
          counts[key]! * 100000 +
          (key == _published ? 10000 : 0) +
          (reading.length > 9999 ? 9999 : reading.length);
      if (score > bestScore) {
        best = reading;
        bestScore = score;
      }
    }
    _readings.clear();
    _windowSince = null;
    if (best.toLowerCase() == _published) return null;
    _published = best.toLowerCase();
    _publishedAt = now;
    return best;
  }

  String? force(DateTime now) {
    if (_latest.isEmpty) return null;
    _published = _latest.toLowerCase();
    _publishedAt = now;
    _readings.clear();
    _windowSince = null;
    return _latest;
  }
}

int cameraRotation(int sensor, DeviceOrientation orientation, bool front) {
  final degrees = switch (orientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };
  return (sensor + (front ? degrees : -degrees) + 360) % 360;
}

Uint8List nv21Bytes(CameraImage image) {
  // CameraX converts requested NV21 into one plane, even on builds reporting YUV420.
  if (image.planes.length == 1) {
    final length = image.width * image.height * 3 ~/ 2;
    if (image.planes.first.bytes.length < length) {
      throw const FormatException('Khung hình camera không đủ dữ liệu.');
    }
    return Uint8List.sublistView(image.planes.first.bytes, 0, length);
  }
  if (image.planes.length != 3) {
    throw const FormatException('Camera không hỗ trợ khung hình YUV.');
  }
  final bytes = Uint8List(image.width * image.height * 3 ~/ 2);
  var offset = 0;
  final y = image.planes[0], u = image.planes[1], v = image.planes[2];
  for (var row = 0; row < image.height; row++) {
    for (var col = 0; col < image.width; col++) {
      bytes[offset++] =
          y.bytes[row * y.bytesPerRow + col * (y.bytesPerPixel ?? 1)];
    }
  }
  for (var row = 0; row < image.height ~/ 2; row++) {
    for (var col = 0; col < image.width ~/ 2; col++) {
      bytes[offset++] =
          v.bytes[row * v.bytesPerRow + col * (v.bytesPerPixel ?? 1)];
      bytes[offset++] =
          u.bytes[row * u.bytesPerRow + col * (u.bytesPerPixel ?? 1)];
    }
  }
  return bytes;
}

InputImage cameraInput(CameraImage image, CameraController controller) =>
    InputImage.fromBytes(
      bytes: nv21Bytes(image),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotationValue.fromRawValue(
          cameraRotation(
            controller.description.sensorOrientation,
            controller.value.deviceOrientation,
            controller.description.lensDirection == CameraLensDirection.front,
          ),
        )!,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width,
      ),
    );
