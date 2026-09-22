# Kurdistan ATM Finder

A free, no-signup map of ATMs across the Kurdistan Region, built because salary
domiciliation moved everyone onto bank cards and finding a machine that
actually has cash became a real problem.

The app answers two questions:

1. **Where is the nearest ATM?** — from a dataset that ships inside the app, so
   it works with no signal.
2. **Does it have cash right now?** — from crowd reports, because no bank in
   Iraq exposes ATM telemetry and no amount of engineering can change that.

## Why there are no accounts

There is nothing to log in to. Reports are gated by physical presence instead of
identity: **you can only report on a machine when your GPS puts you within 100 m
of it.** That one rule does the work an account system would have done — it
makes spam expensive, keeps the data honest, and removes any reason to collect
personal information.

## Repository layout

```
data/          Python pipeline that builds the ATM dataset
  banks.py       name normalisation (English / Arabic / Sorani)
  sources.py     OpenStreetMap (Overpass) + National Bank of Iraq fetchers
  build.py       merge, dedupe, write out/atms.json
  out/atms.json  the generated dataset

app/           Flutter application
  lib/models/      Atm, AtmReport, AtmStatus (confidence + decay)
  lib/data/        repositories - bundled ATM list, crowd status
  lib/services/    location, directions hand-off
  lib/ui/          map screen, detail sheet, bank filter
  lib/l10n/        Sorani / Arabic / English strings
  assets/atms.json copy of the generated dataset
```

## Rebuilding the dataset

```bash
cd data
python build.py            # uses cached HTTP responses where possible
python build.py --fresh    # re-fetch everything
cp out/atms.json ../app/assets/atms.json
```

Current coverage: **542 locations** — 530 cash machines and 12 card agents.

| City | Machines |
|---|---|
| Erbil | 215 |
| Sulaymaniyah | 139 |
| Kirkuk | 60 |
| Duhok | 56 |
| Soran | 24 |
| Zakho | 23 |
| Ranya | 12 |
| Halabja | 1 |

**Known gap: only ~46% have a bank identified.** Of the rest, 116 are unnamed in
OpenStreetMap and 174 are labelled with a neighbourhood name rather than a
brand. The pipeline deliberately refuses to guess a brand from a place name — a
wrong bank label is worse than no label when someone drives across town. Closing
this gap means scraping more bank sites (Cihan and RT are the biggest networks)
and letting users confirm in the app.

Halabja's single machine is almost certainly a mapping gap, not reality.

## Running the app

```bash
cd app
flutter pub get
flutter run            # or: flutter run -d chrome
flutter test
```

## Where each machine is

A bank name is not a location: "RT Bank, 7.3 km" says nothing about where you
are going. Two independent build-time passes in `data/landmarks.py` attach a
human cue to each machine, both resolved offline so the app never calls a
geocoder at runtime.

| Pass | What it answers | Radius | Coverage |
|---|---|---|---|
| `landmark` | what it is next to | ≤ 300 m | 447/542 (82%) |
| `area` | which part of town | 400–2000 m by place type | 472/542 (87%) |
| combined | — | — | **514/542 (94%)** |

They are **independent, not a fallback chain**. The motivating example proves
why: an NBI machine in Sulaymaniyah sits 260 m from a supermarket and 92 m from
the centre of Awbara. A fallback would have labelled it "Darya shop"; computing
both gives *near Darya shop* **and** *in Awbara area*.

Three things this deliberately gets right:

- **Category is weighted in metres, not sorted before distance.** Ranking
  hospitals above supermarkets outright picked a health centre 227 m away over
  a market 50 m away. The penalty is now expressed in metres so a genuinely
  close landmark wins.
- **Petrol stations and clinics are excluded.** There are thousands, and "near a
  petrol station" is not a location in a Kurdish city.
- **Areas never claim precision they do not have.** 472 machines share 165
  distinct labels, some covering twenty machines, so the app says "in X area",
  never "at X", and shows no distance for it.

Honest limits: 28 machines get no cue at all, and only about a fifth of
landmarks carry a Sorani name in OSM, so many render in English or Arabic even
for a Sorani reader. Both improve as OpenStreetMap does.

## Typography

The app bundles **Vazirmatn** (SIL OFL 1.1), which covers Sorani Kurdish, Arabic
and Latin in one family so the UI keeps its rhythm when the language changes.

**K24 was requested and rejected.** It is downloadable free but licensed for
personal use only; commercial use needs a paid licence, and a published app
counts as commercial even when it is free to users. If a commercial K24 licence
is ever obtained, swapping it in means replacing the files in
`app/assets/fonts/` and the family name in `app/lib/ui/typography.dart`.

Candidates were chosen by checking actual glyph coverage, not reputation:

