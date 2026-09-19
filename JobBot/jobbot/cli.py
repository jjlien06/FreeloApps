"""python -m jobbot apply --url ... --profile profile.json [--submit]"""
from __future__ import annotations

import argparse
import json
import sys

from .apply import apply_to_job
from .profile import load_profile


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="jobbot", description="Job application autofill bot built on browser-use/jev-ultrafast."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    apply_p = sub.add_parser("apply", help="Fill out and (optionally) submit one job application.")
    apply_p.add_argument("--url", required=True, help="The job application page to open.")
    apply_p.add_argument("--profile", required=True, help="Path to a profile JSON file (see profile.example.json).")
    apply_p.add_argument(
        "--submit", action="store_true",
        help="Actually press the final Submit/Apply button. Without this flag, jobbot fills every "
             "page it can reach and stops the moment it's about to click something that looks "
             "like a final submission (a dry run).",
    )
    apply_p.add_argument(
        "--allowed-host", default=None,
        help="Host to confine navigation to (default: the host in --url). A subdomain of it is "
             "also allowed; anything else stops the run.",
    )
    apply_p.add_argument("--max-steps", type=int, default=40, help="Stop after this many actions either way.")
    apply_p.add_argument("--screenshots", action="store_true", help="Capture a screenshot after every action.")
    apply_p.add_argument("--record-dir", default=None, help="Directory to save per-step screenshots into.")
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    if args.command != "apply":
        return 1

    profile = load_profile(args.profile)
    result = apply_to_job(
        args.url, profile,
        submit=args.submit, max_steps=args.max_steps, allowed_host=args.allowed_host,
        screenshots=args.screenshots, record_dir=args.record_dir,
    )
    print(json.dumps({
        "status": result.status,
        "submitted": result.submitted,
        "final_url": result.final_url,
        "steps_taken": result.steps_taken,
    }, indent=2))
    if result.status == "awaiting_submit":
        print(
            "\n(stopped right before a submit-looking button; re-run with --submit once this looks right)",
            file=sys.stderr,
        )
    return 0 if (result.submitted or not args.submit) else 1


if __name__ == "__main__":
    raise SystemExit(main())
