"""python -m jobbot apply --url ... --profile profile.json [--submit]"""
from __future__ import annotations

import argparse
import json
import sys

from .apply import apply_to_job
from .profile import load_profile


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="jobbot", description="Job application autofill bot built on jev-browser-pilot."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    apply_p = sub.add_parser("apply", help="Fill out and (optionally) submit one job application.")
    apply_p.add_argument("--url", required=True, help="The job application page to open.")
    apply_p.add_argument("--profile", required=True, help="Path to a profile JSON file (see profile.example.json).")
    apply_p.add_argument(
        "--submit", action="store_true",
        help="Actually click through and submit. Without this flag, jobbot fills the first "
             "page and previews the model's next click, but never presses it (a dry run).",
    )
    apply_p.add_argument(
        "--provider", default="jev", choices=["jev", "openai", "mock"],
        help="Decision backend for run_episode. 'jev' (default) needs TYPESAFE_API_KEY; "
             "'mock' is a free, offline keyword matcher for local testing.",
    )
    apply_p.add_argument("--headless", action="store_true", default=True)
    apply_p.add_argument(
        "--show-browser", dest="headless", action="store_false",
        help="Show the Chrome window instead of running headless.",
    )
    apply_p.add_argument("--max-pages", type=int, default=8, help="Stop after this many pages either way.")
    apply_p.add_argument(
        "--floor", type=float, default=0.6,
        help="Confidence floor below which the model escalates instead of clicking (default: 0.6).",
    )
    apply_p.add_argument(
        "--verifier", action="append", dest="verifiers",
        help="A postcondition meaning 'the application was submitted', e.g. 'url-contains:thank-you' "
             "or 'text-contains:thanks for applying'. Repeatable, but every one given must hold "
             "at once (they're ANDed) - for most sites, pass exactly one. Defaults to "
             "'text-contains:thank you'.",
    )
    apply_p.add_argument("-v", "--verbose", action="store_true")
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    if args.command != "apply":
        return 1

    profile = load_profile(args.profile)
    result = apply_to_job(
        args.url, profile,
        submit=args.submit, provider=args.provider, headless=args.headless,
        max_pages=args.max_pages, floor=args.floor, verifiers=args.verifiers,
        verbose=args.verbose,
    )
    print(json.dumps({
        "reached": result.reached,
        "stopped": result.stopped,
        "final_url": result.final_url,
        "pages_filled": result.pages_filled,
        "fields_filled": result.fields_filled,
    }, indent=2))
    if not args.submit:
        print(
            "\n(dry run: nothing was submitted; re-run with --submit once this looks right)",
            file=sys.stderr,
        )
    return 0 if (result.reached or not args.submit) else 1


if __name__ == "__main__":
    raise SystemExit(main())
