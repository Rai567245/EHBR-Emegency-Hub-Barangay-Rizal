import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../phone.dart';
import '../services/api.dart';
import '../services/report_queue.dart';
import '../services/session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/announcement_card.dart';
import '../widgets/async_body.dart';
import '../widgets/emergency_numbers.dart';
import '../widgets/sos_sheet.dart';
import 'queued_reports_screen.dart';

/// announcements, evacuation centers, and whether we are offline
typedef _HomeData = (List<Announcement>, List<EvacCenter>, bool);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.reloadToken, required this.onReport, required this.onOpenNews});

  final int reloadToken;

  /// Opens the Create Report form, optionally pre-selecting a type.
  final ValueChanged<String?> onReport;
  final VoidCallback onOpenNews;

  Future<_HomeData> _load() async {
    try {
      final r = await Future.wait<Object>([Api.announcements(), Api.centers()]);
      return (r[0] as List<Announcement>, r[1] as List<EvacCenter>, false);
    } on ApiException catch (e) {
      // Offline: still show SOS, reporting and the saved emergency numbers.
      if (e.isUnavailable) return (<Announcement>[], <EvacCenter>[], true);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<_HomeData>(
      load: _load,
      reloadToken: reloadToken,
      builder: (context, data, refresh) {
        final cfg = Session.config;
        final announcements = data.$1;
        final offline = data.$3;
        final centers = data.$2.where((c) => c.status != 'closed').toList();
        final alert = announcements.cast<Announcement?>().firstWhere(
              (a) => a!.category == 'alert' && DateTime.now().difference(a.createdAt).inHours < 48,
              orElse: () => null,
            );
        final contacts = cfg.contacts.take(4).toList();

        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 110),
            children: [
              if (offline)
                const _Notice(
                  icon: Icons.wifi_off_rounded,
                  text: 'Can’t reach the barangay server right now. Calling, reporting and your saved numbers still work.',
                ),
              ValueListenableBuilder<int>(
                valueListenable: ReportQueue.changes,
                builder: (context, _, __) {
                  final n = ReportQueue.pending.length;
                  if (n == 0) return const SizedBox.shrink();
                  return _Notice(
                    icon: Icons.schedule_send_outlined,
                    text: '$n report${n == 1 ? '' : 's'} waiting to send – tap to view',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const QueuedReportsScreen()),
                    ),
                  );
                },
              ),
              _SosButton(
                number: cfg.sosNumber,
                hold: false,
                onCall: () => showSosSheet(context),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  cfg.sosHold
                      ? 'Press and hold for 3 seconds · shares your location'
                      : 'Tap to call ${cfg.sosNumber}',
                  style: manrope(10, FontWeight.w500, EhbrColors.muted),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ActionTile(
                      outlined: true,
                      icon: Icons.error_outline,
                      title: 'Report Incident',
                      body: 'Immediately report an incident (e.g, accident, injuries, etc.)',
                      onTap: () => onReport(null),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionTile(
                      icon: Icons.warning_amber_rounded,
                      title: 'Report Hazard',
                      body: 'Your observation keeps everyone safe. Report potential risks!',
                      onTap: () => onReport('Other hazard'),
                    ),
                  ),
                ],
              ),
              if (contacts.isNotEmpty) ...[
                const SizedBox(height: 10),
                const _SectionTitle('Emergency Contacts'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < contacts.length; i++) ...[
                      Expanded(
                        child: _ContactTile(
                          label: contacts[i].name,
                          onTap: () => callNumber(context, contacts[i].number),
                        ),
                      ),
                      if (i != contacts.length - 1) const SizedBox(width: 12),
                    ],
                  ],
                ),
              ],
              if (alert != null) ...[
                const SizedBox(height: 15),
                _AlertBanner(alert, onTap: onOpenNews),
              ],
              if (offline) ...[
                const SizedBox(height: 15),
                const EmergencyNumbersCard(),
              ] else ...[
              const SizedBox(height: 20),
              const _SectionTitle('Evacuation & Safe Zones'),
              const SizedBox(height: 12),
              if (centers.isEmpty)
                const EmptyState(
                  icon: Icons.shield_outlined,
                  title: 'No evacuation centers listed yet',
                  message: 'Your barangay will add them here.',
                )
              else
                for (final c in centers.take(3)) ...[
                  _CenterCard(c),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(child: _SectionTitle('Announcements')),
                  if (announcements.length > 3)
                    GestureDetector(
                      onTap: onOpenNews,
                      child: Text('See all', style: manrope(12, FontWeight.w600, EhbrColors.muted)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (announcements.isEmpty)
                const EmptyState(
                  icon: Icons.campaign_outlined,
                  title: 'No announcements yet',
                  message: 'Alerts and advisories from the barangay will show up here.',
                )
              else
                for (final a in announcements.take(3)) ...[
                  AnnouncementCard(a, onTap: onOpenNews),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: manrope(14, FontWeight.w700, EhbrColors.ink));
}

/// Calls straight away, or after a 3-second press-and-hold when [hold] is on.
class _SosButton extends StatefulWidget {
  const _SosButton({required this.number, required this.hold, required this.onCall});
  final String number;
  final bool hold;
  final VoidCallback onCall;

  @override
  State<_SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<_SosButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) {
            HapticFeedback.heavyImpact();
            widget.onCall();
            _c.reset();
          }
        });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _release() {
    if (widget.hold && _c.status != AnimationStatus.completed) _c.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        if (widget.hold) _c.forward();
      },
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: Material(
        color: EhbrColors.sos,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: .25),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.hold
              ? () => ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('Keep holding for 3 seconds to call.')))
              : widget.onCall,
          child: SizedBox(
            height: 50,
            child: Stack(
              children: [
                AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) => FractionallySizedBox(
                    widthFactor: _c.value,
                    child: Container(color: Colors.black.withValues(alpha: .22)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 30, right: 15),
                  child: Row(
                    children: [
                      const Icon(Icons.phone, color: Colors.white, size: 24),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Text(
                          Session.config.sosHold ? 'Hold to Call Emergency / SOS' : 'Call Emergency / SOS',
                          style: manrope(16, FontWeight.w500, Colors.white, spacing: .256),
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

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title, required this.body, required this.onTap, this.outlined = false});
  final bool outlined;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EhbrColors.ink,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 100,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: outlined ? Border.all(color: EhbrColors.brand, width: 2) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(14, FontWeight.w600, Colors.white)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: manrope(12, FontWeight.w400, Colors.white.withValues(alpha: .5))),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EhbrColors.ink,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          height: 80,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.phone_in_talk_outlined, color: Colors.white, size: 28),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: manrope(12, FontWeight.w600, Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner(this.a, {required this.onTap});
  final Announcement a;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: EhbrColors.brand, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${a.title} · ${ago(a.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: manrope(12, FontWeight.w600, Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterCard extends StatelessWidget {
  const _CenterCard(this.c);
  final EvacCenter c;

  @override
  Widget build(BuildContext context) {
    final open = c.status == 'open';
    final sub = [
      if (c.address.isNotEmpty) c.address,
      if (c.capacity > 0) '${c.occupied}/${c.capacity} inside',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (open ? EhbrColors.green : EhbrColors.amber).withValues(alpha: .18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.shield_outlined, color: open ? EhbrColors.green : EhbrColors.amber),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: manrope(14, FontWeight.w700, EhbrColors.ink)),
                const SizedBox(height: 3),
                Text(open ? 'Open${sub.isEmpty ? '' : ' · $sub'}' : 'Standby${sub.isEmpty ? '' : ' · $sub'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: manrope(11, FontWeight.w600, EhbrColors.ink.withValues(alpha: .55))),
              ],
            ),
          ),
          if (c.lat != null && c.lng != null)
            OutlinedButton(
              onPressed: () => openDirections(c.lat!, c.lng!),
              style: OutlinedButton.styleFrom(
                foregroundColor: EhbrColors.ink,
                side: const BorderSide(color: Colors.black),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: const Size(55, 30),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text('Route', style: manrope(12, FontWeight.w600, EhbrColors.ink)),
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFFFF4D6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFFF2D58A)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 18, color: const Color(0xFF8A6100)),
                const SizedBox(width: 8),
                Expanded(child: Text(text, style: manrope(12, FontWeight.w700, const Color(0xFF8A6100)))),
                if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF8A6100)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
