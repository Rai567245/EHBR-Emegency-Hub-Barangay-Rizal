import 'package:flutter/material.dart';

import '../services/report_queue.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/async_body.dart';

/// Reports saved on this phone that haven't reached the barangay yet.
class QueuedReportsScreen extends StatelessWidget {
  const QueuedReportsScreen({super.key});

  void _snack(BuildContext context, String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _sendNow(BuildContext context, QueuedReport q) async {
    await ReportQueue.retry(q.localId);
    final sent = await ReportQueue.flush();
    if (!context.mounted) return;
    _snack(context, sent.isEmpty ? 'Still no connection – it will send automatically.' : 'Sent! Reference ${sent.first.id}');
  }

  Future<void> _delete(BuildContext context, QueuedReport q) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete this saved report?', style: manrope(16, FontWeight.w800, EhbrColors.ink)),
        content: Text('It has not been sent, so the barangay will never see it.',
            style: manrope(13, FontWeight.w400, EhbrColors.ink)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await ReportQueue.remove(q.localId);
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
                  Text('Waiting to send', style: manrope(18, FontWeight.w800, EhbrColors.ink)),
                ],
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: ReportQueue.changes,
                builder: (context, _, __) {
                  final list = ReportQueue.pending;
                  if (list.isEmpty) {
                    return const Center(
                      child: EmptyState(
                        icon: Icons.cloud_done_outlined,
                        title: 'Nothing is waiting',
                        message: 'Reports saved while offline show here until they are sent.',
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final q = list[i];
                      final refused = q.error != null;
                      final c = refused ? EhbrColors.brand : const Color(0xFF8A6100);
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: EhbrColors.card,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(q.type, style: manrope(15, FontWeight.w800, EhbrColors.ink))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
                                  child: Text(refused ? 'Couldn’t send' : 'Waiting to send',
                                      style: manrope(10, FontWeight.w800, c)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('Saved ${stamp(q.savedAt)}', style: manrope(11, FontWeight.w600, EhbrColors.muted)),
                            const SizedBox(height: 8),
                            Text(q.description,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: manrope(12, FontWeight.w500, EhbrColors.ink)),
                            if (q.locationText.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('Location: ${q.locationText}', style: manrope(12, FontWeight.w600, EhbrColors.ink)),
                            ],
                            if (refused) ...[
                              const SizedBox(height: 6),
                              Text(q.error!, style: manrope(12, FontWeight.w600, EhbrColors.brand)),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () => _sendNow(context, q),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: EhbrColors.brand,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: Text('Send now', style: manrope(13, FontWeight.w700, Colors.white)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton(
                                  onPressed: () => _delete(context, q),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: EhbrColors.brand,
                                    side: const BorderSide(color: EhbrColors.brand),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: Text('Delete', style: manrope(13, FontWeight.w700, EhbrColors.brand)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
