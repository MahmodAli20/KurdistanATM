"""Merge every ATM source into one dataset the app can ship offline.

    python build.py            # build, write out/atms.json, print a coverage report
    python build.py --fresh    # ignore the HTTP cache

Two records are treated as the same physical machine when they sit within
MERGE_METRES of each other and their bank sets don't contradict.
"""

import argparse
import hashlib
import json
import math
import os
import shutil
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import banks as banks_mod
import landmarks as landmarks_mod
import sources as sources_mod

MERGE_METRES = 35
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

# Approximate centres used to label a record with a city. Radius is in degrees.
CITIES = [
    ("erbil", "Erbil", "هەولێر", 36.19, 44.01, 0.32),
    ("sulaymaniyah", "Sulaymaniyah", "سلێمانی", 35.56, 45.43, 0.30),
    ("duhok", "Duhok", "دهۆک", 36.86, 42.99, 0.25),
    ("zakho", "Zakho", "زاخۆ", 37.14, 42.68, 0.18),
    ("soran", "Soran", "سۆران", 36.65, 44.54, 0.20),
    ("ranya", "Ranya", "ڕانیە", 36.25, 44.88, 0.20),
    ("halabja", "Halabja", "هەڵەبجە", 35.18, 45.99, 0.20),
    ("kirkuk", "Kirkuk", "کەرکووک", 35.47, 44.39, 0.30),
]


def haversine(lat1, lon1, lat2, lon2):
    """Great-circle distance in metres."""
    radius = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * radius * math.asin(math.sqrt(a))


def city_of(lat, lon):
    for city_id, _, _, clat, clon, radius in CITIES:
        if abs(lat - clat) < radius and abs(lon - clon) < radius:
            return city_id
    return "other"


def compatible(a, b):
    """Can these two records describe the same machine?"""
    if not a["banks"] or not b["banks"]:
        return True  # one side is unlabelled, let proximity decide
    return bool(set(a["banks"]) & set(b["banks"]))


def merge_into(target, extra):
    """Fold `extra` into `target`, preferring the richer value for each field."""
    target["banks"] = sorted(set(target["banks"]) | set(extra["banks"]))
    target["agents"] = sorted(set(target["agents"]) | set(extra["agents"]))
    target["currencies"] = sorted(set(target["currencies"]) | set(extra["currencies"]))
    target["sources"].append(extra["source"])
    # A confirmed bank machine outranks an agent-only guess.
    if extra["kind"] == "atm" or target["banks"]:
        target["kind"] = "atm"
    for field in ("name", "name_ckb", "hours"):
        if not target[field] and extra[field]:
            target[field] = extra[field]
    for flag in ("indoor", "drive_through", "cash_in"):
        target[flag] = target[flag] or extra[flag]


def bucket_key(lat, lon):
    """Grid cell ~100m on a side, so merging doesn't need an O(n^2) sweep."""
    return (round(lat / 0.001), round(lon / 0.001))


def dedupe(records):
    grid = defaultdict(list)
    merged = []
    duplicates = 0

    for rec in records:
        key = bucket_key(rec["lat"], rec["lon"])
        neighbours = []
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                neighbours += grid[(key[0] + dy, key[1] + dx)]

        hit = None
        for candidate in neighbours:
            distance = haversine(rec["lat"], rec["lon"], candidate["lat"], candidate["lon"])
            if distance <= MERGE_METRES and compatible(rec, candidate):
                hit = candidate
                break

        if hit:
            merge_into(hit, rec)
            duplicates += 1
        else:
            entry = dict(rec)
            entry["sources"] = [rec.pop("source")]
            entry.pop("source", None)
            merged.append(entry)
            grid[key].append(entry)

    return merged, duplicates


