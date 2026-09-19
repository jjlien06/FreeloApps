"""Drive jev_pilot through a job application.

Each page: fill every field jobbot can confidently match against the
applicant's profile (deterministic, no model involved), then ask jev_pilot's
decision model to pick the single button that advances the flow (Apply,
Continue, Next, Review, Submit). One `run_episode` call handles exactly one
click, so apply_to_job's own loop is what walks a multi-page application.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import List, Optional

from jev_pilot import Episode, SafetyPolicy, run_episode
from jev_pilot.browser import BrowserPilot
from jev_pilot.providers import build_chooser

from . import formfill
from .profile import match_value

NAVIGATION_GOAL = (
    "move the job application forward: click Apply, Continue, Next, Review, "
    "or Submit application - whichever single button advances this step"
)

# jev_pilot ANDs every verifier together (all_passed requires every one to hold),
# so the default is deliberately a single, common confirmation phrase. Override
# with --verifier for the specific ATS you're applying through (Greenhouse,
# Lever, Workday, etc. each word their confirmation page differently).
DEFAULT_VERIFIERS = ["text-contains:thank you"]

TERMINAL_OUTCOMES = ("stuck", "error", "escalate", "blocked", "dry_run")


@dataclass
class ApplyResult:
    reached: bool
    stopped: str
    final_url: Optional[str]
    pages_filled: int
    fields_filled: int
    episodes: List[Episode] = field(default_factory=list)


def fill_current_page(port: int, profile: dict) -> int:
    """Fill every field on the current page that matches the profile. Returns count filled."""
    fields = formfill.read_fields(port)
    matches = {}
    for f in fields:
        if f.get("value"):
            continue  # don't clobber anything already populated (browser autofill, a default option)
        value = match_value(f.get("label", ""), f.get("name", ""), f.get("id", ""), profile)
        if value is not None:
            matches[f["idx"]] = value
    if not matches:
        return 0
    results = formfill.fill_fields(port, matches)
    return sum(1 for ok in results.values() if ok)


def apply_to_job(
    url: str,
    profile: dict,
    *,
    submit: bool = False,
    provider: str = "jev",
    headless: bool = True,
    max_pages: int = 8,
    floor: float = 0.6,
    verifiers: Optional[List[str]] = None,
    verbose: bool = False,
) -> ApplyResult:
    """Fill and step through a job application at `url`.

    Safety is scoped to `url`'s own host, so a redirect or an ad off that host
    stops the run instead of being followed. Unless `submit=True`, `run_episode`
    is called with `dry_run=True`: the page for step one gets filled and the
    model's first choice is recorded, but nothing is ever clicked. Only pass
    `submit=True` once a dry run's output looks right.
    """
    safety = SafetyPolicy.for_url(url)
    chooser = build_chooser(provider)
    verifiers = verifiers or DEFAULT_VERIFIERS

    episodes: List[Episode] = []
    fields_filled = 0
    with BrowserPilot(url, headless=headless, safety=safety, verbose=verbose) as pilot:
        for page_index in range(1, max_pages + 1):
            fields_filled += fill_current_page(pilot.port, profile)

            episode = run_episode(
                pilot, chooser, goal=NAVIGATION_GOAL,
                verifiers=verifiers, steps=1, floor=floor, safety=safety,
                dry_run=not submit,
            )
            episodes.append(episode)

            if episode.reached or episode.stopped in TERMINAL_OUTCOMES:
                return ApplyResult(
                    reached=episode.reached, stopped=episode.stopped,
                    final_url=episode.final_url, pages_filled=page_index,
                    fields_filled=fields_filled, episodes=episodes,
                )
            time.sleep(0.3)  # let a client-side form validator settle before the next observe

    return ApplyResult(
        reached=False, stopped="budget",
        final_url=episodes[-1].final_url if episodes else None,
        pages_filled=max_pages, fields_filled=fields_filled, episodes=episodes,
    )
