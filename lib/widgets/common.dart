import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/format.dart';

void notice(BuildContext context, Object message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message.toString()),
      backgroundColor: error ? const Color(0xFFB42338) : navy,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<T?> openPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));
Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    ) ??
    false;

class PageBody extends StatelessWidget {
  final Widget child;
  const PageBody({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1000),
      child: child,
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? caption;
  final Widget? action;
  const SectionTitle(this.title, {super.key, this.caption, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              if (caption != null) ...[
                const SizedBox(height: 7),
                Text(caption!, style: const TextStyle(color: muted)),
              ],
            ],
          ),
        ),
        ?action,
      ],
    ),
  );
}

class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final color =
        [
          'Late',
          'Rejected',
          'INACTIVE',
          'rejected',
          'suspended',
          'clarify',
        ].contains(status)
        ? const Color(0xFFB42338)
        : [
            'Draft',
            'Pending',
            'draft',
            'pending',
            'submitted',
            'open',
          ].contains(status)
        ? const Color(0xFF9B6500)
        : const Color(0xFF087E63);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class LoadView<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(T data, VoidCallback reload) builder;
  final Duration? refreshInterval;
  const LoadView({
    super.key,
    required this.load,
    required this.builder,
    this.refreshInterval,
  });
  @override
  State<LoadView<T>> createState() => _LoadViewState<T>();
}

class _LoadViewState<T> extends State<LoadView<T>> with WidgetsBindingObserver {
  T? data;
  Object? error;
  bool loaded = false, busy = false;
  DateTime? updatedAt;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(fetch());
    final interval = widget.refreshInterval;
    if (interval != null) {
      timer = Timer.periodic(interval, (_) => poll());
    }
  }

  void poll() {
    final state = WidgetsBinding.instance.lifecycleState;
    if (mounted &&
        (state == null || state == AppLifecycleState.resumed) &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      unawaited(fetch());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.refreshInterval != null) {
      poll();
    }
  }

  Future<void> fetch() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await widget.load();
      if (!mounted) return;
      setState(() {
        data = result;
        loaded = true;
        error = null;
        updatedAt = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void reload() => unawaited(fetch());

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      if (error == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 44, color: muted),
              const SizedBox(height: 16),
              Text(error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    final content = widget.builder(data as T, reload);
    if (widget.refreshInterval == null) return content;
    return Column(
      children: [
        Material(
          color: error == null
              ? const Color(0xFFEAF4F7)
              : const Color(0xFFFFF0E8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(
                  error == null ? Icons.sync : Icons.cloud_off,
                  size: 16,
                  color: muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error != null
                        ? 'Mất kết nối · dữ liệu cũ. $error'
                        : 'Tự cập nhật ${widget.refreshInterval!.inSeconds}s · ${timeOnly(updatedAt!.toUtc().toIso8601String())}',
                    style: const TextStyle(fontSize: 11, color: muted),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: busy ? null : reload,
                  tooltip: 'Cập nhật ngay',
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  final String message;
  const EmptyState(this.message, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
    child: Column(
      children: [
        const Icon(Icons.inbox_outlined, size: 46, color: muted),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted),
        ),
      ],
    ),
  );
}

class InfoLine extends StatelessWidget {
  final String label;
  final dynamic value;
  const InfoLine(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ),
        Expanded(
          child: SelectableText(
            value?.toString().isNotEmpty == true ? value.toString() : '—',
          ),
        ),
      ],
    ),
  );
}

class BusyButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  const BusyButton({
    super.key,
    required this.busy,
    required this.onPressed,
    required this.label,
    this.icon,
  });
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: busy ? null : onPressed,
    icon: busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon ?? Icons.arrow_forward_rounded, size: 20),
    label: Text(label),
  );
}

class ApiList extends StatefulWidget {
  final Future<List<Json>> Function(int offset) load;
  final Widget Function(Json row, VoidCallback reload) item;
  final String empty;
  const ApiList({
    super.key,
    required this.load,
    required this.item,
    this.empty = 'Chưa có dữ liệu.',
  });
  @override
  State<ApiList> createState() => _ApiListState();
}

class _ApiListState extends State<ApiList> {
  int offset = 0;
  int revision = 0;
  void reload() => setState(() => revision++);
  @override
  Widget build(BuildContext context) => LoadView<List<Json>>(
    key: ValueKey('$offset-$revision'),
    load: () => widget.load(offset),
    builder: (rows, _) => RefreshIndicator(
      onRefresh: () async => reload(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (rows.isEmpty) EmptyState(widget.empty),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: widget.item(r, reload),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: offset == 0
                    ? null
                    : () => setState(() => offset -= 50),
                child: const Text('Trang trước'),
              ),
              Text('${offset ~/ 50 + 1}'),
              TextButton(
                onPressed: rows.length < 50
                    ? null
                    : () => setState(() => offset += 50),
                child: const Text('Trang sau'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
