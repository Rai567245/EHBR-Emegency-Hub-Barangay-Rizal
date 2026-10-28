import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/async_body.dart';

/// The bell: everything the barangay sent you. Pops with the tab to open
/// (1 = Map, 3 = News, 4 = Profile) when a notification is tapped.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static IconData _icon(String kind) => switch (kind) {
        'alert' => Icons.warning_amber_rounded,
        'report' => Icons.description_outlined,
        'security' => Icons.lock_outline_rounded,
        _ => Icons.campaign_outlined,
      };

  static int _tab(String kind) => switch (kind) {
        'alert' => 1,
        'report' => 4,
        'security' => 4,
        _ => 3,
      };

  Future<NotificationFeed> _load() async {
    final feed = await Api.notifications();
    try {
      await Api.markNotificationsRead(); // the badge clears; this list still shows what was new
    } catch (_) {}
    return feed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: EhbrColors.ink),
                  ),
                  Text('Notifications', style: manrope(18, FontWeight.w800, EhbrColors.ink)),
                ],
              ),
            ),
            Expanded(
              child: AsyncBody<NotificationFeed>(
                load: _load,
                builder: (context, feed, refresh) => RefreshIndicator(
                  onRefresh: refresh,
                  child: feed.items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 60),
                            EmptyState(
                              icon: Icons.notifications_none_rounded,
                              title: 'No notifications yet',
                              message: 'Alerts from the barangay and updates on your reports will appear here.',
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: feed.items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final n = feed.items[i];
                            return Material(
                              color: n.unread ? const Color(0xFFFDEEF0) : EhbrColors.card,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.of(context).pop(_tab(n.kind)),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: n.kind == 'alert' ? EhbrColors.brand : EhbrColors.ink,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(_icon(n.kind), color: Colors.white, size: 18),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(n.title,
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: manrope(13, FontWeight.w800, EhbrColors.ink)),
                                                ),
                                                if (n.unread)
                                                  const Padding(
                                                    padding: EdgeInsets.only(left: 6),
                                                    child: Icon(Icons.circle, size: 9, color: EhbrColors.brand),
                                                  ),
                                              ],
                                            ),
                                            if (n.body.isNotEmpty) ...[
                                              const SizedBox(height: 3),
                                              Text(n.body,
                                                  maxLines: 3,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: manrope(12, FontWeight.w500, EhbrColors.ink.withValues(alpha: .7))),
                                            ],
                                            const SizedBox(height: 6),
                                            Text(ago(n.createdAt),
                                                style: manrope(11, FontWeight.w600, EhbrColors.muted)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
