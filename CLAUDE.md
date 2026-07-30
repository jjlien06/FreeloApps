# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An iOS app answering one question for U-M Ann Arbor: **where can I park free, and
until when?** U-M lots are permit-gated during posted enforcement hours and open to
anyone outside them; those hours differ per lot. "Free" means *no payment and no
permit required*, which is distinct from *usable* — see the Tier/PermitClass note
below.

## Commands

Domain logic lives in a local SwiftPM package, so most work needs no simulator:

```sh
cd Packages/ParkingKit
swift test                                      # 59 tests, under a second
swift test --filter FacilityFilterTests         # one suite (type name, NOT the display name)
swift test --filter FacilityFilterTests/tierFilter   # one test
swift test --filter "DST|Permit"                # regex across suites
```

`--filter` matches Swift type/function identifiers. The `@Suite("...")` display
string does not match — `--filter "Facility filtering"` silently runs 0 tests.

The CLI is the fastest way to check the engine against what LTP publishes:

```sh
swift run parkingctl                            # what is free right now
swift run parkingctl --at "2026-08-05 19:00"
swift run parkingctl --permit blue
swift run parkingctl --lot S8                   # one lot's week as an hour grid
swift run parkingctl --live                     # fetch live occupancy
```

App build and run:

```sh
xcodegen generate                               # required after adding/removing app source files
xcodebuild -project MParking.xcodeproj -scheme MParking \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
xcrun simctl launch <device> com.jeremylien.MParking -mparking.startTab settings
xcrun simctl location <device> set 42.2764,-83.7385   # Central Campus, so distances are real
```

`xcodegen generate` is mandatory when app source files are added or deleted —
`project.yml` is the source of truth and a stale `.xcodeproj` fails with "Build
input file cannot be found". The `.xcodeproj` is committed anyway so the repo opens
without tooling.

`-mparking.startTab free|map|settings` is read via `UserDefaults` from launch
arguments; use it to open a screen directly instead of driving the GUI.

Rebuilding the dataset:

```sh
python3 tools/build_dataset.py                  # geocodes new addresses via Nominatim (1 req/sec)
python3 tools/build_dataset.py --no-geocode     # cache only, fast
```

## Architecture

### Two layers, and why the boundary is where it is

`Packages/ParkingKit/` is pure domain logic — no UIKit, no SwiftUI, no I/O in the
core types. `MParking/` is the SwiftUI app. **The app target has no test target.**
Anything that needs testing must live in ParkingKit; that is why `FacilityFilter`
is a ParkingKit value type rather than state on `AppModel`. `AppModel` exposes
`systemFilter` / `campusFilter` / `tierFilter` / `hideNeverFree` as computed
pass-throughs onto a single `FacilityFilter`, so changing the filter's shape means
touching both files.

### The dataset is generated — never hand-edit it

`Packages/ParkingKit/Sources/ParkingKit/Resources/facilities.json` is output.
Source of truth is `tools/raw/*.tsv` (hours transcribed verbatim, each file
carrying its source URL) plus the mapping tables in `tools/build_dataset.py`.
Editing the JSON directly gets clobbered on the next build.

To change hours: edit the TSV, bump `HARVEST_DATE`, re-run the builder, run
`swift test` (dataset integrity tests live in `AvailabilityTests.swift`).

### Enforcement windows: the load-bearing invariant

An `EnforcementWindow` is confined to a **single day**, with `"24:00"` allowed as an
end time, and `start < end` always holds. Overnight and multi-day spans are split
across days *at build time* by `continuous()` in the builder — M93's `"6 am Mon –
1 am Sat"` becomes Mon 06:00–24:00, Tue–Fri full days, Sat 00:00–01:00.

This is deliberate: it keeps wrap-around arithmetic out of the Swift engine, which
is where off-by-one bugs in this kind of code live. If you add a new hours format,
expand it in the Python parser; do not teach `ParkingRules` about wrapping.
`DatasetTests.windowsWellFormed` enforces the invariant.

`isEnforced` is half-open — a window ending 17:00 does not cover 17:00 itself.

### The trust gate

