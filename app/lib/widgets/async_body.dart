import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';

/// Loads data once, shows a spinner / error with retry, and re-loads quietly
/// whenever [reloadToken] changes (used when the user comes back to a tab).
class AsyncBody<T> extends StatefulWidget {
  const AsyncBody({super.key, required this.load, required this.builder, this.reloadToken = 0});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() refresh) builder;
  final int reloadToken;

  @override
  State<AsyncBody<T>> createState() => _AsyncBodyState<T>();
}

class _AsyncBodyState<T> extends State<AsyncBody<T>> {
  T? _data;
  bool _hasData = false;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant AsyncBody<T> old) {
    super.didUpdateWidget(old);
    if (old.reloadToken != widget.reloadToken) _fetch(silent: true);
  }

  Future<void> _fetch({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _hasData = true;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent && _hasData) return; // keep showing what we have
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasData) return widget.builder(context, _data as T, _fetch);
    if (_loading) return const Center(child: CircularProgressIndicator(color: EhbrColors.muted));
    final msg = _error is ApiException ? (_error as ApiException).message : 'Something went wrong.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40, color: EhbrColors.muted),
            const SizedBox(height: 12),
            Text(msg, textAlign: TextAlign.center, style: manrope(13, FontWeight.w600, EhbrColors.ink)),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _fetch,
              style: OutlinedButton.styleFrom(
                foregroundColor: EhbrColors.ink,
                side: const BorderSide(color: EhbrColors.ink),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Try again', style: manrope(12, FontWeight.w700, EhbrColors.ink)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Friendly "nothing here yet" block.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message = '', this.icon = Icons.inbox_outlined});
  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, size: 30, color: EhbrColors.muted.withValues(alpha: .7)),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center, style: manrope(13, FontWeight.w700, EhbrColors.ink)),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(message,
                  textAlign: TextAlign.center, style: manrope(12, FontWeight.w400, EhbrColors.muted)),
            ],
          ],
        ),
      );
}
