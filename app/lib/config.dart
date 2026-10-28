import 'package:flutter/foundation.dart';

/// Where the Emergency Hub server lives.
///
/// Override at run time:  flutter run --dart-define=API_BASE=http://192.168.1.20:3000
/// Defaults: web/desktop/iOS simulator -> localhost, Android emulator -> 10.0.2.2.
/// A physical phone needs your computer's LAN IP (see README).
const String _fromEnv = String.fromEnvironment('API_BASE');

String get apiBase {
  if (_fromEnv.isNotEmpty) return _fromEnv.replaceAll(RegExp(r'/+$'), '');
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:3000';
  }
  return 'http://localhost:3000';
}
