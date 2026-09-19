# CLAUDE.md — JobBot

## What this is

A CLI that fills out and (opt-in) submits a job application, given a profile
JSON and a URL. It's built on [`browser-use/jev-ultrafast`](https://github.com/browser-use/jev-ultrafast)
("Jev Ultrafast"), which drives a real Chrome via CDP and, per step, sends
TypeSafe's `Jev` model one typed decision: which operation (CLICK, TYPE_TEXT,
SELECT, SCROLL_UP/DOWN, WAIT, DONE, BLOCKED) and which indexed page element.
When the operation is TYPE_TEXT, a *second*, small text-generation model
(DeepSeek by default, configurable) writes the actual text to type.

Earlier revisions of this app were built against a different, unrelated
package that is also called `jev` (`jev-browser-pilot` by a different author,
which has no typing action at all). That was the wrong "jev" — the intended
one is `browser-use/jev-ultrafast`, prompted by the HN post it shipped with
(<https://news.ycombinator.com/item?id=49735979>). `jobbot/apply.py`,
`jobbot/cli.py` and `jobbot/profile.py` were rewritten for the real package;
`jobbot/formfill.py` (a hand-rolled CDP form-filler needed only because the
other library couldn't type) is gone — jev-ultrafast fills fields itself.

## Two things jobbot adds that jev-ultrafast doesn't do itself

1. **Submit-gating.** `jev_ultrafast.Agent` has no dry-run mode — every
   `command("act")` executes for real, immediately. `profile.build_goal()`
   tells the model not to press the final Submit/Apply button, but `Jev` is a
   probabilistic classifier over candidates, not an instruction-follower, so
   that's advisory at best. `apply.py` therefore drives `Agent.command()`
   manually (`predict` then `act`, rather than the `Agent.run()` convenience
   generator) so it can inspect the chosen action's label *before* executing
   it, and hard-stops before clicking anything matching `SUBMIT_WORDS`
   unless `submit=True` was passed in.
2. **Host scoping.** `jev_ultrafast.Browser` has no domain allow-list — it
   will navigate anywhere a link points. `apply.py` checks the page's host
   after every action and stops (`status="blocked_offsite"`) if it left the
   application's own site (or a subdomain of it).

## What the two model calls see

- The `Jev` decision call sees the page's structured element list and the
  goal text, but never generates content — it only ever returns which
  element and which operation.
- The text-generation call (TYPE_TEXT only) sees the goal text plus the
  target field's context (`jev_ultrafast/model.py`'s `field_context`,
  including up to 6000 chars of page content) and returns the literal string
  to type. Since `profile.build_goal()` embeds every profile value verbatim
  in the goal, that text model does see the candidate's actual data —
  unlike the earlier, wrong-library revision, there is no way with this
  package to keep personal data out of the model's context. Its prompt
  (`jev_ultrafast/questions.py`'s `TEXT_VALUE`) is told to return null rather
  than invent a value that isn't given, which is why unmatched fields are
  told to stay blank rather than guessed.

## Environment

- `TYPESAFE_API_KEY` — required, the Jev decision model.
- `TEXT_MODEL_API_KEY` — required for any form with text fields. Defaults to
  DeepSeek's own API (`TEXT_MODEL_BASE_URL=https://api.deepseek.com/v1`,
  `TEXT_MODEL=deepseek-chat`); point it at OpenRouter or another
  OpenAI-compatible endpoint by overriding those two.
- Chrome/Chromium itself is managed by jev-ultrafast's `browser-harness`
  dependency, not by jobbot.

## Testing

There is no free/offline decision backend for this package (unlike
`jev-browser-pilot`'s `mock` provider, which the earlier revision's test
relied on) — every run costs real API calls. `tests/local_check.py` keeps
the *browser* off a real job site (a local fake two-page form), but still
needs both API keys set. Run it after touching `apply.py` or `profile.py`,
before pointing jobbot at a real application.

## Known limitations

- No file-upload support (resume/cover-letter as an actual file, not text) —
  `jev_ultrafast`'s action space has no upload operation as of this writing.
- `SUBMIT_WORDS` (in `apply.py`) is an English-only keyword guess at what a
  final submission button looks like; a site whose button says something
  else entirely won't be caught by the gate, so review a run's `history`
  before trusting `--submit` on a new site.
- Many ATS platforms' terms of service restrict automated applications —
  check the specific site's terms before pointing this at it.
