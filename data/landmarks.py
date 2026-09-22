"""Give every machine a human answer to "where is it?".

A bank name is not a location. "RT Bank, 7.3 km" tells you nothing about where
you are going; "RT Bank - Family Mall" does.

The obvious source is OpenStreetMap's `place=neighbourhood/quarter/suburb`
nodes, and it does not work here: measured against the real dataset, only 21 of
542 machines have a named area within 300 m. Kurdistan's neighbourhood mapping
is sparse.

What does work is navigable landmarks - malls, markets, hotels, parks,
universities, bus stations. The same measurement gives 421 of 542 within 300 m,
and they are what people actually navigate by. Combined coverage:

    300 m -> 442/542 (81%)
    500 m -> 485/542 (89%)

300 m is the default because beyond that the cue stops being true: a mall
800 m away does not tell you where the machine is, it misleads you.

The honest limitation: only about a quarter of these landmarks carry a Sorani
name in OSM, so most render in English or Arabic even for a Sorani user. That is
still better than no location at all, and it improves as OSM does.
"""

import json
import math
import os
import time
import urllib.parse
import urllib.request
from collections import defaultdict

CACHE_DIR = os.path.join(os.path.dirname(__file__), ".cache")
UA = "kurdistan-atm-map/0.1 (open data project; contact via project repo)"
ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]

# Generous enough to cover the region, tight enough to keep Iran and Turkey out.
BBOX = "35.0,42.3,37.4,46.4"

# Things people give directions by. Deliberately excludes fuel stations and
# clinics: there are thousands of them and "near a petrol station" is not a
# location in a Kurdish city.
LANDMARK_QUERY = """[out:json][timeout:180];
(
  nwr["name"]["shop"~"^(mall|department_store|supermarket)$"](%(bbox)s);
  nwr["name"]["amenity"~"^(university|college|hospital|marketplace|bus_station)$"](%(bbox)s);
  nwr["name"]["tourism"~"^(hotel|attraction|museum)$"](%(bbox)s);
  nwr["name"]["leisure"="park"](%(bbox)s);
  nwr["name"]["building"="mall"](%(bbox)s);
  node["place"~"^(neighbourhood|quarter|suburb)$"]["name"](%(bbox)s);
);
out center;""" % {"bbox": BBOX}

# How close a landmark must be before naming it is honest.
MAX_METRES = 300

# How much worse a category is as a direction, expressed in metres so it trades
# off against distance instead of overriding it.
#
# Sorting by category first and distance second gets this wrong: it picks a
# health centre 227 m away over a market 50 m away, because hospitals outrank
# supermarkets. But "at Matin Market" is a better direction than "near
# bahdinan health center" even though a hospital is the grander building.
# Adding the penalty to the distance lets a genuinely close landmark win.
PENALTY_METRES = {
    "shop=mall": 0,
    "building=mall": 0,
    "amenity=marketplace": 20,
    "leisure=park": 40,
    "amenity=university": 40,
    "amenity=bus_station": 50,
    "shop=department_store": 60,
    "amenity=hospital": 80,
    "amenity=college": 90,
    "shop=supermarket": 100,
    "tourism=museum": 110,
    "tourism=attraction": 110,
    "tourism=hotel": 130,
    # A neighbourhood centroid is a weak cue: the node is the middle of an
    # area, so the distance means much less than it does for a building.
    "place": 150,
}


def _kind(tags):
    for key in ("shop", "amenity", "tourism", "leisure", "building"):
        if key in tags:
            return "%s=%s" % (key, tags[key])
    if "place" in tags:
        return "place"
    return "?"


def _fetch(query, cache_name, max_age):
    """Run an Overpass query, cached on disk.

    Overpass rejects a meaningful share of requests with a dispatcher error, so
    this retries across mirrors rather than failing the whole build. A failure
    returns an empty list: a machine with no location cue is a worse app, not a
    broken one.
    """
    os.makedirs(CACHE_DIR, exist_ok=True)
    path = os.path.join(CACHE_DIR, cache_name)
    if os.path.exists(path) and time.time() - os.path.getmtime(path) < max_age:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)["elements"]

    body = urllib.parse.urlencode({"data": query}).encode()
    last = None
    for attempt in range(6):
        endpoint = ENDPOINTS[attempt % len(ENDPOINTS)]
        try:
            req = urllib.request.Request(endpoint, data=body, headers={"User-Agent": UA})
            text = urllib.request.urlopen(req, timeout=240).read().decode("utf-8", "replace")
            if not text.lstrip().startswith("{"):
                raise RuntimeError("non-JSON reply (dispatcher busy)")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
            return json.loads(text)["elements"]
        except Exception as exc:                       # noqa: BLE001 - retry any failure
            last = exc
            print("  %s: attempt %d failed (%s), retrying" % (cache_name, attempt + 1, exc))
            time.sleep(10)

    print("  ! %s unavailable, those cues will be missing: %s" % (cache_name, last))
    return []


def fetch(max_age=604800):
    """Landmarks across the region, cached for a week."""
    return _fetch(LANDMARK_QUERY, "landmarks.json", max_age)


