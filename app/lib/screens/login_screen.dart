
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

  static const Color _red = Color(0xFFC9183A);
  static const Color _fieldColor = Color(0xFF202020);
  static const Color _muted = Color(0xFF999999);

  bool _hide = true;
  bool _remember = false;
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
      final out = await Api.login(
        _contact.text.trim(),
        _password.text,
      );

      await Session.signIn(out, remember: _remember);

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const AppShell(),
        ),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _forgot() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          initialContact: _contact.text.trim(),
        ),
      ),
    );
  }

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: manrope(
        12,
        FontWeight.w400,
        const Color(0xFFCACACA),
      ),
      prefixIcon: Icon(
        icon,
        color: const Color(0xFFD4D4D8),
        size: 18,
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: _fieldColor,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 13,
      ),
      prefixIconConstraints: const BoxConstraints(
        minWidth: 36,
        minHeight: 42,
      ),
      suffixIconConstraints: const BoxConstraints(
        minWidth: 40,
        minHeight: 42,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(
          color: _red,
          width: 1.2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(
          color: _red,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(
          color: _red,
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(
        text,
        style: manrope(
          14,
          FontWeight.w400,
          EhbrColors.ink,
        ),
      ),
    );
  }

  Widget _buildInputField({
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 3,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = Session.config;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // EHBR emblem
                Center(
                  child: EhbrEmblem(size: 44),
                ),

                const SizedBox(height: 7),

                // App title
                Text(
                  'Emergency Hub',
                  textAlign: TextAlign.center,
                  style: manrope(
                    24,
                    FontWeight.w500,
                    EhbrColors.ink,
                    spacing: .4,
                  ),
                ),

                // Location subtitle
                Text(
                  cfg.locationLine.isNotEmpty
                      ? cfg.locationLine
                      : 'Barangay Rizal, Raguig',
                  textAlign: TextAlign.center,
                  style: manrope(
                    14,
                    FontWeight.w400,
                    _muted,
                  ),
                ),

                const SizedBox(height: 28),

                // Contact number
                _fieldLabel('Contact number'),

                _buildInputField(
                  child: TextFormField(
                    controller: _contact,
                    keyboardType: TextInputType.phone,
                    style: manrope(
                      12,
                      FontWeight.w400,
                      Colors.white,
                    ),
                    cursorColor: Colors.white,
                    decoration: _decoration(
                      hint: 'Enter your contact number',
                      icon: Icons.phone,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().length < 7) {
                        return 'Enter a valid contact number';
                      }
                      return null;
                    },
                  ),
                ),

                const SizedBox(height: 14),

                // Password
                _fieldLabel('Password'),

                _buildInputField(
                  child: TextFormField(
                    controller: _password,
                    obscureText: _hide,
                    style: manrope(
                      12,
                      FontWeight.w400,
                      Colors.white,
                    ),
                    cursorColor: Colors.white,
                    decoration: _decoration(
                      hint: 'Enter password',
                      icon: Icons.lock,
                      suffix: IconButton(
                        onPressed: () {
                          setState(() => _hide = !_hide);
                        },
                        icon: Icon(
                          _hide
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: const Color(0xFFD4D4D8),
                          size: 19,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Enter your password';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _login(),
                  ),
                ),

                const SizedBox(height: 8),

                // Remember Me and Forgot Password
                Row(
                  children: [
                    Expanded(
                      child: SquareCheck(
                        value: _remember,
                        onChanged: (v) {
                          setState(() => _remember = v);
                        },
                        label: Text(
                          'Remember Me',
                          style: manrope(
                            12,
                            FontWeight.w400,
                            EhbrColors.ink,
                            spacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _forgot,
                      style: TextButton.styleFrom(
                        foregroundColor: EhbrColors.ink,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Forgot password?',
                        style: manrope(
                          14,
                          FontWeight.w500,
                          EhbrColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),

                // Login error
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  FormError(_error),
                ],

                const SizedBox(height: 24),

                // Login button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _login,
                    style: ButtonStyle(
                      backgroundColor:
                          WidgetStateProperty.resolveWith<Color>(
                        (states) => _red,
                      ),
                      foregroundColor:
                          WidgetStateProperty.all(Colors.white),
                      overlayColor:
                          WidgetStateProperty.all(
                        Colors.white.withValues(alpha: 0.10),
                      ),
                      elevation: WidgetStateProperty.all(3),
                      shadowColor:
                          WidgetStateProperty.all(Colors.black38),
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 21,
                            height: 21,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Login',
                            style: manrope(
                              16,
                              FontWeight.w500,
                              Colors.white,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 22),

                // Sign up
                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: manrope(
                          15,
                          FontWeight.w500,
                          EhbrColors.ink,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const CreateAccountScreen(),
                            ),
                          );
                        },
                        child: Text(
                          'Sign up',
                          style: manrope(
                            15,
                            FontWeight.w600,
                            _red,
                          ),
                        ),
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
