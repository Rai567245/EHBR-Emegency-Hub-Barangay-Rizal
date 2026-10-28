import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart' show LatLng;

import '../models/models.dart';
import '../phone.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/async_body.dart';

typedef _MapData = (List<PublicReport>, List<EvacCenter>, List<Blockage>);

enum _Kind { incident, hazard, evac, blocked }

class _Item {
  _Item(this.kind, this.tag, this.place, this.meta, this.status, this.lat, this.lng);
  final _Kind kind;
  final String tag, place, meta, status;
  final double? lat, lng;
  bool get hasPoint => lat != null && lng != null;
}

/// Verified / dispatched reports and evacuation centers around the barangay.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.reloadToken});
  final int reloadToken;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  _Kind? _filter; // null = all

  Future<_MapData> _load() async {
    final r = await Future.wait<Object>([Api.publicReports(), Api.centers(), Api.blockages()]);
    return (r[0] as List<PublicReport>, r[1] as List<EvacCenter>, r[2] as List<Blockage>);
  }

  List<_Item> _items(_MapData d) => [
        for (final r in d.$1)
          _Item(r.kind == 'incident' ? _Kind.incident : _Kind.hazard, r.type,
              r.locationText.isEmpty ? 'Location shared with responders' : r.locationText,
              'Reported ${ago(r.createdAt)}', r.status == 'DISPATCHED' ? 'RESPONDING' : 'VERIFIED', r.lat, r.lng),
        for (final c in d.$2.where((c) => c.status != 'closed'))
          _Item(_Kind.evac, c.name, c.address.isEmpty ? 'Evacuation center' : c.address,
              c.capacity > 0 ? '${c.occupied}/${c.capacity} inside' : 'Capacity not set',
              c.status == 'open' ? 'OPEN' : 'STANDBY', c.lat, c.lng),
        for (final b in d.$3)
          _Item(_Kind.blocked, b.reason, b.title,
              b.until != null ? 'Expected to reopen ${stamp(b.until!)}' : (b.details.isNotEmpty ? b.details : 'Blocked ${ago(b.createdAt)}'),
              'BLOCKED', b.lat, b.lng),
      ];

  @override
  Widget build(BuildContext context) {
    return AsyncBody<_MapData>(
      load: _load,
      reloadToken: widget.reloadToken,
      builder: (context, data, refresh) {
        final all = _items(data);
        int count(_Kind k) => all.where((i) => i.kind == k).length;
        final shown = all.where((i) => _filter == null || i.kind == _filter).toList();
        final chips = <(String, _Kind?)>[
          ('ALL', null),
          ('Incidents (${count(_Kind.incident)})', _Kind.incident),
          ('Hazards (${count(_Kind.hazard)})', _Kind.hazard),
          ('Evacuate (${count(_Kind.evac)})', _Kind.evac),
          ('Blocked (${count(_Kind.blocked)})', _Kind.blocked),
        ];
        final pts = [for (final i in all.where((i) => i.hasPoint)) LatLng(i.lat!, i.lng!)];
        final cfg = Session.config;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Nearby Reports', style: manrope(14, FontWeight.w700, EhbrColors.ink)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 11),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final c in chips) ...[
                      GestureDetector(
                        onTap: () => setState(() => _filter = c.$2),
                        child: Container(
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _filter == c.$2 ? EhbrColors.muted : Colors.white,
                            border: Border.all(color: _filter == c.$2 ? EhbrColors.muted : Colors.black),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(c.$1,
                              style: manrope(10, FontWeight.w600, _filter == c.$2 ? Colors.white : EhbrColors.ink)),
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 223,
              width: double.infinity,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: pts.length == 1 ? pts.first : LatLng(cfg.lat, cfg.lng),
                  initialZoom: pts.length == 1 ? 16 : 15,
                  initialCameraFit: pts.length >= 2
                      ? CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(40), maxZoom: 16)
                      : cfg.hasBorder
                          ? CameraFit.bounds(bounds: _borderBounds(cfg.boundary), padding: const EdgeInsets.all(12))
                          : null,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                  // Keep the map inside the barangay's service area so residents can't wander off to another town.
                  minZoom: (cfg.hasBorder || cfg.radiusKm > 0) ? 12 : 3,
                  cameraConstraint: cfg.hasBorder
                      ? CameraConstraint.containCenter(bounds: _borderBounds(cfg.boundary))
                      : cfg.radiusKm > 0
                          ? CameraConstraint.containCenter(bounds: _areaBounds(cfg.lat, cfg.lng, cfg.radiusKm))
                          : const CameraConstraint.unconstrained(),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'ph.barangay.ehbr',
                  ),
                  if (cfg.hasBorder)
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: [for (final p in cfg.boundary) LatLng(p[0], p[1])],
                          color: const Color(0x14C8203C),
                          borderColor: const Color(0xFFC8203C),
                          borderStrokeWidth: 2.5,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      for (final i in shown.where((i) => i.hasPoint))
                        Marker(
                          point: LatLng(i.lat!, i.lng!),
                          width: 30,
                          height: 30,
                          child: GestureDetector(
                            onTap: () => ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(SnackBar(content: Text('${i.tag} · ${i.place}'))),
                            child: _Pin(i.kind),
                          ),
                        ),
                    ],
                  ),
                  const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: RefreshIndicator(
                  onRefresh: refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
                    children: [
                      Text(
                        shown.isEmpty ? 'Nothing to show' : '${shown.length} item${shown.length == 1 ? '' : 's'} nearby',
                        style: manrope(14, FontWeight.w700, EhbrColors.ink.withValues(alpha: .5)),
                      ),
                      const SizedBox(height: 12),
                      if (shown.isEmpty)
                        const EmptyState(
                          icon: Icons.map_outlined,
                          title: 'No reports or evacuation centers yet',
                          message: 'Verified reports and evacuation centers appear here once the barangay confirms them.',
                        ),
                      for (final i in shown) ...[
                        _Row(i),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin(this.kind);
  final _Kind kind;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (kind) {
      _Kind.incident => (Icons.local_fire_department, EhbrColors.sos),
      _Kind.hazard => (Icons.warning_amber_rounded, EhbrColors.amber),
      _Kind.evac => (Icons.shield_outlined, EhbrColors.green),
      _Kind.blocked => (Icons.block, const Color(0xFF111827)),
    };
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 3)],
      ),
      child: Icon(icon, color: Colors.white, size: 16),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.i);
  final _Item i;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 8, right: 8),
      decoration: BoxDecoration(color: EhbrColors.card, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      flex: 0,
                      child: Container(
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: EhbrColors.muted, borderRadius: BorderRadius.circular(6)),
                        child: Text(i.tag,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: manrope(10, FontWeight.w600, Colors.white)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(i.place,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: manrope(12, FontWeight.w700, EhbrColors.ink)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(i.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: manrope(12, FontWeight.w700, EhbrColors.ink.withValues(alpha: .5))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: i.hasPoint ? () => openDirections(i.lat!, i.lng!) : null,
            child: Container(
              width: 84,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: EhbrColors.muted),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('[${i.status}]', maxLines: 1, style: manrope(11, FontWeight.w600, EhbrColors.muted)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A box around the barangay: centre ± radius (plus a little room so edge markers are not cut off).
LatLngBounds _areaBounds(double lat, double lng, double radiusKm) {
  final r = radiusKm * 1.25;
  final dLat = r / 111.32;
  final dLng = r / (111.32 * math.cos(lat * math.pi / 180));
  return LatLngBounds(LatLng(lat - dLat, lng - dLng), LatLng(lat + dLat, lng + dLng));
}

/// Bounding box of the border plus 15% room, so markers on the edge are not cut off.
LatLngBounds _borderBounds(List<List<double>> ring) {
  final lats = ring.map((p) => p[0]), lngs = ring.map((p) => p[1]);
  final a = lats.reduce(math.min), b = lats.reduce(math.max), x = lngs.reduce(math.min), y = lngs.reduce(math.max);
  final pa = (b - a) * 0.15 + 0.0005, px = (y - x) * 0.15 + 0.0005;
  return LatLngBounds(LatLng(a - pa, x - px), LatLng(b + pa, y + px));
}
