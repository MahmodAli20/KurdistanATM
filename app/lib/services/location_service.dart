import 'package:geolocator/geolocator.dart';

enum LocationOutcome { ok, denied, deniedForever, serviceOff, error }

class LocationResult {
  const LocationResult(this.outcome, [this.position]);

  final LocationOutcome outcome;
  final Position? position;

  bool get ok => outcome == LocationOutcome.ok && position != null;
}

/// Thin wrapper over geolocator.
///
/// The app asks for location for two reasons only: centring the map, and
/// proving you are standing at a machine before you may report on it. Nothing
/// is stored and nothing is transmitted beyond the proximity check.
class LocationService {
  Position? _last;
  Future<LocationResult>? _inFlight;

  /// Last known fix, useful for an instant first paint before the GPS settles.
  Position? get lastKnown => _last;

  /// Several tabs ask for a fix the moment the app opens. Without this, each
  /// one starts its own GPS acquisition and they compete for the same radio;
  /// sharing the in-flight future means one request serves all callers.
  Future<LocationResult> current({bool highAccuracy = true}) {
    final pending = _inFlight;
    if (pending != null) return pending;

    final request = _acquire(highAccuracy: highAccuracy);
    _inFlight = request;
    return request.whenComplete(() => _inFlight = null);
  }

  Future<LocationResult> _acquire({required bool highAccuracy}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(LocationOutcome.serviceOff);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult(LocationOutcome.deniedForever);
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult(LocationOutcome.denied);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy:
              highAccuracy ? LocationAccuracy.best : LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 15),
        ),
      );
      _last = position;
      return LocationResult(LocationOutcome.ok, position);
    } catch (_) {
      // A timeout on a weak signal is normal, not exceptional; fall back to the
      // previous fix rather than showing an error.
      if (_last != null) return LocationResult(LocationOutcome.ok, _last);
      return const LocationResult(LocationOutcome.error);
    }
  }

  Stream<Position> watch() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        ),
      ).map((position) {
        _last = position;
        return position;
      });

  static Future<void> openSettings() => Geolocator.openAppSettings();
}
