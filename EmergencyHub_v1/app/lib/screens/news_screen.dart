import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/announcement_card.dart';
import '../widgets/async_body.dart';

/// News tab: list ⇄ article. The top bar and nav stay put.
class NewsTab extends StatefulWidget {
  const NewsTab({super.key, required this.reloadToken});
  final int reloadToken;

  @override
  State<NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<NewsTab> {
  Announcement? _open;

  @override
  Widget build(BuildContext context) {
    final open = _open;
    if (open != null) return _Article(a: open, onBack: () => setState(() => _open = null));
    return AsyncBody<List<Announcement>>(
      load: Api.announcements,
      reloadToken: widget.reloadToken,
      builder: (context, list, refresh) =>
          _NewsList(items: list, onRefresh: refresh, onOpen: (a) => setState(() => _open = a)),
    );
  }
}

class _NewsList extends StatefulWidget {
  const _NewsList({required this.items, required this.onRefresh, required this.onOpen});
  final List<Announcement> items;
  final Future<void> Function() onRefresh;
  final ValueChanged<Announcement> onOpen;

  @override
  State<_NewsList> createState() => _NewsListState();
}

class _NewsListState extends State<_NewsList> {
  String? _filter; // null = all
  String _query = '';

  bool _matches(Announcement a) {
    if (_filter != null && a.category != _filter) return false;
    final q = _query.trim().toLowerCase();
    return q.isEmpty || a.title.toLowerCase().contains(q) || a.body.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.items.where(_matches).toList();
    final alerts = visible.where((a) => a.category != 'event').toList();
    final community = visible.where((a) => a.category == 'event').toList();
    final chips = <(String, String?)>[('ALL', null), ('Alert', 'alert'), ('Advisory', 'advisory'), ('Event', 'event')];

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 110),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text('News & Announcements', style: manrope(18, FontWeight.w800, EhbrColors.ink)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final c in chips) ...[
                GestureDetector(
                  onTap: () => setState(() => _filter = c.$2),
                  child: Container(
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _filter == c.$2 ? EhbrColors.muted : EhbrColors.card,
                      border: Border.all(color: _filter == c.$2 ? EhbrColors.muted : Colors.black),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(c.$1,
                        style: manrope(10, FontWeight.w600, _filter == c.$2 ? Colors.white : EhbrColors.ink)),
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 12),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          onChanged: (v) => setState(() => _query = v),
                          style: manrope(10, FontWeight.w600, Colors.black),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: 'Search',
                            hintStyle: manrope(10, FontWeight.w600, Colors.black),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (widget.items.isEmpty)
            const EmptyState(
              icon: Icons.campaign_outlined,
              title: 'No announcements yet',
              message: 'When the barangay posts an alert, advisory or event it will appear here.',
            )
          else if (visible.isEmpty)
            const EmptyState(title: 'No announcements match your search')
          else ...[
            if (alerts.isNotEmpty) ...[
              Text('Alerts & Advisories', style: manrope(14, FontWeight.w700, EhbrColors.ink)),
              const SizedBox(height: 10),
              for (final a in alerts) _NewsCard(a, onTap: () => widget.onOpen(a)),
            ],
            if (community.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Community Updates', style: manrope(14, FontWeight.w700, EhbrColors.ink)),
              const SizedBox(height: 10),
              for (final a in community) _NewsCard(a, onTap: () => widget.onOpen(a)),
            ],
            const SizedBox(height: 14),
            Center(
              child: Text('You’re up to date with barangay notices.',
                  style: manrope(12, FontWeight.w700, EhbrColors.ink)),
            ),
          ],
        ],
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard(this.a, {required this.onTap});
  final Announcement a;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = categoryColor(a.category);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFF2F2F3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: c)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: c),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(9, 7, 10, 8),
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
                            Text(ago(a.createdAt), style: manrope(10, FontWeight.w600, c)),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(a.body,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: manrope(11, FontWeight.w600, EhbrColors.ink.withValues(alpha: .6))),
                      ],
                    ),
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

class _Article extends StatelessWidget {
  const _Article({required this.a, required this.onBack});
  final Announcement a;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: onBack,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: EhbrColors.ink, shape: BoxShape.circle),
                child: const Icon(Icons.chevron_left, color: Colors.white, size: 16),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onBack,
              child: Text('Back to News', style: manrope(14, FontWeight.w600, EhbrColors.ink)),
            ),
            const Spacer(),
            CategoryTag(a.category),
          ],
        ),
        const SizedBox(height: 18),
        Text(stamp(a.createdAt), style: manrope(11, FontWeight.w600, EhbrColors.muted)),
        const SizedBox(height: 8),
        Text(a.title, style: manrope(20, FontWeight.w800, EhbrColors.ink).copyWith(height: 26 / 20)),
        const SizedBox(height: 14),
        const Divider(height: 1, thickness: 1, color: Color(0xFFD9D9DE)),
        const SizedBox(height: 12),
        Text(a.body, style: manrope(13, FontWeight.w400, EhbrColors.ink).copyWith(height: 20 / 13)),
      ],
    );
  }
}
