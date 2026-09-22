import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/atm.dart';

/// Loads the bundled ATM dataset.
///
/// The list ships inside the app rather than coming from the network: it is
/// ~260 KB, changes at most weekly, and keeping it local means the map works
/// with no signal and costs nothing to serve.
class AtmRepository {
  AtmRepository._(this._all);

  final List<Atm> _all;
  static AtmRepository? _instance;

  static Future<AtmRepository> load() async {
    if (_instance != null) return _instance!;
    final raw = await rootBundle.loadString('assets/atms.json');
    final decoded = json.decode(raw) as Map<String, dynamic>;
    final atms = (decoded['atms'] as List)
        .map((e) => Atm.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return _instance = AtmRepository._(atms);
  }

  List<Atm> get all => _all;

  Atm? byId(String id) {
    for (final atm in _all) {
      if (atm.id == id) return atm;
    }
    return null;
  }

  /// Every canonical bank id present in the data, ordered by how many machines
  /// each one has - the filter list should lead with the banks people actually
  /// hold cards for.
  List<({String id, String nameEn, String nameCkb, int count})> banksBySize() {
    final counts = <String, int>{};
    final namesEn = <String, String>{};
    final namesCkb = <String, String>{};

    for (final atm in _all) {
      for (var i = 0; i < atm.banks.length; i++) {
        final id = atm.banks[i];
        counts[id] = (counts[id] ?? 0) + 1;
        if (i < atm.bankNamesEn.length) namesEn[id] = atm.bankNamesEn[i];
        if (i < atm.bankNamesCkb.length) namesCkb[id] = atm.bankNamesCkb[i];
      }
    }

    final ids = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return [
      for (final id in ids)
        (
          id: id,
          nameEn: namesEn[id] ?? id,
          nameCkb: namesCkb[id] ?? id,
          count: counts[id]!,
        )
    ];
  }

  /// Whether a position is close enough to the dataset to be worth centring
  /// the map on.
  ///
  /// The app covers the Kurdistan Region and Kirkuk. Someone opening it
  /// anywhere else - a reviewer in California, a user travelling - would
  /// otherwise be shown an empty map at their own coordinates, which looks
  /// broken rather than out of scope.
  bool covers(double lat, double lon, {double radiusMetres = 60000}) {
    for (final atm in _all) {
      if (atm.distanceTo(lat, lon) <= radiusMetres) return true;
    }
    return false;
  }

  /// Machines near a point, nearest first.
  ///
  /// Runs on-device over the bundled list, so it needs no geo index, no network
  /// round trip and no Firestore reads.
  List<Atm> near(
    double lat,
    double lon, {
    double radiusMetres = 5000,
    int limit = 100,
    Set<String>? banks,
    bool includeAgents = false,
    bool onlyUnknownBank = false,
  }) {
    final matches = <({Atm atm, double distance})>[];

    for (final atm in _all) {
      if (!includeAgents && atm.kind == AtmKind.agent) continue;
      if (onlyUnknownBank && atm.bankKnown) continue;
      // An unlabelled machine still dispenses cash, so it survives a bank
      // filter. Hiding it would hide half the network.
      if (banks != null &&
          banks.isNotEmpty &&
          atm.bankKnown &&
          !atm.banks.any(banks.contains)) {
        continue;
      }

      final distance = atm.distanceTo(lat, lon);
      if (distance <= radiusMetres) {
        matches.add((atm: atm, distance: distance));
      }
    }

    matches.sort((a, b) => a.distance.compareTo(b.distance));
    return matches.take(limit).map((m) => m.atm).toList();
  }

  /// Every city id present in the data, ordered by how many machines each has.
  List<({String id, int count})> citiesBySize() {
    final counts = <String, int>{};
    for (final atm in _all) {
      if (atm.kind != AtmKind.atm) continue;
      counts[atm.city] = (counts[atm.city] ?? 0) + 1;
    }
    final ids = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return [for (final id in ids) (id: id, count: counts[id]!)];
  }

  /// Machines in one city, optionally narrowed to a set of banks.
  ///
  /// Deliberately has no radius. Asking for "NBI in Duhok" while standing in
  /// Erbil is a reasonable question, and a distance cap would answer it with an
  /// empty list. When [fromLat]/[fromLon] are given the result is still ordered
  /// nearest-first, which keeps the ranking useful even across cities.
  List<Atm> inCity(
    String city, {
    Set<String>? banks,
    double? fromLat,
    double? fromLon,
    bool includeAgents = false,
    int limit = 400,
  }) {
    final matches = <Atm>[];
    for (final atm in _all) {
      if (!includeAgents && atm.kind == AtmKind.agent) continue;
      if (atm.city != city) continue;
      if (banks != null &&
          banks.isNotEmpty &&
          atm.bankKnown &&
          !atm.banks.any(banks.contains)) {
        continue;
      }
      matches.add(atm);
    }

    if (fromLat != null && fromLon != null) {
      matches.sort((a, b) => a
          .distanceTo(fromLat, fromLon)
          .compareTo(b.distanceTo(fromLat, fromLon)));
    } else {
      // No fix yet: a stable alphabetical order beats dataset order, which
      // would look arbitrary to the user.
      matches.sort((a, b) {
        final an = a.bankNamesEn.isEmpty ? '~' : a.bankNamesEn.first;
        final bn = b.bankNamesEn.isEmpty ? '~' : b.bankNamesEn.first;
        return an.compareTo(bn);
      });
    }

    return matches.take(limit).toList();
  }

  /// Machines whose coordinates fall inside the visible map rectangle.
  List<Atm> inBounds(
    double south,
    double west,
    double north,
    double east, {
    Set<String>? banks,
    bool includeAgents = false,
    int limit = 400,
  }) {
    final result = <Atm>[];
    for (final atm in _all) {
      if (!includeAgents && atm.kind == AtmKind.agent) continue;
      if (atm.lat < south || atm.lat > north) continue;
      if (atm.lon < west || atm.lon > east) continue;
      if (banks != null &&
          banks.isNotEmpty &&
          atm.bankKnown &&
          !atm.banks.any(banks.contains)) {
        continue;
      }
      result.add(atm);
      if (result.length >= limit) break;
    }
    return result;
  }
}
