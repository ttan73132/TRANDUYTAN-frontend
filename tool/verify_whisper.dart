import 'dart:io';
import 'dart:ffi';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

// Usage: dart run tool/verify_whisper.dart MODEL_DIR WAV_PATH LANGUAGE [NATIVE_LIB_DIR]
void main(List<String> args) {
  if (args.length < 3) {
    throw ArgumentError('MODEL_DIR WAV_PATH LANGUAGE [NATIVE_LIB_DIR]');
  }
  if (Platform.isWindows && args.length > 3) {
    // Windows also ships an older ORT in System32; preload matching package DLL.
    DynamicLibrary.open('${args[3]}/onnxruntime.dll');
  }
  sherpa.initBindings(args.length > 3 ? args[3] : null);
  final folder = args[0];
  final recognizer = sherpa.OfflineRecognizer(
    args[2] == 'vi'
        ? sherpa.OfflineRecognizerConfig(
            model: sherpa.OfflineModelConfig(
              transducer: sherpa.OfflineTransducerModelConfig(
                encoder: '$folder/encoder.int8.onnx',
                decoder: '$folder/decoder.onnx',
                joiner: '$folder/joiner.int8.onnx',
              ),
              tokens: '$folder/tokens.txt',
              numThreads: 2,
            debug: false,
            ),
            decodingMethod: 'modified_beam_search',
            maxActivePaths: 4,
          )
        : sherpa.OfflineRecognizerConfig(
            model: sherpa.OfflineModelConfig(
              whisper: sherpa.OfflineWhisperModelConfig(
                encoder: '$folder/tiny-encoder.int8.onnx',
                decoder: '$folder/tiny-decoder.int8.onnx',
                language: args[2],
                task: 'transcribe',
                tailPaddings: 1000,
              ),
              tokens: '$folder/tiny-tokens.txt',
              modelType: 'whisper',
              numThreads: 2,
              debug: false,
            ),
          ),
  );
  final stream = recognizer.createStream();
  try {
    final wave = sherpa.readWave(args[1]);
    stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
    final watch = Stopwatch()..start();
    recognizer.decode(stream);
    final text = recognizer.getResult(stream).text.trim();
    stdout.writeln(
      'Local CPU: ${watch.elapsedMilliseconds} ms; transcript: $text',
    );
    if (text.isEmpty) throw StateError('No speech recognized');
  } finally {
    stream.free();
    recognizer.free();
  }
}
