import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/auth_widgets.dart';

/// Forgot password, in two steps:
///  1. Ask the barangay office for a code (they confirm who you are first).
///  2. Enter the 8-digit code they give you and choose a new password.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialContact = ''});
  final String initialContact;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  late final _contact = TextEditingController(text: widget.initialContact);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _hide = true;
  bool _haveCode = false; // false = step 1 (ask), true = step 2 (enter code)
  bool _requested = false;
  bool _staffAsked = false; // the resident chose the barangay office instead of (or after) the email
  bool get _email => Session.config.emailReset;
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _contact.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _contactCheck(String? v) => (v == null || v.trim().length < 7) ? 'Enter your contact number' : null;

  Future<void> _request({bool staff = false}) async {
    if (_contactCheck(_contact.text) != null) {
      setState(() => _error = 'Enter the contact number you signed up with');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.forgotPassword(_contact.text.trim(), staff: staff);
      if (mounted) {
        setState(() {
          _requested = true;
          if (staff || !_email) _staffAsked = true;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.resetPassword(_contact.text.trim(), _code.text.trim(), _password.text);
      if (mounted) setState(() => _done = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hotline = Session.config.hotline;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: EhbrColors.ink,
        title: Text('Forgot password', style: manrope(16, FontWeight.w800, EhbrColors.ink)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: _done ? _success(context) : Form(key: _form, child: _haveCode ? _step2(hotline) : _step1(hotline)),
        ),
      ),
    );
  }

  Widget _success(BuildContext context) => Column(
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.check_circle_rounded, size: 64, color: Color(0xFF2E7D32)),
          const SizedBox(height: 14),
          Text('Password changed', style: manrope(20, FontWeight.w800, EhbrColors.ink)),
          const SizedBox(height: 8),
          Text('You were signed out everywhere. Log in with your new password.',
              textAlign: TextAlign.center, style: manrope(13, FontWeight.w400, EhbrColors.muted)),
          const SizedBox(height: 28),
          AuthButton(label: 'Back to login', onPressed: () => Navigator.of(context).pop(), busy: false),
        ],
      );

  Widget _step1(String hotline) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _email
                ? 'Enter the number you signed up with. If your account has an email, we will send you a 6-digit code.'
                : 'For your safety, the barangay office confirms who you are before giving you a reset code.',
            style: manrope(13, FontWeight.w400, EhbrColors.muted),
          ),
          const SizedBox(height: 20),
          const FieldLabel('Contact number'),
          TextFormField(
            controller: _contact,
            enabled: !_requested,
            keyboardType: TextInputType.phone,
            style: darkInputStyle,
            cursorColor: Colors.white,
            decoration: darkDecoration(hint: 'The number you signed up with', icon: Icons.phone),
          ),
          FormError(_error),
          const SizedBox(height: 20),
          if (!_requested)
            AuthButton(label: _email ? 'Send me a code' : 'Request a reset code', onPressed: _request, busy: _busy)
          else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF1F8F1), borderRadius: BorderRadius.circular(10)),
              child: Text(
                _staffAsked
                    ? 'Request sent. Barangay staff can now see it. '
                        '${hotline.isNotEmpty ? 'Call $hotline or visit' : 'Visit'} the barangay hall, confirm who you are, '
                        'and they will give you an 8-digit code (valid for 30 minutes).'
                    : 'If that number is registered and has an email, a 6-digit code is on its way. Check your spam folder too. '
                        'It works once and expires in 15 minutes.',
                style: manrope(13, FontWeight.w500, EhbrColors.ink),
              ),
            ),
            const SizedBox(height: 16),
            AuthButton(label: 'I have my code', onPressed: () => setState(() { _haveCode = true; _error = null; }), busy: false),
          ],
          if (_email && _requested && !_staffAsked) ...[
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: _busy ? null : () => _request(staff: true),
                child: Text('No email, or it did not arrive? Ask the barangay office',
                    textAlign: TextAlign.center, style: manrope(13, FontWeight.w600, EhbrColors.muted)),
              ),
            ),
          ],
          if (!_requested) ...[
            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: () => setState(() { _haveCode = true; _error = null; }),
                child: Text('I already have a code', style: manrope(14, FontWeight.w600, EhbrColors.muted)),
              ),
            ),
          ],
        ],
      );

  Widget _step2(String hotline) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter the code we emailed you (or the one the barangay office gave you) and choose a new password.',
              style: manrope(13, FontWeight.w400, EhbrColors.muted)),
          const SizedBox(height: 20),
          const FieldLabel('Contact number'),
          TextFormField(
            controller: _contact,
            keyboardType: TextInputType.phone,
            style: darkInputStyle,
            cursorColor: Colors.white,
            decoration: darkDecoration(hint: 'The number you signed up with', icon: Icons.phone),
            validator: _contactCheck,
          ),
          const SizedBox(height: 14),
          const FieldLabel('Reset code'),
          TextFormField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 8,
            style: darkInputStyle,
            cursorColor: Colors.white,
            decoration: darkDecoration(hint: 'Code from email or office', icon: Icons.pin_outlined).copyWith(counterText: ''),
            validator: (v) => RegExp(r'^\d{6,8}$').hasMatch((v ?? '').trim()) ? null : 'Enter the 6 to 8 digit code',
          ),
          const SizedBox(height: 14),
          const FieldLabel('New password'),
          TextFormField(
            controller: _password,
            obscureText: _hide,
            style: darkInputStyle,
            cursorColor: Colors.white,
            decoration: darkDecoration(
              hint: 'At least 8 characters',
              icon: Icons.lock,
              suffix: IconButton(
                onPressed: () => setState(() => _hide = !_hide),
                icon: Icon(_hide ? Icons.visibility : Icons.visibility_off, color: const Color(0xFFD4D4D8), size: 20),
              ),
            ),
            validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
          ),
          const SizedBox(height: 14),
          const FieldLabel('Confirm new password'),
          TextFormField(
            controller: _confirm,
            obscureText: _hide,
            style: darkInputStyle,
            cursorColor: Colors.white,
            decoration: darkDecoration(hint: 'Type it again', icon: Icons.lock),
            validator: (v) => v != _password.text ? 'Passwords do not match' : null,
            onFieldSubmitted: (_) => _reset(),
          ),
          FormError(_error),
          const SizedBox(height: 22),
          AuthButton(label: 'Change password', onPressed: _reset, busy: _busy),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => setState(() { _haveCode = false; _error = null; }),
              child: Text('I need a code', style: manrope(14, FontWeight.w600, EhbrColors.muted)),
            ),
          ),
        ],
      );
}
