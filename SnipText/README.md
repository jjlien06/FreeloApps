# SnipText

A native macOS menu-bar OCR utility: press a hotkey, drag a box around any text you can
see, and the recognized text lands on your clipboard. Everything runs on-device via
Apple's Vision framework — no internet, nothing uploaded.

Because it reads pixels, the source doesn't matter: photos, screenshots, locked-down
PDFs, videos, presentations, any app window. It also decodes QR codes and barcodes.

## Usage

| Action | Default shortcut |
|---|---|
| Capture text → clipboard | ⇧⌘2 |
| Capture text → clipboard + speak it aloud | ⌥⇧⌘2 |

- **During a capture**: drag to select; hold **⌥** to invert the line-break setting for
  that capture only; **Esc** or right-click cancels.
- **Menu bar** (viewfinder icon): capture, capture & speak, copy all history, clear
  history, Settings, quit.
- **History**: every capture is appended to a persistent buffer
  (`~/Library/Application Support/SnipText/history.txt`) that survives restarts.
  "Copy All History" puts the whole buffer on the clipboard. Clearing is not undoable.
- **Settings** (⌘, from the menu): join vs. preserve line breaks, auto-open captured
  links (http/https only), shutter sound, and both shortcuts are re-recordable.

OCR joins hard line breaks into spaces by default — OCR on a justified column or slide
returns a break wherever the visual line ended, which is almost never what you want
when pasting into prose. Turn it off (or hold ⌥) when you want the layout preserved.

## Build & install

```sh
make test      # unit tests, incl. a headless Vision OCR round-trip
make run       # build → assemble signed SnipText.app → install to ~/Applications → launch
make logs      # stream the app's os_log output
```

First run: macOS asks for **Screen Recording** access (System Settings → Privacy &
Security → Screen Recording → enable SnipText, then relaunch the app). A headless
pipeline check is available anytime: `open ~/Applications/SnipText.app --args --selftest`
captures the top-left corner of the main display and puts the OCR result on the
clipboard (`pbpaste` to inspect).

## Signing / permission notes

- The bundle is signed with the local Apple Development identity (see
  `Support/bundle.sh`). This keeps the Screen Recording grant stable across rebuilds —
  ad-hoc signing would reset the permission on every build.
- Apple Development certificates expire yearly; after re-signing with a renewed cert,
  macOS will re-prompt for Screen Recording once.
- macOS periodically shows a "continue to allow SnipText to record your screen"
  confirmation — that's standard OS behavior for all screen-capture apps.
- Never launch the bare binary from a terminal to test capture (`swift run`): TCC would
  attribute the permission to the terminal, not the app. Use `make run`.

## Architecture

- `Sources/SnipTextCore` — UI-free, unit-tested: Vision recognition
  (`RecognizeTextRequest` + `DetectBarcodesRequest`), line-break post-processing, URL
  detection, history persistence.
- `Sources/SnipText` — the app: SwiftUI `MenuBarExtra` + Settings, AppKit selection
  overlay (per-screen panels, invisible to ScreenCaptureKit via `sharingType = .none`),
  ScreenCaptureKit screenshot service, KeyboardShortcuts-based global hotkeys,
  AVSpeechSynthesizer TTS, HUD confirmation.
