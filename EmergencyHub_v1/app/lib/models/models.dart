double? _d(dynamic v) => (v as num?)?.toDouble();

class AppUser {
  AppUser({required this.id, required this.role, required this.firstName, required this.lastName,
      required this.contact, required this.address, required this.zone, this.email = ''});

  final String id, role, firstName, lastName, contact, address, zone, email;

  String get fullName => '$firstName $lastName'.trim();

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'firstName': firstName,
        'lastName': lastName,
        'contact': contact,
        'email': email,
        'address': address,
        'zone': zone,
      };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        role: (j['role'] ?? 'resident') as String,
        firstName: (j['firstName'] ?? '') as String,
        lastName: (j['lastName'] ?? '') as String,
        contact: (j['contact'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        address: (j['address'] ?? '') as String,
        zone: (j['zone'] ?? '') as String,
      );
}

class ContactEntry {
  ContactEntry({required this.name, required this.number, required this.category});
  final String name, number, category; // category: local | utility

  factory ContactEntry.fromJson(Map<String, dynamic> j) => ContactEntry(
      name: j['name'] as String, number: j['number'] as String, category: (j['category'] ?? 'local') as String);
}

class AppConfig {
  AppConfig({
    this.barangayName = '',
    this.city = '',
    this.hotline = '',
    this.sosNumber = '911',
    this.sosHold = true,
    this.lat = 14.5995,
    this.lng = 120.9842,
    this.radiusKm = 0,
    this.boundary = const [],
    this.zones = const [],
    this.allowAnonymous = true,
    this.contacts = const [],
    this.incidentTypes = const [],
    this.hazardTypes = const [],
    this.emailReset = false,
  });

  final String barangayName, city, hotline, sosNumber;
  final bool sosHold, allowAnonymous;

  /// True when the server can email password-reset codes.
  final bool emailReset;
  final double lat, lng;

  /// Service area around (lat, lng) in km. 0 = no limit.
  final double radiusKm;

  /// Exact border of the barangay as [lat, lng] pairs. Empty = use the radius.
  final List<List<double>> boundary;
  final List<String> zones;
  final List<ContactEntry> contacts;
  final List<String> incidentTypes, hazardTypes;

  bool get hasBorder => boundary.length >= 3;

  /// "Barangay Rizal, Taguig" – empty until the admin fills in Settings.
  String get locationLine => [
        if (barangayName.isNotEmpty) 'Barangay $barangayName',
        if (city.isNotEmpty) city,
      ].join(', ');

  List<String> get allTypes => [...incidentTypes, ...hazardTypes];

  factory AppConfig.fromJson(Map<String, dynamic> j) {
    final b = (j['barangay'] ?? {}) as Map<String, dynamic>;
    final sos = (j['sos'] ?? {}) as Map<String, dynamic>;
    final mc = (j['mapCenter'] ?? {}) as Map<String, dynamic>;
    final types = (j['reportTypes'] ?? {}) as Map<String, dynamic>;
    List<String> strs(dynamic v) => ((v ?? []) as List).map((e) => e as String).toList();
    return AppConfig(
      barangayName: (b['name'] ?? '') as String,
      city: (b['city'] ?? '') as String,
      hotline: (b['hotline'] ?? '') as String,
      sosNumber: (sos['number'] ?? '911') as String,
      sosHold: (sos['holdToConfirm'] ?? true) as bool,
      lat: _d(mc['lat']) ?? 14.5995,
      lng: _d(mc['lng']) ?? 120.9842,
      radiusKm: _d(mc['radiusKm']) ?? 0,
      boundary: [
        for (final p in ((mc['boundary'] ?? const []) as List))
          if (p is List && p.length >= 2 && _d(p[0]) != null && _d(p[1]) != null) [_d(p[0])!, _d(p[1])!],
      ],
      zones: strs(j['zones']),
      allowAnonymous: (j['allowAnonymous'] ?? true) as bool,
      emailReset: (j['emailReset'] ?? false) as bool,
      contacts: ((j['contacts'] ?? []) as List)
          .map((e) => ContactEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      incidentTypes: strs(types['incident']),
      hazardTypes: strs(types['hazard']),
    );
  }
}

class Announcement {
  Announcement({required this.id, required this.category, required this.title, required this.body, required this.createdAt});
  final String id, category, title, body; // category: alert | advisory | event
  final DateTime createdAt;

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: j['id'] as String,
        category: j['category'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      );
}

/// A road the barangay has marked as blocked (cleared by the admin when it reopens).
class Blockage {
  Blockage({required this.id, required this.title, required this.reason, required this.details,
      required this.lat, required this.lng, this.until, required this.createdAt});
  final String id, title, reason, details;
  final double lat, lng;
  final DateTime? until;
  final DateTime createdAt;

