import 'package:flutter/material.dart';

import '../config.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/auth_widgets.dart';
import 'app_shell.dart';
import 'login_screen.dart';
import 'permissions_screen.dart';

/// Loads the server configuration and any saved login, then routes onward.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<Object?>([
        Future<Object?>(() async {
          await Session.loadConfig();
          return Session.restore();
        }),
        Future<Object?>.delayed(const Duration(milliseconds: 900)),
      ]);
      if (!mounted) return;
      final signedIn = results[0] == true;
      final intro = !await permissionsIntroSeen();
      if (!mounted) return;
      Widget next() => signedIn ? const AppShell() : const LoginScreen();
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (ctx, __, ___) => intro
              ? PermissionsScreen(
                  onDone: () => Navigator.of(ctx).pushReplacement(MaterialPageRoute(builder: (_) => next())),
                )
              : next(),
          transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const EhbrEmblem(size: 100),
              if (_error != null) ...[
                const SizedBox(height: 28),
                Text(_error!,
                    textAlign: TextAlign.center, style: manrope(13, FontWeight.w600, EhbrColors.ink)),
                const SizedBox(height: 6),
                Text('Server address: $apiBase',
                    textAlign: TextAlign.center, style: manrope(11, FontWeight.w400, EhbrColors.muted)),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _boot,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: EhbrColors.ink,
                    side: const BorderSide(color: EhbrColors.ink),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Try again', style: manrope(12, FontWeight.w700, EhbrColors.ink)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
