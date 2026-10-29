import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../providers/session.dart';
import '../services/api.dart';
import '../services/translation.dart';
import '../widgets/common.dart';

class SharedHandovers extends StatefulWidget {
  const SharedHandovers({super.key});
  @override
  State<SharedHandovers> createState() => _SharedHandoversState();
}

class _SharedHandoversState extends State<SharedHandovers> {
  int revision = 0;
  Future<void> open(Widget page) async {
    await openPage(context, page);
    if (mounted) setState(() => revision++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bàn giao song ngữ')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => open(const SharedHandoverEditor()),
      icon: const Icon(Icons.add),
      label: const Text('Soạn bàn giao'),
    ),
    body: LoadView<List<Json>>(
      key: ValueKey(revision),
      refreshInterval: const Duration(seconds: 15),
      load: () => context.read<Session>().api.list('/handovers'),
      builder: (rows, reload) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
        children: [
          const SectionTitle(
            'Chuyển ca, giữ đủ thông tin.',
            caption: 'Người nhận tự xác nhận từng mục và nhập lại thông tin quan trọng.',
          ),
          if (rows.isEmpty)
            const EmptyState('Chưa có phiếu bàn giao trong phạm vi tài khoản.'),
          for (final row in rows)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                title: Text('${row['shiftTitle'] ?? 'Bàn giao'}'),
                subtitle: Text(
                  '${row['createdByName'] ?? ''} · ${row['recipientName'] ?? ''}\n${row['originalText']}',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: StatusBadge(row['status'] as String),
                onTap: () =>
                    open(SharedHandoverDetail(id: row['id'] as String)),
              ),
            ),
        ],
      ),
    ),
  );
}

class SharedHandoverDetail extends StatefulWidget {
  final String id;
  const SharedHandoverDetail({super.key, required this.id});
  @override
  State<SharedHandoverDetail> createState() => _SharedHandoverDetailState();
}

class _SharedHandoverDetailState extends State<SharedHandoverDetail> {
  Json? row;
  Object? error;
  bool busy = false, conflict = false;
  final states = <String, String>{};
  final answers = <String, TextEditingController>{};
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  void clearAnswers() {
    for (final c in answers.values) {
      c.dispose();
    }
    answers.clear();
  }

