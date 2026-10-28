import 'package:flutter/material.dart';

import '../phone.dart';
import '../services/session.dart';
import '../theme.dart';

/// Every emergency number the admin has entered (Settings → SOS / Barangay
/// profile / Emergency contacts). Read from the copy saved on the phone, so it
/// is available with no internet.
class EmergencyNumbersCard extends StatelessWidget {
  const EmergencyNumbersCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cfg = Session.config;
    final entries = <(String, String)>[
      ('Emergency hotline', cfg.sosNumber),
      if (cfg.hotline.isNotEmpty) ('Barangay hotline', cfg.hotline),
      for (final c in cfg.contacts.where((c) => c.category == 'local')) (c.name, c.number),
      for (final c in cfg.contacts.where((c) => c.category == 'utility')) (c.name, c.number),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDEEF0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF2B8C0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('In danger? Don’t wait – call now.', style: manrope(14, FontWeight.w800, EhbrColors.brand)),
          const SizedBox(height: 2),
          Text('Calls work even without mobile data.', style: manrope(11, FontWeight.w400, EhbrColors.muted)),
          const SizedBox(height: 10),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: manrope(12, FontWeight.w700, EhbrColors.ink)),
                        Text(e.$2, style: manrope(12, FontWeight.w500, EhbrColors.muted)),
                      ],
                    ),
                  ),
                  Material(
                    color: EhbrColors.brand,
                    borderRadius: BorderRadius.circular(99),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: () => callNumber(context, e.$2),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.phone, size: 14, color: Colors.white),
                            const SizedBox(width: 5),
                            Text('Call', style: manrope(12, FontWeight.w700, Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
