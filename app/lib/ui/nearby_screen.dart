import 'package:flutter/material.dart';

import '../data/atm_repository.dart';
import '../l10n/bank_names.dart';
import '../data/cities.dart';
import '../data/status_repository.dart';
import '../l10n/strings.dart';
import '../models/atm.dart';
import '../models/atm_status.dart';
import '../services/location_service.dart';
import 'theme.dart';
import 'widgets/atm_sheet.dart';
import 'widgets/bank_filter_sheet.dart';
import 'widgets/city_filter_sheet.dart';

/// Machines as a plain ranked list, filterable by bank and by city.
///
/// This exists alongside the map on purpose. On payday the question is not
/// "where are the machines" - people already know - it is "which of these has
/// money". A list answers that at a glance and stays usable on a cheap phone
/// where panning a tile map is slow.
///
/// The two filters combine, so "NBI in Sulaymaniyah" is one tap each.
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({
    super.key,
    required this.atms,
    required this.status,
    required this.location,
    required this.selectedBanks,
    required this.onBanksChanged,
    required this.onNavigate,
  });

  final AtmRepository atms;
  final StatusRepository status;
  final LocationService location;
  final Set<String> selectedBanks;
  final ValueChanged<Set<String>> onBanksChanged;
  final void Function(Atm atm) onNavigate;

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  /// null means "around me" - use the GPS fix and a radius instead of a city.
  String? _city;

  List<Atm> _atms = const [];
  Map<String, AtmStatus> _statuses = const {};
  double? _lat;
  double? _lon;
  bool _loading = true;

  /// Only blocks the list when no city is chosen. With a city selected the
  /// list is perfectly useful without a fix - it just cannot rank by distance.
  bool _noLocation = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NearbyScreen old) {
    super.didUpdateWidget(old);
    if (old.selectedBanks != widget.selectedBanks) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _noLocation = false;
    });

    final result = await widget.location.current();
    if (!mounted) return;

    final lat = result.ok ? result.position!.latitude : null;
    final lon = result.ok ? result.position!.longitude : null;

    final List<Atm> found;
    if (_city != null) {
      // A city was chosen: ignore radius entirely, since the user may be
      // asking about a city they are not currently standing in.
      found = widget.atms.inCity(
        _city!,
        banks: widget.selectedBanks,
        fromLat: lat,
        fromLon: lon,
      );
    } else if (lat != null && lon != null) {
      found = widget.atms.near(
        lat,
        lon,
        radiusMetres: 15000,
        limit: 60,
        banks: widget.selectedBanks,
      );
    } else {
      // No city and no fix: there is nothing sensible to rank by.
      setState(() {
        _loading = false;
        _noLocation = true;
        _atms = const [];
      });
      return;
    }

    final statuses = <String, AtmStatus>{};
    for (final city in found.map((a) => a.city).toSet()) {
      statuses.addAll(await widget.status.statusesForCity(city));
    }

    if (!mounted) return;
    setState(() {
      _lat = lat;
      _lon = lon;
      _atms = found;
      _statuses = statuses;
      _loading = false;
    });
  }

  /// Splits the results into confirmed matches and machines whose owner was
  /// never recorded.
  ///
  /// Half the dataset has no bank attached, so a bank filter that dropped them
  /// would send people past working machines. But someone who asked for "NBI in
  /// Sulaymaniyah" should not have to hunt for the two NBI rows among six
  /// unlabelled ones either - so the unknowns stay, below a heading that says
  /// what they are.
  ({List<Atm> matches, List<Atm> unknown}) _partition() {
    if (widget.selectedBanks.isEmpty) {
      return (matches: _atms, unknown: const <Atm>[]);
    }
    final matches = <Atm>[];
    final unknown = <Atm>[];
    for (final atm in _atms) {
      if (atm.banks.any(widget.selectedBanks.contains)) {
        matches.add(atm);
      } else {
        unknown.add(atm);
      }
    }
    return (matches: matches, unknown: unknown);
  }

  Future<void> _pickBank() async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BankFilterSheet(
        banks: widget.atms.banksBySize(),
        selected: widget.selectedBanks,
      ),
    );
    if (picked == null || !mounted) return;
    widget.onBanksChanged(picked);
  }

  Future<void> _pickCity() async {
    final choice = await showModalBottomSheet<CityChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CityFilterSheet(
        cities: widget.atms.citiesBySize(),
        selected: _city,
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _city = choice.cityId);
    await _load();
  }

  void _clearFilters() {
    setState(() => _city = null);
    widget.onBanksChanged({});
    _load();
  }

  Future<void> _open(Atm atm) async {
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
    await _load();
  }

  String _bankLabel(Strings s) {
    if (widget.selectedBanks.isEmpty) return s.allBanks;
    if (widget.selectedBanks.length > 1) {
      return '${s.bank} (${widget.selectedBanks.length})';
    }
    final id = widget.selectedBanks.first;
    for (final bank in widget.atms.banksBySize()) {
      if (bank.id == id) {
        return s.lang == AppLang.ckb ? bank.nameCkb : bank.nameEn;
      }
    }
    return s.allBanks;
  }

  String _cityLabel(Strings s) {
    if (_city == null) return s.aroundMe;
    final display = cityDisplay(_city!);
    return switch (s.lang) {
      AppLang.ckb => display.ckb,
      AppLang.ar => display.ar,
      AppLang.en => display.en,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final filtered = widget.selectedBanks.isNotEmpty || _city != null;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _city == null ? s.nearby : _cityLabel(s),
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                if (filtered)
                  TextButton(
                    onPressed: _clearFilters,
                    child: Text(s.clearFilters),
                  ),
              ],
            ),
          ),
          _FilterRow(
            bankLabel: _bankLabel(s),
            cityLabel: _cityLabel(s),
            bankActive: widget.selectedBanks.isNotEmpty,
            cityActive: _city != null,
            onBank: _pickBank,
            onCity: _pickCity,
          ),
          const SizedBox(height: 4),
          Expanded(child: _body(s, theme)),
        ],
      ),
    );
  }

  Widget _body(Strings s, ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_noLocation) {
      return _Empty(
        icon: Icons.location_off_rounded,
        message: s.turnOnLocationForNearest,
        actionLabel: s.retry,
        onAction: _load,
      );
    }

    if (_atms.isEmpty) {
      return _Empty(
        icon: Icons.search_off_rounded,
        message: s.nothingMatches,
        actionLabel: s.clearFilters,
        onAction: _clearFilters,
      );
    }

    final knowsWhereIAm = _lat != null && _lon != null;
    final groups = _partition();

    Widget row(Atm atm) => _AtmRow(
          atm: atm,
          distance: knowsWhereIAm ? atm.distanceTo(_lat!, _lon!) : null,
          status: _statuses[atm.id] ?? AtmStatus.unknownStatus,
          onTap: () => _open(atm),
        );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          for (final atm in groups.matches) ...[
            row(atm),
            const SizedBox(height: 8),
          ],
          if (groups.unknown.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.bankNotRecorded,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.mightBeYourBank,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            for (final atm in groups.unknown) ...[
              row(atm),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.bankLabel,
    required this.cityLabel,
    required this.bankActive,
    required this.cityActive,
    required this.onBank,
    required this.onCity,
  });

  final String bankLabel;
  final String cityLabel;
  final bool bankActive;
  final bool cityActive;
  final VoidCallback onBank;
  final VoidCallback onCity;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: _FilterButton(
              icon: Icons.account_balance,
              label: bankLabel,
              active: bankActive,
              onTap: onBank,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _FilterButton(
              icon: Icons.location_city,
              label: cityLabel,
              active: cityActive,
              onTap: onCity,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground =
        active ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface;

    return Material(
      color: active
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHigh,
      shape: StadiumBorder(
        side: BorderSide(
          color: active
              ? theme.colorScheme.primary.withValues(alpha: 0.4)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.expand_more, size: 18, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _AtmRow extends StatelessWidget {
  const _AtmRow({
    required this.atm,
    required this.distance,
    required this.status,
    required this.onTap,
  });

  final Atm atm;

  /// null when there is no GPS fix - the row then shows the city instead.
  final double? distance;
  final AtmStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final names = atm.namesFor(s.lang).map(shortBankName).toList();
    final trusted = status.isTrustworthy;
    final state = trusted ? status.status : CashStatus.unknown;
    final ink = state.ink(theme.brightness);
    final wash = state.wash(theme.brightness);
    final age = status.age;

    final display = cityDisplay(atm.city);
    final cityName = switch (s.lang) {
      AppLang.ckb => display.ckb,
      AppLang.ar => display.ar,
      AppLang.en => display.en,
    };

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: wash, shape: BoxShape.circle),
                child: Icon(
                  trusted ? status.status.icon : Icons.local_atm_rounded,
                  color: ink,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      names.isNotEmpty ? names.join(' · ') : s.unknownBank,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      trusted && age != null
                          ? '${status.status.label(s)} · '
                              '${relativeTime(age, s)}'
                          : s.noReports,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            trusted ? ink : theme.colorScheme.onSurfaceVariant,
                        fontWeight: trusted ? FontWeight.w600 : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    distance != null
                        ? formatDistance(distance!, s)
                        : cityName,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (atm.isOpen24h)
                    Text(
                      s.open24h,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
