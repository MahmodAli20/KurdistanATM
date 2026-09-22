import 'package:flutter/material.dart';

import '../data/atm_repository.dart';
import '../l10n/bank_names.dart';
import '../data/featured_banks.dart';
import '../data/status_repository.dart';
import '../l10n/strings.dart';
import '../models/atm.dart';
import '../models/atm_status.dart';
import '../services/location_service.dart';
import 'theme.dart';
import 'widgets/atm_sheet.dart';

/// Landing screen: pick your bank, or see the one machine nearest to you.
///
/// The bank cards are the point of this screen - most people open the app
/// already knowing which card is in their pocket, and want the map filtered to
/// it rather than a wall of every machine in the city.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.atms,
    required this.status,
    required this.location,
    required this.onBankSelected,
    required this.onSeeAllNearby,
    required this.onNavigate,
  });

  final AtmRepository atms;
  final StatusRepository status;
  final LocationService location;

  /// null means "all banks".
  final void Function(String? bankId) onBankSelected;
  final VoidCallback onSeeAllNearby;
  final void Function(Atm atm) onNavigate;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Atm? _nearest;
  double? _nearestDistance;
  AtmStatus _nearestStatus = AtmStatus.unknownStatus;
  bool _locating = true;
  bool _locationDenied = false;
  bool _outsideCoverage = false;

  @override
  void initState() {
    super.initState();
    _findNearest();
  }

  Future<void> _findNearest() async {
    setState(() {
      _locating = true;
      _locationDenied = false;
      _outsideCoverage = false;
    });

    final result = await widget.location.current();
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _locating = false;
        _locationDenied = true;
      });
      return;
    }

    final position = result.position!;
    final near = widget.atms.near(
      position.latitude,
      position.longitude,
      radiusMetres: 20000,
      limit: 1,
    );

    if (near.isEmpty) {
      // Location worked; there simply are no machines here. Saying "turn on
      // location" would be both wrong and impossible to act on.
      setState(() {
        _locating = false;
        _outsideCoverage = true;
      });
      return;
    }

    final atm = near.first;
    final statuses = await widget.status.statusesForCity(atm.city);
    if (!mounted) return;

    setState(() {
      _nearest = atm;
      _nearestDistance = atm.distanceTo(position.latitude, position.longitude);
      _nearestStatus = statuses[atm.id] ?? AtmStatus.unknownStatus;
      _locating = false;
    });
  }

  Future<void> _openAtm(Atm atm) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AtmSheet(
        atm: atm,
        repository: widget.status,
        location: widget.location,
        onNavigate: widget.onNavigate,
      ),
    );
    await _findNearest();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);

    // Featured first, ordered by real coverage; everything else after.
    final all = widget.atms.banksBySize();
    final featured = [
      for (final bank in all)
        if (featuredBankIds.contains(bank.id)) bank
    ];
    final others = [
      for (final bank in all)
        if (!featuredBankIds.contains(bank.id) && bank.count >= 3) bank
    ];

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _findNearest,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              s.appTitle,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            _NearestCard(
              atm: _nearest,
              distance: _nearestDistance,
              status: _nearestStatus,
              locating: _locating,
              denied: _locationDenied,
              outsideCoverage: _outsideCoverage,
              onTap: _nearest == null ? null : () => _openAtm(_nearest!),
              onRetry: _findNearest,
            ),
            const SizedBox(height: 28),
            _SectionHeader(
              title: s.mainBanks,
              action: s.seeAll,
              onAction: () => widget.onBankSelected(null),
            ),
            const SizedBox(height: 12),
            ...featured.map((bank) => _BankTile(
                  nameEn: bank.nameEn,
                  nameCkb: bank.nameCkb,
                  count: bank.count,
                  onTap: () => widget.onBankSelected(bank.id),
                )),
            const SizedBox(height: 10),
            Text(
              s.countsCaveat,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 28),
              _SectionHeader(title: s.otherBanks),
              const SizedBox(height: 12),
              ...others.map((bank) => _BankTile(
                    nameEn: bank.nameEn,
                    nameCkb: bank.nameCkb,
                    count: bank.count,
                    onTap: () => widget.onBankSelected(bank.id),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

/// The single most useful fact on the screen: what is closest, and does it
/// have money.
class _NearestCard extends StatelessWidget {
  const _NearestCard({
    required this.atm,
    required this.distance,
    required this.status,
    required this.locating,
    required this.denied,
    required this.outsideCoverage,
    required this.onTap,
    required this.onRetry,
  });

  final Atm? atm;
  final double? distance;
  final AtmStatus status;
  final bool locating;
  final bool denied;
  final bool outsideCoverage;
  final VoidCallback? onTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);

    Widget body;
    if (locating) {
      body = Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 14),
          Text(s.findingNearest, style: theme.textTheme.bodyLarge),
        ],
      );
    } else if (outsideCoverage) {
      // Distinct from "location denied": location worked perfectly, the user
      // is just somewhere the app does not cover.
      body = Row(
        children: [
          const Icon(Icons.travel_explore_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              s.outsideCoverage,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      );
    } else if (denied || atm == null) {
      body = Row(
        children: [
          const Icon(Icons.location_off_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              s.turnOnLocationForNearest,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(s.retry)),
        ],
      );
    } else {
      final names = atm!.namesFor(s.lang).map(shortBankName).toList();
      final trusted = status.isTrustworthy;
      final state = trusted ? status.status : CashStatus.unknown;
      final ink = state.ink(theme.brightness);
      final wash = state.wash(theme.brightness);

      body = Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: wash, shape: BoxShape.circle),
            child: Icon(
              trusted ? status.status.icon : Icons.local_atm_rounded,
              color: ink,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  names.isNotEmpty ? names.join(' · ') : s.unknownBank,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatDistance(distance!, s)} · '
                  '${trusted ? status.status.label(s) : s.noReports}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: trusted ? ink : theme.colorScheme.onSurfaceVariant,
                    fontWeight: trusted ? FontWeight.w600 : null,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      );
    }

    return Card(
      elevation: 0,
      // Solid surfaceContainerHigh, not a faded tint: fading it back toward the
      // scaffold cancels the tonal step Material computed and leaves the card
      // at ~1.1:1 against its own background, which reads as unbroken text.
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Weight and colour mark this as an eyebrow label. Uppercase
              // and letter spacing would not: toUpperCase() does nothing to
              // Arabic script, and tracking prises its joined letters apart.
              Text(
                s.nearestAtm,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              body,
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    );
  }
}

class _BankTile extends StatelessWidget {
  const _BankTile({
    required this.nameEn,
    required this.nameCkb,
    required this.count,
    required this.onTap,
  });

  final String nameEn;
  final String nameCkb;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final primary = s.lang == AppLang.ckb ? nameCkb : nameEn;
    // Sorani readers still recognise the Latin brand on the machine itself.
    final secondary = s.lang == AppLang.ckb ? nameEn : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.account_balance,
                    size: 22, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        primary,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (secondary != null)
                        Text(
                          secondary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  s.machines(count),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
