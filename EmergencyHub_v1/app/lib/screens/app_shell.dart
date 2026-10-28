import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/push.dart';
import '../services/report_queue.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/top_bar.dart';
import 'contacts_screen.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'news_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'report_screen.dart';

/// Top bar + floating bottom nav around the five tabs. A tab refreshes its
/// data quietly every time you switch back to it.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _tab = 0;
  int _unread = 0;
  int _reportsRequest = 0;
  Timer? _poll;
  Timer? _flushTimer;
  final List<int> _tokens = [0, 0, 0, 0, 0];
  bool _reporting = false;
  String? _reportType;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ReportQueue.load().then((_) => _flushQueue());
    _refreshUnread();
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => _refreshUnread());
    // Saved (offline) reports go out as soon as there is a connection again.
    _flushTimer = Timer.periodic(const Duration(seconds: 15), (_) => _flushQueue());
    Push.start(onForeground: _onPush, onOpened: _openNotifications);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _flushTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _flushQueue();
      _refreshUnread();
      setState(() => _tokens[_tab]++);
    }
  }

  Future<void> _flushQueue() async {
    final sent = await ReportQueue.flush();
    if (sent.isEmpty || !mounted) return;
    setState(() {
      for (var i = 0; i < _tokens.length; i++) {
        _tokens[i]++;
      }
    });
    _refreshUnread();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(sent.length == 1
            ? 'Your saved report ${sent.first.id} was sent to the barangay.'
            : '${sent.length} saved reports were sent to the barangay.'),
        duration: const Duration(seconds: 6),
      ));
  }

  Future<void> _refreshUnread() async {
    try {
      final feed = await Api.notifications();
      if (mounted && feed.unread != _unread) setState(() => _unread = feed.unread);
    } catch (_) {
      // offline – keep the last number
    }
  }

  /// A push arrived while the app is open.
  void _onPush(String title, String body) {
    if (!mounted) return;
    _refreshUnread();
    setState(() {
      for (var i = 0; i < _tokens.length; i++) {
        _tokens[i]++;
      }
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(body.isEmpty ? title : '$title – $body', maxLines: 3, overflow: TextOverflow.ellipsis),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: 'View', onPressed: _openNotifications),
      ));
  }

  Future<void> _openNotifications() async {
    if (!mounted) return;
    final tab = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    if (!mounted) return;
    setState(() => _unread = 0);
    if (tab != null) _select(tab);
  }

  void _select(int i) {
    setState(() {
      if (i != _tab || _reporting) _tokens[i]++;
      _tab = i;
      if (i != 0) _reporting = false;
    });
  }

  List<Widget> get _pages => [
        _reporting
            ? ReportScreen(
                key: ValueKey(_reportType),
                initialType: _reportType,
                onBack: () => setState(() => _reporting = false),
                onSubmitted: () => setState(() {
                  _tokens[0]++;
                  _tokens[4]++;
                }),
                onViewReports: () {
                  setState(() => _reportsRequest++);
                  _select(4);
                },
              )
            : HomeScreen(
                reloadToken: _tokens[0],
                onReport: (type) => setState(() {
                  _reporting = true;
                  _reportType = type;
                }),
                onOpenNews: () => _select(3),
              ),
        MapScreen(reloadToken: _tokens[1]),
        ContactsScreen(reloadToken: _tokens[2]),
        NewsTab(reloadToken: _tokens[3]),
        ProfileTab(reloadToken: _tokens[4], openReportsRequest: _reportsRequest),
      ];

  @override
  Widget build(BuildContext context) {
    final onHome = _tab == 0 && !_reporting;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Column(
            children: [
              SafeArea(
                bottom: false,
                child: EhbrTopBar(
                  subtitle: Session.config.locationLine,
                  accent: onHome ? EhbrColors.brand : EhbrColors.muted,
                  unread: _unread,
                  onBell: _openNotifications,
                ),
              ),
              Expanded(child: IndexedStack(index: _tab, children: _pages)),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 130,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white.withValues(alpha: 0), Colors.white],
                    stops: const [0, .5],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 27),
              child: EhbrBottomNav(
                index: _tab,
                activeColor: onHome ? EhbrColors.brandLight : EhbrColors.muted,
                onTap: _select,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
