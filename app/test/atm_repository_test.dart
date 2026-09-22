import 'package:atm_finder/data/atm_repository.dart';
import 'package:atm_finder/models/atm.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the contract between the Python pipeline and the app. If build.py
/// ever changes a field name, these fail rather than the map quietly emptying.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AtmRepository repository;

  setUpAll(() async => repository = await AtmRepository.load());

  test('bundled dataset loads a plausible number of machines', () {
    expect(repository.all.length, greaterThan(400));
  });

  test('every record has usable coordinates inside the region', () {
    for (final atm in repository.all) {
      expect(atm.lat, inInclusiveRange(34.5, 37.6), reason: atm.id);
      expect(atm.lon, inInclusiveRange(41.0, 46.6), reason: atm.id);
      expect(atm.id, isNotEmpty);
    }
  });

  test('bank display names line up with bank ids', () {
    for (final atm in repository.all) {
      expect(atm.bankNamesEn.length, atm.banks.length, reason: atm.id);
      expect(atm.bankNamesCkb.length, atm.banks.length, reason: atm.id);
    }
  });

  test('Arabic bank names exist and line up with the bank ids', () {
    // Without these an Arabic-speaking user reads English bank names, because
    // the UI falls back to English whenever a name list is empty.
    for (final atm in repository.all) {
      expect(atm.bankNamesAr.length, atm.banks.length, reason: atm.id);
    }
    final withBanks = repository.all.where((a) => a.bankKnown);
    expect(withBanks.any((a) => a.bankNamesAr.isNotEmpty), isTrue);
  });

  test('NBI and TBI carry the initials people know them by', () {
    for (final id in ['nbi', 'tbi']) {
      final atm = repository.all.firstWhere((a) => a.banks.contains(id));
      final index = atm.banks.indexOf(id);
      final expected = id.toUpperCase();
      expect(atm.bankNamesEn[index], contains(expected));
      expect(atm.bankNamesCkb[index], contains(expected));
      expect(atm.bankNamesAr[index], contains(expected));
    }
  });

  test('most machines carry a human location cue', () {
    // The whole point of the landmark/area passes. If a pipeline change drops
    // them this fails loudly instead of the app quietly losing the feature.
    final located = repository.all
        .where((a) => a.landmark != null || a.area != null)
        .length;
    expect(located / repository.all.length, greaterThan(0.8));
  });

  test('landmarks are close enough for the claim to be true', () {
    for (final atm in repository.all) {
      final landmark = atm.landmark;
      if (landmark == null) continue;
      // Beyond this the cue stops describing where the machine is.
      expect(landmark.metres, lessThanOrEqualTo(300), reason: atm.id);
      expect(landmark.name(false, false), isNotEmpty, reason: atm.id);
    }
  });

  test('the major Kurdish banks are all present', () {
    final ids = repository.banksBySize().map((b) => b.id).toSet();
    expect(ids, containsAll(['cihan', 'rt', 'nbi', 'tbi']));
  });

  test('banks are ordered largest network first', () {
    final counts = repository.banksBySize().map((b) => b.count).toList();
    for (var i = 1; i < counts.length; i++) {
      expect(counts[i], lessThanOrEqualTo(counts[i - 1]));
    }
  });

  test('nearby search returns machines sorted by distance', () {
    // Erbil citadel, the centre of the densest part of the network.
    final near = repository.near(36.1911, 44.0091, radiusMetres: 3000);
    expect(near, isNotEmpty);

    var previous = 0.0;
    for (final atm in near) {
      final distance = atm.distanceTo(36.1911, 44.0091);
      expect(distance, greaterThanOrEqualTo(previous - 0.001));
      expect(distance, lessThanOrEqualTo(3000));
      previous = distance;
    }
  });

  test('card agents are excluded from cash searches by default', () {
    final cashOnly = repository.near(36.1911, 44.0091, radiusMetres: 50000);
    expect(cashOnly.every((a) => a.kind == AtmKind.atm), isTrue);
  });

  test('filtering by bank keeps unlabelled machines visible', () {
    // Half the network has no recorded owner. Dropping those would send people
    // past working ATMs, so a bank filter must never hide them.
    final filtered = repository.near(
      36.1911,
      44.0091,
      radiusMetres: 20000,
      banks: {'cihan'},
    );
    expect(filtered.any((a) => a.banks.contains('cihan')), isTrue);
    expect(filtered.any((a) => !a.bankKnown), isTrue);
    expect(
      filtered.any((a) => a.bankKnown && !a.banks.contains('cihan')),
      isFalse,
      reason: 'a machine known to belong to another bank must be filtered out',
    );
  });

  test('bounds search only returns machines inside the rectangle', () {
    final inside = repository.inBounds(36.15, 43.95, 36.25, 44.10);
    expect(inside, isNotEmpty);
    for (final atm in inside) {
      expect(atm.lat, inInclusiveRange(36.15, 36.25));
      expect(atm.lon, inInclusiveRange(43.95, 44.10));
    }
  });

  test('distance calculation is accurate against a known pair', () {
    // Erbil citadel to Sulaymaniyah centre is roughly 140 km.
    const citadel = Atm(
      id: 'x', kind: AtmKind.atm, lat: 36.1911, lon: 44.0091, city: 'erbil',
      name: '', nameCkb: '', banks: [], bankNamesEn: [], bankNamesCkb: [],
      currencies: [], hours: '', indoor: false, driveThrough: false,
      cashIn: false, atBranch: false, landmark: null,
    );
    final metres = citadel.distanceTo(35.5613, 45.4408);
    expect(metres / 1000, closeTo(140, 15));
  });
}
