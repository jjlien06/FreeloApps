# MParking

Answers one question for U-M Ann Arbor: **where can I park free, and until when?**

Run everything from this folder (`cd MParking` from the repo root).

U-M lots are permit-gated during posted enforcement hours, and outside those hours
the gates go up and anyone parks free. Those hours differ per lot — Church Street
Structure is enforced 24h Mon–Sat, Hill Street only 6am–5pm Mon–Sat — and nothing
surfaces that as "what's free right now." U-M's own MGoPark app shows occupancy and
hours, but it won't tell you where to park free at 8pm tonight.

## How to use

It's a personal build, not an App Store app, so it goes on your phone through Xcode:

1. Plug your iPhone into the Mac (or have it on the same Wi-Fi with Xcode paired),
   open `MParking.xcodeproj`, pick your phone as the run destination, press ⌘R.
2. First install only: the phone will refuse to launch it until you trust the
   developer profile — Settings → General → VPN & Device Management → trust.
3. On a free Apple ID the install expires after 7 days; plugging in and pressing
   ⌘R again is the whole renewal.

Then day to day:

- **Free now** — every lot that's free at this moment, sorted by distance, each
  saying *until when*. The time picker answers "what's free at 8pm tonight?"
  without waiting until 8pm. Tap a lot for its whole week as an hour grid plus
  live space counts.
- **Map** — the same verdicts as pins, for picking by geography instead of by list.
- **Settings** — set the permit you hold (including After Hours) so "usable with
  your permit" shows alongside "free to anyone"; hide the ~20 lots that never
  become free; narrow to U-M and/or downtown DDA, and by campus.

Allow location ("while using") when it asks — that's what sorts lots by how far
you are from them; decline and everything still works, sorted by name. Two
warnings the app repeats on purpose: the sign at the entrance always wins over the
app, and football Saturdays, move-in and commencement override normal enforcement
everywhere.

## Layout

```
Packages/ParkingKit/     domain logic, no UI — `swift test` runs in under a second
  ParkingRules.swift     the engine: status(of:at:permit:), neverBecomesFree
  FacilityFilter.swift   which lots to show
  Availability.swift     live occupancy clients + pure HTML/JSON parsers
  Resources/facilities.json   the shipped dataset (generated, do not hand-edit)
  Sources/parkingctl/    CLI for checking the engine without a simulator
MParking/                SwiftUI app (stock List/Form, system colours, Dynamic Type)
tools/
  raw/*.tsv              hours as harvested, verbatim, with source URLs
  build_dataset.py       parses the hours, geocodes addresses, writes facilities.json
```

## Checking it

```sh
cd Packages/ParkingKit && swift test        # 59 tests
swift run parkingctl                        # what is free right now
swift run parkingctl --at "2026-08-05 19:00"
swift run parkingctl --permit blue
swift run parkingctl --lot S8               # one lot's whole week as an hour grid
swift run parkingctl --live                 # fetch live occupancy
```

`--lot` prints the week as a grid, which is the fastest way to eyeball a facility
against what LTP publishes:

```
S8 · Hill Street Parking Structure
  LTP hours: 6am – 5pm, Mon – Sat
    Mon ......###########.......
    ...
    Sun ........................
```

## Where the data comes from

| What | Source | How |
|---|---|---|
| U-M enforcement hours, 150 lots | [LTP locations and enforcement](https://ltp.umich.edu/parking/locations-and-enforcement/) | transcribed into `tools/raw/*.tsv` |
| Downtown geometry and capacity, 20 facilities | DDA ArcGIS `DDAParkingAreaView` | queried once |
| Downtown hours | [DDA rates](https://www.a2dda.org/parking-rates/) | rates Mon–Sat, free Sun 4am–Mon 4am; meters Mon–Sat 8am–6pm |
| U-M occupancy | [Parking Space Availability](https://ltp.umich.edu/parking/parking-space-availability/) | fetched live, `?tier=both` |
| Downtown space counts | `a2dda.org/map/AADDACount.json` | fetched live |

Hours ship with the app rather than being scraped at runtime, so it works with no
signal. They change roughly once an academic year.

### Rebuilding the dataset

```sh
python3 tools/build_dataset.py               # geocodes new addresses (cached)
python3 tools/build_dataset.py --no-geocode  # faster, uses the cache only
cd Packages/ParkingKit && swift test         # dataset integrity tests run here
```

To refresh hours, re-harvest the four LTP campus tables into `tools/raw/*.tsv` and
bump `HARVEST_DATE`. Note `ltp.umich.edu` sits behind Cloudflare: plain `curl` gets
403, but Python `urllib` and Apple's `URLSession` get through, and it rate-limits
under repeated hits. The app treats a 403 as "try later" and keeps the last figures.

## Things worth knowing

- **A wrong "free" costs a ticket**, so anything the sources don't establish is
  shown as "Check the sign" rather than guessed. A test sweeps the whole dataset at
  30-minute intervals across a week asserting no unverified facility ever reports
  free. Currently every one of the 170 facilities has published hours.
- **Enforcement windows are split per day at build time**, so `start < end` always
  holds and the engine needs no wrap-around arithmetic. Overnight and multi-day
  spans (M93 is "6 am Mon – 1 am Sat") expand into single-day windows.
- **All time maths runs through `Calendar` in `America/Detroit`**, so DST is the
  calendar's problem. Tests cover both 2027 transitions.
- **A permit makes a lot usable, not free.** The two are kept distinct everywhere,
  including in the "never free" filter, which hides 24/7 lots even for a permit
  holder who could park in them.
- **Football Saturdays, move-in and commencement override everything.** LTP says so
  and the app repeats it rather than quietly being wrong.
- **The DDA live feed emits bad rows** — a negative count was observed on facility
  84. Negatives are dropped rather than shown as "full".
- **DDA publishes no key→name mapping** for its count feed (`80`, `87 S`, …), and it
  isn't in their ArcGIS layers either, so those counts are not yet attributed to
  named facilities.
