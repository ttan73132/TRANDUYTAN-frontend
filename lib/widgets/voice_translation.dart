import 'dart:async';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../services/offline_speech.dart';
import 'common.dart';

class VoiceTranslation extends StatefulWidget {
  final String language;
  final bool enabled;
  final ValueChanged<String> onText;
  const VoiceTranslation({
    super.key,
    required this.language,
    required this.enabled,
    required this.onText,
  });
  @override
  State<VoiceTranslation> createState() => _VoiceTranslationState();
}

class _VoiceTranslationState extends State<VoiceTranslation>
    with WidgetsBindingObserver {
  late final _models = SpeechModels(language: widget.language);
  AudioRecorder? _recorder;
  SpeechDecoder? _decoder;
  StreamSubscription? _audio, _recordState;
  SpeechSegments _segments = SpeechSegments();
  final _queue = <SpeechChunk>[];
  final _transcripts = <int, String>{};
  bool _installed = false, _downloading = false, _starting = false;
  bool _checkingModels = true;
  bool _listening = false, _decoding = false, _closed = false;
  bool _stopping = false;
  double _progress = 0;
  int _generation = 0;
  String? _error;
  Future<void>? _work;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_check());
  }

  Future<void> _check() async {
    try {
      final installed = await _models.installed();
      if (!_closed) setState(() => _installed = installed);
    } catch (e) {
      if (!_closed) setState(() => _error = e.toString());
    } finally {
      if (!_closed) setState(() => _checkingModels = false);
    }
  }

  @override
  void didUpdateWidget(VoiceTranslation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language || !widget.enabled) {
      unawaited(_stop(discard: true));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_stop(discard: true));
    }
  }

  Future<void> _download() async {
    if (!await confirm(
      context,
      'Tải nhận dạng giọng nói ngoại tuyến?',
      '${_models.name} cần khoảng ${_models.megabytes} MB. Chỉ tải một lần rồi giữ trên máy; không gửi âm thanh. Có thể dùng dữ liệu di động.',
    )) {
      return;
    }
    if (_closed) return;
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      await _models.download((progress) {
        if (!_closed) setState(() => _progress = progress);
      });
      if (!_closed) setState(() => _installed = true);
    } catch (e) {
      if (!_closed) setState(() => _error = 'Chưa tải được mô hình. $e');
    } finally {
      if (!_closed) setState(() => _downloading = false);
    }
  }

  Future<void> _start() async {
    if (_stopping ||
        _starting ||
        _listening ||
        _decoding ||
        !_installed ||
        !widget.enabled) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _starting = true;
      _error = null;
    });
    final decoder = WhisperDecoder();
    AudioRecorder? recorder;
    try {
      final folder = await _models.directory();
      await decoder.open(folder.path, widget.language);
      if (_closed || generation != _generation) {
        await decoder.close();
        return;
      }
      recorder = AudioRecorder();
      if (!await recorder.hasPermission()) {
        throw StateError(
          'Chưa được cấp quyền Micro. Bật quyền trong cài đặt ứng dụng.',
        );
      }
      if (_closed || generation != _generation) {
        await recorder.dispose();
        await decoder.close();
        return;
      }
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          noiseSuppress: true,
          streamBufferSize: 3200,
        ),
      );
      if (_closed || generation != _generation) {
        await recorder.dispose();
        await decoder.close();
        return;
      }
      _recorder = recorder;
      _decoder = decoder;
      _segments = SpeechSegments();
      _transcripts.clear();
      _queue.clear();
      widget.onText('');
      setState(() => _listening = true);
      _audio = stream.listen(
        (pcm) {
          if (_closed || generation != _generation || !_listening) return;
          final chunk = _segments.add(pcm);
          if (chunk != null) _enqueue(chunk, generation);
        },
        onError: (Object e) {
          if (_closed || generation != _generation) return;
          if (!_closed) setState(() => _error = 'Micro bị gián đoạn: $e');
          unawaited(_stop(discard: true));
        },
        onDone: () {
          if (!_closed && generation == _generation && _listening) {
            setState(
              () => _error = 'Micro đã bị ngắt. Bấm bắt đầu để tiếp tục.',
            );
            unawaited(_stop(discard: true));
          }
        },
      );
      _recordState = recorder.onStateChanged().listen((state) {
        if (state != RecordState.record && _listening) {
          if (!_closed) {
            setState(
              () => _error =
                  'Micro bị ứng dụng khác ngắt. Bấm bắt đầu để tiếp tục.',
            );
          }
          unawaited(_stop(discard: true));
        }
      });
    } catch (e) {
      await recorder?.dispose();
      await decoder.close();
      if (!_closed && generation == _generation) {
        setState(() => _error = 'Không bắt đầu được nhận dạng ngoại tuyến. $e');
      }
    } finally {
      if (!_closed) {
        setState(() => _starting = false);
      }
    }
  }

  void _enqueue(SpeechChunk chunk, int generation) {
    _queue.removeWhere(
      (old) => old.segment == chunk.segment && !old.finalResult,
    );
    // Bound queued audio if this phone cannot keep up with inference.
    if (_queue.length >= 3) {
      setState(
        () =>
            _error = 'Máy xử lý chưa kịp. Nói từng câu ngắn rồi đợi bản dịch.',
      );
      unawaited(_stop(discard: true));
      return;
    }
    _queue.add(chunk);
    if (!_decoding) _work = _drain(generation);
  }

  Future<void> _drain(int generation) async {
    _decoding = true;
    if (!_closed) setState(() {});
    try {
      while (_queue.isNotEmpty && generation == _generation && !_closed) {
        final chunk = _queue.removeAt(0);
        final text = await _decoder!.decode(chunk.samples);
        if (_closed || generation != _generation) return;
        if (text.isNotEmpty) {
          _transcripts[chunk.segment] = text;
          while (_transcripts.length > 1 &&
              _transcripts.values.join(' ').length > 4000) {
            _transcripts.remove(_transcripts.keys.first);
          }
          final transcript = _transcripts.values.join(' ');
          widget.onText(
            transcript.length > 4000
                ? transcript.substring(transcript.length - 4000)
                : transcript,
          );
        }
      }
    } catch (e) {
      if (!_closed && generation == _generation) {
        setState(() => _error = 'Lỗi nhận dạng ngoại tuyến: $e');
        // Do not await stop here: it waits for this drain operation.
        unawaited(_stop(discard: true));
      }
    } finally {
      _decoding = false;
      if (!_closed) setState(() {});
    }
  }

  Future<void> _stop({bool discard = false}) async {
    if (_stopping) {
      if (discard) {
        ++_generation;
        _queue.clear();
      }
      return;
    }
    _stopping = true;
    final recorder = _recorder;
    final decoder = _decoder;
    try {
      _recorder = null;
      if (discard) {
        ++_generation;
        _queue.clear();
      }
      if (!_closed) {
        setState(() {
          _listening = false;
        });
      }
      await _audio?.cancel();
      _audio = null;
      await _recordState?.cancel();
      _recordState = null;
      await recorder?.stop();
      if (!discard && decoder != null) {
        final last = _segments.flush();
        if (last != null) _enqueue(last, _generation);
      }
      await _work;
    } catch (e) {
      ++_generation;
      _queue.clear();
      if (!_closed) setState(() => _error = 'Đã ngừng micro: $e');
    } finally {
      try {
        await recorder?.dispose();
      } finally {
        await decoder?.close();
        if (_decoder == decoder) _decoder = null;
      }
      _stopping = false;
      if (!_closed) setState(() {});
    }
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    _models.close();
    unawaited(_stop(discard: true));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Icon(
        _listening ? Icons.mic : Icons.mic_none,
        size: 64,
        color: _listening ? Colors.red : null,
      ),
      const SizedBox(height: 12),
      if (_checkingModels)
        FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.hourglass_top),
          label: const Text('Đang kiểm tra gói đã tải…'),
        )
      else if (!_installed)
        FilledButton.icon(
          onPressed: _downloading ? null : _download,
          icon: const Icon(Icons.download),
          label: Text(
            _downloading
                ? 'Đang tải ${(_progress * 100).round()}%'
                : 'Tải giọng nói ngoại tuyến · ${_models.megabytes} MB',
          ),
        )
      else
        FilledButton.icon(
          onPressed:
              !widget.enabled ||
                  _starting ||
                  _stopping ||
                  (!_listening && _decoding)
              ? null
              : _listening
              ? _stop
              : _start,
          icon: Icon(_listening ? Icons.stop_circle_outlined : Icons.mic),
          label: Text(
            _starting
                ? 'Đang mở mô hình…'
                : _listening
                ? 'Dừng micro'
                : _decoding
                ? 'Đang nhận dạng câu cuối…'
                : 'Bắt đầu nói',
          ),
        ),
      if (_downloading) LinearProgressIndicator(value: _progress),
      if (_listening || _decoding) const LinearProgressIndicator(),
      const SizedBox(height: 8),
      const Text(
        'Nhận dạng và dịch trên điện thoại, không gửi âm thanh. Nói từng câu rõ ràng; kết quả cập nhật theo đoạn khoảng 3–10 giây, tùy tốc độ máy.',
      ),
      if (_error != null)
        Text(_error!, style: const TextStyle(color: Colors.red)),
    ],
  );
}
