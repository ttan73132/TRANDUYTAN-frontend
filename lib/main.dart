import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'core/navigation.dart';
import 'providers/session.dart';
import 'routes/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => Session()..initialize(),
      child: const TranduytanApp(),
    ),
  );
}

class TranduytanApp extends StatefulWidget {
  const TranduytanApp({super.key});
  @override
  State<TranduytanApp> createState() => _TranduytanAppState();
}

class _TranduytanAppState extends State<TranduytanApp>
    with WidgetsBindingObserver {
  DateTime? backgroundedAt;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) backgroundedAt = DateTime.now();
    if (state == AppLifecycleState.resumed) {
      final since = backgroundedAt;
      backgroundedAt = null;
      if (since != null &&
          DateTime.now().difference(since) >= const Duration(seconds: 30)) {
        context.read<Session>().lock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<Session>().preferences;
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'TRANDUYTAN',
      debugShowCheckedModeBanner: false,
      theme: appTheme(background: preferences.background),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(
              media.textScaler.scale(14) / 14 * preferences.textScale,
            ),
          ),
          child: child!,
        );
      },
      home: const AppGate(),
    );
  }
}
