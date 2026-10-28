import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api.dart';
import 'push.dart';

/// Who is logged in + the public app configuration.
///
/// Both are cached on the phone so the app still opens, shows the emergency
/// numbers and lets you file a report when there is no internet.
class Session {
  static AppUser? user;
  static AppConfig config = AppConfig();
  static const _tokenKey = 'ehbr_token';
  static const _userKey = 'ehbr_user';
  static const _configKey = 'ehbr_config';

  /// Fetches the barangay settings (name, SOS number, emergency contacts…).
  /// If the server can't be reached, the last saved copy is used instead.
  static Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = await Api.configJson();
      await prefs.setString(_configKey, jsonEncode(raw));
      config = AppConfig.fromJson(raw);
    } on ApiException catch (e) {
      final cached = prefs.getString(_configKey);
      if (e.isUnavailable && cached != null) {
        config = AppConfig.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      } else {
        rethrow;
      }
    }
  }

  /// True when a saved login is still valid. Works offline using the saved
  /// copy of your profile. Throws [ApiException] only when there is nothing
  /// saved to fall back on.
  static Future<bool> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_tokenKey);
    if (t == null) return false;
    Api.token = t;
    try {
      user = await Api.me();
      await prefs.setString(_userKey, jsonEncode(user!.toJson()));
      return true;
    } on ApiException catch (e) {
      if (e.status == 401) {
        await clear();
        return false;
      }
      final cached = prefs.getString(_userKey);
      if (e.isUnavailable && cached != null) {
        user = AppUser.fromJson(jsonDecode(cached) as Map<String, dynamic>);
        return true;
      }
      rethrow;
    }
  }

  /// Replaces the signed-in user (e.g. after changing the recovery email) and saves it for offline start-up.
  static Future<void> updateUser(AppUser u) async {
    user = u;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_userKey)) await prefs.setString(_userKey, jsonEncode(u.toJson()));
  }

  static Future<void> signIn(Map<String, dynamic> response, {bool remember = true}) async {
    final u = AppUser.fromJson(response['user'] as Map<String, dynamic>);
    if (u.role != 'resident') {
      throw ApiException('This is an admin account. Please use the admin console instead.');
    }
    user = u;
    Api.token = response['token'] as String;
    if (remember) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, Api.token!);
      await prefs.setString(_userKey, jsonEncode(u.toJson()));
    }
  }

  static Future<void> signOut() async {
    await Push.stop(); // forget this phone before the login token is dropped
    await Api.logout();
    await clear();
  }

  static Future<void> clear() async {
    await Push.stop();
    user = null;
    Api.token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }
}
