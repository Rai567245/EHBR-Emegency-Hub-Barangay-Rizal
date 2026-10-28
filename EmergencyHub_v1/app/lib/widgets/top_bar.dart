import 'package:flutter/material.dart';

import '../theme.dart';

class EhbrTopBar extends StatelessWidget {
  const EhbrTopBar({
    super.key,
    this.subtitle = '',
    this.accent = EhbrColors.brand,
    this.unread = 0,
    this.onBell,
  });

  /// e.g. "Barangay Rizal, Taguig" – hidden until the admin sets it.
  final String subtitle;
  final Color accent;
  final int unread;
  final VoidCallback? onBell;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      color: EhbrColors.ink,
      padding: const EdgeInsets.only(left: 16, right: 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(6)),
            alignment: Alignment.center,
            child: Text('✚', style: manrope(20, FontWeight.w800, Colors.white)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle.isNotEmpty) ...[
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: manrope(12, FontWeight.w400, Colors.white)),
                  const SizedBox(height: 3),
                ],
                Text('Emergency Hub', style: manrope(16, FontWeight.w800, accent)),
              ],
            ),
          ),
          if (onBell != null)
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: 'Notifications',
                  onPressed: onBell,
                  icon: Icon(unread > 0 ? Icons.notifications_active : Icons.notifications_none_rounded,
                      color: accent, size: 26),
                ),
                if (unread > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 16),
                        decoration: BoxDecoration(
                          color: EhbrColors.sos,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: EhbrColors.ink, width: 1.5),
                        ),
                        child: Text(unread > 9 ? '9+' : '$unread',
                            textAlign: TextAlign.center,
                            style: manrope(9, FontWeight.w800, Colors.white)),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
