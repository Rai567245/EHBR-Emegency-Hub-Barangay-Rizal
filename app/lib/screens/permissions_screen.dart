import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

const _seenKey = 'permissions_intro_seen';

Future<bool> permissionsIntroSeen() async {
  try {
    return (await SharedPreferences.getInstance()).getBool(_seenKey) ?? false;
  } catch (_) {
    return true;
  }
}

/// Friendly explainer shown once on first launch (Figma: RES-PERM). Location, then notifications.
/// The real system prompts appear only when the person taps "Allow"; "Not now" never blocks the app.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  int _step = 0;

  static const _pages = [
    (
      icon: Icons.location_on_outlined,
      title: 'Allow location access',
      text: 'EHBR uses your location to show nearby reports and safe zones, and to share where you are when you send an SOS or a report.',
      points: ['See hazards and shelters near you', 'Attach your location to reports automatically', 'Share your position with responders during SOS'],
      allow: 'Allow Location',
    ),
    (
      icon: Icons.notifications_none_rounded,
      title: 'Turn on alerts',
      text: 'Get warnings from your barangay right away – typhoons, floods, road blockages and evacuation notices.',
      points: ['Emergency announcements from Barangay Rizal', 'Updates when your report changes status', 'Only important alerts – no spam'],
      allow: 'Allow Notifications',
    ),
  ];

  Future<void> _finish() async {
    try {
      (await SharedPreferences.getInstance()).setBool(_seenKey, true);
    } catch (_) {}
    widget.onDone();
  }

  Future<void> _next({required bool allow}) async {
    if (allow && _step == 0) {
      try {
        final p = await Geolocator.checkPermission();
        if (p == LocationPermission.denied) await Geolocator.requestPermission();
      } catch (_) {}
    }
    // Notifications: the system prompt is raised by the app itself right after sign-in.
    if (_step >= _pages.length - 1) {
      await _finish();
    } else if (mounted) {
      setState(() => _step++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _pages[_step];
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 36, 16, 20),
          child: Column(
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: const BoxDecoration(color: Color(0xFFFCE8EB), shape: BoxShape.circle),
                child: Icon(p.icon, size: 48, color: EhbrColors.brand),
              ),
              const SizedBox(height: 28),
              Text(p.title, textAlign: TextAlign.center, style: manrope(24, FontWeight.w500, EhbrColors.ink)),
              const SizedBox(height: 14),
              Text(p.text, textAlign: TextAlign.center, style: manrope(14, FontWeight.w400, EhbrColors.muted)),
              const SizedBox(height: 22),
              for (final t in p.points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.check, size: 18, color: Color(0xFF1E7A46)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(t, style: manrope(14, FontWeight.w500, EhbrColors.ink))),
                  ]),
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: EhbrColors.brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () => _next(allow: true),
                  child: Text(p.allow, style: manrope(16, FontWeight.w600, Colors.white)),
                ),
              ),
              TextButton(
                onPressed: () => _next(allow: false),
                child: Text('Not now', style: manrope(14, FontWeight.w600, EhbrColors.brand)),
              ),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _step ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(color: i == _step ? EhbrColors.brand : const Color(0xFFD0D0D0), borderRadius: BorderRadius.circular(8)),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
