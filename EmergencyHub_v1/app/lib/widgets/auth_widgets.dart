import 'package:flutter/material.dart';

import '../theme.dart';

/// Stand-in for the barangay emblem (the Figma file uses an SVG logo).
/// Replace with an asset image once exported.
class EhbrEmblem extends StatelessWidget {
  const EhbrEmblem({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.shield_moon_outlined, size: size, color: EhbrColors.muted);
}

/// Dark rounded input used on the login / sign-up screens.
InputDecoration darkDecoration({required String hint, IconData? icon, Widget? suffix}) {
  const radius = BorderRadius.all(Radius.circular(10));
  return InputDecoration(
    filled: true,
    fillColor: EhbrColors.ink,
    hintText: hint,
    hintStyle: manrope(13, FontWeight.w400, Colors.white.withValues(alpha: .75)),
    prefixIcon: icon == null ? null : Icon(icon, color: const Color(0xFFD4D4D8), size: 20),
    suffixIcon: suffix,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    errorStyle: manrope(11, FontWeight.w600, const Color(0xFFD32F2F)),
    border: const OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
    enabledBorder: const OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: Colors.white.withValues(alpha: .55), width: 1.2),
    ),
    errorBorder: const OutlineInputBorder(
        borderRadius: radius, borderSide: BorderSide(color: Color(0xFFD32F2F))),
    focusedErrorBorder: const OutlineInputBorder(
        borderRadius: radius, borderSide: BorderSide(color: Color(0xFFD32F2F), width: 1.4)),
  );
}

TextStyle get darkInputStyle => manrope(13, FontWeight.w500, Colors.white);

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: manrope(14, FontWeight.w500, EhbrColors.ink)),
      );
}

/// Large gray call-to-action button. Shows a spinner while [busy].
class AuthButton extends StatelessWidget {
  const AuthButton({super.key, required this.label, required this.onPressed, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Material(
      color: enabled || busy ? EhbrColors.muted : EhbrColors.muted.withValues(alpha: .55),
      elevation: enabled ? 4 : 0,
      shadowColor: Colors.black.withValues(alpha: .3),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onPressed : null,
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text(label, style: manrope(18, FontWeight.w500, Colors.white, spacing: .3)),
          ),
        ),
      ),
    );
  }
}

/// Red inline error line for forms.
class FormError extends StatelessWidget {
  const FormError(this.message, {super.key});
  final String? message;
  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(message!, style: manrope(12, FontWeight.w600, const Color(0xFFD32F2F))),
        );
}

/// Square outlined checkbox + label, as drawn in the design.
class SquareCheck extends StatelessWidget {
  const SquareCheck({super.key, required this.value, required this.onChanged, required this.label});
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: EhbrColors.ink,
              side: const BorderSide(color: EhbrColors.ink, width: 1.5),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(width: 8),
          label,
        ],
      ),
    );
  }
}
