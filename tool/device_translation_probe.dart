import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'package:tranduytan/services/camera_text.dart';
import 'package:tranduytan/services/offline_speech.dart';

// Test entry point only: downloads fixed fixtures, never user media or accounts.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _Probe()));
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final results = <String>[];
  @override
  void initState() {
    super.initState();
    run();
  }

  void report(String line) {
    // Only fixed test fixture content is logged, never user input or credentials.
    debugPrint('TRANSLATION_PROBE $line');
    if (mounted) setState(() => results.add(line));
  }

  Future<void> run() async {
    final models = SpeechModels();
    final decoder = WhisperDecoder();
    try {
      for (final entry in {
        'en': 'Hello 123',
        'zh': '你好世界',
        'ja': 'こんにちは',
      }.entries) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(Colors.white, BlendMode.src);
        final text = TextPainter(
          text: TextSpan(
            text: entry.value,
            style: const TextStyle(fontSize: 80, color: Colors.black),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 1100);
        text.paint(canvas, const Offset(40, 50));
        final picture = recorder.endRecording();
        final image = await picture.toImage(1200, 220);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          '${(await getTemporaryDirectory()).path}/ocr-probe-${entry.key}.png',
        );
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        final recognizer = TextRecognizer(script: textScript(entry.key));
        try {
          final result = await recognizer.processImage(
            InputImage.fromFilePath(file.path),
          );
          report('OCR ${entry.key}: ${result.text}');
          if (!result.text
              .replaceAll(RegExp(r'\s'), '')
              .contains(entry.value.replaceAll(' ', ''))) {
            throw StateError('OCR mismatch ${entry.key}');
          }
        } finally {
          await recognizer.close();
          await file.delete();
          text.dispose();
          image.dispose();
          picture.dispose();
        }
      }
      final folder = await models.directory();
      report('Model folder: ${folder.path}');
      for (final name in speechModelFiles.keys) {
        final file = File('${folder.path}/$name');
        report(
          '$name exists=${await file.exists()} bytes=${await file.exists() ? await file.length() : 0}',
        );
      }
      if (!await models.installed()) {
        var last = -1;
        await models.download((progress) {
          final percent = (progress * 100).floor();
          if (percent ~/ 10 != last) {
            last = percent ~/ 10;
            report('Fixture model download $percent%');
          }
        });
        if (!await models.installed()) {
          throw StateError('Whisper fixture models missing');
        }
      }
      final fixture = File('${folder.path}/english.wav');
      if (!await fixture.exists()) {
        final response = await http.get(
          Uri.parse(
            'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/$speechModelRevision/test_wavs/1.wav',
          ),
        );
        if (response.statusCode != 200) {
          throw StateError('Fixture download failed');
        }
        await fixture.writeAsBytes(response.bodyBytes);
      }
      models.close();
      sherpa.initBindings();
      final wave = sherpa.readWave(fixture.path);
      final loading = Stopwatch()..start();
      await decoder.open(folder.path, 'en');
      report('Whisper model loaded ${loading.elapsedMilliseconds} ms');
      final watch = Stopwatch()..start();
      final text = await decoder.decode(wave.samples);
      report('Whisper CPU ${watch.elapsedMilliseconds} ms: $text');
      if (!text.toLowerCase().contains('consequence')) {
        throw StateError('Whisper fixture mismatch');
      }
      final viModels = SpeechModels(language: 'vi');
      final viDecoder = WhisperDecoder();
      try {
        if (!await viModels.installed()) {
          await viModels.download((_) {});
        }
        final viFolder = await viModels.directory();
        final viFixture = File('${viFolder.path}/vietnamese.wav');
        if (!await viFixture.exists()) {
          final response = await http.get(
            Uri.parse(
              'https://huggingface.co/${viModels.repository}/resolve/${viModels.revision}/test_wavs/0.wav',
            ),
          );
          if (response.statusCode != 200) {
            throw StateError('Vietnamese fixture download failed');
          }
          await viFixture.writeAsBytes(response.bodyBytes);
        }
        final viWave = sherpa.readWave(viFixture.path);
        await viDecoder.open(viFolder.path, 'vi');
        final viWatch = Stopwatch()..start();
        final viText = await viDecoder.decode(viWave.samples);
        report(
          'Vietnamese Zipformer CPU ${viWatch.elapsedMilliseconds} ms: $viText',
        );
        if (viText.isEmpty) throw StateError('Vietnamese fixture empty');
      } finally {
        viModels.close();
        await viDecoder.close();
      }
      report(
        'PASS: native OCR en/zh/ja + Whisper + Vietnamese Zipformer on Android',
      );
    } catch (e) {
      report('FAIL: $e');
    } finally {
      models.close();
      await decoder.close();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('TRANDUYTAN · Native test')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: SelectableText(results.join('\n\n')),
    ),
  );
}
