import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

const translationLanguages = {
  'vi': 'Tiếng Việt',
  'en': 'English',
  'zh': '中文',
  'ja': '日本語',
};

// Shared backend accepts only these language codes in saved handovers.
const handoverLanguageCodes = {'vi', 'en', 'zh'};

abstract class TranslationEngine {
  Future<bool> installed(String source, String target);
  Future<void> prepare(String source, String target);
  Future<String> translate(String text, String source, String target);
}

class DeviceTranslation implements TranslationEngine {
  final manager = OnDeviceTranslatorModelManager();
  TranslateLanguage language(String code) => switch (code) {
    'vi' => TranslateLanguage.vietnamese,
    'zh' => TranslateLanguage.chinese,
    'ja' => TranslateLanguage.japanese,
    'en' => TranslateLanguage.english,
    _ => throw ArgumentError.value(code, 'code', 'Unsupported language'),
  };

  @override
  Future<bool> installed(String source, String target) async {
    for (final code in {source, target}) {
      if (!await manager.isModelDownloaded(code)) return false;
    }
    return true;
  }

  @override
  Future<void> prepare(String source, String target) async {
    for (final code in {source, target}) {
      if (!await manager.isModelDownloaded(code) &&
          !await manager.downloadModel(code, isWifiRequired: false)) {
        throw StateError(
          'Chưa tải được mô hình ngôn ngữ. Kiểm tra mạng rồi thử lại.',
        );
      }
    }
  }

  @override
  Future<String> translate(String text, String source, String target) async {
    if (source == target) return text;
    final translator = OnDeviceTranslator(
      sourceLanguage: language(source),
      targetLanguage: language(target),
    );
    try {
      return await translator.translateText(text);
    } finally {
      await translator.close();
    }
  }
}

class LiveTranslation extends ChangeNotifier {
  final TranslationEngine engine;
  final Duration debounce;
  String source = 'vi', target = 'en', result = '';
  String? error;
  bool ready = false, busy = false, downloading = false;
  Timer? _timer;
  int _revision = 0;
  int _modelRevision = 0;
  String _text = '';
  bool _disposed = false;
  LiveTranslation({
    TranslationEngine? engine,
    this.debounce = const Duration(milliseconds: 600),
  }) : engine = engine ?? DeviceTranslation();

  Future<void> checkModels() async {
    final revision = _modelRevision;
    try {
      final available = await engine.installed(source, target);
      if (_disposed || revision != _modelRevision) return;
      ready = available;
      notifyListeners();
      if (ready && _text.isNotEmpty) update(_text);
    } catch (e) {
      if (!_disposed && revision == _modelRevision) {
        error = e.toString();
        notifyListeners();
      }
    }
  }

  Future<void> prepare() async {
    final revision = ++_modelRevision;
    downloading = true;
    error = null;
    notifyListeners();
    try {
      await engine.prepare(source, target);
      if (!_disposed && revision == _modelRevision) ready = true;
    } catch (e) {
      if (!_disposed && revision == _modelRevision) error = e.toString();
    } finally {
      if (!_disposed && revision == _modelRevision) {
        downloading = false;
        notifyListeners();
      }
    }
  }

  void languages(String from, String to) {
    _revision++;
    _modelRevision++;
    _timer?.cancel();
    source = from;
    target = to;
    ready = false;
    busy = false;
    downloading = false;
    result = '';
    error = null;
    notifyListeners();
    unawaited(checkModels());
  }

  void update(String text) {
    _text = text;
    final revision = ++_revision;
    _timer?.cancel();
    if (!ready || text.trim().isEmpty) result = '';
    error = null;
    busy = ready && text.trim().isNotEmpty;
    notifyListeners();
    if (!ready || text.trim().isEmpty) return;
    _timer = Timer(debounce, () async {
      busy = true;
      notifyListeners();
      try {
        final translated = await engine.translate(text, source, target);
        // Older translation requests must never replace newer input.
        if (!_disposed && revision == _revision) result = translated;
      } catch (e) {
        if (!_disposed && revision == _revision) {
          result = '';
          error = e.toString();
        }
      } finally {
        if (!_disposed && revision == _revision) {
          busy = false;
          notifyListeners();
        }
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _modelRevision++;
    _timer?.cancel();
    super.dispose();
  }
}
