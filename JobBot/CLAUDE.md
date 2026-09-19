# CLAUDE.md — JobBot

## What this is

A CLI that fills out and (optionally) submits a job application, given a
profile JSON and a URL. It's built on [`jev-browser-pilot`](https://github.com/aidil2105/jev-browser-pilot),
a "decision-only" browser automation library: a model picks exactly one
next click per step from a candidate list your own code builds; your code
owns everything else (perception, content, verification).

## Why two CDP connections

`jev_pilot.browser.BrowserPilot` launches a real Chrome and drives it over
CDP, but its only action is `click` — there is no typing path anywhere in
its loop (`jev_pilot/loop.py` hardcodes `safety.check_action("click", ...)`
on every step, and `SafetyPolicy.allow_typing` is never read there). That's
deliberate on the library's part: the decision model never sees or writes
field content, so nothing it says can inject text into a resume field or a
salary answer.

So `jobbot/formfill.py` opens a *second* CDP connection to the same
`BrowserPilot.port` and writes form values directly via `Runtime.evaluate` —
the same technique the library's own `Tab` class uses internally, just from
jobbot's side. `apply.py`'s loop is: fill the current page deterministically
from the profile, *then* ask `run_episode` for one click (Continue / Submit
/ etc.), repeat per page. The model only ever chooses which button to press.

## Safety defaults

- `SafetyPolicy.for_url(url)` scopes every click and navigation to that
  URL's own host — a redirect off-site stops the run.
- `submit=False` (the CLI default) passes `dry_run=True` into `run_episode`,
  which fills page one and records the model's first pick, but the loop
  returns before ever calling `surface.act()`. Nothing is clicked, let alone
  submitted, until `--submit` is passed.
- `run_episode`'s verifiers are ANDed, not ORed — `apply.py` defaults to a
  single postcondition rather than several alternates that would never all
  hold at once. Override `--verifier` per site.

## Testing without a real job site or API key

`build_chooser("mock")` returns a keyword-overlap chooser that needs no
credentials — it's the library's own stand-in for CI. `tests/smoke_test.py`
serves `tests/fixtures/fake_application.html` on localhost and runs the
whole fill → click → verify loop against it with `--provider mock`. Run
that first after any change to `apply.py` or `formfill.py`, before pointing
jobbot at a real application.

## Known limitations / next steps

- Field-to-answer matching (`profile.py`) is alias/substring heuristics, not
  a model — it will miss unusually worded questions. Add them to the
  profile's `answers` dict (matched by substring against the question text)
  rather than growing `FIELD_ALIASES` for one-off sites.
- `DomRules`'s default root selectors fall back to `body`, so it should see
  most sites, but a heavily customized ATS may need a narrower
  `DomRules(root_selectors=[...])` passed through to `BrowserPilot` — not
  currently exposed as a CLI flag.
- Multi-file uploads (resume/cover letter as files, not text) aren't handled;
  CDP file input automation (`DOM.setFileInputFiles`) would need to be added
  to `formfill.py`.
