import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../providers/session.dart';
import '../services/api.dart';
import '../services/location.dart';
import '../widgets/common.dart';
import 'shared_management.dart';

String reviewHint(Json row) {
  final timing = row['timing'] is Map ? row['timing'] as Map : {};
  if (timing['missingCheckOut'] == true ||
      timing['state'] == 'missing_check_out') {
    return 'Thiếu chấm ra: kiểm tra và gửi đề nghị nếu cần.';
  }
  if (timing['state'] == 'missing_check_in') {
    return 'Thiếu chấm vào: đối chiếu lịch làm việc.';
  }
  if (timing['late'] == true) {
    return 'Đi muộn ${timing['arrivalDelayMinutes']} phút theo chính sách ca.';
  }
  if (timing['earlyLeave'] == true) {
    return 'Về sớm ${timing['earlyLeaveMinutes']} phút theo chính sách ca.';
  }
  return '';
}

class SharedAttendanceScreen extends StatefulWidget {
  final bool embedded;
  const SharedAttendanceScreen({super.key, this.embedded = false});
  @override
  State<SharedAttendanceScreen> createState() => _SharedAttendanceScreenState();
}

class _SharedAttendanceScreenState extends State<SharedAttendanceScreen> {
  late final TextEditingController month;
  late String requestedMonth;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    month = TextEditingController(
      text: vnTime(DateTime.now().toUtc().toIso8601String())
          .toIso8601String()
          .substring(0, 7),
    );
    requestedMonth = month.text;
  }

  @override
  void dispose() {
    month.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: month,
                  decoration: const InputDecoration(
                    labelText: 'Tháng đối soát · YYYY-MM',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: () {
                  if (!RegExp(r'^(19|20|21)\d{2}-(0[1-9]|1[0-2])$')
                      .hasMatch(month.text.trim())) {
                    notice(context, 'Nhập tháng dạng YYYY-MM.', error: true);
                    return;
                  }
                  setState(() {
                    requestedMonth = month.text.trim();
                    revision++;
                  });
                },
                tooltip: 'Tải bảng công',
                icon: const Icon(Icons.search),
              ),
            ],
          ),
        ),
        Expanded(
          child: LoadView<Json>(
            refreshInterval: const Duration(seconds: 15),
            key: ValueKey(revision),
            load: () => session.api.get(
              '/reports/monthly?month=${Uri.encodeQueryComponent(requestedMonth)}',
            ),
            builder: (report, reload) {
              final rows = (report['rows'] as List)
                  .cast<Map<String, dynamic>>();
              final totals = report['totals'] as Map;
              final flagged = rows
                  .where((r) => reviewHint(r).isNotEmpty)
                  .length;
              return RefreshIndicator(
                onRefresh: () async => reload(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SectionTitle(
                      'Trợ lý đối soát ca',
                      caption:
                          '${report['timeZone']} · ${totals['shiftCount']} ca · $flagged ca cần kiểm tra',
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Giờ gốc được giữ để đối chiếu. Chỉ gửi đề nghị điều chỉnh nếu có sai sót; bảng này không tính lương.',
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          openPage(context, const SharedCorrections()),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Xem đơn điều chỉnh'),
                    ),
                    if (rows.isEmpty)
                      const EmptyState(
                        'Không có ca trong tháng hoặc phạm vi tài khoản.',
                      ),
                    for (final row in rows)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${row['title']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${row['employeeName']} · ${row['branchName']}',
                                style: const TextStyle(color: muted),
                              ),
                              InfoLine(
                                'Kế hoạch',
                                '${dateTime(row['startsAt'])}\n${dateTime(row['endsAt'])}',
                              ),
                              InfoLine(
                                'Giờ hiện hành',
                                '${timeOnly(row['checkInAt'])} — ${timeOnly(row['checkOutAt'])}',
                              ),
                              InfoLine(
                                'Giờ gốc thiết bị',
                                '${timeOnly(row['recordedCheckInAt'])} — ${timeOnly(row['recordedCheckOutAt'])}',
                              ),
                              if (reviewHint(row).isNotEmpty)
                                Text(
                                  reviewHint(row),
                                  style: const TextStyle(
                                    color: Color(0xFF9B6500),
                                  ),
                                ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: () => openPage(
                                      context,
                                      SharedResourceDetail(
                                        kind: 'shifts',
                                        id: row['shiftId'] as String,
                                      ),
                                    ),
                                    child: const Text('Chi tiết ca'),
                                  ),
                                  if (row['employeeId'] == session.user!.id)
                                    TextButton(
                                      onPressed: () async {
                                        await openPage(
                                          context,
                                          SharedCorrectionEditor(
                                            shift: {
                                              'id': row['shiftId'],
                                              'title': row['title'],
                                            },
                                          ),
                                        );
                                        if (mounted) setState(() => revision++);
                                      },
                                      child: const Text('Đề nghị điều chỉnh'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
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
            appBar: AppBar(title: const Text('Bảng công và đối soát')),
            body: body,
          );
  }
}

class SharedCorrections extends StatefulWidget {
  const SharedCorrections({super.key});
  @override
  State<SharedCorrections> createState() => _SharedCorrectionsState();
}

class _SharedCorrectionsState extends State<SharedCorrections> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Đơn điều chỉnh')),
    body: LoadView<List<Json>>(
      refreshInterval: const Duration(seconds: 15),
      key: ValueKey(revision),
      load: () => context.read<Session>().api.list('/corrections'),
      builder: (rows, reload) => RefreshIndicator(
        onRefresh: () async => reload(),
        child: ListView(
          padding: const EdgeInsets.all(24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const Text(
              'Chọn ca của chính bạn để gửi đơn. Đơn đã duyệt giữ bằng chứng trước và sau thay đổi.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 16),
            if (rows.isEmpty) const EmptyState('Chưa có đơn điều chỉnh.'),
            for (final row in rows)
              Card(
                child: ListTile(
                  title: Text('${row['employeeName'] ?? 'Đề nghị điều chỉnh'}'),
                  subtitle: Text('${row['reason']}'),
                  trailing: StatusBadge(row['status'] as String),
                  onTap: () async {
                    await openPage(
                      context,
                      SharedCorrectionDetail(id: row['id'] as String),
                    );
                    if (mounted) setState(() => revision++);
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class SharedCorrectionDetail extends StatefulWidget {
  final String id;
  const SharedCorrectionDetail({super.key, required this.id});
  @override
  State<SharedCorrectionDetail> createState() => _SharedCorrectionDetailState();
}

class _SharedCorrectionDetailState extends State<SharedCorrectionDetail> {
  int revision = 0;
  bool busy = false;
  Future<void> review(String status) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          status == 'approved' ? 'Duyệt điều chỉnh?' : 'Từ chối điều chỉnh?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Duyệt sẽ cập nhật giờ hiện hành; giờ gốc thiết bị vẫn được giữ.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Ghi chú xử lý (tùy chọn)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (note == null || !mounted) return;
    await run(() async {
      await context.read<Session>().api.patch('/corrections/${widget.id}', {
        'status': status,
        if (note.isNotEmpty) 'resolutionNote': note,
      });
    });
  }

  Future<bool> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
      if (mounted) setState(() => revision++);
      return true;
    } catch (e) {
      if (mounted) notice(context, e, error: true);
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết điều chỉnh')),
      body: LoadView<Json>(
        key: ValueKey(revision),
        load: () => session.api.get('/corrections/${widget.id}'),
        builder: (row, reload) {
          final own = row['employeeId'] == session.user!.id;
          final pending = row['status'] == 'pending';
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              StatusBadge(row['status'] as String),
              const SizedBox(height: 18),
              InfoLine('Nhân viên', row['employeeName'] ?? row['employeeId']),
              InfoLine('Lý do', row['reason']),
              InfoLine('Đề nghị vào', dateTime(row['requestedCheckIn'])),
              InfoLine('Đề nghị ra', dateTime(row['requestedCheckOut'])),
              InfoLine('Ghi chú duyệt', row['resolutionNote']),
              InfoLine('Xử lý lúc', dateTime(row['resolvedAt'])),
              for (final key in ['beforeAttendance', 'afterAttendance'])
                if (row[key] is Map) ...[
                  const Divider(),
                  Text(
                    key == 'beforeAttendance'
                        ? 'Trước điều chỉnh'
                        : 'Sau điều chỉnh',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  InfoLine('Chấm vào', dateTime(row[key]['checkInAt'])),
                  InfoLine('Chấm ra', dateTime(row[key]['checkOutAt'])),
                ],
              if (own && pending) ...[
                BusyButton(
                  busy: busy,
                  onPressed: () async {
                    await openPage(
                      context,
                      SharedCorrectionEditor(
                        shift: {'id': row['shiftId'], 'title': 'Ca làm'},
                        row: row,
                      ),
                    );
                    if (mounted) setState(() => revision++);
                  },
                  label: 'Sửa đơn đang chờ',
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!await confirm(
                            context,
                            'Rút đơn?',
                            'Chỉ đơn đang chờ mới được rút.',
                          )) {
                            return;
                          }
                          if (!mounted) return;
                          final removed = await run(
                            () =>
                                session.api.delete('/corrections/${widget.id}'),
                          );
                          if (removed && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                  child: const Text('Rút đơn'),
                ),
              ],
              if (!own && pending && session.user!.canManage) ...[
                BusyButton(
                  busy: busy,
                  onPressed: () => review('approved'),
                  label: 'Duyệt đề nghị',
                ),
                TextButton(
                  onPressed: busy ? null : () => review('rejected'),
                  child: const Text('Từ chối'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class SharedCorrectionEditor extends StatefulWidget {
  final Json shift;
  final Json? row;
  const SharedCorrectionEditor({super.key, required this.shift, this.row});
  @override
  State<SharedCorrectionEditor> createState() => _SharedCorrectionEditorState();
}

class _SharedCorrectionEditorState extends State<SharedCorrectionEditor> {
  final reason = TextEditingController(),
      checkIn = TextEditingController(),
      checkOut = TextEditingController();
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final row = widget.row;
    if (row != null) {
      reason.text = row['reason'] as String;
      for (final pair in [
        (checkIn, 'requestedCheckIn'),
        (checkOut, 'requestedCheckOut'),
      ]) {
        if (row[pair.$2] != null) {
          pair.$1.text = vnTime(row[pair.$2] as String)
              .toIso8601String()
              .substring(0, 16)
              .replaceFirst('T', ' ');
        }
      }
    }
  }

  @override
  void dispose() {
    reason.dispose();
    checkIn.dispose();
    checkOut.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      if (reason.text.trim().length < 5 || reason.text.trim().length > 2000) {
        throw const FormatException('Lý do cần 5–2000 ký tự.');
      }
      if (checkIn.text.trim().isEmpty && checkOut.text.trim().isEmpty) {
        throw const FormatException('Nhập ít nhất một giờ đề nghị.');
      }
      final body = <String, dynamic>{
        'reason': reason.text.trim(),
        if (checkIn.text.trim().isNotEmpty)
          'requestedCheckIn': parseVietnamInput(checkIn.text.trim()),
        if (checkOut.text.trim().isNotEmpty)
          'requestedCheckOut': parseVietnamInput(checkOut.text.trim()),
      };
      final api = context.read<Session>().api;
      if (widget.row == null) {
        body['shiftId'] = widget.shift['id'];
        await api.post('/corrections', body);
      } else {
        if (checkIn.text.trim().isEmpty) body['requestedCheckIn'] = null;
        if (checkOut.text.trim().isEmpty) body['requestedCheckOut'] = null;
        await api.patch('/corrections/${widget.row!['id']}', body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) notice(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Đề nghị điều chỉnh')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SectionTitle(
          '${widget.shift['title']}',
          caption: 'Chỉ điền giờ bạn đề nghị. Không tự thay giờ gốc để che việc đi muộn.',
        ),
        const SizedBox(height: 20),
        for (final pair in [
          (checkIn, 'Giờ vào đề nghị'),
          (checkOut, 'Giờ ra đề nghị'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              controller: pair.$1,
              decoration: InputDecoration(
                labelText: pair.$2,
                helperText: 'Giờ Việt Nam · yyyy-MM-dd HH:mm; có thể để trống',
              ),
            ),
          ),
        TextField(
          controller: reason,
          minLines: 3,
          maxLines: 6,
          maxLength: 2000,
          decoration: const InputDecoration(
            labelText: 'Lý do, thông tin để đối chiếu',
          ),
        ),
        const SizedBox(height: 20),
        BusyButton(busy: busy, onPressed: save, label: 'Gửi đề nghị'),
      ],
    ),
  );
}

class SharedPunch extends StatefulWidget {
  final Json shift;
  const SharedPunch({super.key, required this.shift});
  @override
  State<SharedPunch> createState() => _SharedPunchState();
}

class _SharedPunchState extends State<SharedPunch> with WidgetsBindingObserver {
  late Future<Json?> record;
  StreamSubscription<UserAccelerometerEvent>? sensor;
  Timer? timer;
  Position? position;
  bool busy = false,
      armed = false,
      checkout = false,
      uncertain = false,
      done = false;
  int seconds = 30, peaks = 0;
  DateTime? lastPeak;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    record = load();
  }

  Future<Json?> load() async {
    final rows = await context.read<Session>().api.list('/attendance');
    return rows.where((r) => r['shiftId'] == widget.shift['id']).firstOrNull;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      stopMotion();
      if (mounted) setState(() => armed = false);
    }
  }

  void stopMotion() {
    sensor?.cancel();
    timer?.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    stopMotion();
    super.dispose();
  }

  Future<void> locate() async {
    setState(() {
      busy = true;
      error = null;
      armed = false;
    });
    stopMotion();
    try {
      final p = await currentLocation();
      if (!mounted) return;
      setState(() {
        position = p;
        armed = true;
        seconds = 30;
        peaks = 0;
        lastPeak = null;
      });
      timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || busy || done) return;
        setState(() => seconds = max(0, seconds - 1));
        if (seconds == 0) {
          stopMotion();
          setState(() => armed = false);
        }
      });
      sensor =
          userAccelerometerEventStream(
            samplingPeriod: SensorInterval.gameInterval,
          ).listen(
            (e) {
              if (!mounted || !armed || busy || done || seconds <= 0) return;
              final now = DateTime.now();
              if (sqrt(e.x * e.x + e.y * e.y + e.z * e.z) > 14 &&
                  (lastPeak == null ||
                      now.difference(lastPeak!).inMilliseconds > 300)) {
                if (lastPeak != null &&
                    now.difference(lastPeak!).inSeconds > 3) {
                  peaks = 0;
                }
                lastPeak = now;
                if (++peaks >= 2) submit();
              }
            },
            onError: (Object e) {
              if (mounted) {
                setState(
                  () => error =
                      'Không đọc được cảm biến. Dùng nút xác nhận bên dưới.',
                );
              }
            },
          );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy || done || uncertain || !armed || seconds <= 0) return;
    setState(() => busy = true);
    stopMotion();
    bool sent = false;
    try {
      final api = context.read<Session>().api;
      final p = await currentLocation();
      if (!mounted) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        throw const ApiException('Mở lại màn hình để xác nhận chấm công.');
      }
      sent = true;
      await api.post('/attendance/${checkout ? 'check-out' : 'check-in'}', {
        'shiftId': widget.shift['id'],
        'latitude': p.latitude,
        'longitude': p.longitude,
        'accuracyMeters': p.accuracy,
      });
      if (mounted) {
        setState(() {
          done = true;
          armed = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          armed = false;
          uncertain = sent && (e is! ApiException || e.status == 0);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chấm công GPS')),
    body: FutureBuilder<Json?>(
      future: record,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final row = snapshot.data;
        checkout = row != null;
        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            SectionTitle(
              '${widget.shift['title']}',
              caption:
                  '${dateTime(widget.shift['startsAt'])} — ${dateTime(widget.shift['endsAt'])}',
            ),
            const SizedBox(height: 24),
            if (done || row?['checkOutAt'] != null) ...[
              const Icon(
                Icons.check_circle_outline,
                color: Color(0xFF087E63),
                size: 80,
              ),
              const SizedBox(height: 20),
              const Text(
                'Máy chủ đã ghi nhận chấm công.',
                textAlign: TextAlign.center,
              ),
            ] else ...[
              Text(
                checkout ? 'Xác nhận ra ca' : 'Xác nhận vào ca',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Server kiểm tra bán kính, sai số GPS và cửa sổ thời gian của ca. Lắc nhẹ hai lần chỉ xác nhận thao tác trên điện thoại, không xác thực danh tính.',
                style: TextStyle(color: muted),
              ),
              if (position != null) ...[
                const SizedBox(height: 18),
                InfoLine(
                  'Vị trí',
                  '${position!.latitude.toStringAsFixed(6)}, ${position!.longitude.toStringAsFixed(6)}',
                ),
                InfoLine('Sai số GPS', '${position!.accuracy.round()} m'),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (uncertain) ...[
                const Text(
                  'Chưa rõ máy chủ đã nhận hay chưa. Kiểm tra lại bản ghi trước khi thực hiện thêm.',
                ),
                FilledButton(
                  onPressed: () => setState(() {
                    uncertain = false;
                    record = load();
                  }),
                  child: const Text('Kiểm tra bản ghi từ máy chủ'),
                ),
              ] else ...[
                const SizedBox(height: 24),
                BusyButton(
                  busy: busy,
                  onPressed: locate,
                  label: 'Lấy GPS và bắt đầu xác nhận',
                  icon: Icons.my_location,
                ),
                if (armed) ...[
                  const SizedBox(height: 20),
                  Text(
                    '$seconds giây · lắc nhẹ hai lần',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  BusyButton(
                    busy: busy,
                    onPressed: seconds > 0 ? submit : null,
                    label: 'Dùng nút xác nhận thay thế',
                  ),
                ],
              ],
            ],
          ],
        );
      },
    ),
  );
}
