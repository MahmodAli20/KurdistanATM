import 'dart:math' as math;

/// Whether a pin dispenses cash or is a card agent (Qi Card, FastPay).
/// Agents matter for salary cards but cannot hand out money, so the map
/// keeps them visually distinct and filters them out by default.
enum AtmKind { atm, agent }

/// A nearby thing people actually navigate by - a mall, a bazaar, a park.
///
/// Assigned at build time by `data/landmarks.py` from OpenStreetMap, never at
/// runtime, so it works offline like the rest of the dataset. Present on about
/// four machines in five; absent when nothing credible sits within 300 m,
/// because naming a landmark further away misleads rather than helps.
class Landmark {
  const Landmark({
    required this.en,
    required this.ckb,
    required this.ar,
    required this.kind,
    required this.metres,
  });

  final String en;
  final String ckb;
  final String ar;

  /// The OSM tag it came from, e.g. `shop=mall`, used to pick an icon.
  final String kind;
  final int metres;

  /// Only about a fifth of these carry a Sorani name in OSM, so both RTL
  /// languages fall back through Arabic to English rather than showing
  /// nothing.
  String name(bool sorani, bool arabic) {
    if (sorani && ckb.isNotEmpty) return ckb;
    if ((sorani || arabic) && ar.isNotEmpty) return ar;
    return en.isNotEmpty ? en : (ar.isNotEmpty ? ar : ckb);
  }

  static Landmark? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final en = raw['en'] as String? ?? '';
    final ckb = raw['ckb'] as String? ?? '';
    final ar = raw['ar'] as String? ?? '';
    if (en.isEmpty && ckb.isEmpty && ar.isEmpty) return null;
    return Landmark(
      en: en,
      ckb: ckb,
      ar: ar,
      kind: raw['kind'] as String? ?? '',
      metres: (raw['metres'] as num?)?.round() ?? 0,
    );
  }
}

class Atm {
  const Atm({
    required this.id,
    required this.kind,
    required this.lat,
    required this.lon,
    required this.city,
    required this.name,
    required this.nameCkb,
    required this.banks,
    required this.bankNamesEn,
    required this.bankNamesCkb,
    required this.currencies,
    required this.hours,
    required this.indoor,
    required this.driveThrough,
    required this.cashIn,
    required this.atBranch,
    required this.landmark,
    this.area,
    this.bankNamesAr = const [],
  });

  final String id;
  final AtmKind kind;
  final double lat;
  final double lon;
  final String city;
  final String name;
  final String nameCkb;

  /// Canonical bank ids. Empty means nobody has recorded which bank owns this
  /// machine yet - roughly half the dataset. The UI must say "unknown bank"
  /// rather than hiding the pin, because an unlabelled ATM still gives cash.
  final List<String> banks;
  final List<String> bankNamesEn;
  final List<String> bankNamesCkb;

  /// Defaulted rather than required: a const Atm literal in the tests lists
  /// every field, and a required parameter would break it.
  final List<String> bankNamesAr;

  final List<String> currencies;
  final String hours;
  final bool indoor;
  final bool driveThrough;
  final bool cashIn;
  final bool atBranch;

  /// The nearest thing to navigate by - a mall, a bazaar. See [Landmark].
  final Landmark? landmark;

  /// Which part of town. Computed independently of [landmark], not as a
  /// fallback: a machine can be 260 m from a supermarket and 90 m from the
  /// middle of Awbara, and "in Awbara area" is the better answer.
  final Landmark? area;

  bool get bankKnown => banks.isNotEmpty;
  bool get isOpen24h => hours.trim() == '24/7';

  factory Atm.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) =>
        (json[key] as List?)?.map((e) => e.toString()).toList() ?? const [];

    return Atm(
      id: json['id'] as String,
      kind: json['kind'] == 'agent' ? AtmKind.agent : AtmKind.atm,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      city: json['city'] as String? ?? 'other',
      name: json['name'] as String? ?? '',
      nameCkb: json['name_ckb'] as String? ?? '',
      banks: strings('banks'),
      bankNamesEn: strings('bank_names_en'),
      bankNamesCkb: strings('bank_names_ckb'),
      bankNamesAr: strings('bank_names_ar'),
      currencies: strings('currencies'),
      hours: json['hours'] as String? ?? '',
      indoor: json['indoor'] as bool? ?? false,
      driveThrough: json['drive_through'] as bool? ?? false,
      cashIn: json['cash_in'] as bool? ?? false,
      atBranch: json['at_branch'] as bool? ?? false,
      landmark: Landmark.fromJson(json['landmark']),
      area: Landmark.fromJson(json['area']),
    );
  }

  /// Great-circle distance in metres.
  double distanceTo(double otherLat, double otherLon) {
    const earthRadius = 6371000.0;
    final dLat = _radians(otherLat - lat);
    final dLon = _radians(otherLon - lon);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat)) *
            math.cos(_radians(otherLat)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * earthRadius * math.asin(math.sqrt(a));
  }

  static double _radians(double degrees) => degrees * math.pi / 180.0;
}
