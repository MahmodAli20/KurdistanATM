import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/atm_status.dart';
import 'typography.dart';

/// Visual language for the app.
///
/// One decision drives the palette: status colour has to survive being shrunk
/// to a 14px map pin in bright sunlight, which is how most people will see it
/// while standing on a street in Erbil in July.
class AppTheme {
  static const seed = Color(0xFF00695C);

  /// The theme depends on the active language because the text theme does:
  /// Arabic script needs different leading and zero letter spacing. See
  /// [AppTypography].
  static ThemeData light(AppLang lang) => _build(Brightness.light, lang);
  static ThemeData dark(AppLang lang) => _build(Brightness.dark, lang);

  static ThemeData _build(Brightness brightness, AppLang lang) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      fontFamily: AppTypography.family,
      // Built from *this* scheme, not a shared one: AppTypography bakes
      // scheme.onSurface into every style, so handing the light scheme to the
      // dark theme would paint dark text on a dark ground.
      textTheme: AppTypography.textTheme(scheme, lang),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: const StadiumBorder(),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
          // fontFamily is spelled out because ButtonStyle REPLACES the
          // inherited labelLarge rather than merging with it. Without it the
          // primary call-to-action in the app would keep the device's default
          // Arabic face while everything around it is Vazirmatn.
          textStyle: const TextStyle(
            fontFamily: AppTypography.family,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

/// The route drawn on the map.
///
/// Deliberately not the app's teal: the route sits on the OSM raster, which is
/// always a light tile, and teal-on-teal against the primary colour used
/// elsewhere on the map chrome is hard to follow. Blue reads as "route" and is
/// far from every status colour below.
const kRouteInk = Color(0xFF1A73E8);
const kRouteCasing = Color(0xFF0B2545);

/// Icon for a landmark's OSM tag, so "where is it" carries a glyph as well as
/// a name.
IconData landmarkIcon(String kind) => switch (kind) {
      'shop=mall' || 'building=mall' => Icons.local_mall_rounded,
      'shop=department_store' => Icons.storefront_rounded,
      'shop=supermarket' => Icons.shopping_cart_rounded,
      'amenity=marketplace' => Icons.storefront_rounded,
      'amenity=hospital' => Icons.local_hospital_rounded,
      'amenity=university' || 'amenity=college' => Icons.school_rounded,
      'amenity=bus_station' => Icons.directions_bus_rounded,
      'leisure=park' => Icons.park_rounded,
      'tourism=hotel' => Icons.hotel_rounded,
      'tourism=museum' || 'tourism=attraction' => Icons.attractions_rounded,
      _ => Icons.place_rounded,
    };

/// Everything the UI needs to render one [CashStatus] consistently.
///
/// Status colour does two incompatible jobs, so it is split into three.
///
/// [pinColour] is a solid fill on the map, which is an always-light raster
/// regardless of the app theme, so it never varies by brightness.
///
/// [ink] is the same status used as *text or an icon* on a tinted surface, and
/// it must vary by brightness. A single fixed colour cannot do both: the old
/// shared value measured 2.83:1 as text in light mode, below even the 3:1 floor
/// for non-text content, let alone the 4.5:1 that body text needs.
///
/// [wash] is the tinted background those sit on.
///
/// Colour is never the only channel. Every status also carries a distinct
/// [icon] and a translated [label], because the green/amber/red trio is the
/// worst case for the most common form of colour blindness.
extension CashStatusVisuals on CashStatus {
  /// Solid fill for map pins. Tuned for a light map tile in bright sunlight.
  Color get pinColour => switch (this) {
        CashStatus.hasCash => const Color(0xFF0E7C3A),
        CashStatus.noCash => const Color(0xFFD97706),
        CashStatus.outOfService => const Color(0xFFC42B22),
        CashStatus.longQueue => const Color(0xFF6D28D9),
        CashStatus.unknown => const Color(0xFF4A5A70),
      };

  /// Status as text or an icon, darkened for light themes and lightened for
  /// dark ones so both clear WCAG AA against [wash].
  Color ink(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (this) {
      CashStatus.hasCash =>
        dark ? const Color(0xFF6EE7A0) : const Color(0xFF10632F),
      CashStatus.noCash =>
        dark ? const Color(0xFFFFC978) : const Color(0xFF8A5100),
      CashStatus.outOfService =>
        dark ? const Color(0xFFFFA8A0) : const Color(0xFF96201A),
      CashStatus.longQueue =>
        dark ? const Color(0xFFCDB4FF) : const Color(0xFF5B21B6),
      CashStatus.unknown =>
        dark ? const Color(0xFFBAC4D2) : const Color(0xFF3A4655),
    };
  }

  /// Tinted ground for [ink]. Slightly stronger in dark mode, where a 12% tint
  /// disappears into the surface.
  Color wash(Brightness brightness) => pinColour
      .withValues(alpha: brightness == Brightness.dark ? 0.16 : 0.12);

  IconData get icon => switch (this) {
        CashStatus.hasCash => Icons.payments_rounded,
        CashStatus.noCash => Icons.money_off_rounded,
        CashStatus.outOfService => Icons.build_rounded,
        CashStatus.longQueue => Icons.groups_rounded,
        CashStatus.unknown => Icons.help_outline_rounded,
      };

  String label(Strings s) => switch (this) {
        CashStatus.hasCash => s.hasCash,
        CashStatus.noCash => s.noCash,
        CashStatus.outOfService => s.outOfService,
        CashStatus.longQueue => s.longQueue,
        CashStatus.unknown => s.noReports,
      };
}

/// Human phrasing for how old a report is.
String relativeTime(Duration age, Strings s) {
  if (age.inMinutes < 2) return s.justNow;
  if (age.inMinutes < 60) return s.minutesAgo(age.inMinutes);
  return s.hoursAgo(age.inHours);
}

/// Distance in the unit that reads best at that range.
String formatDistance(double metres, Strings s) {
  if (metres < 1000) return s.metres((metres / 10).round() * 10);
  return s.kilometres((metres / 1000).toStringAsFixed(1));
}
