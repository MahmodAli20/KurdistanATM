import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/atm_status.dart';

/// How close you must physically be to report on a machine.
///
/// This one rule is what makes the crowd data trustworthy without accounts:
/// you cannot report on an ATM you are not standing at, so spam requires
/// actually driving there. It also removes any reason to collect identity.
const double kReportRadiusMetres = 100;

/// Minimum gap between two reports from the same device on the same machine.
const Duration kReportCooldown = Duration(minutes: 10);

/// Source of crowd-reported machine status.
///
/// Deliberately narrow so the Firestore implementation can slot in behind it
/// untouched. The shape mirrors the planned backend: status is read per *city*
/// as one aggregated document, never one document per ATM, which is what keeps
/// the app inside Firebase's free read quota.
abstract class StatusRepository {
  /// The anonymous, per-install identifier attached to this device's reports.
  ///
  /// Surfaced in the app because it is the only way a user can ask for their
  /// reports to be deleted: there are no accounts, so this string is the only
  /// handle that links a person to what they submitted. A deletion process
  /// nobody can actually use is not a deletion process.
  String get anonymousId;

  /// Aggregated status for every reported machine in a city, keyed by ATM id.
  Future<Map<String, AtmStatus>> statusesForCity(String city);

  /// Live updates for a city, if the backend supports them.
  Stream<Map<String, AtmStatus>> watchCity(String city);

  /// Raw reports for one machine, newest first - powers the detail sheet.
  Future<List<AtmReport>> reportsFor(String atmId);

  /// Record a report. Callers must have already verified proximity.
  Future<void> submit(AtmReport report);

  /// When this device may next report on [atmId], or null if it may report now.
  Future<DateTime?> cooldownUntil(String atmId);
}

/// On-device implementation used until Firebase is wired up.
///
/// Reports stay on the phone, so nothing is shared between users yet - but
/// every screen, decay curve and confidence badge is exercised exactly as it
/// will be against the real backend.
class LocalStatusRepository implements StatusRepository {
  LocalStatusRepository(this._prefs);

  static const _reportsKey = 'atm_reports_v1';
  static const _deviceKey = 'device_id_v1';

  final SharedPreferences _prefs;
  final _controllers = <String, StreamController<Map<String, AtmStatus>>>{};

  static Future<LocalStatusRepository> create() async =>
      LocalStatusRepository(await SharedPreferences.getInstance());

  @override
  String get anonymousId => deviceId;

  /// Anonymous per-install id. Random, never tied to a person or a phone
  /// number, and only ever used for rate limiting.
  String get deviceId {
    final existing = _prefs.getString(_deviceKey);
    if (existing != null) return existing;
    final random = Random.secure();
    final id = List.generate(16, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    _prefs.setString(_deviceKey, id);
    return id;
  }

  List<AtmReport> _allReports() {
    final raw = _prefs.getStringList(_reportsKey) ?? const [];
    final reports = <AtmReport>[];
    for (final entry in raw) {
      try {
        reports.add(
            AtmReport.fromJson(json.decode(entry) as Map<String, dynamic>));
      } on FormatException {
        // A corrupted entry should not take the whole history down with it.
        continue;
      }
    }
    return reports;
  }

  @override
  Future<Map<String, AtmStatus>> statusesForCity(String city) async {
    final grouped = <String, List<AtmReport>>{};
    for (final report in _allReports()) {
      // An empty city means "everything I have" - the map screen uses that to
      // colour pins without caring which city they fall in.
      if (city.isNotEmpty && report.city != city) continue;
      grouped.putIfAbsent(report.atmId, () => []).add(report);
    }
    return grouped
        .map((id, reports) => MapEntry(id, AtmStatus.fromReports(reports)));
  }

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

  @override
  Future<List<AtmReport>> reportsFor(String atmId) async {
    final reports = _allReports().where((r) => r.atmId == atmId).toList()
      ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
    return reports;
  }

  @override
  Future<DateTime?> cooldownUntil(String atmId) async {
    final mine = _allReports()
        .where((r) => r.atmId == atmId && r.deviceId == deviceId)
        .toList();
    if (mine.isEmpty) return null;

    mine.sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
    final next = mine.first.reportedAt.add(kReportCooldown);
    return next.isAfter(DateTime.now()) ? next : null;
  }

  @override
  Future<void> submit(AtmReport report) async {
    final raw = _prefs.getStringList(_reportsKey) ?? <String>[];
    raw.add(json.encode(report.toJson()));

    // Reports older than a day carry no weight, so there is no point storing
    // them; this keeps the local store from growing without bound.
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    final kept = raw.where((entry) {
      try {
        final decoded =
            AtmReport.fromJson(json.decode(entry) as Map<String, dynamic>);
        return decoded.reportedAt.isAfter(cutoff);
      } on FormatException {
        return false;
      }
    }).toList();

    await _prefs.setStringList(_reportsKey, kept);

    final refreshed = await statusesForCity('');
    for (final controller in _controllers.values) {
      if (!controller.isClosed) controller.add(refreshed);
    }
  }

  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
  }
}
