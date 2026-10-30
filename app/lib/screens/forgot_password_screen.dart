
import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/auth_widgets.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    this.initialContact = '',
  });

  final String initialContact;

  @override
  State<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState
    extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();

  late final TextEditingController _contact =
      TextEditingController(text: widget.initialContact);

  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  static const Color _red = Color(0xFFC9183A);
  static const Color _fieldColor = Color(0xFF202020);
  static const Color _muted = Color(0xFF999999);
  static const Color _disabledButton = Color(0xFFE3E3E3);

  bool _hide = true;
  bool _haveCode = false;
  bool _requested = false;
  bool _staffAsked = false;
  bool _busy = false;
  bool _done = false;

  String? _error;

  bool get _email => Session.config.emailReset;

  bool get _validContact => _contact.text.trim().length >= 7;

  @override
  void initState() {
    super.initState();
    _contact.addListener(_onContactChanged);
  }

  void _onContactChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _contact.removeListener(_onContactChanged);
    _contact.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _contactCheck(String? value) {
    if (value == null || value.trim().length < 7) {
      return 'Enter your contact number';
    }
    return null;
  }

  Future<void> _request({bool staff = false}) async {
    if (!_validContact) {
      setState(() {
        _error = 'Enter the contact number you signed up with';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await Api.forgotPassword(
        _contact.text.trim(),
        staff: staff,
      );

      if (!mounted) return;

      setState(() {
        _requested = true;
        if (staff || !_email) {
          _staffAsked = true;
        }
      });
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

  Future<void> _reset() async {
    if (!_form.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await Api.resetPassword(
        _contact.text.trim(),
        _code.text.trim(),
        _password.text,
      );

      if (mounted) {
        setState(() => _done = true);
      }
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

  void _backToLogin() {
    Navigator.of(context).pop();
  }

  Widget _buildLogo() {
    return Image.asset(
      'assets/images/ehbr_logo.png',
      width: 44,
      height: 44,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return const SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            Icons.broken_image_outlined,
            size: 32,
            color: _red,
          ),
        );
      },
    );
  }

  Widget _buildHeader({
    required String title,
    required String description,
  }) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: _backToLogin,
            icon: const Icon(
              Icons.arrow_back,
              color: Color(0xFF222222),
              size: 23,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
          ),
        ),
        const SizedBox(height: 2),
        _buildLogo(),
        const SizedBox(height: 9),
        Text(
          title,
          textAlign: TextAlign.center,
          style: manrope(
            24,
            FontWeight.w500,
            EhbrColors.ink,
          ),
        ),
        const SizedBox(height: 7),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            description,
            textAlign: TextAlign.center,
            style: manrope(
              14,
              FontWeight.w400,
              const Color(0xFF555555),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
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
        size: 19,
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: _fieldColor,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 14,
      ),
      prefixIconConstraints: const BoxConstraints(
        minWidth: 42,
        minHeight: 48,
      ),
      suffixIconConstraints: const BoxConstraints(
        minWidth: 42,
        minHeight: 48,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: _red,
          width: 1.2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: Color(0xFFD32F2F),
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: Color(0xFFD32F2F),
          width: 1.2,
        ),
      ),
      errorStyle: manrope(
        11,
        FontWeight.w500,
        const Color(0xFFD32F2F),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
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

  Widget _buildContactField({
    bool enabled = true,
    String hint = 'Enter your contact number',
    bool validate = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 3,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: _contact,
        enabled: enabled,
        keyboardType: TextInputType.phone,
        style: manrope(
          12,
          FontWeight.w400,
          Colors.white,
        ),
        cursorColor: Colors.white,
        decoration: _inputDecoration(
          hint: hint,
          icon: Icons.phone_outlined,
        ),
        validator: validate ? _contactCheck : null,
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback? onPressed,
    bool busy = false,
    bool enabled = true,
  }) {
    final active = enabled && onPressed != null && !busy;

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: active ? onPressed : null,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color>(
            (states) {
              if (states.contains(WidgetState.disabled)) {
                return _disabledButton;
              }
              return _red;
            },
          ),
          foregroundColor: WidgetStateProperty.resolveWith<Color>(
            (states) {
              if (states.contains(WidgetState.disabled)) {
                return const Color(0xFF666666);
              }
              return Colors.white;
            },
          ),
          elevation: WidgetStateProperty.all(0),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 12),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 21,
                height: 21,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _red,
                ),
              )
            : Text(
                label,
                textAlign: TextAlign.center,
                style: manrope(
                  15,
                  FontWeight.w500,
                  active ? Colors.white : const Color(0xFF666666),
                ),
              ),
      ),
    );
  }

  Widget _buildBackToLoginText() {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Remembered it? ',
            style: manrope(
              14,
              FontWeight.w400,
              const Color(0xFF555555),
            ),
          ),
          GestureDetector(
            onTap: _backToLogin,
            child: Text(
              'Back to Login',
              style: manrope(
                14,
                FontWeight.w600,
                _red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hotline = Session.config.hotline;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: _done
              ? _success()
              : Form(
                  key: _form,
                  child: _haveCode
                      ? _step2(hotline)
                      : _step1(hotline),
                ),
        ),
      ),
    );
  }

  Widget _step1(String hotline) {
    final description = _email
        ? 'Enter the mobile number linked to your account and we will text you a 6-digit code to reset your password.'
        : 'For your safety, the barangay office confirms your identity before giving you a reset code.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(
          title: 'Forgot Password?',
          description: description,
        ),
        const SizedBox(height: 17),

        _fieldLabel('Registered contact number'),

        _buildContactField(
          enabled: !_requested,
          hint: 'Enter your contact number',
        ),

        if (!_requested) ...[
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.info_outline,
                  size: 15,
                  color: Color(0xFF555555),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'We will only send a code if this number is registered.',
                  style: manrope(
                    12,
                    FontWeight.w400,
                    const Color(0xFF555555),
                  ),
                ),
              ),
            ],
          ),
        ],

        FormError(_error),

        const SizedBox(height: 22),

        if (!_requested)
          _buildPrimaryButton(
            label: 'Send Verification Code',
            onPressed: _busy ? null : () => _request(),
            busy: _busy,
            enabled: _validContact,
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F8F1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _staffAsked
                  ? 'Your request has been sent. Barangay staff can now see it. '
                      '${hotline.isNotEmpty ? 'Call $hotline or visit' : 'Visit'} '
                      'the barangay hall, confirm your identity, and request your '
                      '8-digit code. It is valid for 30 minutes.'
                  : 'If this number is registered and has an email, a 6-digit code '
                      'is on its way. Check your spam folder too. The code expires '
                      'in 15 minutes and can only be used once.',
              style: manrope(
                13,
                FontWeight.w400,
                EhbrColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildPrimaryButton(
            label: 'I have my code',
            onPressed: () {
              setState(() {
                _haveCode = true;
                _error = null;
              });
            },
          ),
        ],

        if (_email && _requested && !_staffAsked) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => _request(staff: true),
              child: Text(
                'No email, or it did not arrive? Ask the barangay office',
                textAlign: TextAlign.center,
                style: manrope(
                  13,
                  FontWeight.w600,
                  _muted,
                ),
              ),
            ),
          ),
        ],

        if (!_requested) ...[
          const SizedBox(height: 18),
          Center(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _haveCode = true;
                  _error = null;
                });
              },
              child: Text(
                'I already have a code',
                style: manrope(
                  14,
                  FontWeight.w500,
                  _muted,
                ),
              ),
            ),
          ),
        ],

        const SizedBox(height: 1),
        _buildBackToLoginText(),
      ],
    );
  }

  Widget _step2(String hotline) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(
          title: 'Reset Password',
          description:
              'Enter the code sent to you or provided by the barangay office, then choose a new password.',
        ),

        const SizedBox(height: 20),

        _fieldLabel('Registered contact number'),
        _buildContactField(
          hint: 'Enter your contact number',
          validate: true,
        ),

        const SizedBox(height: 14),

        _fieldLabel('Verification code'),
        TextFormField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 8,
          style: manrope(
            13,
            FontWeight.w400,
            Colors.white,
          ),
          cursorColor: Colors.white,
          decoration: _inputDecoration(
            hint: 'Enter your verification code',
            icon: Icons.pin_outlined,
          ).copyWith(counterText: ''),
          validator: (value) {
            return RegExp(r'^\d{6,8}$').hasMatch(
              (value ?? '').trim(),
            )
                ? null
                : 'Enter the 6 to 8 digit code';
          },
        ),

        const SizedBox(height: 14),

        _fieldLabel('New password'),
        TextFormField(
          controller: _password,
          obscureText: _hide,
          style: manrope(
            13,
            FontWeight.w400,
            Colors.white,
          ),
          cursorColor: Colors.white,
          decoration: _inputDecoration(
            hint: 'At least 8 characters',
            icon: Icons.lock_outline,
            suffix: IconButton(
              onPressed: () {
                setState(() => _hide = !_hide);
              },
              icon: Icon(
                _hide ? Icons.visibility : Icons.visibility_off,
                color: const Color(0xFFD4D4D8),
                size: 20,
              ),
            ),
          ),
          validator: (value) {
            if (value == null || value.length < 8) {
              return 'Use at least 8 characters';
            }
            return null;
          },
        ),

        const SizedBox(height: 14),

        _fieldLabel('Confirm new password'),
        TextFormField(
          controller: _confirm,
          obscureText: _hide,
          style: manrope(
            13,
            FontWeight.w400,
            Colors.white,
          ),
          cursorColor: Colors.white,
          decoration: _inputDecoration(
            hint: 'Re-enter your new password',
            icon: Icons.lock_outline,
          ),
          validator: (value) {
            if (value != _password.text) {
              return 'Passwords do not match';
            }
            return null;
          },
          onFieldSubmitted: (_) => _reset(),
        ),

        FormError(_error),

        const SizedBox(height: 22),

        _buildPrimaryButton(
          label: 'Change Password',
          onPressed: _reset,
          busy: _busy,
        ),

        const SizedBox(height: 12),

        Center(
          child: TextButton(
            onPressed: () {
              setState(() {
                _haveCode = false;
                _error = null;
              });
            },
            child: Text(
              'I need a code',
              style: manrope(
                14,
                FontWeight.w500,
                _muted,
              ),
            ),
          ),
        ),

        _buildBackToLoginText(),
      ],
    );
  }

  Widget _success() {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: _backToLogin,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        const SizedBox(height: 30),
        _buildLogo(),
        const SizedBox(height: 24),
        const Icon(
          Icons.check_circle_rounded,
          size: 64,
          color: Color(0xFF2E7D32),
        ),
        const SizedBox(height: 14),
        Text(
          'Password changed',
          style: manrope(
            20,
            FontWeight.w700,
            EhbrColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'You were signed out everywhere. Log in with your new password.',
          textAlign: TextAlign.center,
          style: manrope(
            13,
            FontWeight.w400,
            _muted,
          ),
        ),
        const SizedBox(height: 28),
        _buildPrimaryButton(
          label: 'Back to Login',
          onPressed: _backToLogin,
        ),
      ],
    );
  }
}
