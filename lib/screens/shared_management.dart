import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../providers/session.dart';
import '../widgets/common.dart';
import 'shared_attendance.dart';

String resourceTitle(String kind) => switch (kind) {
  'employees' => 'Nhân viên',
  'branches' => 'Chi nhánh',
  _ => 'Ca làm việc',
};
bool resourceWrite(Session s, String kind) =>
    kind == 'shifts' ? s.user!.canManage : s.user!.isAdmin;

class SharedResourceScreen extends StatefulWidget {
  final String kind;
  final bool embedded;
  const SharedResourceScreen({
    super.key,
    required this.kind,
    this.embedded = false,
  });
  @override
  State<SharedResourceScreen> createState() => _SharedResourceScreenState();
}

class _SharedResourceScreenState extends State<SharedResourceScreen> {
  int revision = 0;
  Future<void> edit([Json? row]) async {
    await openPage(context, SharedEditor(kind: widget.kind, row: row));
    if (mounted) setState(() => revision++);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final body = LoadView<List<Json>>(
      refreshInterval: const Duration(seconds: 15),
      key: ValueKey(revision),
      load: () => session.api.list('/${widget.kind}'),
      builder: (rows, reload) => RefreshIndicator(
        onRefresh: () async => reload(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            SectionTitle(
              resourceTitle(widget.kind),
              caption: 'Dữ liệu trong phạm vi tài khoản của bạn.',
              action: resourceWrite(session, widget.kind)
                  ? IconButton(
                      onPressed: () => edit(),
                      tooltip: 'Thêm mới',
                      icon: const Icon(Icons.add_circle, color: blue),
                    )
                  : null,
            ),
            const SizedBox(height: 20),
            if (rows.isEmpty)
              const EmptyState(
                'Chưa có dữ liệu. Tài khoản cần được gán chi nhánh và phân ca.',
              ),
            for (final row in rows)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(
                    '${row['fullName'] ?? row['name'] ?? row['title']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    widget.kind == 'shifts'
                        ? '${row['employeeName'] ?? ''} · ${row['branchName'] ?? ''}\n${dateTime(row['startsAt'])} — ${dateTime(row['endsAt'])}'
                        : widget.kind == 'employees'
                        ? '${row['email']}\n${statusLabel(row['role'] as String?)} · ${statusLabel(row['status'] as String?)}'
                        : '${row['address']}\nBán kính ${row['radiusMeters']} m',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await openPage(
                      context,
                      SharedResourceDetail(
                        kind: widget.kind,
                        id: row['id'] as String,
                      ),
                    );
                    if (mounted) setState(() => revision++);
                  },
                ),
              ),
          ],
        ),
      ),
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: Text(resourceTitle(widget.kind))),
            body: PageBody(child: body),
          );
  }
}

class SharedResourceDetail extends StatefulWidget {
  final String kind, id;
  const SharedResourceDetail({super.key, required this.kind, required this.id});
  @override
  State<SharedResourceDetail> createState() => _SharedResourceDetailState();
}

