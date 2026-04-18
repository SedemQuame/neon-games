import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'services/firebase_bootstrap.dart';
import 'services/session_manager.dart';
import 'screens/auth_screen.dart';
import 'screens/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrap.initialize();
  runApp(
    ChangeNotifierProvider(
      create: (_) => SessionManager(),
      child: const GameTraderApp(),
    ),
  );
}

class GameTraderApp extends StatelessWidget {
  const GameTraderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionManager>(
      builder: (context, session, _) {
        return MaterialApp(
          title: 'Gaming Trader App',
          theme: AppTheme.darkTheme,
          home: session.isAuthenticated
              ? const DashboardScreen()
              : const AuthScreen(),
        );
      },
    );
  }
}
