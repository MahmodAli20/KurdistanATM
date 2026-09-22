/// Display names for the city ids the pipeline assigns.
///
/// The ids come from `data/build.py`, which labels every machine by proximity
/// to a known centre. Anything that fell outside all of them is dropped during
/// the build, so every id here is one the dataset actually uses.
const cityNames = <String, ({String en, String ckb, String ar})>{
  'erbil': (en: 'Erbil', ckb: 'هەولێر', ar: 'أربيل'),
  'sulaymaniyah': (en: 'Sulaymaniyah', ckb: 'سلێمانی', ar: 'السليمانية'),
  'duhok': (en: 'Duhok', ckb: 'دهۆک', ar: 'دهوك'),
  'kirkuk': (en: 'Kirkuk', ckb: 'کەرکووک', ar: 'كركوك'),
  'soran': (en: 'Soran', ckb: 'سۆران', ar: 'سوران'),
  'zakho': (en: 'Zakho', ckb: 'زاخۆ', ar: 'زاخو'),
  'ranya': (en: 'Ranya', ckb: 'ڕانیە', ar: 'رانية'),
  'halabja': (en: 'Halabja', ckb: 'هەڵەبجە', ar: 'حلبجة'),
};

({String en, String ckb, String ar}) cityDisplay(String id) =>
    cityNames[id] ?? (en: id, ckb: id, ar: id);
