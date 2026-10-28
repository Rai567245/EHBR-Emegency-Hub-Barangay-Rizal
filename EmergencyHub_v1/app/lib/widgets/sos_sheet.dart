import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../location.dart';
import '../services/session.dart';
import '../theme.dart';

/// Opens the SOS bottom sheet (Figma: RES-SOS). Confirm → find location →
/// 4-second cancel window → dial. Handles "no location", "didn't connect" and "no signal".
Future<void> showSosSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _SosSheet(),
    );

enum _Stage { confirm, locating, connecting, noLocation, failed, noSignal }

class _SosSheet extends StatefulWidget {
  const _SosSheet();
  @override
  State<_SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends State<_SosSheet> with SingleTickerProviderStateMixin {
  _Stage _stage = _Stage.confirm;
  ({double lat, double lng})? _where;
  int _left = 4;
  int _failures = 0;
  Timer? _timer;
  bool _locating = false;

  late final AnimationController _hold =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) {
            HapticFeedback.heavyImpact();
            _start();
          }
        });

  String get _number => Session.config.sosNumber;
  String get _hotline => Session.config.hotline;

  @override
  void dispose() {
    _timer?.cancel();
    _hold.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_locating) return;
    _locating = true;
    setState(() => _stage = _Stage.locating);
    try {
      _where = await currentLocation().timeout(const Duration(seconds: 8));
    } catch (_) {
      _where = null;
    }
    _locating = false;
    if (!mounted) return;
    if (_where == null) {
      setState(() => _stage = _Stage.noLocation);
    } else {
      _connect();
    }
  }

  void _connect() {
    _timer?.cancel();
    setState(() {
      _stage = _Stage.connecting;
      _left = 4;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_left <= 1) {
        t.cancel();
        _dial(_number);
      } else {
        setState(() => _left--);
      }
    });
  }

  Future<void> _dial(String number) async {
    bool ok = false;
    try {
      ok = await launchUrl(Uri(scheme: 'tel', path: number));
    } catch (_) {}
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      _failures++;
      setState(() => _stage = _failures >= 2 ? _Stage.noSignal : _Stage.failed);
    }
  }

  Future<void> _text() async {
    final w = _where;
    final body = 'EMERGENCY – I need help.${w == null ? '' : ' My location: https://maps.google.com/?q=${w.lat},${w.lng}'}';
    final to = _hotline.isNotEmpty ? _hotline : _number;
    final ok = await launchUrl(Uri(scheme: 'sms', path: to, queryParameters: {'body': body}));
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final (title, text, steps) = switch (_stage) {
      _Stage.confirm => ('Call Emergency / SOS?', 'This will call the Barangay Rizal emergency line and share your live location with responders.', _steps(0)),
      _Stage.locating => ('Finding you…', 'Getting your location so responders know where you are.', _steps(0)),
      _Stage.connecting => ('Connecting...', 'Calling the Barangay Rizal emergency line. Stay where you are if it is safe.', _steps(1)),
      _Stage.noLocation => ('Can’t find your location', 'You can still call. Tell the responder exactly where you are.', _steps(2)),
      _Stage.failed => ('Call didn’t connect', 'The emergency line did not answer. Try again or use another number.', _steps(0)),
      _Stage.noSignal => ('No Signal', 'The emergency line did not answer. Try again or use another number.', _steps(3)),
    };
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFD0D0D0), borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 22),
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: EhbrColors.brand, shape: BoxShape.circle),
              child: Text('SOS', style: manrope(16, FontWeight.w800, Colors.white)),
            ),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: manrope(22, FontWeight.w800, EhbrColors.ink)),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: manrope(14, FontWeight.w400, EhbrColors.ink)),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF1F1F1), borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                for (var i = 0; i < steps.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                    child: Row(children: [
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: EhbrColors.ink, shape: BoxShape.circle),
                        child: Text('${i + 1}', style: manrope(11, FontWeight.w700, Colors.white)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(steps[i], style: manrope(13, FontWeight.w600, EhbrColors.ink))),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 18),
            ..._actions(),
          ],
        ),
      ),
    );
  }

  List<String> _steps(int variant) => switch (variant) {
        1 => ['Calling emergency line...', 'Barangay responders are alerted', 'A call connects to the emergency line'],
        2 => ['Calling still works', 'Barangay responders are alerted', 'A call connects to the emergency line'],
        3 => ['A text message can still send', 'Barangay responders are alerted', 'A call connects to the emergency line'],
        _ => ['Your location is shared with responders', 'Barangay responders are alerted', 'A call connects to the emergency line'],
      };

  Widget _primary(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: EhbrColors.brand, shape: const StadiumBorder()),
          onPressed: onTap,
          child: Text(label, style: manrope(16, FontWeight.w700, Colors.white)),
        ),
      );

  Widget _outline(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(side: const BorderSide(color: EhbrColors.ink, width: 1.5), shape: const StadiumBorder()),
          onPressed: onTap,
          child: Text(label, style: manrope(15, FontWeight.w600, EhbrColors.ink)),
        ),
      );

  List<Widget> _actions() {
    const gap = SizedBox(height: 10);
    final alt = _number == '911' ? null : '911';
    switch (_stage) {
      case _Stage.confirm:
        return [
          if (Session.config.sosHold) ...[
            Listener(
              onPointerDown: (_) => _hold.forward(),
              onPointerUp: (_) => _hold.status == AnimationStatus.completed ? null : _hold.reset(),
              onPointerCancel: (_) => _hold.reset(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: Stack(children: [
                    Container(color: EhbrColors.brand),
                    AnimatedBuilder(
                      animation: _hold,
                      builder: (_, __) => FractionallySizedBox(
                        widthFactor: _hold.value,
                        child: Container(color: const Color(0xFF9E1230)),
                      ),
                    ),
                    Center(child: Text('Hold to Call', style: manrope(18, FontWeight.w800, Colors.white))),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Keep holding for 3 seconds. Let go to stop.', style: manrope(11, FontWeight.w500, EhbrColors.muted)),
          ] else
            _primary('Call Now', _start),
          const SizedBox(height: 14),
          _outline('Cancel · I don’t need help', () => Navigator.of(context).pop()),
        ];
      case _Stage.locating:
        return [
          const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: CircularProgressIndicator()),
          gap,
          _outline('Cancel', () => Navigator.of(context).pop()),
        ];
      case _Stage.connecting:
        return [
          _outline('Cancel (${_left}s)', () {
            _timer?.cancel();
            Navigator.of(context).pop();
          }),
        ];
      case _Stage.noLocation:
        return [_primary('Call Anyway', () => _connect()), gap, _outline('Retry Location', _start)];
      case _Stage.failed:
        return [
          _primary('Retry Call', _connect),
          gap,
          if (alt != null) ...[_outline('Call $alt Instead', () => _dial(alt)), gap],
          if (_hotline.isNotEmpty)
            TextButton(
              onPressed: () => _dial(_hotline),
              child: Text('Call Barangay Hall · $_hotline', style: manrope(13, FontWeight.w700, EhbrColors.brand)),
            ),
        ];
      case _Stage.noSignal:
        return [_primary('Send SOS by Text', _text), gap, _outline('Try Calling Again', _connect)];
    }
  }
}
