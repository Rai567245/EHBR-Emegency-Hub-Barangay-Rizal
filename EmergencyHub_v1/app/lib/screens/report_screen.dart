import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../location.dart';
import '../models/models.dart';
import '../phone.dart';
import '../services/api.dart';
import '../services/report_queue.dart';
import '../services/session.dart';
import '../theme.dart';
import '../util.dart';
import 'queued_reports_screen.dart';
import 'report_result_views.dart';

/// Create a Report. Lives inside the Home tab (top bar + nav stay visible).
class ReportScreen extends StatefulWidget {
  const ReportScreen({
    super.key,
    required this.onBack,
    required this.onSubmitted,
    required this.onViewReports,
    this.initialType,
  });

  final VoidCallback onBack;
  final VoidCallback onSubmitted;
  final VoidCallback onViewReports;
  final String? initialType;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  static const _urgencies = ['Low', 'Medium', 'High', 'Critical'];
  static const _bg = Color(0xFFF3F4F8);

  final _desc = TextEditingController();
  final List<Uint8List> _photos = [];
  static const _maxPhotos = 3;
  final _where = TextEditingController();
  final DateTime _when = DateTime.now();

  String? _type;
  String _urgency = 'Medium';
  bool _hideName = true;
  double? _lat, _lng;
  bool _gpsBusy = false;
  bool _busy = false;
  String? _error;
  Report? _done;
  QueuedReport? _queued;

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null && Session.config.allTypes.contains(widget.initialType)) {
      _type = widget.initialType;
    }
  }

  @override
  void dispose() {
    _desc.dispose();
    _where.dispose();
    super.dispose();
  }

  Future<void> _gps() async {
    setState(() {
      _gpsBusy = true;
      _error = null;
    });
    try {
      final p = await currentLocation();
      if (mounted) {
        setState(() {
          _lat = p.lat;
          _lng = p.lng;
          final c = Session.config;
          final outside = c.hasBorder
              ? !insidePolygon(p.lat, p.lng, c.boundary)
              : (c.radiusKm > 0 && kmBetween(c.lat, c.lng, p.lat, p.lng) > c.radiusKm);
          if (outside) {
            _error = 'Your GPS location looks outside ${c.barangayName.isEmpty ? 'the barangay' : 'Barangay ${c.barangayName}'}. '
                'You can still send this report – the barangay will see where you are.';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _gpsBusy = false);
    }
  }

  Future<void> _submit() async {
    final msg = _type == null
        ? 'Choose the type of incident.'
        : _desc.text.trim().length < 3
            ? 'Describe what happened.'
            : (_where.text.trim().isEmpty && _lat == null)
                ? 'Add where it is – type the address/landmark or use GPS.'
                : null;
    if (msg != null) {
      setState(() => _error = msg);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // clientId lets the server ignore a retry of the same report; reportedAt keeps
    // the real time even if it can only be sent later.
    final payload = <String, dynamic>{
      'type': _type,
      'description': _desc.text.trim(),
      'urgency': _urgency,
      'locationText': _where.text.trim(),
      'lat': _lat,
      'lng': _lng,
      'anonymous': Session.config.allowAnonymous && _hideName,
      if (_photos.isNotEmpty) 'photos': [for (final b in _photos) base64Encode(b)],
      'clientId': ReportQueue.newClientId(),
      'reportedAt': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      final r = await Api.submitReport(payload);
      if (!mounted) return;
      setState(() => _done = r);
      widget.onSubmitted();
    } on ApiException catch (e) {
      if (e.isUnavailable) {
        // No signal (or the server is down): keep the report safe on the phone.
        final q = await ReportQueue.enqueue(payload);
        if (!mounted) return;
        setState(() => _queued = q);
        widget.onSubmitted();
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _tryNow() async {
    final sent = await ReportQueue.flush();
    if (!mounted || sent.isNotEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Still no connection – it will send automatically.')));
  }

  @override
  Widget build(BuildContext context) {
    final cfg = Session.config;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: widget.onBack,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: EhbrColors.ink, shape: BoxShape.circle),
                child: const Icon(Icons.chevron_left, color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: widget.onBack,
              child: Text('Back to Home', style: manrope(14, FontWeight.w600, EhbrColors.ink)),
            ),
            const Spacer(),
            Material(
              color: EhbrColors.ink,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => callNumber(context, cfg.sosNumber),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.phone_outlined, size: 16, color: EhbrColors.muted),
                      const SizedBox(width: 6),
                      Text('In danger? Call SOS',
                          style: manrope(11, FontWeight.w600, const Color(0xFFB4B8C0))),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_done != null)
          ReportSubmittedView(report: _done!, onBack: widget.onBack, onViewReports: widget.onViewReports)
        else if (_queued != null)
          ValueListenableBuilder<int>(
            valueListenable: ReportQueue.changes,
            builder: (context, _, __) {
              final sent = ReportQueue.sent[_queued!.localId];
              if (sent != null) {
                return ReportSubmittedView(
                  report: sent,
                  sentFromQueue: true,
                  onBack: widget.onBack,
                  onViewReports: widget.onViewReports,
                );
              }
              return ReportQueuedView(
                queued: _queued!,
                onBack: widget.onBack,
                onRetry: _tryNow,
                onViewQueued: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QueuedReportsScreen()),
                ),
              );
            },
          )
        else
          _form(cfg),
      ],
    );
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= _maxPhotos) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    try {
      // Shrunk on the phone so it uploads quickly on mobile data (and can wait in the offline queue).
      final x = await ImagePicker().pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 70);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (bytes.length > 1400 * 1024) {
        if (mounted) setState(() => _error = 'That photo is too large. Try a different one.');
        return;
      }
      if (mounted) setState(() => _photos.add(bytes));
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the camera or gallery. Check the app’s permissions in your phone settings.');
    }
  }

  Widget _photoPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label('Photos (optional, up to $_maxPhotos)'),
        Row(
          children: [
            for (var i = 0; i < _photos.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_photos[i], width: 72, height: 72, fit: BoxFit.cover)),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: InkWell(
                        onTap: () => setState(() => _photos.removeAt(i)),
                        child: const CircleAvatar(radius: 11, backgroundColor: EhbrColors.ink, child: Icon(Icons.close, size: 14, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            if (_photos.length < _maxPhotos)
              InkWell(
                onTap: _addPhoto,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFD9DCE3))),
                  child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_a_photo_outlined, size: 22, color: EhbrColors.ink),
                    SizedBox(height: 2),
                    Text('Add', style: TextStyle(fontSize: 11)),
                  ]),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _form(AppConfig cfg) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD9DCE3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Create a Report', style: manrope(20, FontWeight.w800, EhbrColors.ink)),
          const SizedBox(height: 4),
          Text('Tell us what happened and where it is so responders can act faster.',
              style: manrope(12, FontWeight.w400, EhbrColors.muted)),
          const SizedBox(height: 12),
          const _Label('Type of Incident'),
          _Box(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _type,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, size: 22, color: EhbrColors.ink),
                hint: Text('Choose incident type', style: manrope(11, FontWeight.w500, EhbrColors.ink)),
                style: manrope(11, FontWeight.w500, EhbrColors.ink),
                items: [for (final t in cfg.allTypes) DropdownMenuItem(value: t, child: Text(t))],
                onChanged: (v) => setState(() => _type = v),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _Label('Description'),
          _Box(
            height: 70,
            child: TextField(
              controller: _desc,
              maxLines: 3,
              maxLength: 1000,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              style: manrope(11, FontWeight.w500, EhbrColors.ink),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Describe what happened and who is affected...',
                hintStyle: manrope(11, FontWeight.w500, EhbrColors.ink),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _photoPicker(),
          const SizedBox(height: 12),
          const _Label('Location'),
          _Box(
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 18, color: EhbrColors.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _where,
                    maxLength: 200,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    style: manrope(11, FontWeight.w500, EhbrColors.ink),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: 'Street, landmark or address',
                      hintStyle: manrope(11, FontWeight.w500, EhbrColors.ink),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _gpsBusy ? null : _gps,
                  child: _gpsBusy
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_lat == null ? 'Use GPS' : 'Update',
                          style: manrope(12, FontWeight.w600, EhbrColors.muted)),
                ),
              ],
            ),
          ),
          if (_lat != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text('GPS attached (${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)})',
                  style: manrope(10, FontWeight.w600, const Color(0xFF15803D))),
            ),
          const SizedBox(height: 12),
          const _Label('Urgency'),
          Row(
            children: [
              for (final u in _urgencies) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _urgency = u),
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: u == _urgency ? const Color(0xFFEDEEF2) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: u == _urgency ? EhbrColors.muted : const Color(0xFFE2E4EA),
                          width: u == _urgency ? 1.6 : 1,
                        ),
                      ),
                      child: Text(u,
                          style: manrope(12, u == _urgency ? FontWeight.w700 : FontWeight.w500,
                              u == _urgency ? EhbrColors.muted : EhbrColors.ink)),
                    ),
                  ),
                ),
                if (u != _urgencies.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _InfoCard(label: 'Date / Time', value: stamp(_when))),
              if (cfg.allowAnonymous) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _InfoCard(
                    label: 'Privacy (tap to change)',
                    value: _hideName ? 'Name hidden from others' : 'Name visible to staff',
                    onTap: () => setState(() => _hideName = !_hideName),
                  ),
                ),
              ],
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: manrope(12, FontWeight.w600, const Color(0xFFD32F2F))),
            ),
          const SizedBox(height: 10),
          Material(
            color: _busy ? EhbrColors.muted.withValues(alpha: .7) : EhbrColors.muted,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _busy ? null : _submit,
              child: SizedBox(
                height: 40,
                width: double.infinity,
                child: Center(
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                      : Text('Submit Report', style: manrope(14, FontWeight.w700, Colors.white)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: manrope(12, FontWeight.w700, EhbrColors.ink)),
      );
}

class _Box extends StatelessWidget {
  const _Box({required this.child, this.height = 40});
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E4EA)),
        ),
        child: child,
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.label, required this.value, this.onTap});
  final String label, value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E4EA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: manrope(10, FontWeight.w600, EhbrColors.muted)),
              const SizedBox(height: 4),
              Text(value,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: manrope(11, FontWeight.w600, EhbrColors.ink)),
            ],
          ),
        ),
      );
}
