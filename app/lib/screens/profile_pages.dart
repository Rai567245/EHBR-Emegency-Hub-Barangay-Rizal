import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../phone.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/password_rules.dart';

Widget _page(BuildContext context, String title, List<Widget> children) => Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: EhbrColors.ink),
        title: Text(title, style: manrope(16, FontWeight.w800, EhbrColors.ink)),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: children),
    );

Widget _card(String title, String body, {Widget? trailing}) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: manrope(14, FontWeight.w800, EhbrColors.ink)),
            const SizedBox(height: 4),
            Text(body, style: manrope(12, FontWeight.w400, EhbrColors.muted)),
          ]),
        ),
        if (trailing != null) trailing,
      ]),
    );

Widget _outlineBtn(String label, VoidCallback onTap) => SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(side: const BorderSide(color: EhbrColors.ink, width: 1.5), shape: const StadiumBorder()),
        onPressed: onTap,
        child: Text(label, style: manrope(14, FontWeight.w700, EhbrColors.ink)),
      ),
    );

/// Figma: Profile – Notifications.
class NotificationsInfoScreen extends StatelessWidget {
  const NotificationsInfoScreen({super.key});
  @override
  Widget build(BuildContext context) => _page(context, 'Notifications', [
        _card('Emergency alerts', 'Urgent warnings for your zone. Always on for your safety.', trailing: const Icon(Icons.check_circle, color: Color(0xFF1E7A46))),
        _card('Report updates', 'You will get a notification when staff verify, dispatch or resolve your report.', trailing: const Icon(Icons.check_circle, color: Color(0xFF1E7A46))),
        _card('Barangay announcements', 'Hazard advisories, notices and events from Barangay Rizal.', trailing: const Icon(Icons.check_circle, color: Color(0xFF1E7A46))),
        const SizedBox(height: 4),
        Text('Permissions are managed in your phone’s settings. If you are not receiving alerts, make sure notifications are allowed for this app.',
            style: manrope(12, FontWeight.w400, EhbrColors.muted)),
        const SizedBox(height: 16),
        _outlineBtn('Open Phone Settings', () => Geolocator.openAppSettings()),
      ]);
}

/// Figma: Profile – Privacy & Security.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});
  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  String _loc = 'Checking…';

  @override
  void initState() {
    super.initState();
    Geolocator.checkPermission().then((p) {
      if (!mounted) return;
      setState(() => _loc = (p == LocationPermission.always || p == LocationPermission.whileInUse) ? 'Allowed' : 'Not allowed');
    }).catchError((_) {
      if (mounted) setState(() => _loc = 'Unknown');
    });
  }

  @override
  Widget build(BuildContext context) => _page(context, 'Privacy & Security', [
        _card('Location permission', 'Used to show nearby reports and to attach your position to reports and SOS.', trailing: Text(_loc, style: manrope(12, FontWeight.w700, EhbrColors.ink))),
        _card('How your data is used', 'Your name and number are visible only to barangay staff. Public reports show your location and type, never your name. You choose what to share each time.'),
        _card('Account security', 'Update your login password. You will be signed in on this phone only.',
            trailing: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
              child: Text('Change', style: manrope(13, FontWeight.w800, EhbrColors.brand)),
            )),
        const SizedBox(height: 8),
        _outlineBtn('Open Phone Settings', () => Geolocator.openAppSettings()),
      ]);
}

/// Uses the server's POST /api/me/password.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _cur = TextEditingController(), _new = TextEditingController(), _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _cur.dispose();
    _new.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!PasswordRules.ok(_new.text)) return setState(() => _error = 'Your new password does not meet all the rules below.');
    if (_new.text != _again.text) return setState(() => _error = 'Passwords do not match.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.changePassword(_cur.text, _new.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated')));
    } on ApiException catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Widget _field(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final match = _again.text.isNotEmpty;
    return _page(context, 'Change Password', [
      Text('Choose a strong password you have not used before.', style: manrope(13, FontWeight.w400, EhbrColors.muted)),
      const SizedBox(height: 14),
      _field('Current password', _cur),
      _field('New password', _new),
      _field('Confirm new password', _again),
      if (match)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(_new.text == _again.text ? 'Passwords match.' : 'Passwords do not match.',
              style: manrope(12, FontWeight.w600, _new.text == _again.text ? const Color(0xFF1E7A46) : EhbrColors.brand)),
        ),
      PasswordRules(password: _new.text),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, style: manrope(12, FontWeight.w600, EhbrColors.brand)),
      ],
      const SizedBox(height: 16),
      SizedBox(
        height: 50,
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: EhbrColors.brand, shape: const StadiumBorder()),
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save Changes', style: manrope(15, FontWeight.w700, Colors.white)),
        ),
      ),
    ]);
  }
}

/// Figma: Profile – Help & Support.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cfg = Session.config;
    const faqs = [
      ('How do I report an incident?', 'Tap Report Incident on Home, pick the type, describe what happened and confirm the location. Staff review it and you get a notification when it changes.'),
      ('What happens when I press SOS?', 'The SOS sheet opens. Hold the button for 3 seconds, and your phone dials the emergency line while your location is prepared for responders. You can cancel during the countdown.'),
      ('Why was my report queued?', 'You had no internet. The report is saved on your phone and sends by itself when you are back online. Nothing is lost.'),
      ('I can’t log in', 'Use Forgot password on the login screen. If you have no recovery email, ask the barangay office for a reset code.'),
    ];
    return _page(context, 'Help & Support', [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFFDEEF0), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFF2B8C0))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('In an emergency', style: manrope(14, FontWeight.w800, EhbrColors.brand)),
          const SizedBox(height: 4),
          Text('Call ${cfg.sosNumber} or hold the SOS button on Home. Do not wait for a report to be reviewed.', style: manrope(12, FontWeight.w400, EhbrColors.ink)),
        ]),
      ),
      const SizedBox(height: 14),
      Text('Frequently asked questions', style: manrope(14, FontWeight.w800, EhbrColors.ink)),
      const SizedBox(height: 6),
      for (final f in faqs)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(f.$1, style: manrope(13, FontWeight.w700, EhbrColors.ink)),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          expandedAlignment: Alignment.centerLeft,
          children: [Text(f.$2, style: manrope(12, FontWeight.w400, EhbrColors.muted))],
        ),
      if (cfg.hotline.isNotEmpty) ...[
        const SizedBox(height: 10),
        _outlineBtn('Call Barangay Hall · ${cfg.hotline}', () => confirmCall(context, 'Barangay Hall', cfg.hotline)),
      ],
    ]);
  }
}
