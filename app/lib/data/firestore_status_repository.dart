import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/atm_status.dart';
import 'status_repository.dart';

/// Crowd status backed by Cloud Firestore, designed to stay inside the Spark
/// (free) plan indefinitely. Three decisions do all the work:
///
/// 1. **One document per city, not per ATM.** Reading status for a map full of
///    215 machines in Erbil costs one document read, not 215. The naive design
///    exhausts the 50k daily reads at a few thousand users; this one uses a
///    few thousand reads at the same traffic.
///
/// 2. **`get()`, never `snapshots()`.** A realtime listener on a shared hot
///    document bills every connected client one read for every write anyone
///    makes. With a few hundred reports a day and a few thousand listeners
///    that is millions of reads. Status is fetched on open, on pull-to-refresh
///    and after the user's own report - which is fresh enough for something
///    that decays over hours.
///
/// 3. **Aggregation happens on the client.** Cloud Functions requires the Blaze
///    plan, so there is no server-side rollup available. Each report is folded
///    into the city document inside a transaction by the reporting device.
///
/// The trade-off of (3) is stated plainly: because clients write the aggregate,
/// a determined attacker who bypasses the app could corrupt a city document.
/// Two things limit that. Every report is also appended to an immutable
/// `reports` collection, so a poisoned city document can be rebuilt. And every
/// report decays to nothing within 12 hours, so damage is temporary. Turning on
/// App Check (free) is the real fix and should happen before any public launch.
class FirestoreStatusRepository implements StatusRepository {
  FirestoreStatusRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required SharedPreferences prefs,
  })  : _db = firestore,
        _auth = auth,
        _prefs = prefs;

  static const _statusCollection = 'status';
  static const _reportsCollection = 'reports';
  static const _cooldownPrefix = 'cooldown_';

  /// Most recent reports kept per machine inside the city document. Enough for
  /// the confidence maths, small enough that a city stays far below the 1 MiB
  /// document ceiling.
  static const _maxReportsPerAtm = 12;

  /// Reports older than this are dropped on write, so the document self-cleans
  /// without a scheduled job.
  static const _retention = Duration(hours: 12);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final SharedPreferences _prefs;

  final _controllers = <String, StreamController<Map<String, AtmStatus>>>{};
  final _cache = <String, List<AtmReport>>{};

  /// Anonymous sign-in. The user never sees this - there is no login screen and
  /// no personal data - but it gives every install a stable uid so security
  /// rules have something to attach per-writer limits to.
  Future<void> ensureSignedIn() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
  }

  String get _uid => _auth.currentUser?.uid ?? '';

  @override
  String get anonymousId => _uid;

  // ---------------------------------------------------------------- reading

  @override
  Future<Map<String, AtmStatus>> statusesForCity(String city) async {
    if (city.isEmpty) return const {};

    try {
      final snapshot =
          await _db.collection(_statusCollection).doc(city).get();
      final reports = _decode(city, snapshot.data());
      _cache[city] = reports;
      return _aggregate(reports);
    } on FirebaseException {
      // Offline or rules rejected the read: fall back to whatever this session
      // already fetched rather than blanking every pin on the map.
      return _aggregate(_cache[city] ?? const []);
    }
  }

  /// Emits on explicit refresh rather than subscribing to Firestore, for the
  /// billing reason described on the class.
  @override
  Stream<Map<String, AtmStatus>> watchCity(String city) {
    final controller = _controllers.putIfAbsent(
      city,
      () => StreamController<Map<String, AtmStatus>>.broadcast(),
    );
    statusesForCity(city).then((value) {
      if (!controller.isClosed) controller.add(value);
    });
    return controller.stream;
  }

  /// Served from the city document already in memory - reading an ATM's history
  /// costs nothing extra.
  @override
  Future<List<AtmReport>> reportsFor(String atmId) async {
    final all = <AtmReport>[];
    for (final reports in _cache.values) {
      all.addAll(reports.where((r) => r.atmId == atmId));
    }
    all.sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
    return all;
  }

  // ---------------------------------------------------------------- writing

  @override
  Future<DateTime?> cooldownUntil(String atmId) async {
    final raw = _prefs.getString('$_cooldownPrefix$atmId');
    if (raw == null) return null;
    final until = DateTime.tryParse(raw)?.add(kReportCooldown);
    if (until == null) return null;
    return until.isAfter(DateTime.now()) ? until : null;
  }

  @override
  Future<void> submit(AtmReport report) async {
    await ensureSignedIn();

    final cityRef = _db.collection(_statusCollection).doc(report.city);

    // The aggregate is read-modify-written, so it has to be a transaction:
    // two people reporting on the same city within the same second must not
    // overwrite each other. Firestore retries this automatically on conflict.
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(cityRef);
      final atms = Map<String, dynamic>.from(
        (snapshot.data()?['atms'] as Map?) ?? const {},
      );

      final cutoff = DateTime.now().subtract(_retention).millisecondsSinceEpoch;
      final existing = List<Map<String, dynamic>>.from(
        (atms[report.atmId] as List?)?.map(
              (e) => Map<String, dynamic>.from(e as Map),
            ) ??
            const [],
      )..removeWhere((entry) => (entry['t'] as int? ?? 0) < cutoff);

      // No uid here. This document is world-readable (firestore.rules:
      // `allow read: if true`), and because a report requires standing within
      // 100 m of a known machine, storing the device id alongside the
      // timestamp would publish a reconstructable per-device location trail to
      // anyone on the internet. The uid is kept in `reports/`, which the rules
      // make unreadable, which is enough for rebuilding and abuse review.
      existing.add({
        's': report.status.name,
        't': report.reportedAt.millisecondsSinceEpoch,
      });

      // Newest first, then truncate - an unbounded list would eventually push
      // the city document past Firestore's 1 MiB limit.
      existing.sort((a, b) => (b['t'] as int).compareTo(a['t'] as int));
      if (existing.length > _maxReportsPerAtm) {
        existing.removeRange(_maxReportsPerAtm, existing.length);
      }

      atms[report.atmId] = existing;

      transaction.set(
        cityRef,
        {'atms': atms, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    });

    // Immutable audit copy. Cheap insurance: if a city document is ever
    // corrupted it can be rebuilt from here.
    await _db.collection(_reportsCollection).add({
      'atmId': report.atmId,
      'city': report.city,
      'status': report.status.name,
      'uid': _uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _prefs.setString(
      '$_cooldownPrefix${report.atmId}',
      DateTime.now().toIso8601String(),
    );

    final refreshed = await statusesForCity(report.city);
    final controller = _controllers[report.city];
    if (controller != null && !controller.isClosed) {
      controller.add(refreshed);
    }
  }

  // ---------------------------------------------------------------- helpers

  List<AtmReport> _decode(String city, Map<String, dynamic>? data) {
    final atms = data?['atms'] as Map?;
    if (atms == null) return const [];

    final reports = <AtmReport>[];
    atms.forEach((atmId, entries) {
      if (entries is! List) return;
      for (final entry in entries) {
        if (entry is! Map) continue;
        final millis = entry['t'];
        if (millis is! int) continue;
        reports.add(AtmReport(
          atmId: atmId.toString(),
          city: city,
          status: AtmReport.statusFromName(entry['s'] as String?),
          reportedAt: DateTime.fromMillisecondsSinceEpoch(millis),
          deviceId: '',
        ));
      }
    });
    return reports;
  }

  Map<String, AtmStatus> _aggregate(List<AtmReport> reports) {
    final grouped = <String, List<AtmReport>>{};
    for (final report in reports) {
      grouped.putIfAbsent(report.atmId, () => []).add(report);
    }
    return grouped
        .map((id, list) => MapEntry(id, AtmStatus.fromReports(list)));
  }

  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
  }
}
