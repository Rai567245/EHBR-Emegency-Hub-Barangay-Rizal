import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/report_queue.dart';
import '../services/session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/async_body.dart';
import 'login_screen.dart';
import 'profile_pages.dart';
import 'queued_reports_screen.dart';

/// Resident-friendly wording + colour for a report status.
String statusLabel(String s) => switch (s) {
      'NEW' => 'Received',
      'VERIFIED' => 'Verified',
      'DISPATCHED' => 'Responders on the way',
      'RESOLVED' => 'Resolved',
      _ => 'Not accepted',
    };

Color statusColor(String s) => switch (s) {
      'NEW' => EhbrColors.advisory,
      'VERIFIED' => const Color(0xFF15803D),
      'DISPATCHED' => EhbrColors.brand,
      _ => EhbrColors.muted,
    };

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key, required this.reloadToken, this.openReportsRequest = 0});
  final int reloadToken;

  /// Increases each time something asks to jump straight to "My Reports".
  final int openReportsRequest;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  bool _showReports = false;
  bool _offline = false;

  @override
  void didUpdateWidget(covariant ProfileTab old) {
    super.didUpdateWidget(old);
    if (widget.openReportsRequest != old.openReportsRequest) setState(() => _showReports = true);
  }

  Future<List<Report>> _loadReports() async {
    try {
      final r = await Api.myReports();
      _offline = false;
      return r;
    } on ApiException catch (e) {
      if (e.isUnavailable) {
        _offline = true; // show the profile anyway; the counts just can't load
        return <Report>[];
      }
      rethrow;
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Log out?', style: manrope(16, FontWeight.w800, EhbrColors.ink)),
        content: Text('You will need to log in again to report or see your reports.',
            style: manrope(13, FontWeight.w400, EhbrColors.ink)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok != true) return;
    await Session.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _account() {
    final u = Session.user;
    if (u == null) return;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 82, child: Text(k, style: manrope(12, FontWeight.w500, EhbrColors.muted))),
              Expanded(child: Text(v.isEmpty ? '—' : v, style: manrope(13, FontWeight.w700, EhbrColors.ink))),
            ],
          ),
        );
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Account details', style: manrope(16, FontWeight.w800, EhbrColors.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row('Name', u.fullName),
            row('Contact', u.contact),
            row('Email', u.email),
            row('Address', u.address),
            row('Zone', u.zone),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _changeEmail();
            },
            child: Text(u.email.isEmpty ? 'Add email' : 'Change email'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  /// The email is only used to send a code if the resident forgets their password.
  Future<void> _changeEmail() async {
    final email = TextEditingController(text: Session.user?.email ?? '');
    final pw = TextEditingController();
    String? error;
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Recovery email', style: manrope(16, FontWeight.w800, EhbrColors.ink)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Used only to send a code if you forget your password. Leave empty to remove it.',
                  style: manrope(12, FontWeight.w400, EhbrColors.muted)),
              const SizedBox(height: 10),
              TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
              TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: 'Your password')),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: manrope(12, FontWeight.w600, const Color(0xFFD32F2F))),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setD(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final u = await Api.setEmail(email.text.trim(), pw.text);
                        await Session.updateUser(u);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recovery email saved')));
                        }
                      } on ApiException catch (e) {
                        setD(() {
                          busy = false;
                          error = e.message;
                        });
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    email.dispose();
    pw.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showReports) return _MyReports(onBack: () => setState(() => _showReports = false));
    final u = Session.user;
    return AsyncBody<List<Report>>(
      load: _loadReports,
      reloadToken: widget.reloadToken,
      builder: (context, reports, refresh) {
        final open = reports.where((r) => ['NEW', 'VERIFIED', 'DISPATCHED'].contains(r.status)).length;
        final resolved = reports.where((r) => r.status == 'RESOLVED').length;
        final menu = <(IconData, String, bool, VoidCallback)>[
          (Icons.description_outlined, 'My Reports', false, () => setState(() => _showReports = true)),
          (Icons.badge_outlined, 'Account details', false, _account),
          (Icons.notifications_none_rounded, 'Notifications', false, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsInfoScreen()))),
          (Icons.lock_outline_rounded, 'Privacy & Security', false, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyScreen()))),
          (Icons.help_outline_rounded, 'Help & Support', false, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen()))),
          (Icons.logout_rounded, 'Log-out', true, _logout),
        ];
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(color: EhbrColors.ink, shape: BoxShape.circle),
                          child: const Icon(Icons.account_circle_outlined, color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(u?.fullName ?? 'Resident',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: manrope(18, FontWeight.w800, EhbrColors.ink)),
                              const SizedBox(height: 4),
                              Text('Resident', style: manrope(13, FontWeight.w400, EhbrColors.muted)),
                              if (u != null && u.zone.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(u.zone, style: manrope(12, FontWeight.w400, EhbrColors.muted)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _Stat('Reports', _offline ? '–' : '${reports.length}')),
                        const SizedBox(width: 12),
                        Expanded(child: _Stat('Open', _offline ? '–' : '$open')),
                        const SizedBox(width: 12),
                        Expanded(child: _Stat('Resolved', _offline ? '–' : '$resolved')),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Account Menu', style: manrope(14, FontWeight.w800, EhbrColors.ink)),
                    const SizedBox(height: 12),
                    for (var i = 0; i < menu.length; i++) ...[
                      _MenuItem(icon: menu[i].$1, label: menu[i].$2, muted: menu[i].$3, onTap: menu[i].$4),
                      if (i != menu.length - 1) const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: manrope(11, FontWeight.w400, EhbrColors.muted)),
            const SizedBox(height: 4),
            Text(value, style: manrope(16, FontWeight.w800, EhbrColors.ink)),
          ],
        ),
      );
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label, required this.onTap, this.muted = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final fg = muted ? EhbrColors.muted : EhbrColors.ink;
    return Material(
      color: const Color(0xFFF5F5F5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: manrope(14, FontWeight.w700, fg))),
              const Icon(Icons.chevron_right_rounded, size: 18, color: EhbrColors.ink),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyReports extends StatelessWidget {
  const _MyReports({required this.onBack});
  final VoidCallback onBack;

  void _details(BuildContext context, Report r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(r.type, style: manrope(18, FontWeight.w800, EhbrColors.ink))),
                  _StatusPill(r.status),
                ],
              ),
              const SizedBox(height: 4),
              Text('${r.id} · ${stamp(r.createdAt)}', style: manrope(11, FontWeight.w600, EhbrColors.muted)),
              const SizedBox(height: 12),
              Text(r.description, style: manrope(13, FontWeight.w400, EhbrColors.ink)),
              if (r.locationText.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Location: ${r.locationText}', style: manrope(12, FontWeight.w600, EhbrColors.ink)),
              ],
              const SizedBox(height: 16),
              Text('Progress', style: manrope(12, FontWeight.w800, EhbrColors.ink)),
              const SizedBox(height: 8),
              for (final t in r.timeline)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Icon(Icons.circle, size: 8, color: EhbrColors.muted),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t.text.replaceAll(RegExp(r'\s*\(.*\)$'), ''), style: manrope(12, FontWeight.w500, EhbrColors.ink))),
                      Text(ago(t.at), style: manrope(11, FontWeight.w400, EhbrColors.muted)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<Report>>(
      load: () async {
        try {
          return await Api.myReports();
        } on ApiException catch (e) {
          if (e.isUnavailable) return <Report>[]; // offline: still show what is waiting on the phone
          rethrow;
        }
      },
      builder: (context, reports, refresh) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                  child: Text('Back to Profile', style: manrope(14, FontWeight.w600, EhbrColors.ink)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('My Reports', style: manrope(18, FontWeight.w800, EhbrColors.ink)),
            const SizedBox(height: 12),
            ValueListenableBuilder<int>(
              valueListenable: ReportQueue.changes,
              builder: (context, _, __) => Column(
                children: [
                  for (final q in ReportQueue.pending) ...[
                    Material(
                      color: const Color(0xFFFFF4D6),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const QueuedReportsScreen()),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              const Icon(Icons.schedule_send_outlined, size: 18, color: Color(0xFF8A6100)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text('${q.type} · saved on your phone',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: manrope(13, FontWeight.w700, EhbrColors.ink)),
                              ),
                              Text('Waiting to send', style: manrope(10, FontWeight.w800, const Color(0xFF8A6100))),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
            if (reports.isEmpty && ReportQueue.pending.isEmpty)
              const EmptyState(
                icon: Icons.description_outlined,
                title: 'You haven’t filed any reports',
                message: 'Use “Report Incident” or “Report Hazard” on the Home screen.',
              ),
            for (final r in reports) ...[
              Material(
                color: EhbrColors.card,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _details(context, r),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.type,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: manrope(13, FontWeight.w700, EhbrColors.ink)),
                              const SizedBox(height: 3),
                              Text('${r.id} · ${ago(r.createdAt)}',
                                  style: manrope(11, FontWeight.w600, EhbrColors.ink.withValues(alpha: .5))),
                            ],
                          ),
                        ),
                        _StatusPill(r.status),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
      child: Text(statusLabel(status), style: manrope(10, FontWeight.w700, c)),
    );
  }
}
