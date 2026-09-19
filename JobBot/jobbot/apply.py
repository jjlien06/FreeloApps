"""Drive jev-ultrafast (browser-use/jev-ultrafast) through a job application.

jev-ultrafast's own Agent already handles the whole per-field type/click/select
loop - unlike the DOM candidate list a "decision-only" model normally clicks
through, its action space includes TYPE_TEXT, so there's no separate form-fill
step here (contrast jev_pilot, an unrelated same-named package this app used
to be built on; see git history / CLAUDE.md).

Two things jev-ultrafast doesn't do on its own, so jobbot adds them:

1. Submit-gating: the goal text asks the model not to press the final
   submit-like button, but it's a probabilistic classifier, not an
   instruction-follower - it can still pick "Submit" as its target. So
   `apply_to_job` drives Agent.command() manually (rather than the Agent.run()
   convenience generator) and hard-stops in code before executing any action
   whose label looks like a final submission, unless `submit=True`.
2. Host scoping: jev-ultrafast's Browser has no domain allow-list at all, so
   jobbot checks the page URL after every action and stops if it left the
   application's own host.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse

from jev_ultrafast import Agent

from .profile import build_goal

SUBMIT_WORDS = re.compile(r"\b(submit|apply now|send application|finish application)\b", re.IGNORECASE)


def _host_of(url: Optional[str]) -> Optional[str]:
    if not url:
        return None
    return (urlparse(url).hostname or "").lower() or None


def _same_site(host: Optional[str], allowed: Optional[str]) -> bool:
    if not host or not allowed:
        return False
    return host == allowed or host.endswith("." + allowed)


def _looks_like_submit(label: str) -> bool:
    return bool(SUBMIT_WORDS.search(label or ""))


@dataclass
class ApplyResult:
    status: str  # "done" | "blocked" | "awaiting_submit" | "blocked_offsite" | "budget"
    submitted: bool  # True only if a submit-like control was actually clicked
    final_url: Optional[str]
    steps_taken: int
    history: List[Dict[str, Any]] = field(default_factory=list)


def apply_to_job(
    url: str,
    profile: dict,
    *,
    submit: bool = False,
    max_steps: int = 40,
    allowed_host: Optional[str] = None,
    screenshots: bool = False,
    record_dir: Optional[str] = None,
) -> ApplyResult:
    """Fill (and, if `submit=True`, complete) a job application at `url`.

    Requires TYPESAFE_API_KEY and TEXT_MODEL_API_KEY in the environment
    (jev-ultrafast calls both TypeSafe's Jev model and a small text-generation
    model for anything it types - see README for what each one sees).
    """
    host = allowed_host or _host_of(url)
    goal = build_goal(profile, allow_submit=submit)

    def _submitted(history: List[Dict[str, Any]]) -> bool:
        return any(_looks_like_submit(h.get("action", "")) for h in history)

    with Agent(url, goal, screenshots=screenshots, record_dir=record_dir) as agent:
        for step in range(1, max_steps + 1):
            agent.command("predict")
            decision = agent.state["decision"]
            page = agent.state["page"]

            if decision["choice"] in ("DONE", "BLOCKED"):
                agent.command("act", {"fingerprint": page["fingerprint"]})
                return ApplyResult(
                    status=agent.state["status"], submitted=_submitted(agent.state["history"]),
                    final_url=agent.state["page"]["url"], steps_taken=step,
                    history=agent.state["history"],
                )

            action = next(a for a in page["actions"] if a["id"] == decision["choice"])
            if not submit and _looks_like_submit(action["label"]):
                return ApplyResult(
                    status="awaiting_submit", submitted=False,
                    final_url=page["url"], steps_taken=step - 1,
                    history=agent.state["history"],
                )

            agent.command("act", {"fingerprint": page["fingerprint"]})

            new_host = _host_of(agent.state["page"]["url"])
            if not _same_site(new_host, host):
                return ApplyResult(
                    status="blocked_offsite", submitted=_submitted(agent.state["history"]),
                    final_url=agent.state["page"]["url"], steps_taken=step,
                    history=agent.state["history"],
                )

        return ApplyResult(
            status="budget", submitted=_submitted(agent.state["history"]),
            final_url=agent.state["page"]["url"], steps_taken=max_steps,
            history=agent.state["history"],
        )
