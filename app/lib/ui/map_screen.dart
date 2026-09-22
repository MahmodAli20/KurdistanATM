import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/atm_repository.dart';
import '../data/status_repository.dart';
import '../l10n/strings.dart';
import '../models/atm.dart';
import '../models/atm_status.dart';
import '../services/location_service.dart';
import '../services/routing_service.dart';
import 'theme.dart';
import 'widgets/atm_pin.dart';
import 'widgets/atm_sheet.dart';
import 'widgets/bank_filter_sheet.dart';
import 'widgets/navigation_banner.dart';

/// Erbil city centre - where the map opens before we know where you are.
const _defaultCentre = LatLng(36.1911, 44.0091);

/// Below this zoom the whole region's pins turn into unreadable confetti, so
/// the map shows a "zoom in" hint instead.
const double _minPinZoom = 11.5;

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.atms,
    required this.status,
    required this.location,
    required this.selectedBanks,
    required this.onBanksChanged,
    required this.navigatingTo,
    required this.onNavigate,
    required this.onStopNavigating,
    required this.showUnlabelled,
    required this.onShowUnlabelledChanged,
  });

  final AtmRepository atms;
  final StatusRepository status;

  /// Shared with the other tabs so one GPS acquisition serves the whole app.
  final LocationService location;

  /// Owned by the shell: picking a bank on Home must show up here too.
  final Set<String> selectedBanks;
  final ValueChanged<Set<String>> onBanksChanged;

  /// The machine being routed to, or null when not navigating.
  final Atm? navigatingTo;
  final void Function(Atm atm) onNavigate;
  final VoidCallback onStopNavigating;

  /// Whether machines with no recorded bank are drawn. Owned by the shell so
  /// it survives a tab switch, and persisted so it survives a restart.
  final bool showUnlabelled;
  final ValueChanged<bool> onShowUnlabelledChanged;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  final _routing = RoutingService();

  List<Atm> _visible = const [];
  Map<String, AtmStatus> _statuses = const {};
  LatLng? _me;
  double _zoom = 12;
  bool _locating = false;

  /// The user is outside every city in the dataset, so their own position is
  /// not a useful place to show them.
  bool _outsideCoverage = false;

  // -- navigation state ----------------------------------------------------
  AtmRoute? _route;
  bool _routeLoading = false;
  double? _remainingMetres;

  /// Direction arrows along the route. flutter_map has no arrow decorator, so
  /// these are ordinary markers. Built ONCE when navigation starts - building
  /// them in build() would recompute on every pan frame.
  List<Marker> _chevrons = const [];

  /// Live position updates, active only while navigating. Keeping the stream
  /// off the rest of the time matters: a continuous high-accuracy GPS
  /// subscription is the most battery-expensive thing this app can do.
  StreamSubscription<Position>? _positionSub;


  /// When each city's status was last fetched, so panning the map does not
  /// re-read the same document over and over. Status decays over hours, so
  /// two minutes of staleness costs nothing and saves a great deal of quota.
  final _lastFetched = <String, DateTime>{};
  static const _statusTtl = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    // Ask for a fix immediately: almost everyone opening this app wants the
    // nearest machine, not a view of Erbil city centre.
    WidgetsBinding.instance.addPostFrameCallback((_) => _goToMe(quiet: true));
  }

  @override
  void didUpdateWidget(MapScreen old) {
    super.didUpdateWidget(old);
    // A bank chosen on the Home tab has to redraw the pins here.
    if (old.selectedBanks != widget.selectedBanks) {
      _recomputeVisible(_map.camera.visibleBounds);
    }
    if (old.navigatingTo?.id != widget.navigatingTo?.id) {
      if (widget.navigatingTo == null) {
        _endNavigation();
      } else {
        _beginNavigation(widget.navigatingTo!);
      }
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _routing.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- navigation

  Future<void> _beginNavigation(Atm target) async {
    setState(() {
      _routeLoading = true;
      _route = null;
      _remainingMetres = null;
    });

    final fix = await widget.location.current();
    if (!mounted) return;

    final origin = fix.ok
        ? LatLng(fix.position!.latitude, fix.position!.longitude)
        : _me;

    if (origin == null) {
      setState(() => _routeLoading = false);
      _showLocationProblem(fix.outcome);
      widget.onStopNavigating();
      return;
    }

    final destination = LatLng(target.lat, target.lon);
    final route = await _routing.route(origin, destination);
    if (!mounted) return;

    setState(() {
      _me = origin;
      _route = route;
      _remainingMetres = route.metres;
      _routeLoading = false;
    });

    _buildChevrons(route);
    _fitRoute(route);
    _followPosition(target);
  }

  /// Arrows every so often along the line, so the route reads as having a
  /// direction rather than just a shape.
  void _buildChevrons(AtmRoute route) {
    final points = route.points;
    if (points.length < 2) {
      setState(() => _chevrons = const []);
      return;
    }

    // A straight-line fallback route has exactly two points, so stepping
    // vertex to vertex would place no arrows on precisely the routes that need
    // the cue most. Interpolate along each segment instead.
    final spacing = math.max(90.0, route.metres / 12);
    final markers = <Marker>[];
    var carried = 0.0;

    for (var i = 0; i < points.length - 1 && markers.length < 18; i++) {
      final a = points[i];
      final b = points[i + 1];
      final segment = _metresBetween(a, b);
      if (segment <= 0) continue;

      final bearing = RoutingService.bearing(a, b);
      var travelled = spacing - carried;
      while (travelled < segment && markers.length < 18) {
        final t = travelled / segment;
        markers.add(
          Marker(
            point: LatLng(
              a.latitude + (b.latitude - a.latitude) * t,
              a.longitude + (b.longitude - a.longitude) * t,
            ),
            width: 18,
            height: 18,
            // The layer already counter-rotates with the camera, so the arrow
            // stays glued to the line.
            rotate: false,
            child: Transform.rotate(
              angle: bearing * math.pi / 180,
              // White, not route blue: a blue arrow on a blue line is invisible.
              child: const Icon(Icons.navigation_rounded,
                  size: 13, color: Colors.white),
            ),
          ),
        );
        travelled += spacing;
      }
      carried = (segment - (travelled - spacing)) % spacing;
    }

    setState(() => _chevrons = markers);
  }

  static double _metresBetween(LatLng a, LatLng b) {
    const radius = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * radius * math.asin(math.sqrt(h));
  }

  /// Follows the user along the fetched route without asking the routing
  /// service anything further - remaining distance is measured locally.
  void _followPosition(Atm target) {
    _positionSub?.cancel();
    _positionSub = widget.location.watch().listen((position) {
      if (!mounted) return;
      final me = LatLng(position.latitude, position.longitude);
      final remaining = target.distanceTo(position.latitude, position.longitude);
      setState(() {
        _me = me;
        _remainingMetres = remaining;
      });
    });
  }

  void _endNavigation() {
    _positionSub?.cancel();
    _positionSub = null;
    if (mounted) {
      setState(() {
        _route = null;
        _remainingMetres = null;
        _routeLoading = false;
        _chevrons = const [];
      });
    }
  }

  void _fitRoute(AtmRoute route) {
    if (route.points.length < 2) return;
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(route.points),
        padding: const EdgeInsets.fromLTRB(48, 120, 48, 220),
        maxZoom: 17,
      ),
    );
  }

  /// Fetch status for whichever cities are currently on screen.
  ///
  /// Status is stored one document per city, so this is one read per city in
  /// view - almost always exactly one.
  Future<void> _refreshStatuses({bool force = false}) async {
    final cities = _visible.map((atm) => atm.city).toSet();
    if (cities.isEmpty) return;

    final now = DateTime.now();
    final merged = <String, AtmStatus>{..._statuses};
    var changed = false;

    for (final city in cities) {
      final last = _lastFetched[city];
      if (!force && last != null && now.difference(last) < _statusTtl) continue;

      _lastFetched[city] = now;
      merged.addAll(await widget.status.statusesForCity(city));
      changed = true;
    }

    if (changed && mounted) setState(() => _statuses = merged);
  }

  void _recomputeVisible(LatLngBounds bounds) {
    setState(() {
      _visible = widget.atms.inBounds(
        bounds.south,
        bounds.west,
        bounds.north,
        bounds.east,
        banks: widget.selectedBanks,
      );
    });
    _refreshStatuses();
  }

  Future<void> _goToMe({bool quiet = false}) async {
    setState(() => _locating = true);
    final result = await widget.location.current();
    if (!mounted) return;
    setState(() => _locating = false);

    if (!result.ok) {
      if (!quiet) _showLocationProblem(result.outcome);
      return;
    }

    final me = LatLng(result.position!.latitude, result.position!.longitude);
    final inRegion = widget.atms.covers(me.latitude, me.longitude);

    setState(() {
      _me = me;
      _outsideCoverage = !inRegion;
    });

    // Only follow the user into the map if there is anything there to see.
    // Centring on an empty patch of another continent is indistinguishable
    // from a broken app.
    if (inRegion) {
      _map.move(me, 15);
    } else {
      _map.move(_defaultCentre, 12);
      if (!quiet && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.of(context).outsideCoverage)),
        );
      }
    }
  }

  void _showLocationProblem(LocationOutcome outcome) {
    final s = Strings.of(context);
    final message = switch (outcome) {
      LocationOutcome.serviceOff => s.locationOff,
      LocationOutcome.denied ||
      LocationOutcome.deniedForever =>
        s.locationDenied,
      _ => s.locationOff,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: outcome == LocationOutcome.deniedForever
            ? SnackBarAction(
                label: s.enableLocation,
                onPressed: LocationService.openSettings,
              )
            : null,
      ),
    );
  }

  Future<void> _openAtm(Atm atm) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AtmSheet(
        atm: atm,
        repository: widget.status,
        location: widget.location,
        myLocation: _me,
        onNavigate: widget.onNavigate,
      ),
    );
    // The user may have just reported, so bypass the staleness window.
    await _refreshStatuses(force: true);
  }

  Future<void> _openFilter() async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BankFilterSheet(
        banks: widget.atms.banksBySize(),
        selected: widget.selectedBanks,
      ),
    );
    if (picked == null || !mounted) return;

    // The shell owns the filter; it will hand it straight back to us.
    widget.onBanksChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final showPins = _zoom >= _minPinZoom;
    final navigating = widget.navigatingTo != null;

    // Roughly half the dataset has no recorded bank, and on a filtered map
    // those hollow pins bury the handful of real matches. Hidden by default,
    // with the count always on screen and one tap from bringing them back.
    // The machine being navigated to is never hidden.
    final pins = [
      for (final atm in _visible)
        if (widget.showUnlabelled ||
            atm.bankKnown ||
            atm.id == widget.navigatingTo?.id)
          atm,
    ];
    final hiddenCount = _visible.length - pins.length;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _defaultCentre,
              initialZoom: 12,
              minZoom: 6,
              maxZoom: 18,
              onMapReady: () => _recomputeVisible(_map.camera.visibleBounds),
              onPositionChanged: (camera, _) {
                _zoom = camera.zoom;
                _recomputeVisible(camera.visibleBounds);
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'iq.krd.kurdistanatm',
                maxNativeZoom: 19,
              ),
              // Route sits under the pins so it never hides a machine.
              if (_route != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route!.points,
                      strokeWidth: 8,
                      // Fully opaque on purpose. flutter_map stencils the
                      // casing out from under the core, so a translucent core
                      // composites against the map tiles instead of against
                      // its own casing - which is what made the old teal line
                      // bleed into the basemap.
                      color: kRouteInk,
                      borderStrokeWidth: 5,
                      borderColor: kRouteCasing,
                      strokeCap: StrokeCap.round,
                      strokeJoin: StrokeJoin.round,
                      // Dashed still means "no road route, this is a direct
                      // line" - widened to stay readable at the new stroke.
                      pattern: _route!.isApproximate
                          ? StrokePattern.dashed(segments: const [18, 12])
                          : const StrokePattern.solid(),
                    ),
                  ],
                ),
              if (_chevrons.isNotEmpty) MarkerLayer(markers: _chevrons),
              if (_me != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _me!,
                      radius: 10,
                      useRadiusInMeter: false,
                      color: Colors.blue.withValues(alpha: 0.9),
                      borderColor: Colors.white,
                      borderStrokeWidth: 3,
                    ),
                  ],
                ),
              if (showPins)
                MarkerLayer(
                  markers: [
                    for (final atm in pins)
                      if (atm.id != widget.navigatingTo?.id)
                        Marker(
                          point: LatLng(atm.lat, atm.lon),
                          width: 44,
                          height: 52,
                          alignment: Alignment.topCenter,
                          child: AtmPin(
                            atm: atm,
                            status:
                                _statuses[atm.id] ?? AtmStatus.unknownStatus,
                            onTap: () => _openAtm(atm),
                            dimmed: navigating,
                          ),
                        ),
                  ],
                ),
              // The destination is drawn outside the zoom gate: zooming out to
              // see the whole trip must not erase the thing you are walking to.
              if (navigating) ...[
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(
                          widget.navigatingTo!.lat, widget.navigatingTo!.lon),
                      radius: 26,
                      useRadiusInMeter: false,
                      color: kRouteInk.withValues(alpha: 0.15),
                      borderColor: kRouteInk.withValues(alpha: 0.45),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                          widget.navigatingTo!.lat, widget.navigatingTo!.lon),
                      width: 60,
                      height: 70,
                      alignment: Alignment.topCenter,
                      child: AtmPin(
                        atm: widget.navigatingTo!,
                        status: _statuses[widget.navigatingTo!.id] ??
                            AtmStatus.unknownStatus,
                        onTap: () => _openAtm(widget.navigatingTo!),
                        emphasis: true,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          // The filter bar would compete with the navigation banner, and
          // changing the bank filter mid-route makes no sense anyway.
          if (!navigating)
            _TopBar(
              selectedCount: widget.selectedBanks.length,
              onFilter: _openFilter,
              visibleCount: pins.length,
              hiddenCount: hiddenCount,
              showUnlabelled: widget.showUnlabelled,
              onToggleUnlabelled: () =>
                  widget.onShowUnlabelledChanged(!widget.showUnlabelled),
            ),
          if (_outsideCoverage && !navigating)
            Positioned(
              left: 0,
              right: 0,
              top: 86,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: _Pill(
                    icon: Icons.travel_explore_rounded,
                    label: s.outsideCoverage,
                  ),
                ),
              ),
            ),
          // Hiding unlabelled machines empties the map entirely in Halabja
          // and nearly so in Ranya, so an empty map explains itself instead of
          // reading as "there are no ATMs here".
          if (showPins && !navigating && pins.isEmpty && hiddenCount > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 104,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => widget.onShowUnlabelledChanged(true),
                    child: _Pill(
                      icon: Icons.question_mark_rounded,
                      label: s.onlyUnlabelledHere,
                    ),
                  ),
                ),
              ),
            )
          else if (!showPins && !navigating)
            Positioned(
              left: 0,
              right: 0,
              bottom: 104,
              child: Center(
                // The pill can wrap to two lines once it has a real sentence in
                // it, so the horizontal padding is what gives _Pill's Flexible
                // a bounded width to wrap inside.
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: _Pill(
                    icon: Icons.zoom_in,
                    label: s.zoomInToSeeAtms,
                  ),
                ),
              ),
            ),
          // Attribution stays on screen in BOTH states. ODbL requires credit
          // wherever the data is shown, and navigation - which also draws an
          // OSM-derived route - is the longest-lived screen in the app.
          if (navigating)
            Positioned(
              left: 8,
              right: 8,
              bottom: 0,
              child: NavigationBanner(
                target: widget.navigatingTo!,
                route: _route,
                remainingMetres: _remainingMetres,
                loading: _routeLoading,
                onStop: widget.onStopNavigating,
              ),
            ),
          Positioned(
            left: 8,
            right: 8,
            // Lifted clear of the navigation banner rather than replaced by it.
            bottom: navigating ? 150 : 4,
            child: _Attribution(routing: navigating && _route != null),
          ),
        ],
      ),
      floatingActionButton: navigating
          ? null
          : FloatingActionButton(
              onPressed: _locating ? null : _goToMe,
              child: _locating
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.my_location),
            ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.selectedCount,
    required this.onFilter,
    required this.visibleCount,
    required this.hiddenCount,
    required this.showUnlabelled,
    required this.onToggleUnlabelled,
  });

  final int selectedCount;
  final VoidCallback onFilter;
  final int visibleCount;
  final int hiddenCount;
  final bool showUnlabelled;
  final VoidCallback onToggleUnlabelled;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(28),
                color: theme.colorScheme.surface,
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: onFilter,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            selectedCount == 0
                                ? s.allBanks
                                : '${s.filterByBank} ($selectedCount)',
                            style: theme.textTheme.bodyLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '$visibleCount',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.tune, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // A sibling of the filter button, not nested inside it, so a
            // near-miss does not open the filter sheet.
            if (hiddenCount > 0 || showUnlabelled) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: s.hiddenUnlabelled(hiddenCount),
                child: Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(28),
                  color: showUnlabelled
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surface,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: onToggleUnlabelled,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            showUnlabelled
                                ? Icons.visibility
                                : Icons.question_mark_rounded,
                            size: 18,
                          ),
                          if (!showUnlabelled) ...[
                            const SizedBox(width: 6),
                            Text('$hiddenCount',
                                style: theme.textTheme.labelLarge),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(20),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelLarge,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// OpenStreetMap's licence requires visible credit wherever its data is shown.
class _Attribution extends StatelessWidget {
  const _Attribution({this.routing = false});

  /// Adds the routing credit while a route is displayed.
  final bool routing;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);

    return Align(
      alignment: AlignmentDirectional.bottomStart,
      child: GestureDetector(
        // The licence asks for a link to the copyright page, not just a name.
        onTap: () => launchUrl(
          Uri.parse('https://www.openstreetmap.org/copyright'),
          mode: LaunchMode.externalApplication,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(4),
          ),
          // U+00A9 is bidi class ON, so inside an RTL paragraph the reordering
          // rules would render this as "OpenStreetMap ©".
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              routing
                  ? '© OpenStreetMap contributors · ${s.routingCredit}'
                  : '© OpenStreetMap contributors',
              style: theme.textTheme.labelSmall,
            ),
          ),
        ),
      ),
    );
  }
}
