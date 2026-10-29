import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const speechModelRevision = '65176e2deb88badc814a94058666cadccc29b61c';
const speechModelFiles = <String, (int, String)>{
  'tiny-encoder.int8.onnx': (
    12937772,
    'd24fb083ae3b1041fc24e97971d60e280c9342201fbb67b0ab428a8b4a51a434',
  ),
  'tiny-decoder.int8.onnx': (
    89855401,
    'd2fece8dd42771f1df975c6c0445770d0c292bf7547c2cae04a6c0cc57540925',
  ),
  'tiny-tokens.txt': (
    816730,
    'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
  ),
};

const vietnameseModelRevision = '83e140db6d23fbb8480fd5fb868f74ab80e7092c';
const vietnameseModelFiles = <String, (int, String)>{
  'encoder.int8.onnx': (
    27699063,
    '8ef5286dd427eb108055c2ddc1982aa31e544706072d5ea228729292dacade68',
  ),
  'decoder.onnx': (
    5165084,
    'cf2aa385b82c9d5d40cd29c3188af52d0249b3b78f0d4b7eb84ad502d50c7e7f',
  ),
  'joiner.int8.onnx': (
    1033417,
    '7311d2e17b810ecea515d79c71cc4668af8759256a06fa01d27047772320c821',
  ),
  'tokens.txt': (
    23238,
    'ca8171f8bbd516c050b627582f2125c8f5f1f6ed967ab41b0fa9aae2cf61b492',
  ),
  'bpe.model': (
    268106,
    '002894e7a82d80ffa5e25008ec8c5496159db804005e2103de96b01b4c13d445',
  ),
};

class SpeechModels {
  final String language;
  SpeechModels({this.language = 'en'});
  bool get vietnamese => language == 'vi';
  String get name => vietnamese ? 'Zipformer tiếng Việt' : 'Whisper Tiny';
  int get megabytes => vietnamese ? 35 : 104;
  String get revision =>
      vietnamese ? vietnameseModelRevision : speechModelRevision;
  String get repository => vietnamese
      ? 'csukuangfj2/sherpa-onnx-zipformer-vi-30M-int8-2026-02-09'
      : 'csukuangfj/sherpa-onnx-whisper-tiny';
  Map<String, (int, String)> get files =>
      vietnamese ? vietnameseModelFiles : speechModelFiles;
  final http.Client _client = http.Client();
  bool _closed = false;

  Future<Directory> directory() async {
    final base = await getApplicationSupportDirectory();
    final prefix = vietnamese ? 'zipformer-vi' : 'whisper-tiny';
    return Directory('${base.path}/$prefix-$revision').create(recursive: true);
  }

  Future<bool> _valid(File file, (int, String) spec) async =>
      await file.exists() &&
      await file.length() == spec.$1 &&
      (await sha256.bind(file.openRead()).first).toString() == spec.$2;

  Future<bool> installed() async {
    final folder = await directory();
    for (final file in files.entries) {
      if (!await _valid(File('${folder.path}/${file.key}'), file.value)) {
        return false;
      }
    }
    return true;
  }

  Future<void> download(void Function(double) progress) async {
    final folder = await directory();
    final total = files.values.fold<int>(0, (sum, file) => sum + file.$1);
    var completed = 0;
    for (final entry in files.entries) {
      if (_closed) throw StateError('Đã hủy tải mô hình.');
      final file = File('${folder.path}/${entry.key}');
      if (await _valid(file, entry.value)) {
        completed += entry.value.$1;
        progress(completed / total);
        continue;
      }
      final partial = File('${file.path}.part');
      IOSink? sink;
      try {
        final response = await _client
            .send(
              http.Request(
                'GET',
                Uri.parse(
                  'https://huggingface.co/$repository/resolve/$revision/${entry.key}',
                ),
              ),
            )
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw HttpException('Tải mô hình lỗi HTTP ${response.statusCode}');
        }
        sink = partial.openWrite();
        var received = 0;
        await for (final bytes in response.stream.timeout(
          const Duration(seconds: 30),
        )) {
          if (_closed) throw StateError('Đã hủy tải mô hình.');
          received += bytes.length;
          if (received > entry.value.$1) {
            throw const FormatException('Sai kích thước mô hình.');
          }
          sink.add(bytes);
          progress((completed + received) / total);
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (!await _valid(partial, entry.value)) {
          throw const FormatException(
            'Mô hình tải thiếu hoặc sai SHA-256. Thử tải lại.',
          );
        }
        if (await file.exists()) await file.delete();
        await partial.rename(file.path);
        completed += entry.value.$1;
      } finally {
        await sink?.close();
        if (await partial.exists()) await partial.delete();
      }
    }
  }

  void close() {
    _closed = true;
    _client.close();
  }
}

abstract class SpeechDecoder {
  Future<void> open(String folder, String language);
  Future<String> decode(Float32List samples);
  Future<void> close();
}

sherpa.OfflineRecognizerConfig speechRecognizerConfig(
  String folder,
  String language,
) {
  if (language == 'vi') {
    return sherpa.OfflineRecognizerConfig(
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
    );
  }
  return sherpa.OfflineRecognizerConfig(
    model: sherpa.OfflineModelConfig(
      whisper: sherpa.OfflineWhisperModelConfig(
        encoder: '$folder/tiny-encoder.int8.onnx',
        decoder: '$folder/tiny-decoder.int8.onnx',
        language: language,
        task: 'transcribe',
        tailPaddings: 1000,
      ),
      tokens: '$folder/tiny-tokens.txt',
      modelType: 'whisper',
      numThreads: 2,
      debug: false,
    ),
  );
}