def finalise(records):
    """Assign stable ids, city labels and display names."""
    out = []
    for rec in records:
        city = city_of(rec["lat"], rec["lon"])
        # Stable id from rounded position: survives small coordinate corrections.
        seed = "%.4f,%.4f,%s" % (rec["lat"], rec["lon"], ",".join(rec["banks"]))
        atm_id = hashlib.sha1(seed.encode()).hexdigest()[:12]

        bank_names = [banks_mod.display(b) for b in rec["banks"]]
        out.append({
            "id": atm_id,
            "kind": rec["kind"],
            "lat": round(rec["lat"], 6),
            "lon": round(rec["lon"], 6),
            "city": city,
            "name": rec["name"],
            "name_ckb": rec["name_ckb"],
            "banks": rec["banks"],
            "agents": rec["agents"],
            "bank_names_en": [n[0] for n in bank_names],
            "bank_names_ckb": [n[1] for n in bank_names],
            # Without this every Arabic-speaking user reads English bank names,
            # because the UI falls back to English when a name is missing.
            "bank_names_ar": [n[2] for n in bank_names],
            "currencies": rec["currencies"],
            "hours": rec["hours"],
            "indoor": rec["indoor"],
            "drive_through": rec["drive_through"],
            "cash_in": rec["cash_in"],
            "at_branch": rec["is_bank_poi"],
            "sources": sorted(set(rec["sources"])),
        })
    out.sort(key=lambda r: (r["city"], r["bank_names_en"][0] if r["bank_names_en"] else "zz"))
    return out


def report(atms, duplicates, per_source):
    print("\n" + "=" * 58)
    print("  KURDISTAN ATM DATASET")
    print("=" * 58)
    for name, count in per_source.items():
        print("  %-8s %5d records" % (name, count))
    print("  %-8s %5d merged as duplicates" % ("", duplicates))
    print("  %-8s %5d unique ATMs" % ("TOTAL", len(atms)))

    cash = [a for a in atms if a["kind"] == "atm"]
    print("\n  %d cash machines + %d card agents (Qi Card / wallets)"
          % (len(cash), len(atms) - len(cash)))

    print("\n  Cash machines by city")
    for city_id, count in Counter(a["city"] for a in cash).most_common():
        print("    %-16s %4d" % (city_id, count))

    print("\n  By bank")
    counter = Counter()
    for atm in atms:
        for name in atm["bank_names_en"] or ["(unidentified)"]:
            counter[name] += 1
    for name, count in counter.most_common(12):
        print("    %-38s %4d" % (name[:38], count))

    total = len(atms) or 1
    print("\n  Field coverage")
    for label, test in [
        ("bank identified", lambda a: bool(a["banks"])),
        ("opening hours", lambda a: bool(a["hours"])),
        ("currencies", lambda a: bool(a["currencies"])),
        ("name", lambda a: bool(a["name"])),
        ("multi-source", lambda a: len(a["sources"]) > 1),
        ("landmark", lambda a: bool(a.get("landmark"))),
        ("area", lambda a: bool(a.get("area"))),
    ]:
        count = sum(1 for a in atms if test(a))
        print("    %-18s %4d  (%3d%%)" % (label, count, 100 * count // total))
    print()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fresh", action="store_true", help="ignore the HTTP cache")
    args = parser.parse_args()

    if args.fresh:
        shutil.rmtree(sources_mod.CACHE_DIR, ignore_errors=True)

    records, per_source = [], {}
    for name, fetch in sources_mod.SOURCES.items():
        print("fetching %s ..." % name, flush=True)
        try:
            got = fetch()
        except Exception as exc:                      # a dead source must not kill the build
            print("  ! %s failed: %s" % (name, exc))
            per_source[name] = 0
            continue
        # National banks cover all of Iraq; keep only what falls in our cities.
        got = [r for r in got if city_of(r["lat"], r["lon"]) != "other"]
        per_source[name] = len(got)
        records += got
        print("  %d records in region" % len(got))

    merged, duplicates = dedupe(records)
    atms = finalise(merged)

    # A bank name is not a location. Attach the nearest thing people actually
    # navigate by, so the app can say "RT Bank - Family Mall" instead of just
    # "RT Bank, 7.3 km away".
    print("fetching landmarks ...", flush=True)
    landmark_elements = landmarks_mod.fetch()
    located = landmarks_mod.assign(atms, landmark_elements)
    print("  %d of %d machines have a nearby landmark" % (located, len(atms)))

    # Second, independent pass: which part of town. Not a fallback - a machine
    # can and should have both.
    place_elements = landmarks_mod.fetch_places()
    areas = landmarks_mod.assign_areas(atms, place_elements)
    print("  %d of %d machines have an area name" % (areas, len(atms)))

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, "atms.json"), "w", encoding="utf-8") as fh:
        json.dump({"version": 1, "count": len(atms), "atms": atms}, fh,
                  ensure_ascii=False, indent=1)

    report(atms, duplicates, per_source)
    print("written -> %s" % os.path.join(OUT_DIR, "atms.json"))


if __name__ == "__main__":
    main()
