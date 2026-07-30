# Heft

An iOS photo browser that sorts your library by **file size**, so you can find the 4K
videos and burst sequences quietly eating tens of gigabytes — and delete them in bulk.

Photos.app has no way to sort by size. This does.

## What it does

- Grid of every photo and video in your library, each cell badged with its size
- Sort by **largest / smallest / newest / oldest**; filter to photos, videos, or all
- Running total of your library's measured footprint in the header
- Tap any item for a full-screen view with size, dimensions, duration, date, filename
- **Select** mode: multi-select, watch the running "N items · 4.2 GB" total, delete in
  one shot. Deleted items go to Recently Deleted and stay recoverable for 30 days.
- **Export & Delete**: copy originals to an external drive, verify them, and only then
  delete from the library.
- **Convert RAW**: turn camera RAW / Apple ProRAW into HEIC or JPEG, optionally deleting
  the RAW original once the replacement is confirmed present.

## Convert RAW

RAW assets are flagged with a yellow **RAW** badge and can be isolated with the **RAW**
media filter. Detection is free: it tests whether any `PHAssetResource`'s UTI conforms to
`public.camera-raw-image` (Apple ProRAW's `com.adobe.raw-image` conforms too), using the
resource list the size pass already enumerates.

In Select mode, a **Convert N RAW to HEIC** button appears whenever the selection contains
RAW. The confirmation offers three routes: convert and delete the originals, convert and
keep them, or convert to JPEG and keep them.

Rendering goes through `PHImageManager` at `PHImageManagerMaximumSize` with
`version = .current`, so the output matches what Photos already shows you — including your
edits — rather than a differently-demosaiced reinterpretation. The encoder falls back from
HEIC to JPEG where HEIC encoding isn't available.

Order of operations, which is what makes deletion safe: render → encode → **decode the
encoded result to prove it's valid** → add to the library → **re-fetch by local identifier
to confirm it exists** → only then delete the original. Creation date, location, and
favourite status carry across. Anything that fails at any step keeps its RAW file.

Note that "convert and keep" makes your library **bigger**, not smaller — both copies then
exist. Only deleting the originals reclaims space.

## Export & Delete

Pick a destination once via **Options → Export destination → Choose folder…**, navigating
to your external drive in the system picker. The app stores a security-scoped bookmark, so
it doesn't have to ask again.

In Select mode, an **Export to <drive> & Delete** button appears — but only while that
bookmarked folder currently resolves and is writable. Unplug the drive and the button
disappears on the next foreground.

> **Why it works that way:** iOS has no API for enumerating mounted volumes. A sandboxed
> app reaches external storage only through a URL the user hands it via the document
> picker, so "is a drive connected?" genuinely cannot be asked directly. Bookmark
> reachability is the closest honest proxy.

The safety contract: an asset is deleted **only** when every one of its resources was
written to the destination and verified. Verification is two-tier, because a byte count
isn't always available:

1. **Exact byte match** when PhotoKit reports the resource's `fileSize`.
2. **Content verification** when it doesn't — which is common precisely for the
   iCloud-optimized originals downloaded mid-export, i.e. the files most exposed to a
   truncated write. Images must decode their actual pixel data (a thumbnail forced *from
   the image*, never the embedded preview, so a header-only truncation still fails);
   videos must load tracks and report a real duration.

Failing either tier is a failure, and failures are never deleted — they stay in your
library and are listed by name in the summary. There is deliberately no third tier that
passes on "the file is non-empty": accepting a nonzero byte count as proof would let a
40-byte truncation of a 4 GB video authorise deleting the original.

Unlike size measurement, export **does** allow network access, so iCloud-only originals are
pulled down first; otherwise the app would report success for a file it never copied.

Files land in a `Heft Export` subfolder, named `<yyyy-MM-dd_HHmmss>_<original>.<ext>`
with a numeric suffix on collision (every camera roll has several `IMG_0001.JPG`).

The destination is remembered permanently. Unplug the drive and the button is replaced by
a "Reconnect <name> to export" hint; plug it back in and the button returns on its own
within ~3 seconds. It never asks you to pick the folder again. Reachability is re-tested on
foreground, on entering Select mode, and on a 3-second poll while selecting — iOS emits no
volume-mount notification an app can observe, so polling is the only option.

### Why export can look frozen

`PHAssetResourceManager.writeData` has to **download the original from iCloud** when the
local copy is optimized away. Locally-resident files are effectively instant — measured at
83.5 MB across 6 assets, including a single 69 MB file, in **0.07 s**. So any wait you see
is network transfer, not the exporter working.

To make that legible rather than looking like a hang, the sheet shows byte-weighted
progress (item counting sits at 0% for the entire first file), sub-file progress via
`PHAssetResourceRequestOptions.progressHandler` (which only fires during iCloud
downloads — that's exactly the slow case), a live elapsed clock on a 1-second tick,
throughput, an ETA, and a **Cancel** button. Cancelling takes effect between files, since
`writeData` exposes no cancel; it skips deletion entirely.

### Debug smoke test

`Heft/Debug/ExportSmokeTest.swift` (wrapped in `#if DEBUG`, so it never ships in Release)
runs the export headlessly, bypassing the document picker — useful because verifying the
real flow otherwise needs taps against a physical drive:

```
xcrun simctl launch booted com.jeremylien.Heft -HeftExportSmokeTest /abs/path/to/dest
# results land in <app-container>/Documents/smoke.log
```

It logs every progress tick with timestamps, per-resource reported vs. written bytes, and
the final verified count. Note the app container UUID changes on reinstall — re-read it
with `xcrun simctl get_app_container booted com.jeremylien.Heft data` *after* installing.

## Requirements

- **Xcode 16 or later** (the project uses the synchronized-folder project format).
  Not currently installed on this machine — grab it from the Mac App Store.
- iOS 17+ on the target device.
- An iPhone. The Simulator works, but its stock library is a handful of images, so
  there's not much to sort.

## Running it

1. `open ~/Developer/Heft/Heft.xcodeproj`
2. Select the **Heft** target → **Signing & Capabilities**.
3. Set **Team** to your Apple ID (add one under Xcode → Settings → Accounts if needed).
4. Change **Bundle Identifier** from `com.example.Heft` to something unique to you,
   e.g. `com.jeremylien.Heft`. Free-tier signing rejects `com.example.*`.
5. Plug in your iPhone, pick it as the run destination, and hit ⌘R.
6. On first launch, grant **Full Access** when iOS asks for photo permission. Limited
   access works, but you'll only see the assets you hand-picked.

### Free Apple ID signing

A free account signs the app for **7 days**, after which it stops launching and you
re-run from Xcode to refresh it. You'll also need to trust the developer certificate
once, under Settings → General → VPN & Device Management.

## How sizes are measured

PhotoKit deliberately exposes no public file-size API, so `AssetSizer` works in two
tiers:

1. **Fast pass** — reads the undocumented `fileSize` key off each `PHAssetResource`
   via KVC. Costs nothing and answers the large majority of a library in seconds.
2. **Deep pass** — for whatever tier one couldn't answer, streams the resource through
   `PHAssetResourceManager` and counts bytes. Public and accurate, but it has to touch
   the file, so it runs in the background after the grid is already usable.

Both tiers sum **every** resource attached to an asset. For a Live Photo that's the
still plus the paired video; for an edited photo it's the original plus the rendered
version. That total is what deleting the asset actually reclaims, which is the number
you care about.

Results are cached to a binary plist in Application Support, keyed by local identifier
and invalidated when an asset's modification date moves — so relaunches are instant.
**Sort → Rescan sizes** throws the cache away and re-measures.

Network access is disabled during measurement, so scanning never silently pulls
originals down from iCloud or burns cellular data. The cost: assets that live only in
the cloud may not resolve. Those show `—` and sort to the **tail** of size orders
rather than being treated as zero bytes — an unknown is not a small file.

> **App Store note:** tier one reads a private key. That's fine for personal and
> sideloaded builds but is a plausible rejection trigger for App Store review. To make
> the app submission-safe, delete `AssetSizer.fastSize` and have `AssetSizeIndex` send
> everything through `streamedSize`. Correctness is unaffected; a full scan just gets
> considerably slower.

## Layout

```
Heft/
├── HeftApp.swift               App entry point
├── Model/
│   ├── AssetItem.swift         An asset plus its resolved size
│   ├── AssetSizer.swift        The two-tier size resolver
│   ├── AssetSizeIndex.swift    Staged indexing + cache coordination
│   ├── SizeCacheStore.swift    Disk persistence for measurements
│   ├── LibraryModel.swift      Fetch, sort, filter, selection, deletion
│   ├── LibrarySort.swift       Sort orders, media filters, comparators
│   ├── ByteFormatting.swift    Byte and duration rendering
│   └── PhotoLibraryAuthorizer.swift
└── View/
    ├── RootView.swift          Navigation, toolbar, sort menu
    ├── PhotoGridView.swift     Grid, header stats, scan progress
    ├── AssetCell.swift         Thumbnail + size/video badges + selection
    ├── AssetThumbnail.swift    PHImageManager-backed image loading
    ├── AssetDetailView.swift   Full-screen viewer + metadata
    ├── SelectionBar.swift      Selection total + batch delete
    └── PermissionGateView.swift
```

The project uses a synchronized root group: every `.swift` file under `Heft/` is
compiled automatically. Add files by dropping them in the folder — no project edits.

## Known gaps

- **No test target.** Sort comparators, byte formatting, and cache encoding are pure
  and dependency-free so they're straightforward to test, but no target is wired up.
- **The picker and bookmark path is still untapped.** The exporter itself is verified
  (6/6 assets, 83.5 MB, byte-exact) via the debug smoke test, but choosing a destination
  through the document picker and resolving its bookmark after a real drive reconnect
  needs physical taps and hardware. The bookmark-creation bug (missing security-scoped
  access around `bookmarkData()`) was found by inspection, not by running it.
- **iCloud download progress is unverified.** `progressHandler` is wired correctly per
  Apple's contract, but it only fires for cloud-resident originals, and simulator assets
  are all local — every measured tick reported `frac=0.000`. Whether the bar moves
  smoothly during a real iCloud fetch can only be confirmed on-device.
- Very large libraries (50k+) will feel the `LazyVGrid` at the extremes of scrolling.
- Sorting mid-scan re-sorts every ~1500 newly measured assets, so the grid shuffles
  while the fast pass runs. It settles once the pass completes.
