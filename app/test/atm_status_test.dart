import 'package:atm_finder/models/atm_status.dart';
import 'package:flutter_test/flutter_test.dart';

AtmReport report(CashStatus status, Duration ago, {String device = 'a'}) =>
    AtmReport(
      atmId: 'atm1',
      city: 'erbil',
      status: status,
      reportedAt: DateTime.now().subtract(ago),
      deviceId: device,
    );

void main() {
  group('freshness decay', () {
    test('full weight for the first two hours', () {
      expect(AtmStatus.freshness(const Duration(minutes: 5)), 1.0);
      expect(AtmStatus.freshness(const Duration(hours: 2)), 1.0);
    });

    test('decays to nothing by twelve hours', () {
      expect(AtmStatus.freshness(const Duration(hours: 12)), 0.0);
      expect(AtmStatus.freshness(const Duration(hours: 24)), 0.0);
      final midway = AtmStatus.freshness(const Duration(hours: 7));
      expect(midway, greaterThan(0.0));
      expect(midway, lessThan(1.0));
    });
  });

  group('aggregation', () {
    test('no reports means unknown, not a guess', () {
      final status = AtmStatus.fromReports([]);
      expect(status.status, CashStatus.unknown);
      expect(status.isTrustworthy, isFalse);
    });

    test('reports older than the decay window are ignored entirely', () {
      final status = AtmStatus.fromReports([
        report(CashStatus.hasCash, const Duration(hours: 20)),
      ]);
      expect(status.status, CashStatus.unknown);
    });

    test('a single fresh report is trustworthy but not certain', () {
      final status = AtmStatus.fromReports([
        report(CashStatus.hasCash, const Duration(minutes: 10)),
      ]);
      expect(status.status, CashStatus.hasCash);
      expect(status.isTrustworthy, isTrue);
      expect(status.confidence, closeTo(0.5, 0.01));
    });

    test('agreeing reports raise confidence with diminishing returns', () {
      final one = AtmStatus.fromReports([
        report(CashStatus.hasCash, const Duration(minutes: 5), device: 'a'),
      ]);
      final three = AtmStatus.fromReports([
        report(CashStatus.hasCash, const Duration(minutes: 5), device: 'a'),
        report(CashStatus.hasCash, const Duration(minutes: 6), device: 'b'),
        report(CashStatus.hasCash, const Duration(minutes: 7), device: 'c'),
      ]);
      expect(three.confidence, greaterThan(one.confidence));
      expect(three.confidence, closeTo(0.875, 0.01));
    });

    test('one fresh report outweighs several stale contradicting ones', () {
      // The payday case: cash ran out an hour ago, but four people said it was
      // fine this morning. The recent report has to win.
      final status = AtmStatus.fromReports([
        for (var i = 0; i < 4; i++)
          report(CashStatus.hasCash, const Duration(hours: 10), device: 'old$i'),
        report(CashStatus.noCash, const Duration(minutes: 8), device: 'new'),
      ]);
      expect(status.status, CashStatus.noCash);
    });

    test('disagreement lowers confidence below unanimous agreement', () {
      final split = AtmStatus.fromReports([
        report(CashStatus.hasCash, const Duration(minutes: 5), device: 'a'),
        report(CashStatus.noCash, const Duration(minutes: 5), device: 'b'),
      ]);
      final unanimous = AtmStatus.fromReports([
        report(CashStatus.hasCash, const Duration(minutes: 5), device: 'a'),
        report(CashStatus.hasCash, const Duration(minutes: 5), device: 'b'),
      ]);
      expect(split.confidence, lessThan(unanimous.confidence));
    });

    test('out of service is reported and surfaced like any other state', () {
      final status = AtmStatus.fromReports([
        report(CashStatus.outOfService, const Duration(minutes: 3), device: 'a'),
        report(CashStatus.outOfService, const Duration(minutes: 4), device: 'b'),
      ]);
      expect(status.status, CashStatus.outOfService);
      expect(status.isTrustworthy, isTrue);
    });

    test('lastReportAt tracks the newest report', () {
      final status = AtmStatus.fromReports([
        report(CashStatus.hasCash, const Duration(hours: 3)),
        report(CashStatus.hasCash, const Duration(minutes: 2)),
      ]);
      expect(status.age!.inMinutes, lessThan(5));
    });
  });
}