// Native inference runs on a separate isolate so camera/UI never waits on CPU work.
class WhisperDecoder implements SpeechDecoder {
  ReceivePort? _events;
  SendPort? _commands;
  final _pending = <int, Completer<String>>{};
  int _sequence = 0;
  bool _closed = false;

  @override
  Future<void> open(String folder, String language) async {
    final ready = Completer<void>();
    final events = ReceivePort();
    _events = events;
    events.listen((dynamic message) {
      if (message is SendPort) {
        if (_closed) {
          message.send(null);
          events.close();
          if (!ready.isCompleted) {
            ready.completeError(StateError('Đã dừng nhận dạng.'));
          }
          return;
        }
        _commands = message;
        ready.complete();
      } else if (message is Map) {
        if (message['id'] == null) {
          if (!ready.isCompleted) {
            ready.completeError(StateError('${message['error']}'));
          }
        } else {
          final completer = _pending.remove(message['id']);
          if (message['error'] != null) {
            completer?.completeError(StateError('${message['error']}'));
          } else {
            completer?.complete('${message['text']}');
          }
        }
      } else if (message == null || message is List) {
        final error = StateError('Tiến trình nhận dạng ngoại tuyến đã dừng.');
        if (!ready.isCompleted) ready.completeError(error);
        for (final pending in _pending.values) {
          pending.completeError(error);
        }
        _pending.clear();
        events.close();
      }
    });
    await Isolate.spawn(
      _speechWorker,
      [events.sendPort, folder, language],
      onError: events.sendPort,
      onExit: events.sendPort,
    );
    try {
      await ready.future.timeout(const Duration(seconds: 60));
    } catch (_) {
      _closed = true;
      rethrow;
    }
  }

  @override
  Future<String> decode(Float32List samples) {
    final commands = _commands;
    if (commands == null) throw StateError('Mô hình chưa sẵn sàng.');
    final id = ++_sequence;
    final result = Completer<String>();
    _pending[id] = result;
    commands.send({'id': id, 'samples': samples});
    return result.future;
  }

  @override
  Future<void> close() async {
    _closed = true;
    final opened = _commands != null;
    _commands?.send(null);
    _commands = null;
    for (final pending in _pending.values) {
      pending.completeError(StateError('Đã dừng nhận dạng.'));
    }
    _pending.clear();
    if (opened) {
      _events?.close();
      _events = null;
    }
  }
}

void _speechWorker(List<dynamic> args) {
  final events = args[0] as SendPort;
  final folder = args[1] as String;
  sherpa.OfflineRecognizer? recognizer;
  try {
    sherpa.initBindings();
    recognizer = sherpa.OfflineRecognizer(
      speechRecognizerConfig(folder, args[2] as String),
    );
    final commands = ReceivePort();
    events.send(commands.sendPort);
    commands.listen((dynamic command) {
      if (command == null) {
        recognizer!.free();
        commands.close();
        return;
      }
      final stream = recognizer!.createStream();
      try {
        stream.acceptWaveform(
          samples: command['samples'] as Float32List,
          sampleRate: 16000,
        );
        recognizer.decode(stream);
        events.send({
          'id': command['id'],
          'text': recognizer.getResult(stream).text.trim(),
        });
      } catch (e) {
        events.send({'id': command['id'], 'error': e.toString()});
      } finally {
        stream.free();
      }
    });
  } catch (e) {
    recognizer?.free();
    events.send({'error': e.toString()});
  }
}

class SpeechChunk {
  final int segment;
  final Float32List samples;
  final bool finalResult;
  const SpeechChunk(this.segment, this.samples, this.finalResult);
}

// Keep quiet word onsets; allow natural pauses before finalizing an utterance.
class SpeechSegments {
  final _samples = <double>[];
  final _preRoll = <double>[];
  int _silence = 0, _lastPartial = 0, _segment = 0;
  int? _pendingByte;

  SpeechChunk? add(Uint8List pcm) {
    final bytes = _pendingByte == null
        ? pcm
        : Uint8List.fromList([_pendingByte!, ...pcm]);
    _pendingByte = bytes.length.isOdd ? bytes.last : null;
    final view = ByteData.sublistView(bytes);
    final samples = <double>[];
    var energy = 0.0;
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final sample = view.getInt16(i, Endian.little) / 32768;
      samples.add(sample);
      energy += sample * sample;
    }
    if (samples.isEmpty) return null;
    final speaking = sqrt(energy / samples.length) > 0.012;
    if (_samples.isEmpty) {
      if (!speaking) {
        _preRoll.addAll(samples);
        if (_preRoll.length > 3200) {
          _preRoll.removeRange(0, _preRoll.length - 3200);
        }
        return null;
      }
      _samples.addAll(_preRoll);
      _preRoll.clear();
    }
    _samples.addAll(samples);
    _silence = speaking ? 0 : _silence + samples.length;
    if (_silence >= 16000 || _samples.length >= 160000) return flush();
    if (_samples.length - _lastPartial >= 48000) {
      _lastPartial = _samples.length;
      return SpeechChunk(_segment, Float32List.fromList(_samples), false);
    }
    return null;
  }

  SpeechChunk? flush() {
    final chunk = _samples.length >= 4800
        ? SpeechChunk(_segment, Float32List.fromList(_samples), true)
        : null;
    _samples.clear();
    _preRoll.clear();
    _silence = 0;
    _lastPartial = 0;
    _segment++;
    return chunk;
  }
}