  @override
  void dispose() {
    clearAnswers();
    super.dispose();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await context.read<Session>().api.get(
        '/handovers/${widget.id}',
      );
      if (!mounted) return;
      clearAnswers();
      states.clear();
      for (final item in value['items'] as List) {
        states[item['id'] as String] = item['state'] as String;
      }
      for (final fact in (value['criticalFacts'] as List? ?? [])) {
        answers[fact['id'] as String] = TextEditingController();
      }
      setState(() {
        row = value;
        conflict = false;
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> acknowledge(bool finalConfirmation) async {
    if (busy || conflict) return;
    final data = row!;
    if (finalConfirmation &&
        states.values.any((value) => value != 'understood')) {
      notice(context, 'Cần chọn Đã hiểu cho tất cả mục.', error: true);
      return;
    }
    if (finalConfirmation &&
        !await confirm(
          context,
          'Hoàn tất bàn giao?',
          'Xác nhận bạn đã đối chiếu bản gốc, bản dịch và các thông tin quan trọng.',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final value = await context.read<Session>().api.patch(
        '/handovers/${widget.id}',
        {
          'version': data['version'],
          'status': finalConfirmation ? 'acknowledged' : 'submitted',
          'items': [
            for (final item in data['items'] as List)
              {
                ...Map<String, dynamic>.from(item as Map),
                'state': states[item['id']],
              },
          ],
          if (finalConfirmation)
            'factAnswers': [
              for (final entry in answers.entries)
                {'factId': entry.key, 'value': entry.value.text.trim()},
            ],
        },
      );
      if (!mounted) return;
      setState(() => row = {...data, ...value});
      notice(
        context,
        finalConfirmation
            ? 'Đã xác nhận bàn giao.'
            : 'Đã lưu trạng thái các mục.',
      );
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.status == 409) setState(() => conflict = true);
      notice(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove() async {
    if (!await confirm(
      context,
      'Xóa bản nháp?',
      'Chỉ bản nháp của chính bạn được xóa.',
    )) {
      return;
    }
    if (!mounted || busy) return;
    setState(() => busy = true);
    try {
      await context.read<Session>().api.delete('/handovers/${widget.id}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) notice(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = row;
    final user = context.read<Session>().user!;
    final recipient =
        data?['recipientId'] == user.id && data?['status'] == 'submitted';
    final author = data?['createdBy'] == user.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết bàn giao'),
        actions: [
          IconButton(
            onPressed: busy ? null : load,
            tooltip: 'Tải bản mới, xóa câu trả lời đang nhập',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: data == null
          ? Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$error'),
                        TextButton(
                          onPressed: load,
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
            )
          : PageBody(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  StatusBadge(data['status'] as String),
                  const SizedBox(height: 16),
                  InfoLine('Ca làm', data['shiftTitle'] ?? data['shiftId']),
                  InfoLine(
                    'Người gửi',
                    data['createdByName'] ?? data['createdBy'],
                  ),
                  InfoLine(
                    'Người nhận',
                    data['recipientName'] ?? data['recipientId'],
                  ),
                  InfoLine('Phiên bản', data['version']),
                  const SizedBox(height: 16),
                  const SectionTitle('Bản gốc và bản dịch'),
                  SelectableText('${data['originalText']}'),
                  const Divider(height: 32),
                  SelectableText('${data['translatedText']}'),
                  const SizedBox(height: 12),
                  const Text(
                    'Bản dịch tự động cần được đối chiếu. Xác nhận dữ kiện không chứng minh bản dịch đúng toàn bộ ngữ nghĩa.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  for (final item in data['items'] as List)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('${item['text']}'),
                            const SizedBox(height: 8),
                            Text(
                              '${item['translatedText']}',
                              style: const TextStyle(color: muted),
                            ),
                            const SizedBox(height: 12),
                            if (recipient)
                              DropdownButtonFormField<String>(
                                key: ValueKey(
                                  '${item['id']}-${data['version']}',
                                ),
                                initialValue: states[item['id']],
                                items: [
                                  for (final value in [
                                    'open',
                                    'understood',
                                    'clarify',
                                  ])
                                    DropdownMenuItem(
                                      value: value,
                                      child: Text(statusLabel(value)),
                                    ),
                                ],
                                onChanged: busy || conflict
                                    ? null
                                    : (value) => setState(
                                        () => states[item['id'] as String] =
                                            value!,
                                      ),
                              )
                            else
                              StatusBadge(item['state'] as String),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const SectionTitle('Thông tin quan trọng'),
                  for (final fact in data['criticalFacts'] as List? ?? []) ...[
                    InfoLine('${fact['label']}', fact['value']),
                    if (recipient)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: TextField(
                          controller: answers[fact['id']],
                          enabled: !busy && !conflict,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: 'Nhập lại ${fact['label']}',
                          ),
                        ),
                      ),
                  ],
                  if (data['criticalFactConfirmation'] is Map) ...[
                    InfoLine(
                      'Xác nhận lúc',
                      dateTime(data['criticalFactConfirmation']['verifiedAt']),
                    ),
                    InfoLine(
                      'Bởi tài khoản',
                      data['criticalFactConfirmation']['verifiedBy'],
                    ),
                  ] else if (data['status'] == 'acknowledged')
                    const Text(
                      'Phiếu cũ chưa có bằng chứng đối chiếu thông tin quan trọng.',
                    ),
                  if (conflict) ...[
                    const Text(
                      'Phiếu đã đổi. Tải lại bản mới và nhập lại câu trả lời trước khi xác nhận.',
                      style: TextStyle(color: Colors.red),
                    ),
                    TextButton(
                      onPressed: busy ? null : load,
                      child: const Text('Tải phiên bản mới'),
                    ),
                  ],
                  if (recipient && !conflict) ...[
                    TextButton(
                      onPressed: busy ? null : () => acknowledge(false),
                      child: const Text('Lưu trạng thái đã hiểu / cần làm rõ'),
                    ),
                    BusyButton(
                      busy: busy,
                      onPressed: () => acknowledge(true),
                      label: 'Xác nhận hoàn tất bàn giao',
                    ),
                  ],
                  if (author) ...[
                    BusyButton(
                      busy: busy,
                      onPressed: () async {
                        await openPage(
                          context,
                          SharedHandoverEditor(row: data),
                        );
                        if (mounted) await load();
                      },
                      label: 'Sửa nội dung bàn giao',
                    ),
                    if (data['status'] == 'draft')
                      TextButton(
                        onPressed: busy ? null : remove,
                        child: const Text('Xóa bản nháp'),
                      ),
                  ],
                  TextButton.icon(
                    onPressed: () =>
                        openPage(context, HandoverRevisions(id: widget.id)),
                    icon: const Icon(Icons.history),
                    label: const Text('Lịch sử phiên bản'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _TextPair {
  final String id;
  final TextEditingController original, translated;
  final LiveTranslation live;
  _TextPair({
    String? id,
    String text = '',
    String translation = '',
    required TranslationEngine engine,
    required String source,
    required String target,
  }) : id = id ?? const Uuid().v4(),
       original = TextEditingController(text: text),
       translated = TextEditingController(text: translation),
       live = LiveTranslation(engine: engine) {
    live.source = source;
    live.target = target;
    live.addListener(() {
      if (live.result.isNotEmpty && translated.text != live.result) {
        translated.text = live.result;
      }
    });
    unawaited(live.checkModels());
  }
  void change(String text) {
    translated.clear();
    live.update(text);
  }

  void dispose() {
    original.dispose();
    translated.dispose();
    live.dispose();
  }
}

class _FactDraft {
  final String id;
  String kind;
  final TextEditingController label, value;
  _FactDraft([Json? row])
    : id = row?['id'] as String? ?? const Uuid().v4(),
      kind = row?['kind'] as String? ?? 'equipment',
      label = TextEditingController(
        text: row?['label'] as String? ?? 'Mã thiết bị',
      ),
      value = TextEditingController(text: row?['value'] as String? ?? '');
  Json body() => {
    'id': id,
    'kind': kind,
    'label': label.text.trim(),
    'value': canonicalFact(kind, value.text.trim()),
  };
  void dispose() {
    label.dispose();
    value.dispose();
  }
}

String canonicalFact(String kind, String value) {
  if (kind == 'quantity') {
    if (!RegExp(r'^\d{1,9}(\.\d{1,3})?$').hasMatch(value)) {
      throw const FormatException(
        'Số lượng dùng dấu chấm thập phân, không dấu phân cách hàng nghìn.',
      );
    }
    return num.parse(value).toString().replaceFirst(RegExp(r'\.0$'), '');
  }
  if (kind == 'equipment') {
    final canonical = value.toLowerCase();
    if (!RegExp(r'^[a-z0-9](?:[a-z0-9_-]{0,38}[a-z0-9])$')
        .hasMatch(canonical)) {
      throw const FormatException(
        'Mã thiết bị cần 2–40 chữ/số ASCII, dấu - hoặc _.',
      );
    }
    return canonical;
  }
  if (!RegExp(r'^(?:(?:19|20|21)\d{2}-\d{2}-\d{2} )?(?:[01]\d|2[0-3]):[0-5]\d$')
      .hasMatch(value)) {
    throw const FormatException('Thời hạn: HH:mm hoặc YYYY-MM-DD HH:mm.');
  }
  if (value.length > 5) {
    final parsed = DateTime.tryParse('${value.replaceFirst(' ', 'T')}:00Z');
    if (parsed == null ||
        parsed.toIso8601String().substring(0, 16).replaceFirst('T', ' ') !=
            value) {
      throw const FormatException('Ngày thời hạn không hợp lệ.');
    }
  }
  return value;
}

class SharedHandoverEditor extends StatefulWidget {
  final Json? row;
  const SharedHandoverEditor({super.key, this.row});
  @override
  State<SharedHandoverEditor> createState() => _SharedHandoverEditorState();
}

class _SharedHandoverEditorState extends State<SharedHandoverEditor> {
  final TranslationEngine engine = DeviceTranslation();
  late _TextPair content;
  final tasks = <_TextPair>[];
  final facts = <_FactDraft>[];
  late Future<List<List<Json>>> options;
  String source = 'vi', target = 'en';
  String? shiftId, recipientId;
  bool busy = false, conflict = false;
  @override
  void initState() {
    super.initState();
    final row = widget.row;
    source = row?['sourceLanguage'] as String? ?? 'vi';
    target = row?['targetLanguage'] as String? ?? 'en';
    shiftId = row?['shiftId'] as String?;
    recipientId = row?['recipientId'] as String?;
    content = pair(
      text: row?['originalText'] as String? ?? '',
      translation: row?['translatedText'] as String? ?? '',
    );
    for (final item in row?['items'] as List? ?? []) {
      tasks.add(
        pair(
          id: item['id'] as String,
          text: item['text'] as String,
          translation: item['translatedText'] as String,
        ),
      );
    }
    if (tasks.isEmpty) tasks.add(pair());
    for (final fact in row?['criticalFacts'] as List? ?? []) {
      facts.add(_FactDraft(Map<String, dynamic>.from(fact as Map)));
    }
    options = loadOptions();
  }

  _TextPair pair({String? id, String text = '', String translation = ''}) =>
      _TextPair(
        id: id,
        text: text,
        translation: translation,
        engine: engine,
        source: source,
        target: target,
      );

  Future<List<List<Json>>> loadOptions() async {
    final session = context.read<Session>();
    return [
      (await session.api.list('/shifts'))
          .where((row) => row['employeeId'] == session.user!.id)
          .toList(),
      await session.api.list('/handover-recipients'),
    ];
  }

  @override
  void dispose() {
    content.dispose();
    for (final task in tasks) {
      task.dispose();
    }
    for (final fact in facts) {
      fact.dispose();
    }
    super.dispose();
  }

  void languages(String from, String to) {
    setState(() {
      source = from;
      target = to;
    });
    for (final p in [content, ...tasks]) {
      p.translated.clear();
      p.live.languages(source, target);
    }
  }

  Future<void> prepare() async {
    if (!await confirm(
      context,
      'Chuẩn bị dịch trên điện thoại?',
      'Tải mô hình ngôn ngữ còn thiếu, khoảng 30 MB mỗi ngôn ngữ. Bản dịch chỉ là gợi ý; cần kiểm tra trước khi gửi.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await engine.prepare(source, target);
      if (!mounted) return;
      for (final p in [content, ...tasks]) {
        p.live.ready = true;
        p.live.update(p.original.text);
      }
      notice(context, 'Đã sẵn sàng dịch trực tiếp khi nhập.');
    } catch (e) {
      if (mounted) notice(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save(bool submit) async {
    if (busy || conflict) return;
    setState(() => busy = true);
    try {
      if (shiftId == null || recipientId == null) {
        throw const FormatException(
          'Chọn ca của bạn và người nhận cùng chi nhánh.',
        );
      }
      if (content.original.text.trim().isEmpty ||
          tasks.any((p) => p.original.text.trim().isEmpty)) {
        throw const FormatException(
          'Nhập nội dung bàn giao và các mục cần xác nhận.',
        );
      }
      if ([content, ...tasks].any((p) => p.live.busy)) {
        throw const FormatException('Chờ bản dịch hoàn tất rồi kiểm tra lại.');
      }
      if (submit &&
          (facts.isEmpty ||
              content.translated.text.trim().isEmpty ||
              tasks.any((p) => p.translated.text.trim().isEmpty))) {
        throw const FormatException(
          'Cần bản dịch và 1–3 thông tin quan trọng trước khi gửi.',
        );
      }
      final body = <String, dynamic>{
        'recipientId': recipientId,
        'originalText': content.original.text.trim(),
        'translatedText': content.translated.text.trim(),
        'sourceLanguage': source,
        'targetLanguage': target,
        'items': [
          for (final p in tasks)
            {
              'id': p.id,
              'text': p.original.text.trim(),
              'translatedText': p.translated.text.trim(),
              'state': 'open',
            },
        ],
        'criticalFacts': facts.map((fact) => fact.body()).toList(),
        'status': submit ? 'submitted' : 'draft',
      };
      final api = context.read<Session>().api;
      if (widget.row == null) {
        body['shiftId'] = shiftId;
        await api.post('/handovers', body);
      } else {
        body['version'] = widget.row!['version'];
        await api.patch('/handovers/${widget.row!['id']}', body);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.status == 409) setState(() => conflict = true);
      notice(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget textPair(_TextPair p, String title, int maxLength) =>
      ListenableBuilder(
        listenable: p.live,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: p.original,
              enabled: !busy && !conflict,
              minLines: 2,
              maxLines: 6,
              maxLength: maxLength,
              onChanged: p.change,
              decoration: InputDecoration(
                labelText: '$title · bản gốc',
                alignLabelWithHint: true,
              ),
            ),
            if (p.live.busy) const LinearProgressIndicator(),
            TextField(
              controller: p.translated,
              enabled: !busy && !conflict && !p.live.busy,
              minLines: 2,
              maxLines: 6,
              maxLength: maxLength * 2,
              decoration: const InputDecoration(
                labelText: 'Bản dịch (có thể sửa)',
                alignLabelWithHint: true,
              ),
            ),
            if (p.live.error != null)
              Text(p.live.error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Soạn bàn giao')),
    body: FutureBuilder<List<List<Json>>>(
      future: options,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${snapshot.error}'),
                TextButton(
                  onPressed: () => setState(() => options = loadOptions()),
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final lists = snapshot.data!;
        return PageBody(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Bản dịch được tạo trên điện thoại. Chỉ nội dung bạn lưu/gửi mới được đưa lên máy chủ nhóm.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 20),
              if (widget.row == null)
                DropdownButtonFormField<String>(
                  initialValue: shiftId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Ca của chính bạn',
                  ),
                  items: [
                    for (final r in lists[0])
                      DropdownMenuItem(
                        value: r['id'] as String,
                        child: Text(
                          '${r['title']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: busy ? null : (v) => setState(() => shiftId = v),
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: lists[1].any((r) => r['id'] == recipientId)
                    ? recipientId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Người nhận cùng chi nhánh',
                ),
                items: [
                  for (final r in lists[1])
                    DropdownMenuItem(
                      value: r['id'] as String,
                      child: Text(
                        '${r['fullName']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: busy ? null : (v) => setState(() => recipientId = v),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final from in [true, false])
                    SizedBox(
                      width: 145,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: from ? source : target,
                        decoration: InputDecoration(
                          labelText: from ? 'Từ' : 'Sang',
                        ),
                        items: [
                          for (final l in translationLanguages.entries.where(
                            (entry) =>
                                handoverLanguageCodes.contains(entry.key),
                          ))
                            DropdownMenuItem(
                              value: l.key,
                              child: Text(l.value),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (v) => languages(
                                from ? v! : source,
                                from ? target : v!,
                              ),
                      ),
                    ),
                ],
              ),
              TextButton.icon(
                onPressed: busy ? null : prepare,
                icon: const Icon(Icons.translate),
                label: const Text('Tải ngôn ngữ / dịch toàn bộ'),
              ),
              textPair(content, 'Nội dung bàn giao', 12000),
              const SizedBox(height: 20),
              const SectionTitle('Danh sách cần xác nhận'),
              for (final p in tasks)
                Card(
                  key: ValueKey(p.id),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        textPair(p, 'Mục ${tasks.indexOf(p) + 1}', 1000),
                        if (tasks.length > 1)
                          TextButton(
                            onPressed: busy
                                ? null
                                : () {
                                    setState(() => tasks.remove(p));
                                    p.dispose();
                                  },
                            child: const Text('Bỏ mục này'),
                          ),
                      ],
                    ),
                  ),
                ),
              if (tasks.length < 40)
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => setState(() => tasks.add(pair())),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm mục'),
                ),
              const SizedBox(height: 20),
              const SectionTitle(
                'Thông tin quan trọng',
                caption: 'Giữ cùng giá trị trong cả nội dung gốc và bản dịch. Người nhận phải nhập lại để xác nhận.',
              ),
              for (final f in facts)
                Card(
                  key: ValueKey(f.id),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: f.kind,
                          items: [
                            for (final e in {
                              'equipment': 'Mã thiết bị',
                              'quantity': 'Số lượng',
                              'deadline': 'Thời hạn',
                            }.entries)
                              DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                          ],
                          onChanged: busy
                              ? null
                              : (v) => setState(() {
                                  f.kind = v!;
                                }),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: f.label,
                          enabled: !busy,
                          maxLength: 80,
                          decoration: const InputDecoration(
                            labelText: 'Nhãn thông tin',
                          ),
                        ),
                        TextField(
                          controller: f.value,
                          enabled: !busy,
                          maxLength: 80,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Giá trị',
                            helperText: f.kind == 'quantity'
                                ? 'Ví dụ 12.5; không dấu phân cách hàng nghìn'
                                : f.kind == 'deadline'
                                ? 'HH:mm hoặc YYYY-MM-DD HH:mm'
                                : 'Ví dụ EQ-12',
                          ),
                        ),
                        Text(
                          factPreview(f),
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () {
                                  setState(() => facts.remove(f));
                                  f.dispose();
                                },
                          child: const Text('Bỏ thông tin này'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (facts.length < 3)
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => setState(() => facts.add(_FactDraft())),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm thông tin quan trọng'),
                ),
              const SizedBox(height: 20),
              if (conflict)
                const Text(
                  'Phiếu đã thay đổi. Quay lại chi tiết, tải bản mới rồi sửa lại.',
                  style: TextStyle(color: Colors.red),
                ),
              if (widget.row == null || widget.row!['status'] == 'draft')
                TextButton(
                  onPressed: busy || conflict ? null : () => save(false),
                  child: const Text('Lưu bản nháp'),
                ),
              BusyButton(
                busy: busy,
                onPressed: conflict ? null : () => save(true),
                label: widget.row == null
                    ? 'Gửi bàn giao'
                    : 'Lưu và yêu cầu xác nhận lại',
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    ),
  );

  String factPreview(_FactDraft fact) {
    if (fact.value.text.trim().isEmpty) return 'Chưa nhập giá trị';
    try {
      return 'Giá trị chuẩn: ${canonicalFact(fact.kind, fact.value.text.trim())}';
    } catch (e) {
      return e.toString();
    }
  }
}

class HandoverRevisions extends StatelessWidget {
  final String id;
  const HandoverRevisions({super.key, required this.id});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Lịch sử bàn giao')),
    body: LoadView<List<Json>>(
      load: () => context.read<Session>().api.list('/handovers/$id/revisions'),
      builder: (rows, reload) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (rows.isEmpty) const EmptyState('Chưa có phiên bản.'),
          for (final row in rows)
            Card(
              child: ExpansionTile(
                title: Text('Phiên bản ${row['version']}'),
                subtitle: Text(dateTime(row['createdAt'])),
                childrenPadding: const EdgeInsets.all(16),
                children: [
                  InfoLine('Người sửa', row['actorId']),
                  if (row['snapshot'] is Map) ...[
                    InfoLine(
                      'Trạng thái',
                      statusLabel(row['snapshot']['status'] as String?),
                    ),
                    InfoLine('Bản gốc', row['snapshot']['originalText']),
                    InfoLine('Bản dịch', row['snapshot']['translatedText']),
                    if (row['snapshot']['criticalFactConfirmation'] is Map)
                      InfoLine(
                        'Xác nhận lúc',
                        dateTime(
                          row['snapshot']['criticalFactConfirmation']['verifiedAt'],
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
