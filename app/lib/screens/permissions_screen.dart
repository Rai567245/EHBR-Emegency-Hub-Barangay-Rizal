
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

const _seenKey = 'permissions_intro_seen';

Future<bool> permissionsIntroSeen() async {
  try {
    return (await SharedPreferences.getInstance())
            .getBool(_seenKey) ??
        false;
  } catch (_) {
    return true;
  }
}

/// Permission introduction shown on first launch.
/// Location is handled here; notification permission remains handled
/// by the app after sign-in.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({
    super.key,
    required this.onDone,
  });

  final VoidCallback onDone;

  @override
  State<PermissionsScreen> createState() =>
      _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  int _step = 0;

  static const Color _red = Color(0xFFC9183A);
  static const Color _paleRed = Color(0xFFFCE8EB);
  static const Color _muted = Color(0xFF666666);
  static const Color _green = Color(0xFF1E7A46);
  static const Color _dotGrey = Color(0xFFC8C8C8);

  static const _pages = [
    (
      icon: Icons.location_on_outlined,
      title: 'Allow location access',
      text:
          'EHBR uses your location to show nearby reports and safe zones, and to share where you are when you send an SOS or a report.',
      points: [
        'See hazards and shelters near you',
        'Attach your location to reports automatically',
        'Share your position with responders during SOS',
      ],
      allow: 'Allow Location',
    ),
    (
      icon: Icons.notifications_none_rounded,
      title: 'Turn on alerts',
      text:
          'Get warnings from your barangay right away – typhoons, floods, road blockages and evacuation notices.',
      points: [
        'Emergency announcements from Barangay Rizal',
        'Updates when your report changes status',
        'Only important alerts – no spam',
      ],
      allow: 'Allow Notifications',
    ),
  ];

  Future<void> _finish() async {
    try {
      await (await SharedPreferences.getInstance())
          .setBool(_seenKey, true);
    } catch (_) {}

    if (!mounted) return;
    widget.onDone();
  }

  Future<void> _next({required bool allow}) async {
    if (allow && _step == 0) {
      try {
        final permission = await Geolocator.checkPermission();

        if (permission == LocationPermission.denied) {
          await Geolocator.requestPermission();
        }
      } catch (_) {}
    }

    // The notification prompt is handled by the app after sign-in.
    if (_step >= _pages.length - 1) {
      await _finish();
    } else if (mounted) {
      setState(() => _step++);
    }
  }

  Widget _buildLogo() {
    return Image.asset(
      'assets/images/ehbr_logo.png',
      width: 38,
      height: 38,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return const SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            Icons.broken_image_outlined,
            color: _red,
            size: 30,
          ),
        );
      },
    );
  }

  Widget _buildProgress() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _pages.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == _step ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == _step ? _red : _dotGrey,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_step];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // EHBR logo
              Center(child: _buildLogo()),

              const SizedBox(height: 20),

              // Large circular permission icon
              Center(
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: const BoxDecoration(
                    color: _paleRed,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    page.icon,
                    size: 52,
                    color: _red,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Title
              Text(
                page.title,
                textAlign: TextAlign.center,
                style: manrope(
                  24,
                  FontWeight.w500,
                  EhbrColors.ink,
                ),
              ),

              const SizedBox(height: 8),

              // Description
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  page.text,
                  textAlign: TextAlign.center,
                  style: manrope(
                    14,
                    FontWeight.w400,
                    _muted,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Permission benefits
              ...page.points.map(
                (point) => Padding(
                  padding: const EdgeInsets.only(
                    bottom: 14,
                    left: 8,
                    right: 4,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.check,
                          size: 18,
                          color: _green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          point,
                          style: manrope(
                            14,
                            FontWeight.w400,
                            EhbrColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Primary action
              SizedBox(
                height: 50,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _next(allow: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    page.allow,
                    style: manrope(
                      16,
                      FontWeight.w500,
                      Colors.white,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 4),

              // Skip action
              SizedBox(
                height: 36,
                child: TextButton(
                  onPressed: () => _next(allow: false),
                  style: TextButton.styleFrom(
                    foregroundColor: _red,
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    'Not now',
                    style: manrope(
                      14,
                      FontWeight.w500,
                      _red,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Page indicator
              _buildProgress(),
            ],
          ),
        ),
      ),
    );
  }
}
