# Cull — design

**Date:** 2026-08-01
**Status:** approved

## Problem

Culling a shoot is the slowest part of photography. Opening a folder in Preview
and dragging keepers around is tedious, and Lightroom is heavyweight for a first
pass. The need is a fast, keyboard-driven pass over a folder of photos that ends
with the keepers copied somewhere useful.

## Scope

A native macOS app that:

1. Opens a folder of photos and shows them one at a time, large.
2. Records a pass/fail verdict and a 0–5 star score per photo.
3. Persists those scores next to the photos so reopening the folder resumes.
4. Copies the passes into a subfolder when the pass is done.

Out of scope: editing, moving or deleting originals, recursion into subfolders,
RAW+JPEG pairing, cloud/library integration.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Platform | Native macOS app, SwiftUI, SwiftPM | Fast full-res decode of RAW, real folder access, matches existing tooling (SnipText) |
| Sandboxing | Non-sandboxed | Personal tool; avoids bookmark friction for arbitrary folders |
| Rating storage | `.cull.json` sidecar per folder | Never mutates originals, survives reopening, trivially exportable |
| File action | Copy passes to `./Selects/` | Non-destructive; originals are never moved or deleted |
| Formats | Everything ImageIO decodes (JPEG/HEIC/PNG + camera RAW) | Derived from `CGImageSourceCopyTypeIdentifiers()` rather than a hardcoded list |
| Traversal | Top level of the chosen folder only | Matches how shoots are dumped off a card |

## Rating model

Two independent axes:

- **Verdict** — `pass`, `fail`, or unrated. The cull decision.
- **Stars** — 0–5. The ranking.

They are independent so "passed but only worth 2 stars" is expressible, and the
filter can select on either. An optional free-text note rounds out the record.

## Sidecar format

`.cull.json`, written to the folder being culled:

```json
{
  "version": 1,
  "ratings": {
    "IMG_0001.CR3": { "verdict": "pass", "stars": 4, "note": "sharp" },
    "IMG_0002.JPG": { "verdict": "fail", "stars": 0 }
  }
}
```

Keyed by filename, not path, so the folder can be moved without losing scores.
Writes are atomic (temp file + `replaceItemAt`) and debounced. A file that fails
to parse is moved aside to `.cull.json.bak` and a fresh store is started, so a
corrupt sidecar can never take the app down or silently erase prior work.

## Keyboard map

| Key | Action |
|---|---|
| `←` / `→` | previous / next |
| `Space` | next |
| `P` / `X` / `U` | pass / fail / clear verdict |
| `1`–`5` | set stars |
| `0` | clear stars |
| `G` | grid ⇄ loupe |
| `Z` | 100% zoom toggle |
| `F` | cycle filter |
| `N` | edit note |
| `⌘O` | open folder |
| `⌘E` | export selects |

Verdict keys auto-advance to the next photo by default (toggleable). That is
what turns an 800-shot folder into a few minutes of work.

## Components

**CullCore** (no UI, fully unit-tested):

- `PhotoItem` — identity, URL, filename, byte size.
- `FolderScanner` — enumerates the top level of a folder, filters to decodable
  image types, sorts by natural filename order.
- `Rating` / `Verdict` — the rating model, `Codable`.
- `RatingStore` — owns `.cull.json`: load, mutate, atomic save, corruption
  recovery.
- `ExportService` — copies passes into a destination folder; reports copied,
  skipped-existing, and failed counts. Never overwrites.

**Cull** (SwiftUI app):

- `CullSession` — observable state: items, cursor, filter, current folder.
  Applies verdicts and advances the cursor.
- `ImageLoader` — an actor with two tiers: `CGImageSourceCreateThumbnailAtIndex`
  thumbnails for the filmstrip and grid, and a downsampled full-res decode for
  the loupe. `NSCache` with a cost limit; prefetches ±3 neighbours so RAW
  decodes never stall navigation.
- `ContentView` / `LoupeView` / `FilmstripView` / `GridView` — dark, photo-first
  chrome: the image gets the space, the controls stay out of the way.

## Failure handling

- An undecodable file renders as a placeholder card; it never crashes the view.
- A corrupt sidecar is backed up and rebuilt (above).
- Export collisions are skipped and reported, never overwritten.
- A source file that vanished between scan and export is reported as failed.

## Testing

Unit tests over temp fixture directories:

- `FolderScanner` — mixes supported, unsupported, and hidden files; natural sort
  ordering; missing directory.
- `RatingStore` — round-trip, unknown-key tolerance, corrupt-file recovery,
  atomic write leaves no partial file.
- `ExportService` — copies only passes, skips collisions, reports missing
  sources.

Image decoding is exercised by hand rather than in unit tests; the decode path
is isolated behind `ImageLoader` so the tested core never needs real RAW files.

## Performance targets

- Scan of a 2,000-file folder: under one second.
- Filmstrip scrolling: smooth at 60fps on cached thumbnails.
- Loupe advance on RAW: under ~400ms with prefetch warm.

**Measured after implementation** (Canon CR3, external drive): forcing a full
RAW render for a 240px thumbnail costs 4755ms against 85ms when the embedded
preview is allowed to satisfy it. Thumbnails therefore use
`kCGImageSourceCreateThumbnailFromImageIfAbsent`, and only the loupe and zoom
force the full render (~145ms at 2400px). Cold reads off an external drive
dominate the first frames of a shoot regardless of decode strategy.