| Font | Kurdish letters | Notes |
|---|---|---|
| Vazirmatn | 11/11 | chosen — 478 KB across four weights |
| IBM Plex Sans Arabic | 11/11 | viable alternative, colder feel |
| Noto Sans Arabic | 11/11 | safest but 824 KB and visually plain |
| Cairo | 6/11 | **missing ڕ ڵ ۆ ێ ە** |
| Almarai | 6/11 | **missing ڕ ڵ ۆ ێ ە** |
| Tajawal | 2/11 | unusable for Kurdish |
| Readex Pro | 1/11 | unusable for Kurdish |

Cairo and Almarai are widely recommended "Arabic" fonts that would have silently
broken Kurdish — they lack exactly the five letters Sorani needs most.

Two things in `app/lib/ui/typography.dart` matter more than the family choice:

- **Letter spacing is never positive.** Material's default text theme tracks
  several styles, which on connected Arabic script prises joined letterforms
  apart so words stop reading as words.
- **Line height is 1.55 in RTL versus 1.35 in Latin.** Arabic carries marks well
  outside the band Latin metrics assume, so default leading makes the dots under
  ڕ and ێ collide with the line below.

## Building an APK

```bash
cd app
flutter build apk --release
```

The output lands in `app/build/app/outputs/flutter-apk/app-release.apk`.

It is currently signed with **debug keys** — Flutter's generated
`android/app/build.gradle.kts` does this so `--release` works before signing is
set up. It installs on a real device (past a Play Protect warning) but cannot be
published. A real keystore is needed before release.

## Backend

Firebase project `atm-finder-4406e`, Firestore in `europe-west3` (Frankfurt),
anonymous authentication enabled. There is no login screen — anonymous sign-in
just gives each install a stable uid so the security rules have a writer to hold
to account.

Two collections:

| Path | Purpose | Client access |
|---|---|---|
| `status/{city}` | Aggregated recent reports for every machine in a city | read by anyone, written in a transaction |
| `reports/{id}` | Immutable audit log | create only — never read, updated or deleted |

Deploy rule changes with:

```bash
firebase deploy --only firestore:rules --project=atm-finder-4406e
```

`scripts/rules_test.mjs` exercises the deployed rules as a real anonymous
client — it checks that the app's own write path works and that fourteen abuse
paths are refused. Run it after any rules change:

```bash
cd scripts && npm install && node rules_test.mjs
```

## Cost

The project runs on the Firebase **Spark** plan — no credit card, no billing
account. Four decisions keep it there:

- **The ATM list ships in the app**, so no hosting bandwidth is spent on it.
- **Live status is one document per city**, not one per ATM. The naive per-ATM
  design would burn Firestore's 50k daily reads at around 2,000 users; the
  aggregate design uses roughly 6,000.
- **Status is fetched with `get()`, never `snapshots()`.** A realtime listener
  on a shared document bills every connected client a read for every write
  anyone makes — that is millions of reads at modest traffic. Status decays
  over hours, so a two-minute staleness window costs nothing.
- **Navigation is handed off** to Google Maps / Waze / Apple Maps rather than
  using a paid routing API.

**There are no Cloud Functions, deliberately.** Since 3 February 2026 Cloud
Functions requires the Blaze plan at any volume, so the rollup job that would
normally aggregate reports server-side is not available. Clients fold their own
report into the city document inside a transaction instead. The trade-off and
its mitigations are documented at the top of
`app/lib/data/firestore_status_repository.dart` and in `firestore.rules`.

**Map tiles** currently come from OpenStreetMap's public servers, which is fine
for development but not for a released app — see below.

## Before release

- [ ] **Enable App Check.** The 100 m proximity gate lives in the app, and
      Firestore rules cannot verify where a caller is standing — so someone
      calling the API directly could submit reports from anywhere. App Check is
      free and blocks callers that are not the genuine app. This is the single
      most important item on this list.
- [ ] Move map tiles off OSM's public servers. Their
      [tile usage policy](https://operations.osmfoundation.org/policies/tiles/)
      does not permit app traffic. MapTiler and Stadia Maps both have free tiers
      that cover a project this size.
- [ ] Have a native Sorani speaker review `app/lib/l10n/strings.dart` — the
      translations there are a starting point, not a verified one.
- [ ] Scrape Cihan and RT Bank to close the bank-identification gap.
- [ ] Set up a real signing keystore; the release APK currently uses debug keys.
- [ ] `flutter build apk --split-per-abi` — the universal APK is ~51 MB, which is
      a lot on the cheap phones much of the audience uses. Per-ABI builds are
      roughly 20 MB.

Done: Firebase wired up (Firestore + anonymous auth + deployed rules).
Done: Vazirmatn bundled with an Arabic-script text theme (see Typography).

## Data sources and licence

ATM locations come from [OpenStreetMap](https://www.openstreetmap.org/)
contributors, licensed under
[ODbL](https://opendatacommons.org/licenses/odbl/), and from banks' own public
branch listings. The attribution shown in the app is required by that licence —
please keep it.
