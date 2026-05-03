import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'services/firebase_bootstrap.dart';
import 'services/session_manager.dart';
import 'screens/dashboard_screen.dart';
import 'screens/unauthenticated_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BootstrapGate());
}

class _BootstrapGate extends StatefulWidget {
  const _BootstrapGate();

  @override
  State<_BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<_BootstrapGate> {
  late Future<void> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _initialize();
  }

  Future<void> _initialize() {
    return FirebaseBootstrap.initialize().timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        throw StateError('Startup timed out while initializing Firebase.');
      },
    );
  }

  void _retry() {
    setState(() {
      _bootstrapFuture = _initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _BootstrapStatusApp(
            title: 'Starting Glory Grid',
            message: 'Preparing live services and wallet access.',
            loading: true,
          );
        }
        if (snapshot.hasError) {
          return _BootstrapStatusApp(
            title: 'Startup Blocked',
            message:
                'The app could not finish Firebase startup. Retry the web session. If this persists, verify the Firebase web configuration and authorized domain.',
            error: snapshot.error?.toString(),
            onRetry: _retry,
          );
        }
        return ChangeNotifierProvider(
          create: (_) => SessionManager(),
          child: const GameTraderApp(),
        );
      },
    );
  }
}

class _BootstrapStatusApp extends StatelessWidget {
  const _BootstrapStatusApp({
    required this.title,
    required this.message,
    this.loading = false,
    this.error,
    this.onRetry,
  });

  final String title;
  final String message;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Glory Grid',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AppTheme.gameBackground,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.gameSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.gameBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.goldButtonTop,
                          AppTheme.goldButtonBottom,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.goldButtonBottom),
                    ),
                    child: Icon(
                      loading ? Icons.hourglass_bottom : Icons.warning_amber,
                      color: AppTheme.goldText,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                  if (loading) ...[
                    const SizedBox(height: 18),
                    const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.goldButtonBottom,
                      ),
                    ),
                  ],
                  if (error != null && error!.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.gameBackground,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.gameBorder),
                      ),
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                  if (onRetry != null) ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onRetry,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.goldButtonBottom,
                          foregroundColor: AppTheme.goldText,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: const Text('Retry Startup'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GameTraderApp extends StatelessWidget {
  const GameTraderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionManager>(
      builder: (context, session, _) {
        return MaterialApp(
          title: 'Glory Grid',
          theme: AppTheme.lightTheme,
          debugShowCheckedModeBanner: false,
          home: session.isAuthenticated
              ? const DashboardScreen()
              : buildUnauthenticatedHome(),
        );
      },
    );
  }
}
