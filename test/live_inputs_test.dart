import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:tranduytan/services/camera_text.dart';
import 'package:tranduytan/services/offline_speech.dart';

Uint8List pcm(int count, {bool silent = false}) {
  final bytes = ByteData(count * 2);
  for (var i = 0; i < count; i++) {
    bytes.setInt16(
      i * 2,
      silent ? 0 : (sin(i * 0.1) * 8000).round(),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}

void main() {
  test(
    'Vietnamese uses dedicated model; other languages keep cached Whisper',
    () {
      final vi = SpeechModels(language: 'vi');
      expect(vi.files.containsKey('encoder.int8.onnx'), true);
      expect(
        vi.files.values.fold<int>(0, (sum, spec) => sum + spec.$1),
        34188908,
      );
      final config = speechRecognizerConfig('/models', 'vi');
      expect(config.model.transducer.encoder, '/models/encoder.int8.onnx');
      expect(config.decodingMethod, 'modified_beam_search');
      for (final language in ['en', 'zh', 'ja']) {
        expect(SpeechModels(language: language).revision, speechModelRevision);
        expect(
          speechRecognizerConfig('/models', language).model.whisper.language,
          language,
        );
      }
      vi.close();
    },
  );

  test('quiet word onset retained and short pause does not split sentence', () {
    final segments = SpeechSegments();
    final quiet = ByteData(3200 * 2);
    for (var i = 0; i < 3200; i++) {
      quiet.setInt16(i * 2, 100, Endian.little);
    }
    segments.add(quiet.buffer.asUint8List());
    segments.add(pcm(8000));
    expect(segments.add(pcm(12800, silent: true)), isNull);
    segments.add(pcm(8000));
    final chunk = segments.flush()!;
    expect(chunk.samples.length, 32000);
    expect(chunk.samples.first, closeTo(100 / 32768, 0.0001));
  });
  test(
    'one readable camera frame still produces output after blank frames',
    () {
      final stable = CameraTextStabilizer();
      final start = DateTime(2026);
      expect(stable.add('Exit 1', start), isNull);
      expect(
        stable.add('', start.add(const Duration(milliseconds: 900))),
        isNull,
      );
      expect(
        stable.add('', start.add(const Duration(milliseconds: 1800))),
        'Exit 1',
      );
    },
  );

  test(
    'manual camera translation bypasses the window using last read text',
    () {
      final stable = CameraTextStabilizer();
      final start = DateTime(2026);
      stable.add('Gate 1.5', start);
      expect(stable.force(start), 'Gate 1.5');
      stable.add('Gate 15', start.add(const Duration(milliseconds: 100)));
      expect(
        stable.force(start.add(const Duration(milliseconds: 100))),
        'Gate 15',
      );
      stable.add('', start.add(const Duration(milliseconds: 200)));
      expect(
        stable.force(start.add(const Duration(milliseconds: 200))),
        isNull,
      );
    },
  );

  test('camera returns text even when successive OCR readings differ', () {
    final stable = CameraTextStabilizer();
    final start = DateTime(2026);
    expect(stable.add('Hello world', start), isNull);
    expect(
      stable.add('Hello wor1d', start.add(const Duration(milliseconds: 900))),
      'Hello world',
    );
    expect(
      stable.add('Hello world', start.add(const Duration(milliseconds: 1800))),
      isNull,
    );
    expect(
      stable.add('Hello world', start.add(const Duration(milliseconds: 2700))),
      isNull,
    );
    expect(
      stable.add(
        'HELLO\n world',
        start.add(const Duration(milliseconds: 3600)),
      ),
      isNull,
    );
  });

  test(
    'camera keeps result readable and preserves meaningful number changes',
    () {
      final stable = CameraTextStabilizer();
      final start = DateTime(2026);
      stable.add('Qty 1.5', start);
      expect(
        stable.add('Qty 1.5', start.add(const Duration(milliseconds: 900))),
        'Qty 1.5',
      );
      expect(
        stable.add('Qty 15', start.add(const Duration(milliseconds: 1800))),
        isNull,
      );
      expect(
        stable.add('Qty 15', start.add(const Duration(milliseconds: 2700))),
        isNull,
      );
      expect(
        stable.add('Qty 15', start.add(const Duration(milliseconds: 3600))),
        'Qty 15',
      );
    },
  );

  test('OCR selects CJK recognizers and computes rotation for both lenses', () {
    expect(textScript('vi'), TextRecognitionScript.latin);
    expect(textScript('en'), TextRecognitionScript.latin);
    expect(textScript('zh'), TextRecognitionScript.chinese);
    expect(textScript('ja'), TextRecognitionScript.japanese);
    expect(cameraRotation(90, DeviceOrientation.portraitUp, false), 90);
    expect(cameraRotation(90, DeviceOrientation.landscapeLeft, false), 0);
    expect(cameraRotation(90, DeviceOrientation.landscapeRight, false), 180);
    expect(cameraRotation(270, DeviceOrientation.landscapeLeft, true), 0);
  });

  test('CameraX single NV21 plane accepted even if format reports YUV420', () {
    final image = CameraImage.fromPlatformInterface(
      CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
        width: 4,
        height: 2,
        planes: [
          CameraImagePlane(
            bytes: Uint8List.fromList(List.generate(12, (i) => i)),
            bytesPerRow: 4,
          ),
        ],
      ),
    );
    expect(nv21Bytes(image), List.generate(12, (i) => i));
  });

  test('YUV planes remove row padding and interleave VU with pixel stride', () {
    final image = CameraImage.fromPlatformInterface(
      CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
        width: 4,
        height: 2,
        planes: [
          CameraImagePlane(
            bytes: Uint8List.fromList([1, 2, 3, 4, 99, 99, 5, 6, 7, 8]),
            bytesPerRow: 6,
            bytesPerPixel: 1,
          ),
          CameraImagePlane(
            bytes: Uint8List.fromList([10, 99, 20]),
            bytesPerRow: 4,
            bytesPerPixel: 2,
          ),
          CameraImagePlane(
            bytes: Uint8List.fromList([30, 99, 40]),
            bytesPerRow: 4,
            bytesPerPixel: 2,
          ),
        ],
      ),
    );
    expect(nv21Bytes(image), [1, 2, 3, 4, 5, 6, 7, 8, 30, 10, 40, 20]);
  });

  test('Silent microphone produces no inference requests', () {
    final segments = SpeechSegments();
    for (var i = 0; i < 100; i++) {
      expect(segments.add(pcm(1600, silent: true)), isNull);
    }
    expect(segments.flush(), isNull);
  });

  test('Speech emits partial updates and final on silence without splitting words every packet', () {
    final segments = SpeechSegments();
    SpeechChunk? partial;
    for (var i = 0; i < 30; i++) {
      partial = segments.add(pcm(1600)) ?? partial;
    }
    expect(partial!.finalResult, false);
    expect(partial.samples.length, 48000);
    SpeechChunk? last;
    for (var i = 0; i < 10; i++) {
      last = segments.add(pcm(1600, silent: true)) ?? last;
    }
    expect(last!.finalResult, true);
    expect(last.segment, partial.segment);
    expect(last.samples.length, 64000);
    expect(segments.flush(), isNull);
    segments.add(pcm(8000));
    expect(segments.flush()!.segment, last.segment + 2);
  });

  test(
    'Long utterances are bounded at ten seconds; stop flushes short phrase',
    () {
      final segments = SpeechSegments();
      final chunks = <SpeechChunk>[];
      for (var i = 0; i < 100; i++) {
        final chunk = segments.add(pcm(1600));
        if (chunk != null) chunks.add(chunk);
      }
      expect(chunks.last.finalResult, true);
      expect(chunks.last.samples.length, 160000);
      segments.add(pcm(8000));
      expect(segments.flush()!.samples.length, 8000);
    },
  );

  test('PCM conversion handles packet boundary inside 16-bit sample', () {
    final segments = SpeechSegments();
    final bytes = pcm(8000);
    segments.add(Uint8List.sublistView(bytes, 0, 1001));
    segments.add(Uint8List.sublistView(bytes, 1001));
    final result = segments.flush()!;
    expect(result.samples.length, 8000);
    expect(result.samples[1000], closeTo(sin(100) * 8000 / 32768, 0.0001));
  });
}
