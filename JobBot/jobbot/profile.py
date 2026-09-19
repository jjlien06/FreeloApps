"""Applicant profile loading and turning it into a goal jev-ultrafast can act on."""
from __future__ import annotations

import json
from pathlib import Path

# Order controls the order they appear in the goal text; cosmetic only.
FIELD_ORDER = [
    ("first_name", "First name"),
    ("last_name", "Last name"),
    ("full_name", "Full name"),
    ("email", "Email"),
    ("phone", "Phone"),
    ("linkedin_url", "LinkedIn"),
    ("github_url", "GitHub"),
    ("portfolio_url", "Portfolio / website"),
    ("address", "Street address"),
    ("city", "City"),
    ("state", "State / province"),
    ("postal_code", "ZIP / postal code"),
    ("country", "Country"),
    ("work_authorization", "Work authorization"),
    ("desired_salary", "Desired salary"),
    ("cover_letter", "Cover letter"),
]


def load_profile(path: str) -> dict:
    data = json.loads(Path(path).read_text())
    data.setdefault("answers", {})
    return data


def build_goal(profile: dict, *, allow_submit: bool) -> str:
    """A goal string for jev_ultrafast.Agent: explicit values first, instructions second.

    jev-ultrafast's TYPE_TEXT operation is handled by a small helper LLM (see
    jev_ultrafast/questions.py's TEXT_VALUE prompt) that is told to return null
    rather than invent a value it wasn't given - so every value the candidate
    actually wants entered has to be spelled out here, verbatim, rather than
    left for the model to guess.
    """
    lines = [
        "Fill out this job application using ONLY the candidate information below.",
        "Copy each value verbatim into the matching field. If a field asks for "
        "something not listed below, leave it blank rather than inventing an answer.",
        "",
        "Candidate information:",
    ]
    for key, display in FIELD_ORDER:
        value = profile.get(key)
        if value:
            lines.append(f"- {display}: {value}")

    answers = profile.get("answers") or {}
    if answers:
        lines.append("")
        lines.append("Answers to specific questions the form may ask (match by meaning, not exact wording):")
        for question, answer in answers.items():
            lines.append(f"- \"{question}\" -> {answer}")

    lines.append("")
    if allow_submit:
        lines.append(
            "Work through every page of the application, filling every matching field, "
            "and finish by submitting the completed application."
        )
    else:
        lines.append(
            "Work through every page of the application, filling every matching field, "
            "until you reach the final review/submit step. Do not press Submit, "
            "Apply, or any button that finalizes the application - stop there."
        )
    return "\n".join(lines)
