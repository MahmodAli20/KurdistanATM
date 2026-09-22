import 'dart:math' as math;

/// Crowd-reported state of a machine.
///
/// Nothing here is measured - no bank in Iraq exposes ATM telemetry. Every
/// value comes from someone standing in front of the machine, so the model is
/// built around *decay* and *agreement* rather than a single truth value. A
/// report that cash was available three hours ago on payday is nearly
/// worthless; the same report four minutes ago is gold.
enum CashStatus { hasCash, noCash, outOfService, longQueue, unknown }

/// One tap by one person at one machine.
class AtmReport {
  const AtmReport({
    required this.atmId,
    required this.city,
    required this.status,
    required this.reportedAt,
    required this.deviceId,
  });

  final String atmId;

  /// Shard key. Status is stored and fetched one city at a time, which is what
  /// keeps a map open to one read instead of one per visible machine.
  final String city;

  final CashStatus status;
  final DateTime reportedAt;

  /// Anonymous, per-install. Used only to rate-limit and to let someone
  /// correct their own report - never to identify a person.
  final String deviceId;

  Map<String, dynamic> toJson() => {
        'atmId': atmId,
        'city': city,
        'status': status.name,
        'reportedAt': reportedAt.toUtc().toIso8601String(),
        'deviceId': deviceId,
      };

  factory AtmReport.fromJson(Map<String, dynamic> json) => AtmReport(
        atmId: json['atmId'] as String,
        city: json['city'] as String? ?? '',
        status: statusFromName(json['status'] as String?),
        reportedAt: DateTime.parse(json['reportedAt'] as String).toLocal(),
        deviceId: json['deviceId'] as String? ?? '',
      );

  static CashStatus statusFromName(String? name) => CashStatus.values
      .firstWhere((s) => s.name == name, orElse: () => CashStatus.unknown);
}

/// Aggregated, decayed view of one machine - what the map actually draws.
class AtmStatus {
  const AtmStatus({
    required this.status,
    required this.confidence,
    required this.reportCount,
    this.lastReportAt,
  });

  static const unknownStatus = AtmStatus(
    status: CashStatus.unknown,
    confidence: 0,
    reportCount: 0,
  );

  final CashStatus status;

  /// 0..1. Drives how strongly the pin is coloured, and whether the app is
  /// willing to make a claim at all.
  final double confidence;
  final int reportCount;
  final DateTime? lastReportAt;

  /// Below this the app says "no recent reports" instead of guessing.
  static const double _minTrustworthy = 0.15;

  bool get isTrustworthy =>
      status != CashStatus.unknown && confidence >= _minTrustworthy;

  Duration? get age =>
      lastReportAt == null ? null : DateTime.now().difference(lastReportAt!);

  /// How much a report still counts, by age.
  ///
  /// Full weight for two hours, fading to nothing at twelve. Cash state on the
  /// 1st of the month can flip in under an hour, so this is deliberately harsh.
  static double freshness(Duration age) {
    const full = Duration(hours: 2);
    const dead = Duration(hours: 12);
    if (age <= full) return 1.0;
    if (age >= dead) return 0.0;
    final span = dead.inSeconds - full.inSeconds;
    return 1.0 - (age.inSeconds - full.inSeconds) / span;
  }

  /// Collapse raw reports into one verdict.
  ///
  /// Each report votes with its own freshness as weight, so five stale "has
  /// cash" votes lose to one report from ten minutes ago. Confidence is then
  /// three independent factors multiplied together:
  ///
  ///   freshness  - how recent the newest report backing the winner is
  ///   agreement  - how much of the total weight the winner holds
  ///   volume     - how many people said it, saturating quickly so a single
  ///                honest report still shows a colour
  factory AtmStatus.fromReports(List<AtmReport> reports, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final weights = <CashStatus, double>{};
    final newestPerStatus = <CashStatus, DateTime>{};
    final countPerStatus = <CashStatus, int>{};
    var totalWeight = 0.0;
    DateTime? latest;

    for (final report in reports) {
      final weight = freshness(clock.difference(report.reportedAt));
      if (weight <= 0) continue;

      weights[report.status] = (weights[report.status] ?? 0) + weight;
      countPerStatus[report.status] = (countPerStatus[report.status] ?? 0) + 1;
      totalWeight += weight;

      final seen = newestPerStatus[report.status];
      if (seen == null || report.reportedAt.isAfter(seen)) {
        newestPerStatus[report.status] = report.reportedAt;
      }
      if (latest == null || report.reportedAt.isAfter(latest)) {
        latest = report.reportedAt;
      }
    }

    if (totalWeight == 0) return unknownStatus;

    final winner = weights.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final supporting = countPerStatus[winner.key] ?? 1;

    final winnerFreshness =
        freshness(clock.difference(newestPerStatus[winner.key]!));
    final agreement = winner.value / totalWeight;
    // 1 report -> 0.5, 2 -> 0.75, 3 -> 0.875. Diminishing, never reaching 1.
    final volume = 1 - math.pow(0.5, supporting).toDouble();

    return AtmStatus(
      status: winner.key,
      confidence: (winnerFreshness * agreement * volume).clamp(0.0, 1.0),
      reportCount: reports.length,
      lastReportAt: latest,
    );
  }
}
