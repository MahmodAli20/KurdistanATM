import 'package:flutter/material.dart';

import '../l10n/strings.dart';

/// Typography for an app whose primary script is Arabic, not Latin.
///
/// Three things here are not the Flutter defaults, and each is deliberate:
///
/// **Line height.** Arabic script carries ascenders, descenders and diacritics
/// well outside the x-height band that Latin metrics assume. Flutter's default
/// leading crowds it badly - Sorani looks cramped and the dots under ڕ and ێ
/// collide with the line below. Everything here runs looser than a Latin scale
/// would.
///
/// **No letter spacing.** Material's default text theme applies positive
/// letterSpacing to several styles. On connected Arabic script that is not a
/// stylistic choice, it is a rendering bug: it prises joined letterforms apart
/// and words stop reading as words. Every style below pins letterSpacing to
/// zero or negative, never positive.
///
/// **Slightly larger base size.** The audience skews older and often reads in
/// bright sunlight on a cheap phone. The body size is a step up from Material's
/// default.
class AppTypography {
  const AppTypography._();

  static const family = 'Vazirmatn';

  /// Arabic script needs materially more leading than Latin at the same size.
  static const _arabicHeight = 1.55;
  static const _latinHeight = 1.35;

  /// Tight leading for large display text, where generous leading looks loose.
  static const _arabicDisplayHeight = 1.35;
  static const _latinDisplayHeight = 1.18;

  static TextTheme textTheme(ColorScheme scheme, AppLang lang) {
    final rtl = lang != AppLang.en;
    final body = rtl ? _arabicHeight : _latinHeight;
    final display = rtl ? _arabicDisplayHeight : _latinDisplayHeight;
    final onSurface = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;

    TextStyle s(
      double size,
      FontWeight weight,
      double height, {
      Color? color,
      double spacing = 0,
    }) =>
        TextStyle(
          fontFamily: family,
          fontSize: size,
          fontWeight: weight,
          height: height,
          // Never positive: see the class doc.
          letterSpacing: rtl ? 0 : spacing,
          color: color ?? onSurface,
        );

    return TextTheme(
      displayLarge: s(40, FontWeight.w800, display, spacing: -0.5),
      displayMedium: s(34, FontWeight.w800, display, spacing: -0.4),
      displaySmall: s(29, FontWeight.w700, display, spacing: -0.3),

      headlineLarge: s(27, FontWeight.w800, display, spacing: -0.3),
      headlineMedium: s(24, FontWeight.w800, display, spacing: -0.2),
      headlineSmall: s(21, FontWeight.w700, display, spacing: -0.2),

      titleLarge: s(19, FontWeight.w700, body),
      titleMedium: s(17, FontWeight.w600, body),
      titleSmall: s(15.5, FontWeight.w600, body),

      bodyLarge: s(16, FontWeight.w400, body),
      bodyMedium: s(14.5, FontWeight.w400, body),
      bodySmall: s(13, FontWeight.w400, body, color: muted),

      labelLarge: s(14.5, FontWeight.w600, body),
      labelMedium: s(13, FontWeight.w600, body),
      labelSmall: s(11.5, FontWeight.w600, body, color: muted),
    );
  }

  /// Numbers that should never be re-ordered by the bidi algorithm.
  ///
  /// A distance like "40 m" sitting inside a right-to-left sentence is a
  /// left-to-right run, and mixing the two is where Arabic UIs most often
  /// produce visibly wrong output - "1.2 km" rendering as "km 1.2", or a minus
  /// sign jumping to the wrong end. Wrapping figures in this style plus an
  /// explicit Directionality keeps them intact.
  static TextStyle numeric(TextStyle base) => base.copyWith(
        fontFamily: family,
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: 0,
      );
}

/// Renders a number or measurement left-to-right regardless of the surrounding
/// text direction.
///
/// Use for distances, counts, times and currency figures inside Sorani or
/// Arabic layouts.
class Figure extends StatelessWidget {
  const Figure(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        text,
        style: AppTypography.numeric(base),
        textAlign: textAlign,
      ),
    );
  }
}
