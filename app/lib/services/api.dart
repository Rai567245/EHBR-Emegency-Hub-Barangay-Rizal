import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status, this.retryAfter});
  final String message;
  final int? status;

  /// Seconds the server asked us to wait (HTTP 429 / 503), if it said.
  final int? retryAfter;

  /// The server is protecting itself from too many requests.
  bool get isRateLimited => status == 429;

  /// No answer from the server at all (no signal, server down, timeout).
  bool get isOffline => status == null;

  /// Offline, busy, rate-limited or failing – nothing is wrong with the request itself, so retry later.
  /// (A saved report is kept and sent again, never thrown away.)
  bool get isUnavailable => status == null || status! >= 500 || status == 429;

  @override
  String toString() => message;
}

/// Thin client for the Emergency Hub server (see /server).
class Api {
  static String? token;

  /// Called when the server says our login is no longer valid.
  static void Function()? onUnauthorized;

  static Future<dynamic> _send(String method, String path,
      {Map<String, dynamic>? body, bool auth = true}) async {
    final uri = Uri.parse('$apiBase/api$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (auth && token != null) 'Authorization': 'Bearer $token',
    };
    http.Response res;
    try {
      final payload = body == null ? null : jsonEncode(body);
      final Future<http.Response> future = method == 'POST'
          ? http.post(uri, headers: headers, body: payload)
          : http.get(uri, headers: headers);
      res = await future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ApiException('The server took too long to respond. Check your connection and try again.');
    } catch (_) {
      throw ApiException('Cannot reach the server at $apiBase. Is it running?');
    }
    dynamic data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (res.statusCode == 401 && auth) {
      token = null;
      onUnauthorized?.call();
      throw ApiException('Your session expired. Please log in again.', status: 401);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = data is Map && data['error'] is String ? data['error'] as String : 'Request failed (${res.statusCode})';
      final ra = data is Map && data['retryAfter'] is num
          ? (data['retryAfter'] as num).toInt()
          : int.tryParse(res.headers['retry-after'] ?? '');
      throw ApiException(
        res.statusCode == 429 && msg.startsWith('Request failed') ? 'Too many requests. Please wait a moment and try again.' : msg,
        status: res.statusCode,
        retryAfter: ra,
      );
    }
    return data;
  }

  // ---- public
  static Future<Map<String, dynamic>> configJson() async =>
      (await _send('GET', '/config', auth: false)) as Map<String, dynamic>;

  static Future<List<Announcement>> announcements() async =>
      ((await _send('GET', '/announcements', auth: false)) as List)
          .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
          .toList();

  static Future<List<EvacCenter>> centers() async =>
      ((await _send('GET', '/centers', auth: false)) as List)
          .map((e) => EvacCenter.fromJson(e as Map<String, dynamic>))
          .toList();

  /// Roads currently blocked. Never fails the map: an old server without this feature just returns nothing.
  static Future<List<Blockage>> blockages() async {
    try {
      return ((await _send('GET', '/blockages')) as List).map((e) => Blockage.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (e.status == 404) return <Blockage>[];
      rethrow;
    }
  }

  // ---- auth
  static Future<Map<String, dynamic>> login(String contact, String password) async =>
      (await _send('POST', '/auth/login', body: {'contact': contact, 'password': password}, auth: false))
          as Map<String, dynamic>;

  static Future<Map<String, dynamic>> register(Map<String, dynamic> fields) async =>
      (await _send('POST', '/auth/register', body: fields, auth: false)) as Map<String, dynamic>;

  /// Asks the barangay office for a password-reset code. Always succeeds, so it never reveals who is registered.
  /// With [staff] true, skips the email and asks the barangay office instead.
  static Future<void> forgotPassword(String contact, {bool staff = false}) async =>
      _send('POST', '/auth/forgot', body: {'contact': contact, if (staff) 'staff': true}, auth: false);

  /// Sets (or clears, with an empty string) the recovery email. Needs the current password.
  static Future<AppUser> setEmail(String email, String password) async =>
      AppUser.fromJson((await _send('POST', '/me/email', body: {'email': email, 'password': password})) as Map<String, dynamic>);

  static Future<void> changePassword(String current, String next) async =>
      _send('POST', '/me/password', body: {'currentPassword': current, 'newPassword': next});

  /// Sets a new password using the one-time code the office read out.
  static Future<void> resetPassword(String contact, String code, String password) async =>
      _send('POST', '/auth/reset', body: {'contact': contact, 'code': code, 'password': password}, auth: false);

  static Future<AppUser> me() async => AppUser.fromJson((await _send('GET', '/me')) as Map<String, dynamic>);

  static Future<void> logout() async {
    try {
      await _send('POST', '/auth/logout', body: {});
    } catch (_) {
      // logging out locally is enough
    }
  }

  // ---- reports
  static Future<List<PublicReport>> publicReports() async =>
      ((await _send('GET', '/reports/public')) as List)
          .map((e) => PublicReport.fromJson(e as Map<String, dynamic>))
          .toList();

  static Future<List<Report>> myReports() async =>
      ((await _send('GET', '/reports/mine')) as List)
          .map((e) => Report.fromJson(e as Map<String, dynamic>))
          .toList();

  static Future<Report> submitReport(Map<String, dynamic> body) async =>
      Report.fromJson((await _send('POST', '/reports', body: body)) as Map<String, dynamic>);

  // ---- notifications & push
  static Future<NotificationFeed> notifications() async {
    final j = (await _send('GET', '/notifications')) as Map<String, dynamic>;
    return NotificationFeed(
      unread: (j['unread'] ?? 0) as int,
      items: ((j['items'] ?? []) as List)
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<void> markNotificationsRead() async {
    await _send('POST', '/notifications/read', body: {});
  }

  static Future<void> registerDevice(String token, String platform) async {
    await _send('POST', '/devices', body: {'token': token, 'platform': platform});
  }

  static Future<void> unregisterDevice(String token) async {
    await _send('POST', '/devices/remove', body: {'token': token});
  }
}
