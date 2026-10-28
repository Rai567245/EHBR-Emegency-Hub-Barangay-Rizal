import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import '../util.dart';

Color categoryColor(String c) => switch (c) {
      'alert' => EhbrColors.brand,
      'advisory' => EhbrColors.advisory,
      _ => EhbrColors.community,
    };

String categoryTag(String c) => switch (c) {
      'alert' => 'ALERT',
      'advisory' => 'ADVISORY',
      _ => 'EVENT',
    };

class CategoryTag extends StatelessWidget {
  const CategoryTag(this.category, {super.key});
  final String category;

  @override
  Widget build(BuildContext context) => Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: categoryColor(category), borderRadius: BorderRadius.circular(6)),
        child: Text(categoryTag(category), style: manrope(10, FontWeight.w600, Colors.white)),
      );
}

/// Compact announcement row used on Home.
class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard(this.a, {super.key, this.onTap});
  final Announcement a;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EhbrColors.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CategoryTag(a.category),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(12, FontWeight.w700, EhbrColors.ink)),
                  ),
                  Text(ago(a.createdAt), style: manrope(11, FontWeight.w500, EhbrColors.ink)),
                ],
              ),
              const SizedBox(height: 6),
              Text(a.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: manrope(12, FontWeight.w700, EhbrColors.ink.withValues(alpha: .5))),
            ],
          ),
        ),
      ),
    );
  }
}
