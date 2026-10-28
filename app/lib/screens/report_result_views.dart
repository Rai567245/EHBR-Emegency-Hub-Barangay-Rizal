import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/report_queue.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/emergency_numbers.dart';
import '../widgets/status_steps.dart';

Widget _bigButton(String label, VoidCallback onTap, {bool filled = true}) => SizedBox(
      width: double.infinity,
      child: Material(
        color: filled ? EhbrColors.brand : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: filled ? BorderSide.none : const BorderSide(color: EhbrColors.ink, width: 1.2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Center(
              child: Text(label, style: manrope(14, FontWeight.w700, filled ? Colors.white : EhbrColors.ink)),
            ),
          ),
        ),
      ),
    );

/// "Report submitted" – Figma frame "Report Submitted".
class ReportSubmittedView extends StatelessWidget {
  const ReportSubmittedView({
    super.key,
    required this.report,
    required this.onBack,
    required this.onViewReports,
    this.sentFromQueue = false,
  });

  final Report report;
  final VoidCallback onBack;
  final VoidCallback onViewReports;

  /// True when this report had been saved offline and just reached the barangay.
  final bool sentFromQueue;

  static const _progress = {'NEW': 1, 'VERIFIED': 2, 'DISPATCHED': 3, 'RESOLVED': 4};

  @override
  Widget build(BuildContext context) {
    final idx = _progress[report.status] ?? 1;
    StepPhase st(int i) => i < idx ? StepPhase.done : (i == idx ? StepPhase.now : StepPhase.pending);
    final where = report.locationText.isEmpty ? report.type : '${report.type} - ${report.locationText}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sentFromQueue)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: const Color(0xFFE6F6EA), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                const Icon(Icons.cloud_done_outlined, size: 18, color: Color(0xFF15803D)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Back online – your saved report reached the barangay.',
                      style: manrope(12, FontWeight.w700, const Color(0xFF15803D))),
                ),
              ],
            ),
          ),
        Center(
          child: Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(color: Color(0xFFDDF3E4), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Container(
              width: 54,
              height: 54,
              decoration: const BoxDecoration(color: Color(0xFF15803D), shape: BoxShape.circle),
              child: const Icon(Icons.check, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(child: Text('Report submitted', style: manrope(20, FontWeight.w800, EhbrColors.ink))),
        const SizedBox(height: 6),
        Text(
          'Thank you. Barangay staff can now see your report and will review it.',
          textAlign: TextAlign.center,
          style: manrope(12, FontWeight.w400, EhbrColors.muted),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E4EA)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reference no.', style: manrope(10, FontWeight.w600, EhbrColors.muted)),
                  const SizedBox(height: 3),
                  Text(report.id, style: manrope(14, FontWeight.w800, EhbrColors.ink)),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(where,
                        maxLines: 2,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(12, FontWeight.w700, EhbrColors.ink)),
                    const SizedBox(height: 3),
                    Text('Posted ${stamp(report.createdAt)}',
                        textAlign: TextAlign.end, style: manrope(10, FontWeight.w500, EhbrColors.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        StatusSteps(steps: [
          StepData('Report sent', '', StepPhase.done, time: stamp(report.createdAt)),
          StepData('Under review', 'Staff are checking the details', st(1)),
          StepData('Responders assigned', 'You will get a notification', st(2)),
          StepData('Resolved', 'We will tell you when it’s closed', st(3)),
        ]),
        const SizedBox(height: 16),
        _bigButton('Back to Home', onBack),
        const SizedBox(height: 10),
        _bigButton('View my reports', onViewReports, filled: false),
      ],
    );
  }
}

/// "Report saved on your phone" – Figma frame "Report Queued / Offline".
/// Instead of a single "Call 911" box it lists every emergency number the
/// admin has entered, read from the copy saved on the phone.
class ReportQueuedView extends StatelessWidget {
  const ReportQueuedView({
    super.key,
    required this.queued,
    required this.onBack,
    required this.onViewQueued,
    required this.onRetry,
  });

  final QueuedReport queued;
  final VoidCallback onBack;
  final VoidCallback onViewQueued;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFD99A06);
    final refused = queued.error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(color: Color(0xFFFFF1CC), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: amber, width: 3),
              ),
              child: const Icon(Icons.priority_high_rounded, color: amber, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(child: Text('Report saved on your phone', style: manrope(20, FontWeight.w800, EhbrColors.ink))),
        const SizedBox(height: 6),
        Text(
          'It has not reached the barangay yet (no connection, or the server is busy). Nothing is lost. '
          'It will send by itself when you are back online – open the app again if you closed it.',
          textAlign: TextAlign.center,
          style: manrope(12, FontWeight.w400, EhbrColors.muted),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(
            color: refused ? const Color(0xFFFDEEF0) : const Color(0xFFFFF4D6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: refused ? const Color(0xFFF2B8C0) : const Color(0xFFF2D58A)),
          ),
          child: Row(
            children: [
              Icon(refused ? Icons.error_outline : Icons.wifi_off_rounded,
                  size: 16, color: refused ? EhbrColors.brand : const Color(0xFF8A6100)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  refused ? 'Couldn’t be sent: ${queued.error}' : 'No internet connection · Waiting to send',
                  style: manrope(11, FontWeight.w700, refused ? EhbrColors.brand : const Color(0xFF8A6100)),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('Try now', style: manrope(11, FontWeight.w800, EhbrColors.ink)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        StatusSteps(
          nowColor: amber,
          steps: [
            StepData('Saved on your phone', '', StepPhase.done, time: stamp(queued.savedAt)),
            const StepData('Waiting for connection', 'Sends automatically when online', StepPhase.now),
            const StepData('Sent to barangay staff', 'You will get a notification', StepPhase.pending),
          ],
        ),
        const SizedBox(height: 12),
        const EmergencyNumbersCard(),
        const SizedBox(height: 16),
        _bigButton('Back to Home', onBack),
        const SizedBox(height: 10),
        _bigButton('View queued report', onViewQueued, filled: false),
      ],
    );
  }
}
