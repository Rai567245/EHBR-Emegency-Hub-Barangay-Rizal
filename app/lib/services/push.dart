import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import 'api.dart';

/// Push notifications through Firebase Cloud Messaging.
///
/// Safe to call when Firebase isn't set up (or on the web): it quietly stays
/// off and the in-app notification list keeps working.
class Push {
  static const topic = 'residents';
  static bool active = false;
  static String? _token;
  static final List<StreamSubscription<dynamic>> _subs = [];

  static Future<void> start({
    required void Function(String title, String body) onForeground,
    required VoidCallback onOpened,
  }) async {
    if (kIsWeb || active) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }
      final fm = FirebaseMessaging.instance;
      final perm = await fm.requestPermission(alert: true, badge: true, sound: true);
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;

      _token = await fm.getToken();
      if (_token != null) await Api.registerDevice(_token!, defaultTargetPlatform.name);
      await fm.subscribeToTopic(topic);

      _subs.add(fm.onTokenRefresh.listen((t) {
        _token = t;
        Api.registerDevice(t, defaultTargetPlatform.name).catchError((_) {});
      }));
      // App is open: the system shows nothing, so we show our own banner.
      _subs.add(FirebaseMessaging.onMessage.listen((m) =>
          onForeground(m.notification?.title ?? 'Emergency Hub', m.notification?.body ?? '')));
      // App was in the background / closed and the user tapped the notification.
      _subs.add(FirebaseMessaging.onMessageOpenedApp.listen((_) => onOpened()));
      if (await fm.getInitialMessage() != null) onOpened();

      active = true;
    } catch (e) {
      debugPrint('Push notifications are off: $e');
    }
  }

  /// Called on log-out (or when the login expires) so this phone stops
  /// receiving the account's alerts. Safe to call twice / re-entrantly.
  static Future<void> stop() async {
    if (!active) return;
    active = false; // first, so a 401 during cleanup can't re-enter
    final token = _token;
    _token = null;
    final subs = List<StreamSubscription<dynamic>>.of(_subs);
    _subs.clear();
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      if (token != null) await Api.unregisterDevice(token);
    } catch (_) {
      // nothing more we can do
    }
    for (final s in subs) {
      await s.cancel();
    }
  }
}
