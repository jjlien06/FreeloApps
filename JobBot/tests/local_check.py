"""Sanity check against a local fake application instead of a real job site.

Unlike jev_pilot (the unrelated, similarly-named package this app used to be
built on), jev-ultrafast has no free/offline decision backend - every run
calls the real TypeSafe API and a real text-generation API. This script
still keeps the browser off any real job site by serving
tests/fixtures/fake_application.html on localhost, but it is NOT free or
offline: it needs TYPESAFE_API_KEY and TEXT_MODEL_API_KEY set, same as a
real run.

Run with: python tests/local_check.py
"""
from __future__ import annotations

import functools
import http.server
import os
import sys
import threading
from pathlib import Path

FIXTURES = Path(__file__).parent / "fixtures"
sys.path.insert(0, str(Path(__file__).parent.parent))

from jobbot.apply import apply_to_job  # noqa: E402

PROFILE = {
    "first_name": "Jane",
    "last_name": "Doe",
    "email": "jane.doe@example.com",
    "phone": "555-123-4567",
    "cover_letter": "I'm excited to apply for this role.",
    "answers": {
        "Are you willing to relocate?": "No",
    },
}


def main() -> int:
    if not os.environ.get("TYPESAFE_API_KEY") or not os.environ.get("TEXT_MODEL_API_KEY"):
        print("Set TYPESAFE_API_KEY and TEXT_MODEL_API_KEY first - this check calls the real APIs, "
              "just against a local fake form instead of a real job site.", file=sys.stderr)
        return 2

    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(FIXTURES))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        url = f"http://127.0.0.1:{port}/fake_application.html"
        result = apply_to_job(url, PROFILE, submit=True, max_steps=15)
        print(result)
        assert result.submitted, f"expected the fake form to be submitted, got status={result.status!r}"
        print("OK")
        return 0
    finally:
        server.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
