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

class TranduytanApp extends StatelessWidget {
  const TranduytanApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: appNavigatorKey,
    title: 'TRANDUYTAN',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: const AppGate(),
  );
}
