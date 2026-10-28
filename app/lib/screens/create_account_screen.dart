import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/password_rules.dart';
import 'app_shell.dart';

/// Step 1: biodata. Step 2: confirm what you typed, accept terms, create.
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _contact = TextEditingController();
  final _address = TextEditingController();
  final _email = TextEditingController();
  final _zoneText = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  int _step = 0;
  String? _zone;
  bool _hidePw = true;
  bool _agreed = false;
  bool _busy = false;
  String? _error;

  List<String> get _zones => Session.config.zones;
  String get _zoneValue => _zones.isEmpty ? _zoneText.text.trim() : (_zone ?? '');

  @override
  void dispose() {
    for (final c in [_first, _last, _contact, _email, _address, _zoneText, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v, String what) =>
      (v == null || v.trim().isEmpty) ? 'Enter $what' : null;

  void _continue() {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _step = 1;
      _error = null;
    });
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final out = await Api.register({
        'firstName': _first.text.trim(),
        'lastName': _last.text.trim(),
        'contact': _contact.text.trim(),
        'email': _email.text.trim(),
        'address': _address.text.trim(),
        'zone': _zoneValue,
        'password': _password.text,
      });
      await Session.signIn(out);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppShell()),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    if (_step == 1) {
      setState(() => _step = 0);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: _busy ? null : _back,
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                    icon: const Icon(Icons.arrow_back, color: EhbrColors.ink, size: 24),
                  ),
                  const Spacer(),
                  const EhbrEmblem(size: 40),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
              Center(
                child: Text('Create an Account', style: manrope(26, FontWeight.w500, EhbrColors.ink)),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text('Help us finish setting up your account.',
                    style: manrope(13, FontWeight.w400, EhbrColors.ink)),
              ),
              const SizedBox(height: 14),
              _Stepper(step: _step),
              const SizedBox(height: 10),
              if (_step == 0) _biodata() else _confirmStep(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _biodata() {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const FieldLabel('First name'),
                  TextFormField(
                    controller: _first,
                    style: darkInputStyle,
                    textCapitalization: TextCapitalization.words,
                    decoration: darkDecoration(hint: 'E.g John'),
                    validator: (v) => _required(v, 'first name'),
                  ),
                ]),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const FieldLabel('Last name'),
                  TextFormField(
                    controller: _last,
                    style: darkInputStyle,
                    textCapitalization: TextCapitalization.words,
                    decoration: darkDecoration(hint: 'E.g Appleseed'),
                    validator: (v) => _required(v, 'last name'),
                  ),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const FieldLabel('Contact number'),
          TextFormField(
            controller: _contact,
            keyboardType: TextInputType.phone,
            style: darkInputStyle,
            decoration: darkDecoration(hint: 'Enter your contact number', icon: Icons.phone),
            validator: (v) => (v == null || v.trim().length < 7) ? 'Enter a valid contact number' : null,
          ),
          const SizedBox(height: 12),
          const FieldLabel('Email (optional – to reset a forgotten password)'),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            style: darkInputStyle,
            decoration: darkDecoration(hint: 'name@example.com', icon: Icons.email_outlined),
            validator: (v) {
              final t = (v ?? '').trim();
              return t.isEmpty || RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(t) ? null : 'Enter a valid email, or leave it empty';
            },
          ),
          const SizedBox(height: 12),
          const FieldLabel('Address'),
          TextFormField(
            controller: _address,
            style: darkInputStyle,
            decoration: darkDecoration(hint: 'Enter your address', icon: Icons.location_on),
            validator: (v) => _required(v, 'your address'),
          ),
          const SizedBox(height: 12),
          const FieldLabel('Zone / Purok'),
          if (_zones.isEmpty)
            TextFormField(
              controller: _zoneText,
              style: darkInputStyle,
              decoration: darkDecoration(hint: 'Enter your zone / purok', icon: Icons.location_on),
              validator: (v) => _required(v, 'your zone'),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _zone,
              isExpanded: true,
              dropdownColor: EhbrColors.ink,
              iconEnabledColor: Colors.white,
              style: darkInputStyle,
              decoration: darkDecoration(hint: 'Select zone', icon: Icons.location_on),
              items: [for (final z in _zones) DropdownMenuItem(value: z, child: Text(z))],
              onChanged: (v) => setState(() => _zone = v),
              validator: (v) => v == null ? 'Select your zone' : null,
            ),
          const SizedBox(height: 12),
          const FieldLabel('Password'),
          TextFormField(
            controller: _password,
            obscureText: _hidePw,
            style: darkInputStyle,
            decoration: darkDecoration(
              hint: 'Enter a password',
              icon: Icons.lock,
              suffix: IconButton(
                onPressed: () => setState(() => _hidePw = !_hidePw),
                icon: Icon(_hidePw ? Icons.visibility : Icons.visibility_off,
                    color: const Color(0xFFD4D4D8), size: 20),
              ),
            ),
            onChanged: (_) => setState(() {}),
            validator: (v) => PasswordRules.ok(v ?? '') ? null : 'Password does not meet the rules below',
          ),
          const SizedBox(height: 8),
          PasswordRules(password: _password.text),
          const SizedBox(height: 12),
          const FieldLabel('Confirm password'),
          TextFormField(
            controller: _confirm,
            obscureText: _hidePw,
            style: darkInputStyle,
            decoration: darkDecoration(hint: 'Confirm password', icon: Icons.lock),
            validator: (v) => v != _password.text ? 'Passwords do not match' : null,
          ),
          const SizedBox(height: 28),
          AuthButton(label: 'Continue', onPressed: _continue),
        ],
      ),
    );
  }

  Widget _confirmStep() {
    Widget ro(String text, {IconData? icon, bool chevron = false}) => Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: EhbrColors.ink, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: const Color(0xFFD4D4D8), size: 20),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: darkInputStyle),
              ),
              if (chevron) const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const FieldLabel('First name'),
                ro(_first.text.trim()),
              ]),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const FieldLabel('Last name'),
                ro(_last.text.trim()),
              ]),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const FieldLabel('Contact number'),
        ro(_contact.text.trim(), icon: Icons.phone),
        if (_email.text.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          const FieldLabel('Email'),
          ro(_email.text.trim(), icon: Icons.email_outlined),
        ],
        const SizedBox(height: 12),
        const FieldLabel('Address'),
        ro(_address.text.trim(), icon: Icons.location_on),
        const SizedBox(height: 12),
        const FieldLabel('Zone / Purok'),
        ro(_zoneValue, icon: Icons.location_on, chevron: _zones.isNotEmpty),
        const SizedBox(height: 14),
        SquareCheck(
          value: _agreed,
          onChanged: (v) => setState(() => _agreed = v),
          label: Text('I agree to the Terms and Privacy Policy',
              style: manrope(13, FontWeight.w500, EhbrColors.ink)),
        ),
        FormError(_error),
        const SizedBox(height: 12),
        AuthButton(label: 'Create an account', onPressed: _agreed ? _create : null, busy: _busy),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    Widget seg(int i, String label) {
      final reached = step >= i;
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: reached ? EhbrColors.muted : EhbrColors.ink,
                    shape: BoxShape.circle,
                  ),
                  child: Text('${i + 1}', style: manrope(9, FontWeight.w700, Colors.white)),
                ),
                const SizedBox(width: 5),
                Text(label, style: manrope(12, FontWeight.w400, EhbrColors.ink)),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: reached ? EhbrColors.muted : EhbrColors.ink,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [seg(0, 'Biodata information'), const SizedBox(width: 16), seg(1, 'Confirm information')],
    );
  }
}
