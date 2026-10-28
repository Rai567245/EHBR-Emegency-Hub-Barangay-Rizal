import 'package:flutter/material.dart';

import '../theme.dart';

/// Live "Your password must have" checklist (Figma: Create New Password).
class PasswordRules extends StatelessWidget {
  const PasswordRules({super.key, required this.password, this.minLength = 8});
  final String password;
  final int minLength;

  static bool ok(String p, {int minLength = 8}) =>
      p.length >= minLength && RegExp('[a-z]').hasMatch(p) && RegExp('[A-Z]').hasMatch(p) && RegExp(r'\d').hasMatch(p) && RegExp(r'[^A-Za-z0-9]').hasMatch(p);

  @override
  Widget build(BuildContext context) {
    final rules = <(String, bool)>[
      ('At least $minLength characters', password.length >= minLength),
      ('An uppercase and a lowercase letter', RegExp('[a-z]').hasMatch(password) && RegExp('[A-Z]').hasMatch(password)),
      ('At least one number', RegExp(r'\d').hasMatch(password)),
      ('At least one symbol (e.g., ! @ #)', RegExp(r'[^A-Za-z0-9]').hasMatch(password)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your password must have:', style: manrope(12, FontWeight.w700, EhbrColors.ink)),
        const SizedBox(height: 6),
        for (final r in rules)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Icon(r.$2 ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: r.$2 ? const Color(0xFF1E7A46) : EhbrColors.muted),
              const SizedBox(width: 8),
              Expanded(child: Semantics(label: r.$2 ? '${r.$1} (met)' : r.$1, child: Text(r.$1, style: manrope(12, FontWeight.w500, r.$2 ? const Color(0xFF1E7A46) : EhbrColors.muted)))),
            ]),
          ),
      ],
    );
  }
}
