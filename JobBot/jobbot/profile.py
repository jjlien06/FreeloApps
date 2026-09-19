"""Applicant profile loading and label -> answer matching heuristics."""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import List, Optional, Tuple

# Checked in this order, so a more specific alias never loses to a shorter one
# it contains (e.g. "last name" is tried before the catch-all "name").
FIELD_ALIASES: List[Tuple[str, List[str]]] = [
    ("email", ["email", "e-mail"]),
    ("phone", ["phone", "mobile", "telephone"]),
    ("first_name", ["first name", "given name", "legal first name"]),
    ("last_name", ["last name", "surname", "family name", "legal last name"]),
    ("linkedin_url", ["linkedin"]),
    ("github_url", ["github"]),
    ("portfolio_url", ["portfolio", "personal website"]),
    ("city", ["city"]),
    ("state", ["state", "province"]),
    ("country", ["country"]),
    ("postal_code", ["zip code", "postal code", "zip"]),
    ("address", ["street address", "address"]),
    ("cover_letter", ["cover letter"]),
    ("desired_salary", ["salary", "compensation expectation"]),
    ("work_authorization", ["work authoriz", "authorized to work", "sponsorship"]),
    ("how_heard", ["how did you hear", "referral source"]),
    ("full_name", ["full name", "your name", "name"]),  # broadest, tried last
]


def load_profile(path: str) -> dict:
    data = json.loads(Path(path).read_text())
    data.setdefault("answers", {})
    return data


def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", text or "").strip().lower()


def match_value(field_label: str, field_name: str, field_id: str, profile: dict) -> Optional[str]:
    """Best-effort mapping from a form field's label/name/id to a profile answer.

    Order: the user's own free-form Q&A (substring match on the question text,
    for anything a fixed alias can't anticipate), then the fixed alias table,
    then a raw lookup by the field's own `name`/`id` attribute for sites that
    happen to reuse profile-shaped keys.
    """
    haystack = _norm(f"{field_label} {field_name} {field_id}")
    if not haystack:
        return None

    for question, answer in profile.get("answers", {}).items():
        if _norm(question) and _norm(question) in haystack:
            return str(answer)

    for key, aliases in FIELD_ALIASES:
        if key not in profile:
            continue
        if any(alias in haystack for alias in aliases):
            return str(profile[key])

    for raw_key in (field_name, field_id):
        norm_key = _norm(raw_key).replace(" ", "_")
        if norm_key and norm_key in profile:
            return str(profile[norm_key])

    return None
