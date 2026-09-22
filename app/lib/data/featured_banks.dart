/// Banks given their own card on the home screen.
///
/// These are the ones people in the region are most likely to hold a salary
/// card with, named by the project owner. Ordering on screen is by how many
/// machines are actually in the dataset, not by this list - a bank with one
/// recorded machine should not sit above one with ninety.
///
/// Both Islamic banks appear because the dataset distinguishes them and
/// "Islamic Bank" on its own is ambiguous here.
const featuredBankIds = <String>[
  'cihan',
  'nbi',
  'rt',
  'tbi',
  'iib',
  'kiib',
];
