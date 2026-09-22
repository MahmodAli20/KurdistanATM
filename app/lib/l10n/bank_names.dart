import '../models/atm.dart';
import 'strings.dart';

/// Picking the right bank name for the active language.
///
/// Lives here rather than on [Atm] so the model stays free of any language
/// concept, and rather than in a hand-written Dart table so there is one source
/// of truth: `data/banks.py` generates all three name lists into `atms.json`.
///
/// Arabic falls back to English when a name is missing, which is what the whole
/// app did for every language before `bank_names_ar` existed.
extension AtmBankNames on Atm {
  List<String> namesFor(AppLang lang) => switch (lang) {
        AppLang.ckb => bankNamesCkb,
        AppLang.ar => bankNamesAr.isNotEmpty ? bankNamesAr : bankNamesEn,
        AppLang.en => bankNamesEn,
      };

  /// Joined label, e.g. "National Bank of Iraq (NBI) · RT Bank".
  String bankLabel(Strings s, {bool short = false}) {
    final names = namesFor(s.lang);
    if (names.isEmpty) return s.unknownBank;
    return names.map((n) => short ? shortBankName(n) : n).join(' · ');
  }
}

/// "National Bank of Iraq (NBI)" -> "NBI".
///
/// For rows and chips that clip at one line. The abbreviation is what is
/// written on the machine, so it is the better thing to keep when there is not
/// room for both. Banks without one keep their full name - inventing initials
/// nobody uses would be worse than truncating.
String shortBankName(String full) =>
    RegExp(r'\(([A-Z]{2,6})\)\s*$').firstMatch(full)?.group(1) ?? full;

/// Drops the abbreviation suffix, for the secondary line under a primary name
/// that already shows it - otherwise a tile reads "(NBI)" twice.
String withoutAbbreviation(String full) =>
    full.replaceFirst(RegExp(r'\s*\([A-Z]{2,6}\)\s*$'), '');
