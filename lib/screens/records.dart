import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../providers/session.dart';
import '../widgets/common.dart';
import 'check_flow.dart';

class ShiftScreen extends StatelessWidget {
  final bool embedded;
  const ShiftScreen({super.key, this.embedded = false});
  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: SectionTitle(
            'Ca của tôi',
            caption: 'Lịch phân công và trạng thái vào / ra ca.',
          ),
        ),
        Expanded(
          child: ApiList(
            load: (offset) => context.read<Session>().api.list(
              '/shifts?limit=50&offset=$offset',
            ),
            empty: 'Bạn chưa được phân ca. Liên hệ quản trị viên.',
            item: (s, reload) {
              final done = s['check_out_at'] != null;
              final checked = s['check_in_at'] != null;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s['name'],
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          if (checked)
                            StatusBadge(
                              done
                                  ? 'Checked Out'
                                  : (s['late_minutes'] ?? 0) > 0
                                  ? 'Late'
                                  : 'On Time',
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${timeOnly(s['start_at'])} — ${timeOnly(s['end_at'])}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: navy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${dateOnly(s['start_at'])} · ${s['workplace_name']}',
                        style: const TextStyle(color: muted),
                      ),
                      if (dateOnly(s['start_at']) != dateOnly(s['end_at']))
                        Text(
                          'Kết thúc ngày ${dateOnly(s['end_at'])}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      if (checked)
                        Text(
                          'Vào ca ${timeOnly(s['check_in_at'])}${done ? ' · Ra ca ${timeOnly(s['check_out_at'])}' : ''}',
                        ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: done
                              ? null
                              : () async {
                                  await openPage(
                                    context,
                                    CheckFlowScreen(
                                      shift: s,
                                      checkout: checked,
                                    ),
                                  );
                                  if (context.mounted) reload();
                                },
                          icon: Icon(
                            checked
                                ? Icons.logout_rounded
                                : Icons.login_rounded,
                          ),
                          label: Text(
                            done
                                ? 'Đã hoàn thành ca'
                                : checked
                                ? 'Check-out'
                                : 'Check-in',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
    return embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('Lịch làm việc')),
            body: PageBody(child: body),
          );
  }
}

class AttendanceScreen extends StatefulWidget {
  final bool embedded;
  const AttendanceScreen({super.key, this.embedded = false});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool onlyLate = false;
  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: SectionTitle(
            'Lịch sử chấm công',
            caption: 'Thời gian hiển thị theo múi giờ Việt Nam.',
            action: IconButton(
              onPressed: () => openPage(context, const ExplanationScreen()),
              tooltip: 'Giải trình đi muộn',
              icon: const Icon(Icons.edit_note),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              label: const Text('Chỉ xem đi muộn'),
              selected: onlyLate,
              onSelected: (v) => setState(() => onlyLate = v),
            ),
          ),
        ),
        Expanded(
          child: ApiList(
            key: ValueKey(onlyLate),
            load: (offset) => context.read<Session>().api.list(
              '/attendance?limit=50&offset=$offset${onlyLate ? '&late=true' : ''}',
            ),
            item: (a, reload) => Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () async {
                  await openPage(context, AttendanceDetailScreen(id: a['id']));
                  if (context.mounted) reload();
                },
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              a['shift_name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          StatusBadge(a['status']),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${a['full_name']} · ${a['workplace_name']}',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '${timeOnly(a['check_in_at'])} — ${timeOnly(a['check_out_at'])}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        dateOnly(a['check_in_at']),
                        style: const TextStyle(color: muted),
                      ),
                      if ((a['late_minutes'] ?? 0) > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Đi muộn ${a['late_minutes']} phút',
                            style: const TextStyle(color: Color(0xFFB42338)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('Dữ liệu chấm công')),
            body: PageBody(child: body),
          );
  }
}

class AttendanceDetailScreen extends StatelessWidget {
  final String id;
  const AttendanceDetailScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chi tiết chấm công')),
    body: PageBody(
      child: LoadView<Json>(
        load: () => context.read<Session>().api.get('/attendance/$id'),
        builder: (a, reload) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            SectionTitle(a['shift_name'], caption: a['full_name']),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusBadge(a['status']),
                    const SizedBox(height: 16),
                    InfoLine('Địa điểm', a['workplace_name']),
                    InfoLine('Giờ vào', dateTime(a['check_in_at'])),
                    InfoLine('Giờ ra', dateTime(a['check_out_at'])),
                    InfoLine('Đi muộn', '${a['late_minutes']} phút'),
                    InfoLine('GPS vào', '${a['latitude']}, ${a['longitude']}'),
                    InfoLine(
                      'Khoảng cách',
                      '${(a['distance_meters'] as num).round()} m',
                    ),
                    InfoLine(
                      'Xác nhận',
                      a['motion_method'] == 'shake'
                          ? 'Cảm biến chuyển động'
                          : 'Nút xác nhận thay thế',
                    ),
                    if (a['checkout_latitude'] != null)
                      InfoLine(
                        'GPS ra',
                        '${a['checkout_latitude']}, ${a['checkout_longitude']}',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (context.read<Session>().user!.isAdmin)
              OutlinedButton.icon(
                onPressed: () async {
                  final changed = await openPage<bool>(
                    context,
                    CorrectionScreen(record: a),
                  );
                  if (changed == true && context.mounted) reload();
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Điều chỉnh có nhật ký'),
              ),
            const SizedBox(height: 20),
            Text(
              'Lịch sử điều chỉnh',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if ((a['corrections'] as List).isEmpty)
              const EmptyState('Chưa có chỉnh sửa.'),
            for (final c in a['corrections'])
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c['reason'],
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${c['reviewer_name']} · ${dateTime(c['created_at'])}',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      InfoLine(
                        'Trước',
                        '${dateTime(c['before_value']['check_in_at'])}\n${dateTime(c['before_value']['check_out_at'])}',
                      ),
                      InfoLine(
                        'Sau',
                        '${dateTime(c['after_value']['check_in_at'])}\n${dateTime(c['after_value']['check_out_at'])}',
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class CorrectionScreen extends StatefulWidget {
  final Json record;
  const CorrectionScreen({super.key, required this.record});
  @override
  State<CorrectionScreen> createState() => _CorrectionScreenState();
}

class _CorrectionScreenState extends State<CorrectionScreen> {
  late String checkIn;
  String? checkOut;
  final reason = TextEditingController();
  bool busy = false;
  @override
  void initState() {
    super.initState();
    checkIn = widget.record['check_in_at'];
    checkOut = widget.record['check_out_at'];
  }

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> pick(bool out) async {
    final initial = vnTime(out ? (checkOut ?? checkIn) : checkIn);
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (time == null || !mounted) return;
    final value = DateTime.utc(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).subtract(const Duration(hours: 7)).toIso8601String();
    setState(() {
      if (out) {
        checkOut = value;
      } else {
        checkIn = value;
      }
    });
  }

  Future<void> save() async {
    if (reason.text.trim().isEmpty) {
      notice(context, 'Nhập lý do điều chỉnh.', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      await context.read<Session>().api.put(
        '/attendance/${widget.record['id']}',
        {
          'checkInAt': checkIn,
          'checkOutAt': checkOut,
          'reason': reason.text.trim(),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) notice(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Điều chỉnh chấm công')),
    body: PageBody(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Mọi thay đổi được lưu trước / sau cùng người thực hiện và lý do.',
          ),
          const SizedBox(height: 20),
          ListTile(
            title: const Text('Giờ vào (Việt Nam)'),
            subtitle: Text(dateTime(checkIn)),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () => pick(false),
          ),
          ListTile(
            title: const Text('Giờ ra (Việt Nam)'),
            subtitle: Text(dateTime(checkOut)),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () => pick(true),
          ),
          if (checkOut != null)
            TextButton(
              onPressed: () => setState(() => checkOut = null),
              child: const Text('Xóa giờ ra'),
            ),
          const SizedBox(height: 20),
          TextField(
            controller: reason,
            maxLines: 4,
            maxLength: 2000,
            decoration: const InputDecoration(labelText: 'Lý do điều chỉnh'),
          ),
          const SizedBox(height: 24),
          BusyButton(
            busy: busy,
            onPressed: save,
            label: 'Lưu điều chỉnh',
            icon: Icons.check,
          ),
        ],
      ),
    ),
  );
}

class ExplanationScreen extends StatelessWidget {
  const ExplanationScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final admin = context.read<Session>().user!.isAdmin;
    return Scaffold(
      appBar: AppBar(
        title: Text(admin ? 'Duyệt giải trình' : 'Giải trình đi muộn'),
      ),
      body: PageBody(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: SectionTitle(
                'Smart Late\nCheck-in Explanation',
                caption: 'Giải trình được tạo từ thời gian chấm công thực tế.',
              ),
            ),
            Expanded(
              child: ApiList(
                load: (offset) => context.read<Session>().api.list(
                  '/explanations?limit=50&offset=$offset',
                ),
                empty: 'Chưa có giải trình đi muộn.',
                item: (x, reload) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                x['shift_name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            StatusBadge(x['status']),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${x['full_name']} · muộn ${x['late_minutes']} phút',
                          style: const TextStyle(color: Color(0xFFB42338)),
                        ),
                        Text(
                          dateTime(x['check_in_at']),
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          (x['reason'] as String).isEmpty
                              ? 'Bản nháp tự động. Hãy bổ sung lý do đi muộn.'
                              : x['reason'],
                        ),
                        if (x['reviewer_name'] != null) ...[
                          const Divider(height: 24),
                          Text(
                            'Người duyệt: ${x['reviewer_name']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            '${dateTime(x['reviewed_at'])} · ${x['review_note']}',
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                        if ((x['reviews'] as List).isNotEmpty)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text(
                              'Lịch sử phê duyệt',
                              style: TextStyle(fontSize: 12),
                            ),
                            children: [
                              for (final r in x['reviews'])
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    '${statusLabel(r['decision'])} · ${r['reviewer_name']}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  subtitle: Text(
                                    '${dateTime(r['created_at'])}\n${r['note']}',
                                  ),
                                ),
                            ],
                          ),
                        if ((admin && x['status'] == 'Pending') ||
                            (!admin &&
                                ['Draft', 'Rejected'].contains(x['status'])))
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () async {
                                  final changed = await openPage<bool>(
                                    context,
                                    ExplanationEditor(
                                      explanation: x,
                                      review: admin,
                                    ),
                                  );
                                  if (changed == true && context.mounted) {
                                    reload();
                                  }
                                },
                                icon: Icon(
                                  admin
                                      ? Icons.fact_check_outlined
                                      : Icons.edit_note,
                                ),
                                label: Text(
                                  admin
                                      ? 'Xem xét giải trình'
                                      : 'Viết và gửi giải trình',
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExplanationEditor extends StatefulWidget {
  final Json explanation;
  final bool review;
  const ExplanationEditor({
    super.key,
    required this.explanation,
    required this.review,
  });
  @override
  State<ExplanationEditor> createState() => _ExplanationEditorState();
}

class _ExplanationEditorState extends State<ExplanationEditor> {
  final controller = TextEditingController();
  bool busy = false;
  @override
  void initState() {
    super.initState();
    if (!widget.review) controller.text = widget.explanation['reason'];
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> submit([String? decision]) async {
    if (!widget.review && controller.text.trim().length < 5) {
      notice(context, 'Lý do cần ít nhất 5 ký tự.', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final api = context.read<Session>().api;
      final id = widget.explanation['id'];
      if (widget.review) {
        await api.post('/explanations/$id/review', {
          'decision': decision,
          'note': controller.text.trim(),
        });
      } else {
        await api.put('/explanations/$id', {'reason': controller.text.trim()});
      }
      if (!mounted) return;
      notice(
        context,
        widget.review ? 'Đã lưu kết quả duyệt.' : 'Đã gửi giải trình.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) notice(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.review ? 'Xem xét giải trình' : 'Gửi giải trình'),
    ),
    body: PageBody(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SectionTitle(
            widget.explanation['full_name'],
            caption:
                '${widget.explanation['shift_name']} · Muộn ${widget.explanation['late_minutes']} phút',
          ),
          if (widget.review) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(widget.explanation['reason']),
              ),
            ),
            const SizedBox(height: 20),
          ],
          TextField(
            controller: controller,
            maxLines: 6,
            maxLength: 2000,
            decoration: InputDecoration(
              labelText: widget.review
                  ? 'Ghi chú của người duyệt'
                  : 'Lý do đi muộn',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          if (widget.review) ...[
            BusyButton(
              busy: busy,
              onPressed: () => submit('Approved'),
              label: 'Chấp thuận',
              icon: Icons.check,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: busy ? null : () => submit('Rejected'),
              child: const Text('Từ chối'),
            ),
          ] else
            BusyButton(
              busy: busy,
              onPressed: submit,
              label: 'Gửi giải trình',
              icon: Icons.send_outlined,
            ),
          const SizedBox(height: 16),
          const Text(
            'Phê duyệt giải trình không thay đổi giờ vào ca đã ghi nhận.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
