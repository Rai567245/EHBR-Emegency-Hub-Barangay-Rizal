import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/api.dart';
import 'services/session.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // If the server rejects our login (expired / removed), go back to Login.
  Api.onUnauthorized = () {
    Session.clear();
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  };
  runApp(const EhbrApp());
}

class EhbrApp extends StatelessWidget {
  const EhbrApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return MaterialApp(
      title: 'Emergency Hub',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: buildTheme(),
      home: const SplashScreen(),
    );
  }
}
