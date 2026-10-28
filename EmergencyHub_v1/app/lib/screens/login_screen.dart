import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/auth_widgets.dart';
import 'app_shell.dart';
import 'create_account_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _contact = TextEditingController();
  final _password = TextEditingController();
  bool _hide = true;
  bool _remember = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _contact.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final out = await Api.login(_contact.text.trim(), _password.text);
      await Session.signIn(out, remember: _remember);
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

  void _forgot() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ForgotPasswordScreen(initialContact: _contact.text.trim())),
      );

  @override
  Widget build(BuildContext context) {
    final cfg = Session.config;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 36, 16, 24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: EhbrEmblem(size: 44)),
                const SizedBox(height: 8),
                Center(
                  child: Text('Emergency Hub',
                      style: manrope(24, FontWeight.w500, EhbrColors.ink, spacing: .4)),
                ),
                if (cfg.locationLine.isNotEmpty)
                  Center(
                    child: Text(cfg.locationLine,
                        style: manrope(14, FontWeight.w400, EhbrColors.muted)),
                  ),
                const SizedBox(height: 28),
                const FieldLabel('Contact number'),
                TextFormField(
                  controller: _contact,
                  keyboardType: TextInputType.phone,
                  style: darkInputStyle,
                  cursorColor: Colors.white,
                  decoration: darkDecoration(hint: 'Enter your contact number', icon: Icons.phone),
                  validator: (v) =>
                      (v == null || v.trim().length < 7) ? 'Enter a valid contact number' : null,
                ),
                const SizedBox(height: 14),
                const FieldLabel('Password'),
                TextFormField(
                  controller: _password,
                  obscureText: _hide,
                  style: darkInputStyle,
                  cursorColor: Colors.white,
                  decoration: darkDecoration(
                    hint: 'Enter password',
                    icon: Icons.lock,
                    suffix: IconButton(
                      onPressed: () => setState(() => _hide = !_hide),
                      icon: Icon(_hide ? Icons.visibility : Icons.visibility_off,
                          color: const Color(0xFFD4D4D8), size: 20),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                  onFieldSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SquareCheck(
                      value: _remember,
                      onChanged: (v) => setState(() => _remember = v),
                      label: Text('Remember Me',
                          style: manrope(13, FontWeight.w400, EhbrColors.ink, spacing: 1.2)),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _forgot,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text('Forgot password?',
                          style: manrope(14, FontWeight.w500, EhbrColors.ink)),
                    ),
                  ],
                ),
                FormError(_error),
                const SizedBox(height: 24),
                AuthButton(label: 'Login', onPressed: _login, busy: _busy),
                const SizedBox(height: 22),
                Center(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text("Don't have an account? ",
                          style: manrope(15, FontWeight.w500, EhbrColors.ink)),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CreateAccountScreen()),
                        ),
                        child: Text('Sign up', style: manrope(15, FontWeight.w600, EhbrColors.muted)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
