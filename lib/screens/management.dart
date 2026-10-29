import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/theme.dart';
import '../core/format.dart';
import '../providers/session.dart';
import '../services/location.dart';
import '../widgets/common.dart';

enum ManagementKind { employees, shifts, workplaces }

extension KindInfo on ManagementKind {
  String get path => '/$name';
  String get title => switch (this) {
    ManagementKind.employees => 'Nhân viên',
    ManagementKind.shifts => 'Ca làm việc',
    ManagementKind.workplaces => 'Địa điểm',
  };
  IconData get icon => switch (this) {
    ManagementKind.employees => Icons.person_outline,
    ManagementKind.shifts => Icons.calendar_month_outlined,
    ManagementKind.workplaces => Icons.location_on_outlined,
  };
}

class ManagementScreen extends StatefulWidget {
  final ManagementKind kind;
  final bool embedded;
  const ManagementScreen({
    super.key,
    required this.kind,
    this.embedded = false,
  });
  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen> {
  int revision = 0;
  bool busy = false;
  Future<void> edit([Json? row]) async {
    final result = await openPage<bool>(
      context,
      ManagementEditor(kind: widget.kind, row: row),
    );
    if (result == true && mounted) setState(() => revision++);
  }

  Future<void> remove(Json row) async {
    final employee = widget.kind == ManagementKind.employees;
    if (!await confirm(
      context,
      employee ? 'Vô hiệu hóa nhân viên?' : 'Xóa dữ liệu?',
      employee
          ? 'Nhân viên sẽ mất quyền đăng nhập. Lịch sử chấm công được giữ lại.'
          : 'Chỉ có thể xóa dữ liệu chưa có bản ghi liên quan.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await context.read<Session>().api.delete(
        '${widget.kind.path}/${row['id']}',
      );
      if (mounted) {
        notice(context, employee ? 'Đã vô hiệu hóa nhân viên.' : 'Đã xóa.');
        setState(() => revision++);
      }
    } catch (e) {
      if (mounted) notice(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void detail(Json row) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row['full_name'] ?? row['name'],
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final e in row.entries) InfoLine(e.key, e.value),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: SectionTitle(
            kind.title,
            caption: 'Dữ liệu đồng bộ từ hệ thống.',
            action: IconButton.filled(
              onPressed: busy ? null : () => edit(),
              tooltip: 'Thêm mới',
              icon: const Icon(Icons.add),
            ),
          ),
        ),
        if (busy) const LinearProgressIndicator(),
        Expanded(
          child: ApiList(
            key: ValueKey(revision),
            load: (offset) => context.read<Session>().api.list(
              '${kind.path}?limit=50&offset=$offset',
            ),
            item: (row, reload) {
              final locked =
                  kind == ManagementKind.shifts && row['attendance_id'] != null;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: blue.withValues(alpha: .08),
                            child: Icon(kind.icon, color: blue),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              row['full_name'] ?? row['name'] ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => detail(row),
                            tooltip: 'Xem chi tiết',
                            icon: const Icon(Icons.info_outline, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (kind == ManagementKind.employees) ...[
                        Text(
                          row['email'],
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            StatusBadge(row['status']),
                            StatusBadge(row['role']),
                            if ((row['department'] ?? '').isNotEmpty)
                              Text(row['department']),
                          ],
                        ),
                      ],
                      if (kind == ManagementKind.shifts) ...[
                        Text(
                          '${dateOnly(row['start_at'])} · ${timeOnly(row['start_at'])} – ${timeOnly(row['end_at'])}',
                        ),
                        Text(
                          '${row['full_name']} · ${row['workplace_name']}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        if (locked)
                          const Text(
                            'Đã chấm công · ca được khóa',
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                      ],
                      if (kind == ManagementKind.workplaces) ...[
                        Text(row['address']),
                        Text(
                          'Bán kính ${row['allowed_radius']}m · ${row['latitude']}, ${row['longitude']}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                      const Divider(height: 26),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: busy || locked ? null : () => edit(row),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Chỉnh sửa'),
                          ),
                          TextButton.icon(
                            onPressed: busy || locked
                                ? null
                                : () => remove(row),
                            icon: const Icon(Icons.block_outlined, size: 18),
                            label: Text(
                              kind == ManagementKind.employees
                                  ? 'Vô hiệu hóa'
                                  : 'Xóa',
                            ),
                          ),
                          if (kind == ManagementKind.workplaces)
                            TextButton.icon(
                              onPressed: () => openPage(
                                context,
                                QrGeneratorScreen(workplace: row),
                              ),
                              icon: const Icon(Icons.qr_code, size: 18),
                              label: const Text('Tạo QR'),
                            ),
                        ],
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
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: Text('Quản lý ${kind.title.toLowerCase()}')),
            body: PageBody(child: body),
          );
  }
}

class ManagementEditor extends StatefulWidget {
  final ManagementKind kind;
  final Json? row;
  const ManagementEditor({super.key, required this.kind, this.row});
  @override
  State<ManagementEditor> createState() => _ManagementEditorState();
}

class _ManagementEditorState extends State<ManagementEditor> {
  final form = GlobalKey<FormState>();
  final controllers = <String, TextEditingController>{};
  final selected = <String, String>{};
  late Future<Map<String, List<Json>>> options;
  bool busy = false;
  String? error;
  static const names = {
    'fullName': 'Họ và tên',
    'username': 'Tên đăng nhập',
    'email': 'Email',
    'password': 'Mật khẩu ban đầu',
    'phone': 'Điện thoại',
    'department': 'Phòng ban',
    'position': 'Chức vụ',
    'name': 'Tên',
    'address': 'Địa chỉ',
    'latitude': 'Vĩ độ',
    'longitude': 'Kinh độ',
    'allowedRadius': 'Bán kính cho phép (m)',
  };
  static const dbNames = {
    'fullName': 'full_name',
    'allowedRadius': 'allowed_radius',
    'employeeId': 'employee_id',
    'workplaceId': 'workplace_id',
    'startAt': 'start_at',
    'endAt': 'end_at',
  };
  List<String> get keys => switch (widget.kind) {
    ManagementKind.employees => [
      'fullName',
      if (widget.row == null) 'username',
      'email',
      if (widget.row == null) 'password',
      'phone',
      'department',
      'position',
    ],
    ManagementKind.workplaces => [
      'name',
      'address',
      'latitude',
      'longitude',
      'allowedRadius',
    ],
    ManagementKind.shifts => ['name', 'startAt', 'endAt'],
  };
  @override
  void initState() {
    super.initState();
    for (final key in keys) {
      controllers[key] = TextEditingController(
        text:
            widget.row?[dbNames[key] ?? key]?.toString() ??
            (key == 'allowedRadius' ? '150' : ''),
      );
    }
    selected['role'] = widget.row?['role'] ?? 'EMPLOYEE';
    selected['status'] = widget.row?['status'] ?? 'ACTIVE';
    for (final key in ['employeeId', 'workplaceId']) {
      final value = widget.row?[dbNames[key]];
      if (value != null) selected[key] = value.toString();
    }
    if (widget.kind == ManagementKind.shifts) {
      final now = DateTime.now().toUtc().add(const Duration(hours: 7));
      controllers['startAt']!.text =
          widget.row?['start_at'] ??
          DateTime.utc(
            now.year,
            now.month,
            now.day,
            8,
          ).subtract(const Duration(hours: 7)).toIso8601String();
      controllers['endAt']!.text =
          widget.row?['end_at'] ??
          DateTime.utc(
            now.year,
            now.month,
            now.day,
            17,
          ).subtract(const Duration(hours: 7)).toIso8601String();
    }
    options = loadOptions();
  }

  Future<List<Json>> all(String path) async {
    final api = context.read<Session>().api;
    final rows = <Json>[];
    while (true) {
      final page = await api.list('$path?limit=200&offset=${rows.length}');
      rows.addAll(page);
      if (page.length < 200) break;
    }
    return rows;
  }

  Future<Map<String, List<Json>>> loadOptions() async {
    if (widget.kind != ManagementKind.shifts) return {};
    final result = await Future.wait([all('/employees'), all('/workplaces')]);
    return {
      'employeeId': result[0]
          .where((e) => e['role'] == 'EMPLOYEE' && e['status'] == 'ACTIVE')
          .toList(),
      'workplaceId': result[1],
    };
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pickDate(String key) async {
    final initial = vnTime(controllers[key]!.text);
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
    setState(
      () => controllers[key]!.text = DateTime.utc(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ).subtract(const Duration(hours: 7)).toIso8601String(),
    );
  }

  Future<void> useGps() async {
    setState(() => busy = true);
    try {
      final p = await currentLocation();
      if (mounted) {
        setState(() {
          controllers['latitude']!.text = p.latitude.toString();
          controllers['longitude']!.text = p.longitude.toString();
        });
      }
    } catch (e) {
      if (mounted) notice(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = <String, dynamic>{
        for (final entry in controllers.entries)
          entry.key: entry.key == 'password'
              ? entry.value.text
              : entry.value.text.trim(),
      };
      if (widget.kind == ManagementKind.workplaces) {
        for (final key in ['latitude', 'longitude', 'allowedRadius']) {
          data[key] = double.parse(data[key]);
        }
      }
      if (widget.kind == ManagementKind.employees) {
        data['role'] = selected['role'];
        if (widget.row != null) data['status'] = selected['status'];
      }
      if (widget.kind == ManagementKind.shifts) {
        data['employeeId'] = selected['employeeId'];
        data['workplaceId'] = selected['workplaceId'];
      }
      final api = context.read<Session>().api;
      if (widget.row == null) {
        await api.post(widget.kind.path, data);
      } else {
        await api.put('${widget.kind.path}/${widget.row!['id']}', data);
      }
      if (!mounted) return;
      notice(context, 'Đã lưu dữ liệu.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '${widget.row == null ? 'Thêm' : 'Sửa'} ${widget.kind.title.toLowerCase()}',
      ),
    ),
    body: PageBody(
      child: FutureBuilder<Map<String, List<Json>>>(
        future: options,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(snapshot.error.toString()),
                  TextButton(
                    onPressed: () => setState(() => options = loadOptions()),
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final key in keys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: ['startAt', 'endAt'].contains(key)
                          ? ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              tileColor: Colors.white,
                              leading: const Icon(Icons.schedule, color: blue),
                              title: Text(
                                key == 'startAt'
                                    ? 'Bắt đầu ca (giờ Việt Nam)'
                                    : 'Kết thúc ca (giờ Việt Nam)',
                              ),
                              subtitle: Text(dateTime(controllers[key]!.text)),
                              onTap: () => pickDate(key),
                            )
                          : TextFormField(
                              controller: controllers[key],
                              obscureText: key == 'password',
                              keyboardType:
                                  [
                                    'latitude',
                                    'longitude',
                                    'allowedRadius',
                                  ].contains(key)
                                  ? const TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: true,
                                    )
                                  : key == 'email'
                                  ? TextInputType.emailAddress
                                  : TextInputType.text,
                              decoration: InputDecoration(
                                labelText: names[key],
                                helperText: key == 'password'
                                    ? 'Ít nhất 10 ký tự, gồm chữ và số'
                                    : null,
                              ),
                              validator: (value) {
                                final v = value ?? '';
                                if (![
                                      'phone',
                                      'department',
                                      'position',
                                    ].contains(key) &&
                                    v.trim().isEmpty) {
                                  return 'Không được để trống';
                                }
                                if ([
                                      'latitude',
                                      'longitude',
                                      'allowedRadius',
                                    ].contains(key) &&
                                    double.tryParse(v) == null) {
                                  return 'Nhập số hợp lệ';
                                }
                                if (key == 'email' &&
                                    !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                        .hasMatch(v)) {
                                  return 'Email không hợp lệ';
                                }
                                return null;
                              },
                            ),
                    ),
                  if (widget.kind == ManagementKind.employees) ...[
                    DropdownButtonFormField<String>(
                      initialValue: selected['role'],
                      decoration: const InputDecoration(labelText: 'Vai trò'),
                      items: ['EMPLOYEE', 'ADMIN']
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(statusLabel(v)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => selected['role'] = v!,
                    ),
                    const SizedBox(height: 18),
                    if (widget.row != null)
                      DropdownButtonFormField<String>(
                        initialValue: selected['status'],
                        decoration: const InputDecoration(
                          labelText: 'Trạng thái',
                        ),
                        items: ['ACTIVE', 'INACTIVE']
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(statusLabel(v)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => selected['status'] = v!,
                      ),
                  ],
                  if (widget.kind == ManagementKind.shifts)
                    for (final key in ['employeeId', 'workplaceId'])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: DropdownButtonFormField<String>(
                          initialValue:
                              (snapshot.data![key] ?? []).any(
                                (e) => e['id'] == selected[key],
                              )
                              ? selected[key]
                              : null,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: key == 'employeeId'
                                ? 'Nhân viên'
                                : 'Địa điểm',
                          ),
                          items: (snapshot.data![key] ?? [])
                              .map(
                                (r) => DropdownMenuItem(
                                  value: r['id'] as String,
                                  child: Text(
                                    r['full_name'] ?? r['name'],
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => selected[key] = v!,
                          validator: (v) => v == null ? 'Vui lòng chọn' : null,
                        ),
                      ),
                  if (widget.kind == ManagementKind.workplaces)
                    OutlinedButton.icon(
                      onPressed: busy ? null : useGps,
                      icon: const Icon(Icons.my_location),
                      label: const Text('Dùng tọa độ GPS hiện tại'),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 24),
                  BusyButton(
                    busy: busy,
                    onPressed: save,
                    label: 'Lưu thông tin',
                    icon: Icons.check,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class QrGeneratorScreen extends StatefulWidget {
  final Json workplace;
  const QrGeneratorScreen({super.key, required this.workplace});
  @override
  State<QrGeneratorScreen> createState() => _QrGeneratorScreenState();
}

class _QrGeneratorScreenState extends State<QrGeneratorScreen> {
  Json? qr;
  bool busy = false;
  String? error;
  late Timer timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => generate());
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  Future<void> generate() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await context.read<Session>().api.post(
        '/workplaces/${widget.workplace['id']}/qr',
        {},
      );
      if (mounted) setState(() => qr = r);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = qr == null
        ? 0
        : DateTime.parse(qr!['expiresAt'])
              .difference(DateTime.now())
              .inSeconds
              .clamp(0, 90);
    return Scaffold(
      appBar: AppBar(title: const Text('QR chấm công')),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            SectionTitle(
              widget.workplace['name'],
              caption: 'Mã dùng chung tại địa điểm, có hiệu lực 90 giây.',
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    if (qr != null && remaining > 0)
                      QrImageView(
                        data: qr!['token'],
                        size: 250,
                        backgroundColor: Colors.white,
                      )
                    else
                      const SizedBox(
                        height: 250,
                        child: Center(
                          child: Icon(Icons.qr_code_2, size: 100, color: muted),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      remaining > 0
                          ? 'Còn ${remaining}s'
                          : 'Mã chưa tạo hoặc đã hết hạn',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Nhân viên quét mã này bằng camera trong app.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 24),
            BusyButton(
              busy: busy,
              onPressed: generate,
              label: 'Tạo mã QR mới',
              icon: Icons.refresh,
            ),
          ],
        ),
      ),
    );
  }
}
