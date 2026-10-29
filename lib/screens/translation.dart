import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../services/translation.dart';
import '../widgets/common.dart';
import '../widgets/camera_translation.dart';
import '../widgets/voice_translation.dart';

class TranslationScreen extends StatefulWidget {
  final TranslationEngine? engine;
  const TranslationScreen({super.key, this.engine});
  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  final input = TextEditingController();
  late final LiveTranslation live;
  String mode = 'camera';

  void recognized(String text) {
    if (!mounted || text == input.text) return;
    input.text = text;
    live.update(text);
  }

  void changeMode(String value) {
    if (value == mode) return;
    FocusScope.of(context).unfocus();
    setState(() => mode = value);
    input.clear();
    live.update('');
  }

  void changeLanguages(String source, String target) {
    input.clear();
    live.update('');
    live.languages(source, target);
  }

  @override
  void initState() {
    super.initState();
    live = LiveTranslation(engine: widget.engine);
    unawaited(live.checkModels());
  }

  @override
  void dispose() {
    input.dispose();
    live.dispose();
    super.dispose();
  }

  Future<void> download() async {
    if (!await confirm(
      context,
      'Tải mô hình dịch?',
      'Mỗi ngôn ngữ cần khoảng 30 MB, có thể dùng dữ liệu di động. Sau khi tải, văn bản được dịch trên điện thoại.',
    )) {
      return;
    }
    if (!mounted) return;
    await live.prepare();
    if (mounted) live.update(input.text);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dịch trực tiếp')),
    body: PageBody(
      child: ListenableBuilder(
        listenable: live,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SectionTitle(
              'Dịch ngay trước mắt.',
              caption: 'Camera đọc chữ · Micro nhận giọng nói · Xử lý trên điện thoại.',
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in const {
                  'camera': 'Camera',
                  'voice': 'Giọng nói',
                  'text': 'Nhập chữ',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: mode == entry.key,
                    onSelected: (_) => changeMode(entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 145,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: live.source,
                    decoration: const InputDecoration(labelText: 'Từ'),
                    items: [
                      for (final entry in translationLanguages.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: live.downloading
                        ? null
                        : (value) {
                            changeLanguages(value!, live.target);
                          },
                  ),
                ),
                SizedBox(
                  width: 145,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: live.target,
                    decoration: const InputDecoration(labelText: 'Sang'),
                    items: [
                      for (final entry in translationLanguages.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: live.downloading
                        ? null
                        : (value) {
                            changeLanguages(live.source, value!);
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (!live.ready)
              BusyButton(
                busy: live.downloading,
                onPressed: download,
                label: 'Tải ngôn ngữ để bắt đầu',
                icon: Icons.download,
              ),
            const SizedBox(height: 16),
            if (mode == 'camera') ...[
              CameraTranslation(
                key: ValueKey('camera-${live.source}-${live.target}'),
                language: live.source,
                enabled: live.ready,
                onText: recognized,
              ),
              const SizedBox(height: 16),
            ],
            if (mode == 'voice') ...[
              VoiceTranslation(
                key: ValueKey('voice-${live.source}-${live.target}'),
                language: live.source,
                enabled: live.ready,
                onText: recognized,
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: input,
              readOnly: mode != 'text',
              minLines: mode == 'text' ? 4 : 2,
              maxLines: mode == 'text' ? 10 : 4,
              maxLength: mode == 'text' ? 4000 : null,
              onChanged: live.update,
              decoration: InputDecoration(
                labelText: mode == 'text'
                    ? 'Nội dung cần dịch'
                    : 'Chữ nhận được',
                alignLabelWithHint: true,
              ),
            ),
            SizedBox(
              height: 4,
              child: live.busy ? const LinearProgressIndicator() : null,
            ),
            if (live.error != null)
              Text(live.error!, style: const TextStyle(color: Colors.red)),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BẢN DỊCH',
                      style: TextStyle(
                        letterSpacing: 1.5,
                        color: blue,
                        fontSize: 11,
                      ),
                    ),
                    SizedBox(
                      height: 18,
                      child: live.busy
                          ? const Text(
                              'Đang cập nhật bản dịch…',
                              style: TextStyle(color: muted, fontSize: 12),
                            )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      live.result.isEmpty
                          ? 'Bản dịch sẽ xuất hiện tại đây.'
                          : live.result,
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: live.result.isEmpty || live.busy
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: live.result),
                              );
                              if (context.mounted) {
                                notice(context, 'Đã sao chép bản dịch.');
                              }
                            },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Sao chép'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Google ML Kit, Zipformer tiếng Việt và Whisper chạy trên máy. Sau khi tải mô hình, có thể dùng khi tắt mạng. Kiểm tra lại tên, số lượng và mã thiết bị trong bản dịch.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