# ---------------------------------------------------------------------------
# Areas: a second, independent pass.
#
# A landmark answers "what is it next to". An area answers "what part of town is
# it in", which is how the project owner actually described the feature ("this
# ATM is at Awbara"). The two are computed separately and BOTH kept, because
# treating areas as a fallback tier only for machines with no landmark gets the
# motivating example wrong: the Awbara machine has a supermarket 260 m away and
# the Awbara place node 99 m away, so a fallback would label it "Darya shop".
#
# The radii are much larger than a landmark's 300 m because a place node is the
# centroid of an area, not a building: being 600 m from the middle of a
# neighbourhood usually means being inside it. That is also why the app says
# "in X area" and never "at X", and why no metre count is ever shown for it.
# ---------------------------------------------------------------------------

PLACES_QUERY = """[out:json][timeout:180];
(
  node["place"~"^(city_block|neighbourhood|quarter|suburb|village|town)$"]["name"](%(bbox)s);
);
out center;""" % {"bbox": BBOX}

# place=city is excluded: at any useful radius it only echoes the `city` field
# the record already carries.
AREA_BUDGET = {
    "city_block": 400,
    "neighbourhood": 900,
    "quarter": 900,
    "suburb": 1200,
    "village": 1000,
    "town": 2000,
}

# Finer beats coarser: a neighbourhood is a better answer than the town it sits
# in, even from further away.
AREA_RANK = {
    "city_block": 0,
    "neighbourhood": 1,
    "quarter": 1,
    "suburb": 2,
    "village": 3,
    "town": 4,
}


def fetch_places(max_age=604800):
    """Named places across the region, cached for a week."""
    return _fetch(PLACES_QUERY, "places.json", max_age)


def assign_areas(atms, elements):
    """Attach the nearest sensible named area to each ATM, in place."""
    if not elements:
        return 0

    grid = defaultdict(list)
    for element in elements:
        lat, lon = _coords(element)
        if lat is None:
            continue
        grid[_cell(lat, lon)].append((lat, lon, element["tags"]))

    widest = max(AREA_BUDGET.values())
    cells = int(widest / 1000) + 1
    assigned = 0

    for atm in atms:
        best = None
        base = _cell(atm["lat"], atm["lon"])
        for dy in range(-cells, cells + 1):
            for dx in range(-cells, cells + 1):
                for lat, lon, tags in grid.get((base[0] + dy, base[1] + dx), []):
                    place = tags.get("place", "")
                    budget = AREA_BUDGET.get(place)
                    if budget is None:
                        continue
                    metres = _haversine(atm["lat"], atm["lon"], lat, lon)
                    if metres > budget:
                        continue
                    # Rank first here, unlike landmarks: a neighbourhood at
                    # 700 m genuinely beats the town centroid at 300 m.
                    score = (AREA_RANK.get(place, 5), metres)
                    if best is None or score < best[0]:
                        best = (score, tags, place, metres)

        if best is None:
            continue

        _, tags, place, metres = best
        name = tags.get("name", "")
        atm["area"] = {
            "en": tags.get("name:en") or name,
            "ckb": tags.get("name:ckb") or tags.get("name:ku") or name,
            "ar": tags.get("name:ar") or name,
            "kind": "place=" + place,
            "metres": round(metres),
        }
        assigned += 1

    return assigned


def _cell(lat, lon):
    """Integer grid cell, ~1 km on a side.

    Integer keys matter: the obvious `round(lat, 2) + dy * 0.01` produces
    36.199999999999996 where the stored key is 36.2, so every lookup outside
    the centre cell silently missed and the whole neighbour search did nothing.
    """
    return (int(round(lat * 100)), int(round(lon * 100)))


def _coords(element):
    lat = element.get("lat") or element.get("center", {}).get("lat")
    lon = element.get("lon") or element.get("center", {}).get("lon")
    return lat, lon


def _haversine(alat, alon, blat, blon):
    radius = 6371000.0
    dlat = math.radians(blat - alat)
    dlon = math.radians(blon - alon)
    h = (math.sin(dlat / 2) ** 2
         + math.cos(math.radians(alat)) * math.cos(math.radians(blat))
         * math.sin(dlon / 2) ** 2)
    return 2 * radius * math.asin(math.sqrt(h))


def assign(atms, elements, max_metres=MAX_METRES):
    """Attach the nearest worthwhile landmark to each ATM record, in place.

    Adds `landmark` = {"en": ..., "ckb": ..., "ar": ..., "kind": ..., "metres": n}
    or leaves it absent when nothing credible is close enough.
    """
    if not elements:
        return 0

    # ~1 km grid cells so the search is local instead of 542 x 9000.
    grid = defaultdict(list)
    for element in elements:
        lat, lon = _coords(element)
        if lat is None:
            continue
        grid[_cell(lat, lon)].append((lat, lon, element["tags"]))

    cells = int(max_metres / 1000) + 1
    assigned = 0

    for atm in atms:
        best = None
        base = _cell(atm["lat"], atm["lon"])
        for dy in range(-cells, cells + 1):
            for dx in range(-cells, cells + 1):
                for lat, lon, tags in grid.get((base[0] + dy, base[1] + dx), []):
                    metres = _haversine(atm["lat"], atm["lon"], lat, lon)
                    if metres > max_metres:
                        continue
                    kind = _kind(tags)
                    score = metres + PENALTY_METRES.get(kind, 120)
                    if best is None or score < best[0]:
                        best = (score, tags, kind, metres)

        if best is None:
            continue

        _, tags, kind, metres = best
        name = tags.get("name", "")
        atm["landmark"] = {
            "en": tags.get("name:en") or name,
            "ckb": tags.get("name:ckb") or "",
            "ar": tags.get("name:ar") or "",
            "kind": kind,
            "metres": round(metres),
        }
        assigned += 1

    return assigned
