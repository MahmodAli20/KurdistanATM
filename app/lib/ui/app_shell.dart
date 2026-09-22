import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/atm_repository.dart';
import '../data/status_repository.dart';
import '../l10n/strings.dart';
import '../models/atm.dart';
import '../services/location_service.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'more_screen.dart';
import 'nearby_screen.dart';

/// Tab order. Home leads because most people arrive knowing which bank they
/// hold a card for, not which patch of the map they want to look at.
enum AppTab { home, map, nearby, more }

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.atms,
    required this.status,
    required this.prefs,
  });

  final AtmRepository atms;
  final StatusRepository status;

  /// Read before the first frame so the map never flashes hundreds of pins
  /// that then vanish.
  final SharedPreferences prefs;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// One instance shared by every tab. It caches the last fix, so switching
  /// tabs does not start a fresh GPS acquisition each time.
  final _location = LocationService();

  AppTab _tab = AppTab.home;

  /// The bank filter lives here rather than inside the map, so that picking a
  /// bank on Home and opening the map show the same selection.
  Set<String> _banks = {};

  /// The machine the user is currently routing to, if any. Held at the shell
  /// because navigation can be started from any tab but is always shown on the
  /// map.
  Atm? _navigatingTo;

  /// Machines with no recorded bank are hidden on the map by default: they are
  /// about half the dataset and they bury the labelled ones. The Nearby list
  /// and the Home card are deliberately untouched - they demote rather than
  /// hide, so nothing the user searches for disappears.
  static const _showUnlabelledKey = 'show_unlabelled_v1';
  late bool _showUnlabelled =
      widget.prefs.getBool(_showUnlabelledKey) ?? false;

  void _setShowUnlabelled(bool value) {
    widget.prefs.setBool(_showUnlabelledKey, value);
    setState(() => _showUnlabelled = value);
  }

  void _showBankOnMap(String? bankId) {
    setState(() {
      _banks = bankId == null ? {} : {bankId};
      _tab = AppTab.map;
    });
  }

  void _openNearby() => setState(() => _tab = AppTab.nearby);

  void _navigateTo(Atm atm) {
    setState(() {
      _navigatingTo = atm;
      _tab = AppTab.map;
    });
  }

  void _stopNavigating() => setState(() => _navigatingTo = null);

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);

    return Scaffold(
      // IndexedStack keeps every tab alive, so the map does not rebuild its
      // tiles and lose its position each time the user leaves and comes back.
      body: IndexedStack(
        index: _tab.index,
        children: [
          HomeScreen(
            atms: widget.atms,
            status: widget.status,
            location: _location,
            onBankSelected: _showBankOnMap,
            onSeeAllNearby: _openNearby,
            onNavigate: _navigateTo,
          ),
          MapScreen(
            atms: widget.atms,
            status: widget.status,
            location: _location,
            selectedBanks: _banks,
            onBanksChanged: (banks) => setState(() => _banks = banks),
            navigatingTo: _navigatingTo,
            onNavigate: _navigateTo,
            onStopNavigating: _stopNavigating,
            showUnlabelled: _showUnlabelled,
            onShowUnlabelledChanged: _setShowUnlabelled,
          ),
          NearbyScreen(
            atms: widget.atms,
            status: widget.status,
            location: _location,
            selectedBanks: _banks,
            onBanksChanged: (banks) => setState(() => _banks = banks),
            onNavigate: _navigateTo,
          ),
          MoreScreen(atms: widget.atms, status: widget.status),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        onDestinationSelected: (i) => setState(() => _tab = AppTab.values[i]),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: s.home,
          ),
          NavigationDestination(
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map_rounded),
            label: s.map,
          ),
          NavigationDestination(
            icon: const Icon(Icons.near_me_outlined),
            selectedIcon: const Icon(Icons.near_me_rounded),
            label: s.nearby,
          ),
          NavigationDestination(
            icon: const Icon(Icons.more_horiz_outlined),
            selectedIcon: const Icon(Icons.more_horiz_rounded),
            label: s.more,
          ),
        ],
      ),
    );
  }
}
