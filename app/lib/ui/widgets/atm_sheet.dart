import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/bank_names.dart';
import '../../data/status_repository.dart';
import '../../l10n/strings.dart';
import '../../models/atm.dart';
import '../../models/atm_status.dart';
import '../../services/directions.dart';
import '../../services/location_service.dart';
import '../theme.dart';

/// Why the report buttons are or are not available right now.
enum _Gate { checking, ready, tooFar, noLocation, cooldown }

class AtmSheet extends StatefulWidget {
  const AtmSheet({
    super.key,
    required this.atm,
    required this.repository,
    required this.location,
    this.myLocation,
    this.onNavigate,
  });

  final Atm atm;
  final StatusRepository repository;
  final LocationService location;
  final LatLng? myLocation;

  /// Starts in-app routing to this machine. When null the sheet falls back to
  /// offering an external maps app only.
  final void Function(Atm atm)? onNavigate;

  @override
  State<AtmSheet> createState() => _AtmSheetState();
}

class _AtmSheetState extends State<AtmSheet> {
  AtmStatus _status = AtmStatus.unknownStatus;
  _Gate _gate = _Gate.checking;
  double? _distanceToMe;
  DateTime? _cooldownUntil;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final reports = await widget.repository.reportsFor(widget.atm.id);
    if (!mounted) return;
    setState(() => _status = AtmStatus.fromReports(reports));
    await _checkGate();
  }

  /// Decide whether this person may report.
  ///
  /// A deliberately fresh fix, not the cached map position: someone may have
  /// opened the app at home and driven to the machine since.
  Future<void> _checkGate() async {
    final cooldown = await widget.repository.cooldownUntil(widget.atm.id);
    if (cooldown != null) {
      if (mounted) {
        setState(() {
          _cooldownUntil = cooldown;
          _gate = _Gate.cooldown;
        });
      }
      return;
    }

    final result = await widget.location.current();
    if (!mounted) return;

    if (!result.ok) {
      setState(() => _gate = _Gate.noLocation);
      return;
    }

    final distance = widget.atm
        .distanceTo(result.position!.latitude, result.position!.longitude);
    setState(() {
      _distanceToMe = distance;
      _gate = distance <= kReportRadiusMetres ? _Gate.ready : _Gate.tooFar;
    });
  }

  Future<void> _report(CashStatus status) async {
    if (_gate != _Gate.ready || _submitting) return;
    setState(() => _submitting = true);

    final repository = widget.repository;
    final deviceId =
        repository is LocalStatusRepository ? repository.deviceId : 'anon';

    // Captured before the await: using context afterwards is unsafe, and on
    // the failure path the sheet must stay open to show the message.
    final s = Strings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    var sent = false;
    try {
      await repository.submit(AtmReport(
        atmId: widget.atm.id,
        city: widget.atm.city,
        status: status,
        reportedAt: DateTime.now(),
        deviceId: deviceId,
      ));
      sent = true;
    } catch (error) {
      // Firestore transactions are not served from the offline cache, so a
      // weak signal throws here. Without this the four buttons simply stayed
      // greyed out and the app said nothing at all.
      debugPrint('Report failed: $error');
    }

    if (!mounted) return;
    setState(() => _submitting = false);

    messenger.showSnackBar(
      SnackBar(content: Text(sent ? s.thanksForReport : s.reportNotSent)),
    );
    if (sent) navigator.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          _header(theme, s),
          const SizedBox(height: 20),
          _statusCard(theme, s),
          const SizedBox(height: 16),
          _attributes(s),
          const SizedBox(height: 20),
          // Routing happens on our own map. Handing off to Google Maps stays
          // available underneath for anyone who wants spoken turn-by-turn,
          // which this app deliberately does not try to reproduce.
          if (widget.onNavigate != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onNavigate!(widget.atm);
              },
              icon: const Icon(Icons.navigation_rounded),
              label: Text(s.startRoute),
            )
          else
            FilledButton.icon(
              onPressed: () => Directions.open(widget.atm),
              icon: const Icon(Icons.directions),
              label: Text(s.directions),
            ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => Directions.open(widget.atm),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(s.openInMapsApp),
          ),
          const SizedBox(height: 28),
          _reportSection(theme, s),
          const SizedBox(height: 16),
          Text(
            s.dataCredit,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, Strings s) {
    final atm = widget.atm;
    final sorani = s.lang == AppLang.ckb;
    final arabic = s.lang == AppLang.ar;

    final landmarkName = atm.landmark?.name(sorani, arabic);
    final areaName = atm.area?.name(sorani, arabic);

    // An unlabelled machine with a location can say something better than
    // "Unknown bank" - which is the whole of what it says today.
    final title = atm.bankKnown
        ? atm.bankLabel(s)
        : (areaName != null
            ? s.atmAt(areaName)
            : (landmarkName != null ? s.atmAt(landmarkName) : s.unknownBank));

    // Only fall back to the raw OSM name when there is no cue at all, and only
    // when it adds something - it is usually just the bank's name again.
    final raw = atm.name.trim();
    final fallbackName = (landmarkName == null && areaName == null &&
            raw.isNotEmpty &&
            !title.toLowerCase().contains(raw.toLowerCase()))
        ? raw
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (_distanceToMe != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: Text(
                  formatDistance(_distanceToMe!, s),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        // Two separate lines, never one joined string: a separator between a
        // Latin landmark name and an RTL area name is bidi-neutral and
        // reorders unpredictably between them.
        if (landmarkName != null) ...[
          const SizedBox(height: 6),
          _CueLine(
            icon: landmarkIcon(atm.landmark!.kind),
            text: s.nearPlace(landmarkName),
            emphasis: true,
          ),
        ],
        if (areaName != null) ...[
          const SizedBox(height: 3),
          _CueLine(icon: Icons.map_outlined, text: s.inArea(areaName)),
        ],
        if (fallbackName != null) ...[
          const SizedBox(height: 6),
          _CueLine(icon: Icons.label_outline_rounded, text: fallbackName),
        ],
        if (!widget.atm.bankKnown) ...[
          const SizedBox(height: 8),
          Text(
            s.reportWrongInfo,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _statusCard(ThemeData theme, Strings s) {
    final trusted = _status.isTrustworthy;
    final state = trusted ? _status.status : CashStatus.unknown;
    final ink = state.ink(theme.brightness);
    final wash = state.wash(theme.brightness);
    final age = _status.age;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ink.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            trusted ? _status.status.icon : Icons.help_outline_rounded,
            color: ink,
            size: 30,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trusted ? _status.status.label(s) : s.noReports,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                if (trusted && age != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${s.peopleReported(_status.reportCount)} · '
                    '${relativeTime(age, s)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _attributes(Strings s) {
    final atm = widget.atm;
    final chips = <({IconData icon, String label})>[
      if (atm.kind == AtmKind.agent)
        (icon: Icons.badge_rounded, label: s.cardAgent)
      else
        (icon: Icons.local_atm_rounded, label: s.atm),
      if (atm.isOpen24h) (icon: Icons.schedule, label: s.open24h),
      if (atm.driveThrough)
        (icon: Icons.directions_car, label: s.driveThrough),
      if (atm.indoor) (icon: Icons.meeting_room, label: s.indoor),
      if (atm.cashIn) (icon: Icons.savings, label: s.cashIn),
      if (atm.atBranch) (icon: Icons.account_balance, label: s.atBranch),
      for (final currency in atm.currencies)
        (icon: Icons.attach_money, label: currency),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final chip in chips)
          Chip(
            avatar: Icon(chip.icon, size: 16),
            label: Text(chip.label),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _reportSection(ThemeData theme, Strings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.howIsThisAtm,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          s.reportHelps,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        _gateNotice(theme, s),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.4,
          children: [
            for (final status in const [
              CashStatus.hasCash,
              CashStatus.noCash,
              CashStatus.outOfService,
              CashStatus.longQueue,
            ])
              _ReportButton(
                status: status,
                enabled: _gate == _Gate.ready && !_submitting,
                onTap: () => _report(status),
              ),
          ],
        ),
      ],
    );
  }

  /// Whole minutes left before this device may report here again, floored at 1
  /// so the message never reads "try again in 0 min".
  int get _minutesUntilCooldownEnds {
    if (_cooldownUntil == null) return 0;
    final left = _cooldownUntil!.difference(DateTime.now()).inMinutes;
    return left < 1 ? 1 : left;
  }

  /// Explains the proximity rule in place rather than just greying buttons out.
  Widget _gateNotice(ThemeData theme, Strings s) {
    final (icon, message) = switch (_gate) {
      _Gate.checking => (Icons.gps_fixed, s.findingYou),
      _Gate.ready => (Icons.check_circle, s.youAreHere),
      _Gate.tooFar => (
          Icons.social_distance,
          '${s.tooFarAway(_distanceToMe!.round())} · ${s.mustBeCloser}'
        ),
      _Gate.noLocation => (Icons.location_disabled, s.locationDenied),
      _Gate.cooldown => (
          Icons.hourglass_bottom,
          s.reportCooldown(_minutesUntilCooldownEnds)
        ),
    };

    final ok = _gate == _Gate.ready;
    final colour =
        ok ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: colour),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(color: colour),
          ),
        ),
        if (_gate == _Gate.tooFar || _gate == _Gate.noLocation)
          TextButton(
            onPressed: () {
              setState(() => _gate = _Gate.checking);
              _checkGate();
            },
            child: Text(s.retry),
          ),
      ],
    );
  }
}

/// One "where is it" line: an icon and a short phrase.
class _CueLine extends StatelessWidget {
  const _CueLine({
    required this.icon,
    required this.text,
    this.emphasis = false,
  });

  final IconData icon;
  final String text;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = emphasis
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 2),
          child: Icon(icon, size: 16, color: colour),
        ),
        const SizedBox(width: 6),
        // Flexible, not Expanded, so a long mall name ellipsizes instead of
        // forcing the row to full width.
        Flexible(
          child: Text(
            text,
            style: (emphasis
                    ? theme.textTheme.bodyMedium
                    : theme.textTheme.bodySmall)
                ?.copyWith(
              color: colour,
              fontWeight: emphasis ? FontWeight.w600 : null,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ReportButton extends StatelessWidget {
  const _ReportButton({
    required this.status,
    required this.enabled,
    required this.onTap,
  });

  final CashStatus status;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final ink = status.ink(theme.brightness);

    return Material(
      color: enabled
          ? status.wash(theme.brightness)
          : theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: enabled
              ? status.ink(theme.brightness).withValues(alpha: 0.35)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                status.icon,
                size: 20,
                color: enabled ? ink : theme.disabledColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status.label(s),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: enabled ? ink : theme.disabledColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
