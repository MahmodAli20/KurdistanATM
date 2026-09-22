# Data safety answers — Kurdistan ATM

Google now cross-references these answers against what your APK actually does.
An inaccurate declaration gets the app removed or the account suspended, so
every answer below is derived from the real code, with the file noted.

---

## Section 1 — Data collection and security

**Does your app collect or share any of the required user data types?**
→ **Yes**

(Saying "no" here would be false: the app writes reports to Firestore and sends
coordinates to a routing server. Both are outbound data flows.)

**Is all of the user data collected by your app encrypted in transit?**
→ **Yes**

Firestore and Firebase Auth use TLS. The routing and tile requests are HTTPS
(`routing_service.dart`, `map_screen.dart`). There is no plaintext traffic.

**Do you provide a way for users to request that their data be deleted?**
→ **Yes**

URL: `https://mahmodali20.github.io/KurdistanATM/delete-data.html`
The app shows the user their anonymous ID in the More tab so they can quote it.

---

## Section 2 — Data types

### Location → Approximate location
→ **NOT collected**

The app never requests or uses coarse-only location for anything.

### Location → Precise location
→ **Collected: YES**
→ **Shared: YES**
→ **Processed ephemerally: YES**
→ **Required or optional: Optional** — the app works without it; only the
   report feature and "nearest machine" need it
→ **Purpose:** *App functionality*

Explanation if asked: precise location is used on-device to show nearby
machines and to verify the user is within 100 m of a machine before they may
report on it (`atm_sheet.dart`, `kReportRadiusMetres`). It is **never stored**
by us. It is transmitted only at the moment the user taps "Start route", when
the origin and destination go to OpenStreetMap's routing server so a route can
be drawn (`routing_service.dart`). That transmission is why "Shared" is Yes.

⚠️ Do **not** answer "not collected" here. `ACCESS_FINE_LOCATION` is in the
manifest and there is an outbound request carrying coordinates. This exact
mismatch is the most common cause of suspension.

### App activity → Other user-generated content
→ **Collected: YES**
→ **Shared: NO**
→ **Processed ephemerally: NO** (reports persist in the audit log)
→ **Required or optional: Optional**
→ **Purpose:** *App functionality*

This is the cash-status report: which machine, which city, which of four
statuses, and the server timestamp.

"Shared: No" is correct — the reports are visible to other users of this app,
but they are not transferred to a *third party*, which is what Play's
"shared" means.

### Device or other IDs
→ **Collected: YES**
→ **Shared: NO**
→ **Processed ephemerally: NO**
→ **Required or optional: Required**
→ **Purpose:** *App functionality*, *Fraud prevention, security and compliance*

This is the Firebase anonymous auth UID. It is random per installation, not
tied to any identity, and exists so the security rules can rate-limit writers.

### Everything else
→ **NOT collected.** Specifically not: name, email address, phone number,
   address, any financial info, health, messages, photos, videos, audio,
   contacts, calendar, search history, installed apps, or crash/diagnostic
   analytics. There is no analytics SDK and no advertising ID in the build.

---

## Section 3 — If asked about account creation

There are no user accounts. Firebase anonymous authentication is not an
account: the user never signs in, provides no credentials, and cannot recover
or transfer it.

---

## Related: App content → Financial features

→ **"My app doesn't provide any financial features"**

The app shows where cash machines are. It does not move money, hold balances,
process payments, lend, or connect to a bank account.

## Related: App content → Government apps

→ **No**. This is an independent community project with no government
   affiliation.

## Related: App content → Health

→ **No**.

---

## Sanity check before you submit

The permissions actually in the built APK, confirmed with `aapt2 dump badging`:

```
android.permission.INTERNET
android.permission.ACCESS_FINE_LOCATION
android.permission.ACCESS_COARSE_LOCATION
android.permission.ACCESS_NETWORK_STATE          (pulled in by Firebase)
com.google.android.providers.gsf.permission.READ_GSERVICES   (Firebase)
```

`ACCESS_COARSE_LOCATION` is present because `ACCESS_FINE_LOCATION` requires it
on modern Android, not because the app uses coarse location separately. If a
reviewer questions why precise location is needed: the 100 m proximity gate
that makes the crowd reports trustworthy cannot work with coarse location,
which is accurate to roughly a city block.
