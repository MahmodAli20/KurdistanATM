import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// How a route was produced, so the UI can be honest about what it is showing.
enum RouteSource {
  /// Real road geometry from a routing server.
  roads,

  /// No routing available - a direct line from you to the machine. Still tells
  /// you which way to walk and how far, which for a 300 m trip is most of the
  /// value.
  straightLine,
}

class AtmRoute {
  const AtmRoute({
    required this.points,
    required this.metres,
    required this.seconds,
    required this.source,
  });

  final List<LatLng> points;
  final double metres;
  final double seconds;
  final RouteSource source;

  bool get isApproximate => source == RouteSource.straightLine;
}

/// Turns "where am I" and "where is the machine" into a line to draw on our own
/// map, instead of handing the user off to Google Maps.
///
/// ## Why this is built the way it is
///
/// Routing is the one part of this app that cannot be done entirely on-device:
/// road geometry for the whole region is far too large to bundle. Every free
/// routing service therefore comes with limits, and the app is designed around
/// the strictest reading of them:
///
///  * **One request per navigation, not per position update.** The route is
///    fetched once when the user starts navigating and then followed locally
///    against their GPS. OSRM's usage policy explicitly calls an app that
///    requests every few seconds "very heavy usage" and forbids it; this
///    pattern is one request per trip.
///  * **Identifying User-Agent**, as the policy requires.
///  * **Never fails closed.** If the service is slow, rate-limited, blocked or
///    the user is offline, [route] returns a straight line rather than an
///    error. The user always gets a direction and a distance.
///
/// At real scale the honest options are to self-host OSRM or use a keyed
/// provider such as OpenRouteService (2,500 requests/day on its free tier).
/// Swapping either in means changing [_endpoint] and [_parse] only.
class RoutingService {
  RoutingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// FOSSGIS-hosted OSRM, the instance the OpenStreetMap community runs.
  static const _endpoint = 'https://routing.openstreetmap.de/routed-foot/route/v1/foot';

  static const _userAgent =
      'KurdistanATM/1.0 (+https://mahmodali20.github.io/KurdistanATM/)';

  /// Attribution the map must show whenever a road route is displayed.
  static const attribution = 'Routing: OSRM · OpenStreetMap contributors';

  static const _timeout = Duration(seconds: 8);

  /// Routes long enough that a road route matters. Below this the straight
  /// line and the walked path are nearly the same, so there is no reason to
  /// spend a request.
  static const _minMetresForRoads = 120;

  Future<AtmRoute> route(LatLng from, LatLng to) async {
    final direct = _straightLine(from, to);
    if (direct.metres < _minMetresForRoads) return direct;

    try {
      // OSRM takes lon,lat - the reverse of almost everything else.
      final url = Uri.parse(
        '$_endpoint/${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson&alternatives=false&steps=false',
      );

      final response = await _client
          .get(url, headers: {'User-Agent': _userAgent})
          .timeout(_timeout);

      if (response.statusCode != 200) return direct;

      final parsed = _parse(response.body);
      return parsed ?? direct;
    } catch (error) {
      // Offline, rate-limited, DNS blocked, malformed reply - all the same
      // answer: show the user a line and a distance anyway.
      debugPrint('Routing unavailable, falling back to straight line: $error');
      return direct;
    }
  }

  AtmRoute? _parse(String body) {
    final decoded = json.decode(body) as Map<String, dynamic>;
    if (decoded['code'] != 'Ok') return null;

    final routes = decoded['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;

    final first = routes.first as Map<String, dynamic>;
    final coordinates =
        (first['geometry'] as Map<String, dynamic>)['coordinates'] as List;
    if (coordinates.isEmpty) return null;

    return AtmRoute(
      points: [
        for (final pair in coordinates)
          LatLng(
            ((pair as List)[1] as num).toDouble(),
            (pair[0] as num).toDouble(),
          ),
      ],
      metres: (first['distance'] as num).toDouble(),
      seconds: (first['duration'] as num).toDouble(),
      source: RouteSource.roads,
    );
  }

  AtmRoute _straightLine(LatLng from, LatLng to) {
    final metres = _haversine(from, to);
    return AtmRoute(
      points: [from, to],
      metres: metres,
      // Roughly walking pace, 1.35 m/s.
      seconds: metres / 1.35,
      source: RouteSource.straightLine,
    );
  }

  static double _haversine(LatLng a, LatLng b) {
    const radius = 6371000.0;
    final dLat = _radians(b.latitude - a.latitude);
    final dLon = _radians(b.longitude - a.longitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(a.latitude)) *
            math.cos(_radians(b.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * radius * math.asin(math.sqrt(h));
  }

  static double _radians(double degrees) => degrees * math.pi / 180.0;

  /// Compass bearing from [from] to [to], in degrees clockwise from north.
  /// Used to point the arrow on the navigation banner.
  static double bearing(LatLng from, LatLng to) {
    final dLon = _radians(to.longitude - from.longitude);
    final y = math.sin(dLon) * math.cos(_radians(to.latitude));
    final x = math.cos(_radians(from.latitude)) *
            math.sin(_radians(to.latitude)) -
        math.sin(_radians(from.latitude)) *
            math.cos(_radians(to.latitude)) *
            math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  void dispose() => _client.close();
}
