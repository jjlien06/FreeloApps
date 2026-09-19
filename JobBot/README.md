# JobBot

A CLI that fills out — and, if you ask it to, submits — a job application
form, given your profile as JSON and the application's URL.

It's built on [`jev-browser-pilot`](https://github.com/aidil2105/jev-browser-pilot),
a lightweight browser-automation library where a small "decision-only" model
picks which button to click next (Apply / Continue / Submit) while jobbot's
own code fills in every text field from your profile — the model never sees
or writes your personal data. See [CLAUDE.md](CLAUDE.md) for how that's wired
together.

## Setup

```bash
cd JobBot
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

You also need a local Chrome or Chromium (`google-chrome`, `chromium`, or
`chromium-browser` on PATH, or set `JEV_PILOT_CHROME=/path/to/it`).

To use the real decision model (recommended for anything but local testing),
get a key from [console.typesafe.ai](https://console.typesafe.ai) and:

```bash
export TYPESAFE_API_KEY=your_key_here
```

## Usage

1. Copy `profile.example.json` to `profile.json` and fill in your details.
   Anything a form field asks that isn't in the fixed fields (name, email,
   phone, links, address, cover letter, ...) goes in `answers` as
   `{"the question, as worded on the form": "your answer"}` — matched by
   substring, so it doesn't need to be exact.

2. Dry run first — fills page one, previews the model's next click, clicks
   nothing:

   ```bash
   python -m jobbot apply --url "https://example.com/careers/123/apply" --profile profile.json
   ```

3. Once that looks right, let it actually click through and submit:

   ```bash
   python -m jobbot apply --url "https://example.com/careers/123/apply" --profile profile.json --submit
   ```

   Add `--verifier 'text-contains:some phrase'` for the confirmation text
   your target site actually shows — the default (`text-contains:thank you`)
   is a guess. Note: if you pass more than one `--verifier`, jev_pilot
   requires *all* of them to hold at once (they're ANDed), so most of the
   time you want exactly one. Use `--show-browser` to watch it work instead
   of running headless, and `-v` for verbose jev_pilot output.

## Testing it without touching a real site

```bash
python tests/smoke_test.py
```

This serves a two-page fake application from `tests/fixtures/` on
localhost and drives jobbot through it with `--provider mock` (a free,
offline keyword-matching stand-in for the real decision model — no API key,
no network). Run this after touching `jobbot/apply.py` or
`jobbot/formfill.py`, before pointing jobbot at anything real.

## Safety notes

- Every run is confined to the target URL's own host; a redirect off-site
  stops it rather than following along.
- Without `--submit`, jobbot fills the first page and previews the model's
  first click — it never actually presses a button.
- There's no file-upload support yet (resume/cover-letter files, not text) —
  see CLAUDE.md.
- Many ATS platforms' terms of service restrict automated applications.
  Check the specific site's terms before pointing this at it, and use
  `--submit` deliberately, one application at a time.

## Status

This was built quickly against `jev-browser-pilot`'s source as of September
2026, before it had a tagged release — pin a version in `requirements.txt`
once one exists. It has not yet been run end-to-end against a real
`TYPESAFE_API_KEY` or a real job site in this environment; run the smoke
test above first, then try a dry run against a real application before
trusting `--submit`.
