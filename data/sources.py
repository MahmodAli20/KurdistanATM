"""Fetchers for each upstream ATM data source.

Every fetcher returns a list of records in the shared shape used by build.py:

    {lat, lon, name, banks[], currencies[], hours, indoor, drive_through,
     cash_in, source}

Responses are cached on disk so repeated builds don't hammer anyone's server.
"""

import json
import os
import re
import time
import urllib.parse
import urllib.request

import banks as banks_mod

CACHE_DIR = os.path.join(os.path.dirname(__file__), ".cache")
UA = "kurdistan-atm-map/0.1 (open data project; contact via project repo)"

# Kurdistan Region governorates + Kirkuk, which matters for salary withdrawal too.
GOVERNORATES = ["IQ-AR", "IQ-SU", "IQ-DA", "IQ-HA", "IQ-KI"]


def _get(url, cache_key, data=None, max_age=86400):
    """HTTP GET/POST with a simple on-disk cache."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    path = os.path.join(CACHE_DIR, cache_key)
    if os.path.exists(path) and time.time() - os.path.getmtime(path) < max_age:
        with open(path, encoding="utf-8") as fh:
            return fh.read()

    body = data.encode() if data else None
    req = urllib.request.Request(url, data=body, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=180) as resp:
        text = resp.read().decode("utf-8", "replace")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return text


# --------------------------------------------------------------------------
# OpenStreetMap via Overpass
# --------------------------------------------------------------------------

OVERPASS_QUERY = """[out:json][timeout:180];
(%s)->.regions;
(
  node["amenity"="atm"](area.regions);
  node["amenity"="bank"]["atm"!="no"](area.regions);
  way["amenity"="bank"]["atm"!="no"](area.regions);
);
out center tags;"""


def fetch_osm():
    areas = "".join('area["ISO3166-2"="%s"];' % g for g in GOVERNORATES)
    query = OVERPASS_QUERY % areas
    raw = _get(
        "https://overpass-api.de/api/interpreter",
        "osm.json",
        data=urllib.parse.urlencode({"data": query}),
    )
    elements = json.loads(raw)["elements"]

    out = []
    for el in elements:
        tags = el.get("tags", {})
        lat = el.get("lat") or el.get("center", {}).get("lat")
        lon = el.get("lon") or el.get("center", {}).get("lon")
        if lat is None or lon is None:
            continue

        # operator/brand/name are all candidates; collect every bank mentioned.
        found, agent_ids, record_kind = [], [], "atm"
        for key in ("operator", "brand", "name:en", "name"):
            value = tags.get(key)
            found += banks_mod.normalise(value)
            agent_ids += banks_mod.agents(value)
        # A card agent is only reclassified when no real bank is named alongside it.
        if agent_ids and not found:
            record_kind = "agent"

        currencies = [
            code
            for code in ("IQD", "USD", "EUR")
            if tags.get("currency:" + code) == "yes"
        ]

        out.append({
            "lat": lat,
            "lon": lon,
            "name": tags.get("name:en") or tags.get("name") or "",
            "name_ckb": tags.get("name:ckb") or tags.get("name:ku") or "",
            "banks": sorted(set(found)),
            "agents": sorted(set(agent_ids)),
            "kind": record_kind,
            "currencies": currencies,
            "hours": tags.get("opening_hours", ""),
            "indoor": tags.get("indoor") == "yes",
            "drive_through": tags.get("drive_through") == "yes",
            "cash_in": tags.get("cash_in") == "yes",
            "is_bank_poi": tags.get("amenity") == "bank",
            "source": "osm:%s/%s" % (el["type"], el["id"]),
        })
    return out


# --------------------------------------------------------------------------
# National Bank of Iraq - undocumented JSON endpoint behind their branches page
# --------------------------------------------------------------------------

NBI_URL = (
    "https://www.nbi.iq/api/BranchesAPI/Get"
    "?pageId=d3327787-b2ff-48c6-b6dc-3357cc813416&culture=en"
)

# Coordinates hide inside the Google Maps embed URL as !2d<lon>!3d<lat>
NBI_COORDS = re.compile(r"!2d(-?\d+\.\d+)!3d(-?\d+\.\d+)")


def fetch_nbi():
    raw = _get(NBI_URL, "nbi.json")
    payload = json.loads(raw)
    if payload.get("StatusCode") != 200 or not payload.get("Result"):
        raise RuntimeError("NBI endpoint returned: %s" % payload.get("StatusMessage"))

    out = []
    for loc in payload["Result"]["Locations"]:
        match = NBI_COORDS.search(loc.get("EmebededGoogleMapsLink") or "")
        if not match:
            continue
        lon, lat = float(match.group(1)), float(match.group(2))

        hours = " ".join(
            part for part in (loc.get("WorkingDays"), loc.get("NormalTimings")) if part
        ).strip()

        out.append({
            "lat": lat,
            "lon": lon,
            "name": (loc.get("LocationName") or "").strip(),
            "name_ckb": "",
            "banks": ["nbi"],
            "agents": [],
            "kind": "atm",
            "currencies": _nbi_currencies(loc.get("Currencies")),
            "hours": hours,
            "indoor": False,
            "drive_through": False,
            "cash_in": False,
            "is_bank_poi": loc.get("LocationType") == 2,
            "source": "nbi",
        })
    return out


def _nbi_currencies(value):
    if not value:
        return []
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    return [code for code in ("IQD", "USD", "EUR") if code in text.upper()]


SOURCES = {"osm": fetch_osm, "nbi": fetch_nbi}
