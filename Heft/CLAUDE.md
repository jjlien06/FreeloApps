# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Heft is a SwiftUI + PhotoKit iOS app that sorts the photo library by **file size** — the
thing Photos.app won't do — so large videos and bursts can be found and removed. It can
also copy originals to an external drive before deleting them, and convert RAW to HEIC.

iOS 17 minimum, no third-party dependencies, Swift 5 language mode.

## Commands

There is no test target. Verification is done by building and by the debug harness below.

```sh
# Build for simulator (no signing needed — use this for fast iteration)
xcodebuild -project Heft.xcodeproj -scheme Heft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build

# Build + sign for a physical device
xcrun devicectl list devices                       # get the device UDID
xcodebuild -project Heft.xcodeproj -scheme Heft \
  -destination 'platform=iOS,id=<UDID>' -configuration Debug \
  -allowProvisioningUpdates build

# Install / launch on device
xcrun devicectl device install app --device <UDID> \
  ~/Library/Developer/Xcode/DerivedData/Heft-*/Build/Products/Debug-iphoneos/Heft.app
xcrun devicectl device process launch --device <UDID> com.jeremylien.Heft
```

`xcodebuild` output is enormous; filter it with `grep -E '^\*\* |error:'`.

No `DEVELOPMENT_TEAM` is committed. Set Team once in Xcode → Signing & Capabilities;
free-tier signing expires after 7 days and needs a re-run from Xcode.

## Debug harness (`Heft/Debug/ExportSmokeTest.swift`, `#if DEBUG` only)

The export and conversion flows normally need taps against real hardware, so they can be
driven headlessly instead. This is the closest thing to a test suite — use it after
touching either pipeline.

```sh
# Export: writes to <dest>/Heft Export, logs every progress tick and verification result
xcrun simctl launch booted com.jeremylien.Heft -HeftExportSmokeTest /abs/path/to/dest

# RAW conversion: renders, encodes, adds to library, reports before/after bytes
xcrun simctl launch booted com.jeremylien.Heft -HeftConvertSmokeTest

# Land directly on a filtered grid (driving the menu needs taps)
xcrun simctl launch booted com.jeremylien.Heft -HeftStartFilter raw

# Results go to a file, NOT stdout — `--console` has to hold the process open to capture
# prints, which makes it useless for scripted runs.
cat "$(xcrun simctl get_app_container booted com.jeremylien.Heft data)/Documents/smoke.log"
```

The app container UUID **changes on every reinstall** — re-read it with
`get_app_container` *after* installing, or you will read a stale path.

Populate a simulator library with `xcrun simctl addmedia booted <files>`. Generate test
images with widely varying sizes and *noisy* content — a flat fill compresses to almost
nothing and makes size behaviour untestable.

## The invariant that matters most

**Nothing is deleted that has not been positively verified.** Both destructive flows are
built around this, and it must not be weakened.

Export (`AssetExporter.swift`) verifies in two tiers, because a byte count is not always
available:

1. **Exact byte match** when PhotoKit reports the resource's `fileSize`.
2. **Content verification** (`FileIntegrity.swift`) when it does not — images must decode
   real pixel data (a thumbnail forced *from the image*, never the embedded preview, so a
   header-only truncation still fails); videos must load tracks and report a real duration.

There is deliberately **no** third tier that passes on "the file is non-empty". That
bug existed once: a missing `fileSize` collapsed to `0`, the mismatch check was gated on
`expected > 0`, and so a 40-byte truncation of a 4 GB video would authorise deleting the
original. Crucially, `fileSize` is nil precisely for iCloud-optimized originals — the ones
downloaded mid-export and most exposed to a partial write. Do not reintroduce that shape.

Conversion (`RawConverter.swift`) applies the same principle by ordering: render → encode →
**decode the encoded result to prove it is valid** → add to library → **re-fetch by local
identifier to confirm it exists** → only then is the original eligible for deletion. The
placeholder identifier from `performChanges` is only a promise; the re-fetch is what proves
the replacement landed.

Deletion is always a *single* batched `performChanges` for the whole selection, so iOS
shows one system confirmation rather than one per asset. Failures are never deleted and are
listed by name in the summary sheet.

## Size measurement, and why it is staged

PhotoKit exposes no public file-size API. `AssetSizer.swift` resolves it in two tiers:

1. `fastSize` reads the **undocumented `fileSize` KVC key** off each `PHAssetResource`.
   Free, and answers most of a library. **This is an App Store rejection risk** — fine for
   personal/sideloaded builds. To make the app submittable, delete `fastSize` and route
   everything through `streamedSize`; correctness is unaffected, a full scan just gets far
   slower.
2. `streamedSize` counts bytes as `PHAssetResourceManager` streams the resource. Public and
   accurate, but must touch the file.

