# JobBot

A CLI that fills out — and, if you ask it to, submits — a job application
form, given your profile as JSON and the application's URL.

It's built on [`jev-ultrafast`](https://github.com/browser-use/jev-ultrafast)
("Jev Ultrafast"), which uses TypeSafe's `Jev` model to pick which page
element to click/type/select next (no screenshots, one small API call per
step) instead of a full vision-language-model agent loop. See
[CLAUDE.md](CLAUDE.md) for exactly what each model call sees and how jobbot
keeps it from clicking Submit until you say so.

## Setup

```bash
cd JobBot
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

`jev-ultrafast` isn't on PyPI yet, so `requirements.txt` installs it straight
from GitHub. It manages its own headless Chromium (via its `browser-harness`
dependency) — you don't need to install a browser yourself.

You need two API keys:

```bash
export TYPESAFE_API_KEY=your_typesafe_key      # console.typesafe.ai — the decision model
export TEXT_MODEL_API_KEY=your_deepseek_key    # or point TEXT_MODEL_BASE_URL/TEXT_MODEL at another
                                                # OpenAI-compatible endpoint, e.g. OpenRouter
```

## Usage

1. Copy `profile.example.json` to `profile.json` and fill in your details.
   Anything a form asks that isn't one of the fixed fields (name, email,
   phone, links, address, cover letter, ...) goes in `answers` as
   `{"the question, roughly as worded on the form": "your answer"}`.

2. Dry run first — fills every page it can reach, then stops the instant
   it's about to click something that looks like a final Submit/Apply:

   ```bash
   python -m jobbot apply --url "https://example.com/careers/123/apply" --profile profile.json
   ```

3. Once that looks right, let it actually press submit:

   ```bash
   python -m jobbot apply --url "https://example.com/careers/123/apply" --profile profile.json --submit
   ```

   Use `--screenshots --record-dir ./run1` to save a picture after every
   action if you want to review what it did.

## Testing it without touching a real site

```bash
python tests/local_check.py
```

This points jobbot at a local two-page fake application
(`tests/fixtures/fake_application.html`) instead of a real job site — but it
still calls the real TypeSafe and text-generation APIs, since jev-ultrafast
has no free/offline mode. Set both API keys first. Run this after touching
`jobbot/apply.py` or `jobbot/profile.py`, before pointing jobbot at anything
real.

## Safety notes

- Every run stops if the browser leaves the target URL's own host (or a
  subdomain of it) — see `--allowed-host` to widen that if a real
  application flow legitimately hands off to another domain (e.g. an SSO
  login).
- Without `--submit`, jobbot fills what it can and stops right before any
  button whose label looks like a final submission — it does not rely on
  the decision model to police itself; the stop is enforced in jobbot's own
  code (see CLAUDE.md).
- There's no file-upload support yet (resume/cover-letter as files, not
  text).
- Many ATS platforms' terms of service restrict automated applications.
  Check the specific site's terms before pointing this at it, and use
  `--submit` deliberately, one application at a time.

## Status

Built against `jev-ultrafast`'s source on GitHub as of September 2026, before
it had a tagged release — expect its API to move. It has not been run
end-to-end in this environment (no API keys, and installing a fresh
third-party package here is sandboxed); run `tests/local_check.py` first,
then try a dry run against a real application before trusting `--submit`.
