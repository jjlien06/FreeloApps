# Cull

A keyboard-driven photo culler for macOS. Point it at a folder off a memory card,
rip through the shoot one frame at a time marking passes and stars, then copy the
keepers into a `Selects` folder. Nothing else is touched.

Culling is the slow part of shooting: Preview can't rate, and Lightroom is a lot of
ceremony for a first pass. Cull does the first pass and nothing more.

## Usage

Open a folder (⌘O), drop one on the window, or `open -a Cull ~/Pictures/Shoot`.
Then keep your hands on the keyboard:

| Key | Action |
|---|---|
| `←` `→` (or `↑` `↓`) | Previous / next |
| `Space` | Next |
| `P` | Pass |
| `X` | Fail |
| `U` | Clear the verdict |
| `1`–`5` | Set stars |
| `0` | Clear stars |
| `G` | Grid ⇄ loupe |
| `Z` | Zoom (click the photo does the same) |
| `F` | Cycle the filter |
| `N` | Jump to the note field |
| `⌘O` / `⌘E` | Open folder / export selects |

**Verdict and stars are independent.** `P`/`X` is the keep-or-cut decision; stars are
the ranking. A shot can be a keeper that's only worth two stars, or a four-star frame
you still cut. The filter selects on either.

`P`, `X` and `U` advance to the next photo automatically — that's what makes an
800-shot folder a few minutes of work. Turn it off with the Auto-advance checkbox.
Stars deliberately don't advance, so you can score and then decide.

Rating a photo while the filter is set to *Unrated* drops it out of view, and the
cursor stays where it is — so filtering to Unrated and hammering `P`/`X` walks you
through exactly the frames you haven't judged yet.

## Where the ratings go

A `.cull.json` sidecar in the folder itself:

```json
{
  "version": 1,
  "ratings": {
    "IMG_0001.CR3": { "verdict": "pass", "stars": 4, "note": "sharp" }
  }
}
```

Keyed by filename, so moving or renaming the folder doesn't lose the pass. Writes are
atomic and debounced. **Your photos are never modified** — no EXIF writes, no moves,
no deletes. Export copies. A sidecar that won't parse is moved aside to
`.cull.json.bak` and a fresh one is started rather than silently wiping prior work.

Because it's plain JSON keyed by filename, it's easy to consume elsewhere:

```sh
jq -r '.ratings | to_entries[] | select(.value.verdict=="pass") | .key' .cull.json
```

## Formats

Whatever ImageIO decodes on your Mac — JPEG, HEIC, PNG, and camera RAW (CR2/CR3, NEF,
ARW, DNG and the rest). The supported list is derived from
`CGImageSourceCopyTypeIdentifiers()` at runtime rather than hardcoded, so it tracks
whatever macOS gains support for.

Only the top level of the chosen folder is scanned; subfolders are ignored. RAW and
JPEG of the same name are separate items. A file that won't decode shows a placeholder
card and stays ratable instead of breaking the view.

RAW thumbnails come from the preview already embedded in the file; only the loupe and
zoom force a full RAW render. Measured on a Canon CR3 off an external drive, that's
**85ms instead of 4755ms** per filmstrip thumbnail — the difference between a folder
of 200 CR3s being usable and being unusable. Cold reads off a slow external drive are
still the floor: the first frames of a shoot are the slow ones, then ±3 prefetching
stays ahead of you.

## Build & install

```sh
make test      # 37 unit tests over the scanner, rating store, export and session
make run       # build → assemble signed Cull.app → install to ~/Applications → launch
```

Signed with your Apple Development certificate so the folder-access (TCC) grants for
Desktop/Documents/Downloads survive rebuilds; ad-hoc signing would re-prompt every
time.

## Architecture

`CullCore` holds everything with behaviour worth testing and no view code:

- `FolderScanner` — top-level enumeration, ImageIO-derived format filter, natural sort
- `RatingStore` — the `.cull.json` sidecar: load, mutate, atomic save, corruption recovery
- `ExportService` — copies passes; never overwrites, reports skips and failures
- `CullSession` — the pass itself: cursor, filter, verdicts, auto-advance

The `Cull` target is SwiftUI on top of that, plus `ImageLoader`, an actor that decodes
off the main thread at three sizes (filmstrip, grid, loupe) with an `NSCache`, request
coalescing, and ±3 prefetching so RAW navigation doesn't stall.

The design doc is in [docs/superpowers/specs](docs/superpowers/specs).