Sizes **sum every resource** on an asset (a Live Photo's still + paired video; an edited
photo's original + render), because that total is what deleting actually reclaims.

Measurement runs with `isNetworkAccessAllowed = false` so scanning never silently pulls
from iCloud. Consequence: cloud-only assets may not resolve. They show `—` and sort to the
**tail** of size orders, never treated as zero — an unknown is not a small file.

Export is the deliberate exception: it *does* allow network access, otherwise the app would
report success for a file it never actually copied.

`AssetSizeIndex.swift` stages the work so the grid is never blocked: cache sweep (instant)
→ fast pass in 250-item chunks on a detached task → deep streaming pass for the remainder.
It hands results back in batches; `LibraryModel.apply` re-sorts only every 6 batches (plus
once at the end) because re-sorting a large library on every batch churns badly.

### Cache landmine

`CachedSize.isRaw` is `Bool?`. **`nil` means the entry predates RAW detection and must be
re-measured, not treated as a cache hit.** Treating it as a hit skips the only pass that
detects RAW, so RAW stays permanently unflagged for every already-measured asset. Same
reasoning applies to any future field added to `CachedSize`: an entry missing it is stale,
not valid.

## External-drive export

iOS has **no API to enumerate mounted volumes**. A sandboxed app reaches external storage
only through a URL the user hands it via the document picker, so "is a drive connected?"
cannot be asked directly. `ExportDestination.swift` answers it indirectly: keep a
security-scoped bookmark and test whether it still resolves and is writable. Unplugged →
bookmark stops resolving → the button hides. A 3-second poll while in Select mode is the
only way the button can reappear on its own, since there is no mount notification.

Two traps in that file:

- `bookmarkData()` **must** be called inside a `startAccessingSecurityScopedResource()`
  window, or the bookmark silently fails to persist and the user is forced to re-pick.
- `withAccess` calls `check`, not `probe`. `probe` opens its own scope and its `defer`
  would close the window `withAccess` just opened. Nested start/stop is not reference
  counted here.

## SwiftUI conventions with teeth

**Sheets read the model from `@Environment`, never take a value parameter.** `ExportSheet`
and `ConversionSheet` read `model.exportRun` / `model.conversionRun` directly. A run struct
passed in at presentation time is a snapshot, and any doubt about whether a sheet's content
closure re-evaluates becomes a frozen progress bar.

**Thumbnails put the image in `.overlay`, never as a `ZStack` sibling.** A ZStack adopts its
largest child's size and `.scaledToFill()` deliberately overflows whatever it is proposed,
so a ZStack grows to the scaled image and spills onto neighbouring cells — `.clipped()`
becomes a no-op because it clips already-inflated bounds. Overlay content cannot influence
its parent's size. See `AssetThumbnail.swift`. Relatedly, grid columns use `.flexible()`,
not hand-computed `.fixed(side)`, which can round a pixel past the available width and wrap
the last column.

**`PHImageManager` result handlers can fire synchronously** with `.opportunistic` delivery,
before `requestImage` returns. `AssetThumbnail.load` guards against stashing a dead request
ID over the handler's cleanup. When a full-quality image is required (`RawConverter`,
`AssetDetailView`), ignore callbacks where `PHImageResultIsDegradedKey` is true or you will
encode the blurry placeholder.

**Progress must be byte-weighted, not item-counted.** Item counting sits at 0% for the
entire first file, which with one large video reads as a hang. `PHAssetResourceRequestOptions
.progressHandler` supplies sub-file movement, but it **only fires during iCloud downloads** —
locally-resident files complete too fast to report anything. Both progress sheets also run a
1-second `TimelineView` tick so the elapsed clock moves even when bytes stall.

## Concurrency shape

`LibraryModel` and `ExportDestination` are `@MainActor @Observable`. `AssetExporter` and
`RawConverter` are `nonisolated` static async, so per SE-0338 they run on the cooperative
pool rather than the main actor even when awaited from it — heavy file I/O does not block
the UI. Progress callbacks are declared `@MainActor` and hop back per tick.

`SWIFT_VERSION` is pinned to 5.0 deliberately: the code passes non-`Sendable` `PHAsset`
values into detached tasks, which is a warning in Swift 5 mode and an error in Swift 6.
Bumping the language mode means auditing every one of those crossings first.

## Known gaps

- **No test target.** `ByteFormatting`, `AssetSorting` and the cache codec are pure and
  dependency-free, so they are straightforward to cover if one is added.
- **The export ETA has never produced a number.** `ExportRun.bytesPerSecond` requires
  `elapsed > 1.5s` and measured exports finish in ~0.1s, so the guard always returns nil.
  It is also wrong by construction: `LibraryModel` builds `totalBytes` with
  `$1.bytes ?? 0`, so cloud-only assets — the slowest ones — contribute zero, making the
  denominator too small and letting the bar reach 100% while work continues. It is advisory
  only and gates nothing.
- **iCloud paths are unverified.** Every measured smoke run was local, so
  `progressHandler`, the content-verification tier, and download timing have only been
  reasoned about, not observed.
- **RAW detection is unverified against real camera files.** It tests UTI conformance to
  `public.camera-raw-image` and was proven against a synthetic DNG typed
  `com.adobe.raw-image`. A `#if DEBUG` `NSLog("HEFT| raw ...")` fires only for RAW-ish
  assets to diagnose this on real hardware.
- RAW conversion holds a full-size `CGImage` plus encoded `Data` in memory at once
  (~195 MB for a 48 MP file). Sequential, so one at a time, but untested under memory
  pressure.
