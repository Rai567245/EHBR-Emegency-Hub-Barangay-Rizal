import 'package:flutter/material.dart';

import '../theme.dart';

enum StepPhase { done, now, pending }

class StepData {
  const StepData(this.title, this.subtitle, this.state, {this.time});
  final String title, subtitle;
  final StepPhase state;
  final String? time; // e.g. "12 Aug 2026, 10:42 AM"
}

/// The vertical "Report status" tracker from the Figma design.
class StatusSteps extends StatelessWidget {
  const StatusSteps({super.key, required this.steps, this.nowColor = EhbrColors.brand});
  final List<StepData> steps;
  final Color nowColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E4EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Report status', style: manrope(13, FontWeight.w800, EhbrColors.ink)),
          const SizedBox(height: 10),
          for (var i = 0; i < steps.length; i++) _row(steps[i], last: i == steps.length - 1),
        ],
      ),
    );
  }

  Widget _row(StepData s, {required bool last}) {
    const green = Color(0xFF15803D);
    final Widget dot = switch (s.state) {
      StepPhase.done => Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(color: green, shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 13, color: Colors.white),
        ),
      StepPhase.now => Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: nowColor, width: 2.2),
          ),
        ),
      StepPhase.pending => Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFC9CDD6), width: 2),
          ),
        ),
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                dot,
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: s.state == StepPhase.done ? green : const Color(0xFFD9DCE3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 4 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(s.title,
                            style: manrope(13, FontWeight.w700,
                                s.state == StepPhase.pending ? EhbrColors.muted : EhbrColors.ink)),
                      ),
                      if (s.state == StepPhase.now) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: nowColor.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text('Now', style: manrope(10, FontWeight.w800, nowColor)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(s.time ?? s.subtitle, style: manrope(11, FontWeight.w400, EhbrColors.muted)),
                  if (s.time != null && s.subtitle.isNotEmpty)
                    Text(s.subtitle, style: manrope(11, FontWeight.w400, EhbrColors.muted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