A wrong "free" costs the user a ticket, so `ParkingRules.status` returns
`.unknown` for anything with `confidence != .verified` or
`enforcement.kind == .unknown`, **before** evaluating windows. Never route around
this to make a lot display as free. Two tests defend it, including one sweeping the
whole dataset at 30-minute intervals across a week.

Currently all 170 facilities are `verified`, so the "Check the sign" section is
empty in practice. That was earned by resolving DDA's gated-vs-metered lots from
their published rules, not by relaxing the gate.

### Tier vs PermitClass

`Tier` is what a lot *requires* (Blue, Gold, …). `PermitClass` is what the user
*holds*. They are separate types on purpose:

- `.freeToAll` — no permit, no payment. This is what "free" means everywhere.
- `.allowedWithPermit` — usable by this user, still not free.

`neverBecomesFree` is a property of the *facility*, so a Gold 24/7 lot counts as
never-free even for a Gold holder. The "hide never-free" filter (on by default,
20 lots) relies on that.

`PermitClass.afterHours` is time-bounded, not just tier-bounded — honoured in
Blue/Yellow/Orange but never Gold, and only outside Mon–Fri 05:00–15:00. It is
handled separately in `status` for that reason.

### Time

Every date computation goes through `Calendar` in `America/Detroit`
(`ParkingRules.timeZone`, mirrored by `Clock.calendar` in the app), so DST is the
calendar's problem rather than arithmetic. Tests cover both 2027 transitions.
`nextTransition` evaluates window boundaries rather than stepping through time.

### Live availability

Two independent, strictly optional sources. The free/paid answer never depends on
the network — a failure keeps the last figures and says so.

- **U-M occupancy**: HTML scrape of LTP's Parking Space Availability page,
  `?tier=both`. Parsers are pure functions over strings so they test against
  `Tests/ParkingKitTests/Fixtures/ltp-availability.html`. The page's row set
  changes through the day (facilities with no data vanish), so never assume a
  fixed roster.
- **Downtown counts**: `a2dda.org/map/AADDACount.json`.

Row labels differ from lot IDs, so `AvailabilityMatcher` checks the alias table
*first*, then falls back to a leading lot-ID token: `"P1 Parking Structure"` is
M15, and its leading `P1` would otherwise be misread as a lot ID. Aliases live in
`AVAILABILITY_ALIASES` in the builder and ship in the dataset.

### Network gotchas

`ltp.umich.edu` sits behind Cloudflare:

- `curl` gets **403** regardless of headers — it is fingerprinted on TLS, so a 403
  from curl does not mean the page is private or gone.
- Python `urllib` and Apple's `URLSession` get through.
- It **rate-limits** under repeated requests; retry with backoff. `ClientError.throttled`
  models a 403 as "try again later", not a real failure.

The DDA feed emits bad rows — a negative count was observed on facility 84.
Negatives are dropped rather than shown as "full"; a genuine `0` still means full.

DDA publishes no key→name mapping for its count feed (`80`, `87 S`, …) and it is
not in their ArcGIS layers either, so those counts are not yet attributed to named
facilities.

## UI conventions

Stock Apple idiom throughout: `List`/`Form`, `Section` header+footer, semantic
colours, Dynamic Type text styles, real `Toggle`/`Picker`/`DatePicker`,
`LabeledContent`, `ContentUnavailableView`. There is no custom palette or type
scale — `DesignSystem.swift` only defines colours that carry meaning (permit tiers
and the free/paid verdict) plus formatters. Light and dark both supported; do not
force a colour scheme.

The 24-hour `EnforcementRibbon` is the one bespoke element, modelled on
Settings › Battery. Each bar needs `.frame(maxWidth: .infinity)` or the strip
collapses into a row of dots.

Distances use `usage: .asProvided` when formatting `Measurement` — the default
localises the unit and turns 0.3 miles back into 1,392 feet.

26 of 170 facilities have no coordinates (addresses like "Palmer Drive-North Side"
do not geocode). They still list, without distance or a map pin, and sort last
within their status group.

## Caveats the app must keep stating

Entrance signage is authoritative, and football Saturdays, move-in and commencement
override normal enforcement. LTP says both explicitly; the UI repeats them rather
than quietly being wrong.
