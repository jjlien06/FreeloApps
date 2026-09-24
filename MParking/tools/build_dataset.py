#!/usr/bin/env python3
"""Build facilities.json from the raw harvested TSVs.

Two jobs:
  1. Turn LTP's free-text "Enforcement Hours" strings into structured windows.
  2. Geocode U-M street addresses to lat/lon (Nominatim, cached on disk).

Every window is confined to a SINGLE day, with "24:00" allowed as an end time.
Overnight/multi-day spans are split across days at build time. That keeps the
Swift rules engine free of wrap-around arithmetic - the source of most
off-by-one bugs in this kind of code.

Usage:  python3 tools/build_dataset.py [--no-geocode]
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "tools" / "raw"
OUT = ROOT / "Packages" / "ParkingKit" / "Sources" / "ParkingKit" / "Resources" / "facilities.json"
GEOCACHE = ROOT / "tools" / "geocache.json"

HARVEST_DATE = "2026-07-30"

# Corrections mirrored from the deployed UMichFreePark data. These stay as an
# overlay rather than being written into the LTP TSV transcription so the
# published table and the field correction remain auditable separately.
DATA_CORRECTIONS = {
    "C5": {
        "enforcementHours": "24 hrs, 7 days",
        "permitTier": "Restricted",
        "confidence": "community",
        "source": "Reported on the ground, 2026-08-06. Contradicts the LTP table, which could not be re-verified: ltp.umich.edu blocks automated requests and the newest archive capture is the one this dataset already uses.",
        "verifiedOn": "2026-08-06",
        "note": "Service vehicles only, monitored around the clock. U-M's published table still lists this as a Blue lot enforced 6am-5pm Mon-Fri; check the sign.",
    },
    "M61": {
        "enforcementHours": "24 hrs, 7 days",
        "permitTier": "Blue",
        "confidence": "verified",
        "source": "https://ltp.umich.edu/parking/locations-and-enforcement/medical-campus/",
        "verifiedOn": "2026-08-08",
        "note": "Posted enforcement: 24 hrs, 7 days. U-M changed this structure from weekday-daytime enforcement to around the clock; it is Blue at every hour now.",
    },
}

CAMPUS_SOURCE = {
    "central": "https://ltp.umich.edu/parking/locations-and-enforcement/central-campus/",
    "medical": "https://ltp.umich.edu/parking/locations-and-enforcement/medical-campus/",
    "north": "https://ltp.umich.edu/parking/locations-and-enforcement/north-campus/",
    "athletic": "https://ltp.umich.edu/parking/locations-and-enforcement/ross-athletic-campus/",
}
DDA_SOURCE = "https://www.a2dda.org/parking-rates/"

# Ann Arbor sanity box - reject any geocode result outside it.
BOX = (42.20, 42.36, -83.82, -83.64)  # minLat, maxLat, minLon, maxLon

# A clock time as LTP writes them: 6am, 6 am, 10 pm, 6:30am, 1 a.m.
CLOCK = r"\d{1,2}(?::\d{2})?\s*[ap]\.?m\.?"

MON, TUE, WED, THU, FRI, SAT, SUN = 1, 2, 3, 4, 5, 6, 7
DAY_NAMES = {"mon": MON, "tue": TUE, "wed": WED, "thu": THU,
             "fri": FRI, "sat": SAT, "sun": SUN}
ALL_DAYS = [MON, TUE, WED, THU, FRI, SAT, SUN]


# ---------------------------------------------------------------- time parsing

def parse_clock(s: str) -> str:
    """'6am' '6 am' '10 pm' '6:30am' '1 am' -> 'HH:MM' (24h)."""
    m = re.match(r"^\s*(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?\s*$", s.strip(), re.I)
    if not m:
        raise ValueError(f"unparseable clock time: {s!r}")
    hour, minute, half = int(m.group(1)), int(m.group(2) or 0), m.group(3).lower()
    if hour == 12:
        hour = 0
    if half == "p":
        hour += 12
    return f"{hour:02d}:{minute:02d}"


def day_span(a: str, b: str) -> list[int]:
    """'Mon','Fri' -> [1,2,3,4,5]  (wraps if needed)."""
    start, end = DAY_NAMES[a.lower()[:3]], DAY_NAMES[b.lower()[:3]]
    out, d = [], start
    while True:
        out.append(d)
        if d == end:
            break
        d = d % 7 + 1
        if len(out) > 7:
            raise ValueError(f"day span never closed: {a}-{b}")
    return out


def norm(s: str) -> str:
    """Normalise dashes and whitespace so one set of patterns covers all rows."""
    return re.sub(r"\s+", " ", s.replace("–", "-").replace("—", "-")).strip()


def win(day: int, start: str, end: str) -> dict:
    return {"day": day, "start": start, "end": end}


def continuous(from_day: int, from_time: str, to_day: int, to_time: str) -> list[dict]:
    """A single span running from one weekday/time to another, split per day."""
    out, d = [], from_day
    while True:
        s = from_time if d == from_day else "00:00"
        e = to_time if d == to_day else "24:00"
        if s != e:
            out.append(win(d, s, e))
        if d == to_day:
            break
        d = d % 7 + 1
    return out


def parse_enforcement(raw: str) -> dict:
    """LTP free text -> {'kind', 'windows', 'raw', 'note'}."""
    s = norm(raw)
    note = None

    if not s or s.upper() == "NA":
        return {"kind": "unknown", "windows": [], "raw": raw,
                "note": "LTP lists no enforcement hours for this lot."}

    # N26-style compound row: two rules in one cell. Use the permit-area rule
    # (the restrictive one) and carry the full text forward as a note.
    if re.search(r"permit areas", s, re.I):
        note = f"LTP lists separate permit and visitor rules: {s}"
        m = re.search(r"permit areas\s*(.+?),?\s*(mon|tue|wed|thu|fri|sat|sun)\s*-\s*"
                      r"(mon|tue|wed|thu|fri|sat|sun)", s, re.I)
        if m:
            times, d1, d2 = m.group(1), m.group(2), m.group(3)
            t = re.match(r"\s*(.+?)\s*-\s*(.+?)\s*$", times)
            if t:
                a, b = parse_clock(t.group(1)), parse_clock(t.group(2))
                days = day_span(d1, d2)
                return {"kind": "windows", "raw": raw, "note": note,
                        "windows": [win(d, a, b) for d in days]}

    # "6 am Mon - 1 am Sat"  (one continuous multi-day span).
    # Requires a time immediately before EACH day name, so it cannot swallow the
    # far more common "6am - 5pm, Mon - Fri" shape.
    m = re.match(rf"^({CLOCK})\s*(mon|tue|wed|thu|fri|sat|sun)\s*-\s*({CLOCK})\s*"
                 r"(mon|tue|wed|thu|fri|sat|sun)$", s, re.I)
    if m:
        a, d1 = parse_clock(m.group(1)), DAY_NAMES[m.group(2).lower()[:3]]
        b, d2 = parse_clock(m.group(3)), DAY_NAMES[m.group(4).lower()[:3]]
        return {"kind": "windows", "raw": raw, "note": note,
                "windows": continuous(d1, a, d2, b)}

    # Day part: "7 days" / "7 Days" / "Sun-Sat" / "Mon - Fri" / "Mon-Sat"
    if re.search(r"7\s*days", s, re.I):
        days = list(ALL_DAYS)
    else:
        m = re.search(r"(mon|tue|wed|thu|fri|sat|sun)\s*-\s*"
                      r"(mon|tue|wed|thu|fri|sat|sun)", s, re.I)
        if not m:
            return {"kind": "unknown", "windows": [], "raw": raw,
                    "note": f"Could not parse enforcement hours: {raw!r}"}
        days = day_span(m.group(1), m.group(2))

    # Time part: "24 hrs" or "6am - 5pm"
    if re.search(r"24\s*hrs?", s, re.I):
        return {"kind": "windows", "raw": raw, "note": note,
                "windows": [win(d, "00:00", "24:00") for d in days]}

    m = re.search(r"(\d{1,2}(?::\d{2})?\s*[ap]\.?m\.?)\s*-\s*"
                  r"(\d{1,2}(?::\d{2})?\s*[ap]\.?m\.?)", s, re.I)
    if not m:
        return {"kind": "unknown", "windows": [], "raw": raw,
                "note": f"Could not parse enforcement hours: {raw!r}"}
    a, b = parse_clock(m.group(1)), parse_clock(m.group(2))
    if a == b:
        return {"kind": "windows", "raw": raw, "note": note,
                "windows": [win(d, "00:00", "24:00") for d in days]}
    if b < a:  # e.g. 6am-1am -> runs past midnight into the next day
        out = []
        for d in days:
            out.append(win(d, a, "24:00"))
            out.append(win(d % 7 + 1, "00:00", b))
        return {"kind": "windows", "raw": raw, "note": note, "windows": out}
    return {"kind": "windows", "raw": raw, "note": note,
            "windows": [win(d, a, b) for d in days]}


# ------------------------------------------------------------------- geocoding

_cache: dict | None = None


def geocode(address: str, name: str, enabled: bool) -> tuple[float | None, float | None, str]:
    """Return (lat, lon, how). Cached; rejects results outside Ann Arbor."""
    global _cache
    if _cache is None:
        _cache = json.loads(GEOCACHE.read_text()) if GEOCACHE.exists() else {}

    addr = (address or "").strip()
    if not addr:
        return None, None, "no-address"
    key = addr.lower()
    if key in _cache:
        c = _cache[key]
        return c.get("lat"), c.get("lon"), c.get("how", "cache")
    if not enabled:
        return None, None, "skipped"

    q = f"{addr}, Ann Arbor, MI"
    url = ("https://nominatim.openstreetmap.org/search?"
           + urllib.parse.urlencode({"q": q, "format": "json", "limit": 1,
                                     "countrycodes": "us"}))
    lat = lon = None
    how = "not-found"
    try:
        # Nominatim's usage policy asks for a contact in the User-Agent.
        # Override with NOMINATIM_CONTACT if this address ever changes.
        contact = os.environ.get("NOMINATIM_CONTACT", "you@example.com")
        req = urllib.request.Request(url, headers={
            "User-Agent": f"MParking/1.0 (U-M parking app; {contact})"})
        with urllib.request.urlopen(req, timeout=25) as r:
            js = json.load(r)
        if js:
            la, lo = float(js[0]["lat"]), float(js[0]["lon"])
            if BOX[0] <= la <= BOX[1] and BOX[2] <= lo <= BOX[3]:
                lat, lon, how = la, lo, "nominatim"
            else:
                how = "out-of-box"
    except Exception as e:  # noqa: BLE001 - network best effort
        how = f"error:{type(e).__name__}"

    _cache[key] = {"lat": lat, "lon": lon, "how": how}
    GEOCACHE.write_text(json.dumps(_cache, indent=1, sort_keys=True))
    time.sleep(1.1)  # Nominatim usage policy: <=1 req/sec
    return lat, lon, how


# --------------------------------------------------------------------- loading

def read_tsv(path: Path) -> list[dict]:
    lines = [ln for ln in path.read_text().splitlines()
             if ln.strip() and not ln.startswith("#")]
    header = lines[0].split("\t")
    rows = []
    for ln in lines[1:]:
        cells = ln.split("\t")
        cells += [""] * (len(header) - len(cells))
        rows.append(dict(zip(header, cells)))
    return rows


TIER_MAP = {
    "blue": "blue", "gold": "gold", "yellow": "yellow", "orange": "orange",
    "visitor": "visitor", "restricted": "restricted", "park & ride": "parkAndRide",
    "contractor": "contractor", "other": "other",
}

# Surface lots that DDA operates like a structure - gated, hourly, rates Mon-Sat
# with Sunday free - rather than by meter.
#
# Source: https://www.a2dda.org/parking-faqs/ heads its hourly-payment section
# "Paying at Parking Structures (& the South Ashley Surface Lot)", grouping this
# one lot with the structures. Everything else in the DDA surface-lot layer is a
# metered lot, and DDA publishes metered hours separately (Mon-Sat 8am-6pm, free
# evenings and Sundays), so no lot needs to be left as "unknown".
GATED_SURFACE_LOTS = {"South Ashley"}

# Availability-page row label -> lot id(s). The page's row set changes over time
# and its labels differ from the enforcement tables, so anything not resolvable
# by a leading lot id needs an explicit alias.
AVAILABILITY_ALIASES = {
    "P1 Parking Structure": ["M15"],
    "P4 Parking Structure": ["M22"],
    "M5/M86 Catherine and Ann Structures": ["M5", "M86"],
    "Forest St. Structure": ["S28"],
}


def build() -> dict:
    geo_on = "--no-geocode" not in sys.argv
    facilities: list[dict] = []
    seen: set[str] = set()

    for campus, src in CAMPUS_SOURCE.items():
        for row in read_tsv(RAW / f"{campus}.tsv"):
            lot_raw = row["Lot"].strip()
            if not lot_raw:
                continue
            relocated = lot_raw.endswith("*")
            lot = lot_raw.rstrip("*")
            fid = f"umich:{lot}"
            if fid in seen:                      # M18 is listed twice (P2 and P3)
                n = 2
                while f"{fid}-{n}" in seen:
                    n += 1
                fid = f"{fid}-{n}"
            seen.add(fid)

            correction = DATA_CORRECTIONS.get(lot)
            hours_raw = correction["enforcementHours"] if correction else row["EnforcementHours"]
            enf = parse_enforcement(hours_raw)
            lat, lon, how = geocode(row["Address"], row["Name"], geo_on)
            tier_name = correction["permitTier"] if correction else row["Tier"]
            tier = TIER_MAP.get(tier_name.strip().lower(), "other")

            notes = [n for n in [enf.get("note"), correction.get("note") if correction else None] if n]
            if relocated:
                notes.append("Accessible spaces relocated to another area (LTP asterisk).")

            facilities.append({
                "id": fid,
                "lotId": lot,
                "name": row["Name"].strip(),
                "system": "umich",
                "campus": campus,
                "address": row["Address"].strip(),
                "lat": lat, "lon": lon, "geocode": how,
                "tier": tier,
                "enforcement": {"kind": enf["kind"], "windows": enf["windows"],
                                "raw": enf["raw"]},
                "confidence": (correction["confidence"] if correction
                               else ("verified" if enf["kind"] != "unknown" else "unknown")),
                "source": correction["source"] if correction else src,
                "verifiedOn": correction["verifiedOn"] if correction else HARVEST_DATE,
                "capacity": None,
                "notes": notes,
                "availabilityAliases": [k for k, v in AVAILABILITY_ALIASES.items()
                                        if lot in v],
            })

    # ---- downtown DDA
    dda_free_sunday = continuous(MON, "04:00", SUN, "04:00")
    for row in read_tsv(RAW / "dda.tsv"):
        name = row["Name"].strip()
        if not name:
            continue
        kind = row["Kind"].strip()
        permit_only = row["ParkingType"].strip().lower() == "permit only"
        fid = "dda:" + re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
        spaces = row["Spaces"].strip()

        if permit_only:
            enf = {"kind": "windows", "windows": [win(d, "00:00", "24:00") for d in ALL_DAYS]}
            conf, notes = "verified", ["Permit-only lot per DDA."]
            raw = "Permit only"
        elif kind == "structure" or name in GATED_SURFACE_LOTS:
            enf = {"kind": "windows", "windows": list(dda_free_sunday)}
            conf = "verified"
            raw = "Rates Mon-Sat; free Sunday 4am-Monday 4am"
            notes = ["Free Sunday 4am - Monday 4am, and on PCI-observed holidays.",
                     "Gates are lowered on Sundays as of June 2024 - pull a ticket "
                     "on entry, insert it to exit. Still free."]
            if name in GATED_SURFACE_LOTS:
                notes.append("DDA groups this surface lot with the structures for "
                             "hourly payment, so the structure hours apply.")
        else:
            # Metered lot. DDA: "Metered parking on-street and in lots is enforced
            # Monday-Saturday 8:00am-6:00pm. Metered parking is free on evenings,
            # Sundays, and on holidays observed by City of Ann Arbor employees."
            enf = {"kind": "windows",
                   "windows": [win(d, "08:00", "18:00") for d in range(MON, SAT + 1)]}
            conf = "verified"
            raw = "Meters enforced 8am-6pm, Mon-Sat"
            notes = ["Metered lot: free evenings after 6pm, all Sunday, and on "
                     "City-observed holidays.",
                     "Time limits are posted per space - free does not mean "
                     "unlimited, and the posted maximum still applies."]

        facilities.append({
            "id": fid,
            "lotId": None,
            "name": name,
            "system": "dda",
            "campus": "downtown",
            "address": None,
            "lat": float(row["Lat"]), "lon": float(row["Lon"]), "geocode": "arcgis",
            "tier": "public",
            "enforcement": {"kind": enf["kind"], "windows": enf["windows"], "raw": raw},
            "confidence": conf,
            "source": DDA_SOURCE,
            "verifiedOn": HARVEST_DATE,
            "capacity": int(spaces) if spaces.isdigit() and int(spaces) > 0 else None,
            "notes": notes,
            "availabilityAliases": [],
        })

    return {
        "version": 1,
        "generated": HARVEST_DATE,
        "timeZone": "America/Detroit",
        "caveat": ("Entrance signage is authoritative. Enforcement is suspended or "
                   "overridden during football games, move-in, and commencement."),
        "sources": {**CAMPUS_SOURCE, "dda": DDA_SOURCE,
                    "availability": "https://ltp.umich.edu/parking/parking-space-availability/",
                    "ddaLiveCounts": "https://www.a2dda.org/map/AADDACount.json"},
        "availabilityAliases": AVAILABILITY_ALIASES,
        "facilities": facilities,
    }


if __name__ == "__main__":
    data = build()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, indent=1) + "\n")

    fs = data["facilities"]
    located = sum(1 for f in fs if f["lat"] is not None)
    unknown = [f["id"] for f in fs if f["enforcement"]["kind"] == "unknown"]
    print(f"wrote {OUT.relative_to(ROOT)}")
    print(f"  facilities:       {len(fs)}")
    print(f"  with coordinates: {located}/{len(fs)}")
    print(f"  unparsed hours:   {len(unknown)} {unknown if unknown else ''}")
    for sysname in ("umich", "dda"):
        print(f"  {sysname}: {sum(1 for f in fs if f['system'] == sysname)}")
