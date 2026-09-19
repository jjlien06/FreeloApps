"""Offline end-to-end check: no network, no TYPESAFE_API_KEY, no real job site.

Serves tests/fixtures/fake_application.html on localhost, points jobbot at it
with the free `mock` decision provider, and asserts it fills both pages and
reaches the confirmation text.

Needs `pip install -r requirements.txt` and a local Chrome/Chromium first
(set JEV_PILOT_CHROME if it isn't on PATH as google-chrome/chromium/chromium-browser).
Run with: python tests/smoke_test.py
"""
from __future__ import annotations

import functools
import http.server
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
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(FIXTURES))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        url = f"http://127.0.0.1:{port}/fake_application.html"
        result = apply_to_job(
            url, PROFILE,
            submit=True, provider="mock", headless=True, max_pages=3,
            verifiers=["text-contains:application submitted"],
        )
        print(result)
        assert result.reached, f"expected to reach the confirmation page, got stopped={result.stopped!r}"
        assert result.pages_filled == 2, f"expected 2 pages, filled {result.pages_filled}"
        assert result.fields_filled >= 5, f"expected at least 5 fields filled, got {result.fields_filled}"
        print("OK")
        return 0
    finally:
        server.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
