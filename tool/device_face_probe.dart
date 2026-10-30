import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:tranduytan/services/local_face.dart';

// Diagnostics only: official fixed fixtures, never accounts or user media.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: FaceProbe()));
}

class FaceProbe extends StatefulWidget {
  const FaceProbe({super.key});
  @override
  State<FaceProbe> createState() => _FaceProbeState();
}

class _FaceProbeState extends State<FaceProbe> {
  final lines = <String>[];
  @override
  void initState() {
    super.initState();
    run();
  }

  void report(String line) {
    debugPrint('LOCAL_FACE_PROBE $line');
    if (mounted) setState(() => lines.add(line));
  }

  Future<void> run() async {
    try {
      final access = LocalFaceAccess();
      final model = await access.prepare((_) {});
      report('model SHA256 verified');
      final fixture = await http.get(
        Uri.parse(
          'https://media.githubusercontent.com/media/opencv/opencv_zoo/$faceModelRevision/models/face_recognition_sface/example_outputs/demo.jpg',
        ),
      );
      if (sha256.convert(fixture.bodyBytes).toString() !=
          '0f879881a598fea6fec74e047e6a1d00e36d81de63bf0ed392b628e6ab6c2fc4') {
        throw StateError('Fixture mismatch');
      }
      final codec = await ui.instantiateImageCodec(fixture.bodyBytes);
      final image = (await codec.getNextFrame()).image;
      final otherFixture = await http.get(
        Uri.parse(
          'https://raw.githubusercontent.com/opencv/opencv/4.12.0/samples/data/lena.jpg',
        ),
      );
      if (sha256.convert(otherFixture.bodyBytes).toString() !=
          '7de7ed51a1594fff247f4cae2301eceacf5313d6011e37b4a4c8733f7bb72c07') {
        throw StateError('Other fixture mismatch');
      }
      final otherCodec = await ui.instantiateImageCodec(otherFixture.bodyBytes);
      final otherImage = (await otherCodec.getNextFrame()).image;
      final folder = await getTemporaryDirectory();
      Future<List<double>> extract(
        String name,
        ui.Rect crop,
        double multiplier, [
        ui.Image? alternative,
      ]) async {
        report('extract $name');
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
          alternative ?? image,
          crop,
          ui.Rect.fromLTWH(
            0,
            0,
            crop.width * multiplier,
            crop.height * multiplier,
          ),
          ui.Paint(),
        );
        final picture = recorder.endRecording();
        final resized = await picture.toImage(
          (crop.width * multiplier).round(),
          (crop.height * multiplier).round(),
        );
        final bytes = await resized.toByteData(format: ui.ImageByteFormat.png);
        final file = File('${folder.path}/fixed-face-$name.png');
        try {
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          final result = await LocalFaceAccess.channel
              .invokeMapMethod<String, dynamic>('features', {
                'image': file.path,
                'model': model,
              });
          return normalizedFace(List<num>.from(result!['embedding'] as List));
        } finally {
          if (await file.exists()) await file.delete();
          resized.dispose();
          picture.dispose();
        }
      }

      final target = await extract(
        'target',
        const ui.Rect.fromLTWH(130, 0, 340, 370),
        2,
      );
      final same = await extract(
        'same',
        const ui.Rect.fromLTWH(867, 120, 145, 170),
        4,
      );
      report('same=${faceSimilarity(target, same)}');
      final different = await extract(
        'different',
        const ui.Rect.fromLTWH(0, 0, 512, 512),
        1,
        otherImage,
      );
      final positive = faceSimilarity(target, same),
          negative = faceSimilarity(target, different);
      report('same=$positive different=$negative dimensions=${target.length}');
      report(positive >= .5 && negative < .5 ? 'PASS' : 'FAIL');
      image.dispose();
      codec.dispose();
      otherImage.dispose();
      otherCodec.dispose();
    } catch (e) {
      report('FAIL $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(lines.join('\n')),
      ),
    ),
  );
}
