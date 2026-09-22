import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import '../models/atm.dart';

enum NavApp { google, waze, apple }

/// Hands navigation off to whatever maps app the user already has.
///
/// The app deliberately does not draw routes itself: turn-by-turn needs a paid
/// routing API and would be worse than what people already use. Deep-linking
/// out costs nothing and lands them in a familiar interface.
class Directions {
  static Future<bool> open(Atm atm, {NavApp? prefer}) async {
    final app = prefer ?? _platformDefault();
    for (final candidate in [app, ...NavApp.values.where((a) => a != app)]) {
      if (await _launch(candidate, atm)) return true;
    }
    return false;
  }

  static NavApp _platformDefault() {
    if (!kIsWeb && Platform.isIOS) return NavApp.apple;
    return NavApp.google;
  }

  static Future<bool> _launch(NavApp app, Atm atm) async {
    final uri = switch (app) {
      NavApp.google => Uri.parse(
          'https://www.google.com/maps/dir/?api=1'
          '&destination=${atm.lat},${atm.lon}&travelmode=driving'),
      NavApp.waze =>
        Uri.parse('https://waze.com/ul?ll=${atm.lat},${atm.lon}&navigate=yes'),
      NavApp.apple =>
        Uri.parse('https://maps.apple.com/?daddr=${atm.lat},${atm.lon}&dirflg=d'),
    };

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Plain coordinates, for the "copy location" action - handy when someone
  /// wants to send an ATM to a friend over WhatsApp.
  static String shareText(Atm atm, String label) =>
      '$label\nhttps://www.google.com/maps/search/?api=1'
      '&query=${atm.lat},${atm.lon}';
}
