import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the phone dialer. Shows a message if the device can't place calls.
Future<void> callNumber(BuildContext context, String number) async {
  final ok = await launchUrl(Uri(scheme: 'tel', path: number));
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Call $number from your phone app.')));
  }
}

/// Opens turn-by-turn directions in the device's maps app / browser.
Future<void> openDirections(double lat, double lng) =>
    launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'),
        mode: LaunchMode.externalApplication);

Widget _sheetButtons(BuildContext c, {required String primary, required VoidCallback onPrimary, required String secondary, required VoidCallback onSecondary}) {
  return Column(children: [
    SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: EhbrColors.brand, shape: const StadiumBorder()),
        onPressed: onPrimary,
        child: Text(primary, style: manrope(15, FontWeight.w700, Colors.white)),
      ),
    ),
    const SizedBox(height: 10),
    SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(side: const BorderSide(color: EhbrColors.ink, width: 1.5), shape: const StadiumBorder()),
        onPressed: onSecondary,
        child: Text(secondary, style: manrope(15, FontWeight.w600, EhbrColors.ink)),
      ),
    ),
  ]);
}

Future<void> _sheet(BuildContext context, Widget Function(BuildContext) child) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 16), child: SingleChildScrollView(child: child(c))),
      ),
    );

Widget _grabber() => Center(
      child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 18), decoration: BoxDecoration(color: const Color(0xFFD0D0D0), borderRadius: BorderRadius.circular(4))),
    );

/// "Call <name>?" sheet – the call starts only after the person confirms in the phone's dialer.
Future<void> confirmCall(BuildContext context, String name, String number) => _sheet(
      context,
      (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _grabber(),
        Text('Call $name?', style: manrope(20, FontWeight.w800, EhbrColors.ink)),
        const SizedBox(height: 10),
        Text('Your phone\u2019s dialer will open with $number ready to call. The call starts only when you confirm in the dialer.',
            style: manrope(13, FontWeight.w400, EhbrColors.muted)),
        const SizedBox(height: 20),
        _sheetButtons(c,
            primary: 'Open Dialer',
            onPrimary: () async {
              Navigator.of(c).pop();
              bool ok = false;
              try {
                ok = await launchUrl(Uri(scheme: 'tel', path: number));
              } catch (_) {}
              if (!ok && context.mounted) await callUnavailable(context, number);
            },
            secondary: 'Cancel',
            onSecondary: () => Navigator.of(c).pop()),
      ]),
    );

/// Shown when the device can't place calls (tablet, no SIM): offers to copy the number.
Future<void> callUnavailable(BuildContext context, String number) => _sheet(
      context,
      (c) => Column(mainAxisSize: MainAxisSize.min, children: [
        _grabber(),
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(color: Color(0xFFFFF1D6), shape: BoxShape.circle),
          child: const Icon(Icons.phone_disabled_outlined, color: EhbrColors.amber, size: 28),
        ),
        const SizedBox(height: 12),
        Text('Can\u2019t place a call from this device', textAlign: TextAlign.center, style: manrope(18, FontWeight.w800, EhbrColors.ink)),
        const SizedBox(height: 8),
        Text('Calling isn\u2019t available right now. Copy the number and call from another phone.',
            textAlign: TextAlign.center, style: manrope(13, FontWeight.w400, EhbrColors.muted)),
        const SizedBox(height: 14),
        Text(number, style: manrope(26, FontWeight.w800, EhbrColors.ink)),
        const SizedBox(height: 18),
        _sheetButtons(c,
            primary: 'Copy Number',
            onPrimary: () async {
              await Clipboard.setData(ClipboardData(text: number));
              if (c.mounted) Navigator.of(c).pop();
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('Number copied.')));
              }
            },
            secondary: 'Close',
            onSecondary: () => Navigator.of(c).pop()),
      ]),
    );

/// Contact details sheet (Figma: Contacts – Full Details).
Future<void> showContactDetails(
  BuildContext context, {
  required String name,
  required String number,
  required String category,
  required String detail,
  required bool favorite,
  required VoidCallback onToggleFavorite,
}) =>
    _sheet(
      context,
      (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _grabber(),
        Text(name, style: manrope(20, FontWeight.w800, EhbrColors.ink)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFF1E8E5A), borderRadius: BorderRadius.circular(4)),
          child: Text(category, style: manrope(11, FontWeight.w600, Colors.white)),
        ),
        const SizedBox(height: 16),
        Text('Phone', style: manrope(11, FontWeight.w500, EhbrColors.muted)),
        Text(number, style: manrope(14, FontWeight.w700, EhbrColors.ink)),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Details', style: manrope(11, FontWeight.w500, EhbrColors.muted)),
          Text(detail, style: manrope(14, FontWeight.w700, EhbrColors.ink)),
        ],
        const SizedBox(height: 20),
        _sheetButtons(c,
            primary: 'Call $number',
            onPrimary: () {
              Navigator.of(c).pop();
              confirmCall(context, name, number);
            },
            secondary: favorite ? 'Remove from Favorites' : 'Add to Favorites',
            onSecondary: () {
              onToggleFavorite();
              Navigator.of(c).pop();
            }),
      ]),
    );
