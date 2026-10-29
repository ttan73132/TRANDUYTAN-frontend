import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tranduytan/widgets/camera_translation.dart';

class TestCamera extends CameraPlatform {
  int created = 0, disposed = 0, streamsStopped = 0;
  final frames = StreamController<CameraImageData>.broadcast();
  final errors = StreamController<CameraErrorEvent>.broadcast();
  TestCamera() {
    frames.onCancel = () => streamsStopped++;
  }
  @override
  Future<List<CameraDescription>> availableCameras() async => [
    const CameraDescription(
      name: 'rear',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];
  @override
  Future<int> createCameraWithSettings(
    CameraDescription camera,
    MediaSettings settings,
  ) async {
    expect(settings.enableAudio, false);
    return ++created;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    expect(imageFormatGroup, ImageFormatGroup.nv21);
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          640,
          480,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => errors.stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  bool supportsImageStreaming() => true;
  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) => frames.stream;
  @override
  Widget buildPreview(int cameraId) => const SizedBox();
  @override
  Future<void> dispose(int cameraId) async {
    disposed++;
  }

  void frame() => frames.add(
    CameraImageData(
      format: const CameraImageFormat(ImageFormatGroup.nv21, raw: 17),
      width: 4,
      height: 2,
      planes: [CameraImagePlane(bytes: Uint8List(12), bytesPerRow: 4)],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('google_mlkit_text_recognizer');

  testWidgets(
    'camera starts on tap, translates current reading on request, stops in background',
    (tester) async {
      final original = CameraPlatform.instance;
      final camera = TestCamera();
      CameraPlatform.instance = camera;
      final text = <String>[];
      var closed = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'vision#closeTextRecognizer') {
          closed++;
          return null;
        }
        return {'text': 'Hello', 'blocks': []};
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CameraTranslation(
              language: 'en',
              enabled: true,
              onText: text.add,
            ),
          ),
        ),
      );
      expect(camera.created, 0);
      await tester.tap(find.text('Bật camera dịch chữ'));
      await tester.pumpAndSettle();
      expect(camera.created, 1);
      camera.frame();
      await tester.pumpAndSettle();
      expect(text, isEmpty);
      await tester.tap(find.text('Dịch ngay chữ vừa đọc'));
      await tester.pumpAndSettle();
      expect(text, ['Hello']);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 950)),
      );
      camera.frame();
      await tester.pumpAndSettle();
      expect(text, ['Hello']);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 950)),
      );
      camera.frame();
      await tester.pumpAndSettle();
      expect(text, ['Hello']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(camera.streamsStopped, 1);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(camera.disposed, 1);
      expect(closed, 1);
      await tester.pumpWidget(const SizedBox());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      CameraPlatform.instance = original;
    },
  );

  testWidgets('leaving camera waits for OCR and discards its late text', (
    tester,
  ) async {
    final original = CameraPlatform.instance;
    final camera = TestCamera();
    CameraPlatform.instance = camera;
    final pending = Completer<Map<String, dynamic>>();
    final text = <String>[];
    var calls = 0, closed = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'vision#closeTextRecognizer') {
        closed++;
        return null;
      }
      calls++;
      return pending.future;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraTranslation(
            language: 'ja',
            enabled: true,
            onText: text.add,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Bật camera dịch chữ'));
    await tester.pumpAndSettle();
    camera.frame();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    camera.frame();
    await tester.pump();
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    expect(camera.disposed, 0);
    pending.complete({'text': '遅い結果', 'blocks': []});
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(text, isEmpty);
    expect(camera.disposed, 1);
    expect(closed, 1);
    CameraPlatform.instance = original;
  });
}