  factory Blockage.fromJson(Map<String, dynamic> j) => Blockage(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        reason: (j['reason'] ?? 'Other') as String,
        details: (j['details'] ?? '') as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        until: (j['until'] ?? '') == '' ? null : DateTime.tryParse(j['until'] as String)?.toLocal(),
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      );
}

class EvacCenter {
  EvacCenter({required this.id, required this.name, required this.address, this.lat, this.lng,
      required this.capacity, required this.occupied, required this.status});
  final String id, name, address, status; // status: open | standby | closed
  final double? lat, lng;
  final int capacity, occupied;

  factory EvacCenter.fromJson(Map<String, dynamic> j) => EvacCenter(
        id: j['id'] as String,
        name: j['name'] as String,
        address: (j['address'] ?? '') as String,
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        capacity: (j['capacity'] ?? 0) as int,
        occupied: (j['occupied'] ?? 0) as int,
        status: (j['status'] ?? 'standby') as String,
      );
}

class TimelineEntry {
  TimelineEntry(this.at, this.text);
  final DateTime at;
  final String text;
}

class Report {
  Report({required this.id, required this.type, required this.kind, required this.description,
      required this.urgency, required this.locationText, this.lat, this.lng, required this.status,
      required this.createdAt, required this.timeline});

  final String id, type, kind, description, urgency, locationText, status;
  final double? lat, lng;
  final DateTime createdAt;
  final List<TimelineEntry> timeline;

  factory Report.fromJson(Map<String, dynamic> j) => Report(
        id: j['id'] as String,
        type: j['type'] as String,
        kind: j['kind'] as String,
        description: (j['description'] ?? '') as String,
        urgency: (j['urgency'] ?? 'Medium') as String,
        locationText: (j['locationText'] ?? '') as String,
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        status: j['status'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        timeline: ((j['timeline'] ?? []) as List)
            .map((e) => TimelineEntry(DateTime.parse(e['at'] as String).toLocal(), e['text'] as String))
            .toList(),
      );
}

/// A verified/dispatched report visible to every resident.
class PublicReport {
  PublicReport({required this.id, required this.type, required this.kind, required this.urgency,
      required this.status, required this.locationText, this.lat, this.lng, required this.createdAt});

  final String id, type, kind, urgency, status, locationText;
  final double? lat, lng;
  final DateTime createdAt;

  factory PublicReport.fromJson(Map<String, dynamic> j) => PublicReport(
        id: j['id'] as String,
        type: j['type'] as String,
        kind: j['kind'] as String,
        urgency: (j['urgency'] ?? 'Medium') as String,
        status: j['status'] as String,
        locationText: (j['locationText'] ?? '') as String,
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      );
}

class AppNotification {
  AppNotification({required this.id, required this.kind, required this.title, required this.body,
      required this.createdAt, required this.unread});

  final String id, kind, title, body; // kind: announcement | report | alert
  final DateTime createdAt;
  final bool unread;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        kind: j['kind'] as String,
        title: j['title'] as String,
        body: (j['body'] ?? '') as String,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        unread: (j['unread'] ?? false) as bool,
      );
}

class NotificationFeed {
  NotificationFeed({required this.unread, required this.items});
  final int unread;
  final List<AppNotification> items;
}
