import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api.dart';
import 'session.dart';

/// A report that couldn't be sent yet and is waiting on the phone.
class QueuedReport {
  QueuedReport({required this.localId, required this.userId, required this.payload, required this.savedAt, this.error});

  final String localId, userId;
  final Map<String, dynamic> payload;
  final DateTime savedAt;

  /// Set when the server refused it (not just "no signal"); needs the resident's attention.
  String? error;

  String get type => (payload['type'] ?? '') as String;
  String get description => (payload['description'] ?? '') as String;
  String get locationText => (payload['locationText'] ?? '') as String;

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'userId': userId,
        'payload': payload,
        'savedAt': savedAt.toIso8601String(),
        'error': error,
      };

  factory QueuedReport.fromJson(Map<String, dynamic> j) => QueuedReport(
        localId: j['localId'] as String,
        userId: j['userId'] as String,
        payload: Map<String, dynamic>.from(j['payload'] as Map),
        savedAt: DateTime.parse(j['savedAt'] as String),
        error: j['error'] as String?,
      );
}

/// Offline queue for reports. Stored on the phone; sent automatically when
/// the connection returns (while the app is open).
///
/// Every report carries a random `clientId`, so if a send succeeds but the
/// answer gets lost, the retry can't create a duplicate on the server.
class ReportQueue {
  static const _key = 'ehbr_report_queue';
  static final List<QueuedReport> _items = [];
  static bool _loaded = false;
  static bool _flushing = false;

  /// Bumps whenever the queue changes (screens listen to this).
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// Reports sent from the queue during this app session, by localId.
  static final Map<String, Report> sent = {};

  static String newClientId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        _items
          ..clear()
          ..addAll((jsonDecode(raw) as List).map((e) => QueuedReport.fromJson(e as Map<String, dynamic>)));
      } catch (_) {
        // a damaged queue must never stop the app from opening
      }
    }
    _loaded = true;
    changes.value++;
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_items.map((q) => q.toJson()).toList()));
    changes.value++;
  }

  /// Waiting reports for whoever is logged in.
  static List<QueuedReport> get pending =>
      _items.where((q) => q.userId == Session.user?.id).toList(growable: false);

  static Future<QueuedReport> enqueue(Map<String, dynamic> payload) async {
    await load();
    final q = QueuedReport(
      localId: newClientId(),
      userId: Session.user!.id,
      payload: payload,
      savedAt: DateTime.now(),
    );
    _items.add(q);
    await _save();
    return q;
  }

  static Future<void> remove(String localId) async {
    _items.removeWhere((q) => q.localId == localId);
    await _save();
  }

  /// Clears a "server refused it" mark so the next flush tries again.
  static Future<void> retry(String localId) async {
    _pausedUntil = null;
    for (final q in _items) {
      if (q.localId == localId) q.error = null;
    }
    await _save();
  }

  /// Tries to send everything waiting. Stops at the first "still offline".
  /// Returns the reports that reached the barangay in this run.
  static DateTime? _pausedUntil; // set when the server says "too many requests, wait N seconds"

  static Future<List<Report>> flush() async {
    if (_flushing || Api.token == null || Session.user == null) return const [];
    if (_pausedUntil != null && DateTime.now().isBefore(_pausedUntil!)) return const [];
    _flushing = true;
    final delivered = <Report>[];
    try {
      await load();
      var changed = false;
      for (final q in pending) {
        if (q.error != null) continue; // refused earlier – waits for the resident
        try {
          final r = await Api.submitReport(q.payload);
          sent[q.localId] = r;
          delivered.add(r);
          _items.remove(q);
          changed = true;
        } on ApiException catch (e) {
          if (e.isRateLimited || e.status == 503) {
            // Be polite: wait as long as the server asked (at least 20 s, at most 5 min) before trying again.
            final secs = (e.retryAfter ?? 20).clamp(20, 300);
            _pausedUntil = DateTime.now().add(Duration(seconds: secs));
            break;
          }
          if (e.isUnavailable || e.status == 401) break; // still offline – try again later
          q.error = e.message; // the server said no; keep it so the resident can see why
          changed = true;
        }
      }
      if (changed) await _save();
    } finally {
      _flushing = false;
    }
    return delivered;
  }
}