class _SharedResourceDetailState extends State<SharedResourceDetail> {
  int revision = 0;
  bool busy = false;
  Future<void> remove() async {
    if (!await confirm(
      context,
      'Xác nhận xóa?',
      widget.kind == 'employees'
          ? 'Tài khoản sẽ bị vô hiệu hóa; lịch sử được giữ lại.'
          : 'Server sẽ từ chối nếu dữ liệu đã được sử dụng.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await context.read<Session>().api.delete('/${widget.kind}/${widget.id}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) notice(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    return Scaffold(
      appBar: AppBar(title: Text(resourceTitle(widget.kind))),
      body: LoadView<Json>(
        key: ValueKey(revision),
        load: () => session.api.get('/${widget.kind}/${widget.id}'),
        builder: (row, reload) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            SectionTitle('${row['fullName'] ?? row['name'] ?? row['title']}'),
            const SizedBox(height: 20),
            if (widget.kind == 'employees') ...[
              InfoLine('Username', row['username']),
              InfoLine('Email', row['email']),
              InfoLine('Vai trò', statusLabel(row['role'] as String?)),
              InfoLine('Trạng thái', statusLabel(row['status'] as String?)),
              InfoLine(
                'Xác minh email',
                row['emailVerified'] == true ? 'Đã xác minh' : 'Chưa xác minh',
              ),
            ],
            if (widget.kind == 'branches') ...[
              InfoLine('Địa chỉ', row['address']),
              InfoLine('Vĩ độ', row['latitude']),
              InfoLine('Kinh độ', row['longitude']),
              InfoLine('Bán kính', '${row['radiusMeters']} m'),
              if (row['timePolicy'] is Map)
                for (final pair in const {
                  'checkInEarlyMinutes': 'Vào sớm',
                  'lateGraceMinutes': 'Dung sai muộn',
                  'earlyLeaveGraceMinutes': 'Dung sai về sớm',
                  'checkOutLateMinutes': 'Ra trễ tối đa',
                }.entries)
                  InfoLine(pair.value, '${row['timePolicy'][pair.key]} phút'),
            ],
            if (widget.kind == 'shifts') ...[
              InfoLine('Nhân viên', row['employeeName'] ?? row['employeeId']),
              InfoLine('Chi nhánh', row['branchName'] ?? row['branchId']),
              InfoLine('Bắt đầu', dateTime(row['startsAt'])),
              InfoLine('Kết thúc', dateTime(row['endsAt'])),
              InfoLine('Trạng thái', statusLabel(row['status'] as String?)),
              if (row['planLocked'] == true)
                const Text(
                  'Ca đã có lịch sử: chỉ được sửa tên ca.',
                  style: TextStyle(color: muted),
                ),
              if (row['employeeId'] == session.user!.id) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () async {
                    await openPage(context, SharedPunch(shift: row));
                    if (mounted) setState(() => revision++);
                  },
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Chấm công ca này'),
                ),
                TextButton(
                  onPressed: () =>
                      openPage(context, SharedCorrectionEditor(shift: row)),
                  child: const Text('Gửi đề nghị điều chỉnh giờ'),
                ),
              ],
            ],
            const SizedBox(height: 24),
            if (resourceWrite(session, widget.kind)) ...[
              BusyButton(
                busy: busy,
                onPressed: () async {
                  await openPage(
                    context,
                    SharedEditor(kind: widget.kind, row: row),
                  );
                  if (mounted) setState(() => revision++);
                },
                label: 'Chỉnh sửa',
                icon: Icons.edit_outlined,
              ),
              TextButton(
                onPressed: busy ? null : remove,
                child: const Text(
                  'Xóa / vô hiệu hóa',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SharedEditor extends StatefulWidget {
  final String kind;
  final Json? row;
  const SharedEditor({super.key, required this.kind, this.row});
  @override
  State<SharedEditor> createState() => _SharedEditorState();
}

class _SharedEditorState extends State<SharedEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  String? role, status, branchId, employeeId;
  bool busy = false;
  late Future<List<List<Json>>> options;
  bool get locked =>
      widget.kind == 'shifts' && widget.row?['planLocked'] == true;
  @override
  void initState() {
    super.initState();
    final row = widget.row ?? {};
    final keys = switch (widget.kind) {
      'employees' => ['fullName', 'username', 'email', 'password'],
      'branches' => [
        'name',
        'address',
        'latitude',
        'longitude',
        'radiusMeters',
      ],
      _ => ['title', 'startsAt', 'endsAt'],
    };
    for (final key in keys) {
      var value = row[key]?.toString() ?? '';
      if (['startsAt', 'endsAt'].contains(key) && value.isNotEmpty) {
        value = vnTime(value)
            .toIso8601String()
            .substring(0, 16)
            .replaceFirst('T', ' ');
      }
      fields[key] = TextEditingController(text: value);
    }
    role = row['role'] as String? ?? 'employee';
    status = row['status'] as String? ?? 'pending';
    branchId = row['branchId'] as String?;
    employeeId = row['employeeId'] as String?;
    final api = context.read<Session>().api;
    options = widget.kind == 'branches'
        ? Future.value([<Json>[], <Json>[]])
        : Future.wait([
            api.list('/branches'),
            widget.kind == 'shifts'
                ? api.list('/employees')
                : Future.value(<Json>[]),
          ]);
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final body = <String, dynamic>{};
      for (final pair in fields.entries) {
        if (locked && pair.key != 'title') continue;
        final value = pair.key == 'password'
            ? pair.value.text
            : pair.value.text.trim();
        if (pair.key == 'password' && widget.row != null && value.isEmpty) {
          continue;
        }
        body[pair.key] =
            ['latitude', 'longitude', 'radiusMeters'].contains(pair.key)
            ? double.parse(value)
            : ['startsAt', 'endsAt'].contains(pair.key)
            ? parseVietnamInput(value)
            : value;
      }
      if (widget.kind == 'employees') {
        body.addAll({'role': role, 'status': status, 'branchId': branchId});
      }
      if (widget.kind == 'shifts' && !locked) {
        if (branchId == null || employeeId == null) {
          throw const FormatException('Chọn chi nhánh và nhân viên.');
        }
        body.addAll({'branchId': branchId, 'employeeId': employeeId});
      }
      final api = context.read<Session>().api;
      if (widget.row == null) {
        await api.post('/${widget.kind}', body);
      } else {
        await api.patch('/${widget.kind}/${widget.row!['id']}', body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) notice(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget choice(
    String label,
    String? value,
    List<(String, String)> values,
    ValueChanged<String?> changed, {
    bool nullable = false,
  }) {
    final items = [...values];
    if (value != null && !items.any((item) => item.$1 == value)) {
      items.add((value, value));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          if (nullable)
            const DropdownMenuItem(value: null, child: Text('Chưa gán')),
          for (final item in items)
            DropdownMenuItem(
              value: item.$1,
              child: Text(item.$2, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: busy ? null : changed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '${widget.row == null ? 'Thêm' : 'Sửa'} ${resourceTitle(widget.kind).toLowerCase()}',
      ),
    ),
    body: FutureBuilder<List<List<Json>>>(
      future: options,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final lists = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (locked)
                    const Text('Kế hoạch ca đã khóa. Chỉ sửa tên ca.'),
                  for (final pair in fields.entries)
                    if (!locked || pair.key == 'title')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: TextFormField(
                          controller: pair.value,
                          obscureText: pair.key == 'password',
                          keyboardType:
                              [
                                'latitude',
                                'longitude',
                                'radiusMeters',
                              ].contains(pair.key)
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                  signed: true,
                                )
                              : pair.key == 'email'
                              ? TextInputType.emailAddress
                              : TextInputType.text,
                          decoration: InputDecoration(
                            labelText: const {
                              'fullName': 'Họ và tên',
                              'username': 'Tên đăng nhập',
                              'email': 'Email',
                              'password': 'Mật khẩu',
                              'name': 'Tên chi nhánh',
                              'address': 'Địa chỉ',
                              'latitude': 'Vĩ độ',
                              'longitude': 'Kinh độ',
                              'radiusMeters': 'Bán kính (m)',
                              'title': 'Tên ca',
                              'startsAt': 'Bắt đầu (giờ Việt Nam)',
                              'endsAt': 'Kết thúc (giờ Việt Nam)',
                            }[pair.key],
                            helperText:
                                ['startsAt', 'endsAt'].contains(pair.key)
                                ? 'yyyy-MM-dd HH:mm, ví dụ 2026-10-30 08:00'
                                : pair.key == 'password' && widget.row != null
                                ? 'Để trống nếu không đổi mật khẩu'
                                : null,
                          ),
                          validator: (v) =>
                              (v?.trim().isEmpty ?? true) &&
                                  !(pair.key == 'password' &&
                                      widget.row != null)
                              ? 'Không được để trống'
                              : null,
                        ),
                      ),
                  if (widget.kind != 'branches' && !locked)
                    choice(
                      'Chi nhánh',
                      branchId,
                      [
                        for (final r in lists[0])
                          (r['id'] as String, r['name'] as String),
                      ],
                      (v) => setState(() => branchId = v),
                      nullable: widget.kind == 'employees',
                    ),
                  if (widget.kind == 'shifts' && !locked)
                    choice('Nhân viên', employeeId, [
                      for (final r in lists[1])
                        (
                          r['id'] as String,
                          '${r['fullName']} · ${statusLabel(r['status'] as String?)}',
                        ),
                    ], (v) => setState(() => employeeId = v)),
                  if (widget.kind == 'employees') ...[
                    choice('Vai trò', role, [
                      for (final r in ['employee', 'manager', 'admin'])
                        (r, statusLabel(r)),
                    ], (v) => setState(() => role = v)),
                    choice('Trạng thái', status, [
                      for (final r in ['pending', 'active', 'suspended'])
                        (r, statusLabel(r)),
                    ], (v) => setState(() => status = v)),
                  ],
                  BusyButton(
                    busy: busy,
                    onPressed: save,
                    label: 'Lưu thay đổi',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

String parseVietnamInput(String input) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(input)) {
    throw const FormatException('Giờ phải có dạng yyyy-MM-dd HH:mm.');
  }
  final parsed = DateTime.tryParse('${input.replaceFirst(' ', 'T')}:00+07:00');
  if (parsed == null ||
      vnTime(parsed.toIso8601String())
              .toIso8601String()
              .substring(0, 16)
              .replaceFirst('T', ' ') !=
          input) {
    throw const FormatException('Ngày giờ không hợp lệ.');
  }
  return parsed.toUtc().toIso8601String();
}
