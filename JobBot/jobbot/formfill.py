"""Deterministic form filling over the same Chrome instance jev_pilot drives.

jev_pilot's BrowserPilot only exposes a `click` action; the decision model
never sees or writes field content (jev_pilot/loop.py hardcodes
`safety.check_action("click", ...)` on every step, and `SafetyPolicy.allow_typing`
is never read there — this browser Surface has no typing path at all).

So content goes in over a second, independent CDP connection to the *same*
debugging port BrowserPilot already opened on localhost, using plain DOM
APIs. No model ever sees or types a value; jobbot's own code decides what
goes in which field (see profile.py) and writes it directly.
"""
from __future__ import annotations

import json
import urllib.request
from typing import Any, Dict, List

import websocket  # from websocket-client, already a jev-browser-pilot dependency

_READ_FIELDS_JS = r"""
(() => {
  function labelFor(el) {
    if (el.labels && el.labels.length) return el.labels[0].innerText.trim();
    const aria = el.getAttribute('aria-label');
    if (aria) return aria;
    const describedBy = el.getAttribute('aria-describedby');
    if (describedBy) {
      const d = document.getElementById(describedBy);
      if (d) return d.innerText.trim();
    }
    const ph = el.getAttribute('placeholder');
    if (ph) return ph;
    const wrapping = el.closest('label');
    if (wrapping) return wrapping.innerText.trim();
    return '';
  }
  const out = [];
  document.querySelectorAll('input, textarea, select').forEach((el, i) => {
    const type = (el.getAttribute('type') || '').toLowerCase();
    if (type === 'hidden' || type === 'submit' || type === 'button' || el.disabled) return;
    if (el.offsetParent === null) return;
    el.setAttribute('data-jobbot-idx', String(i));
    let options = null;
    if (el.tagName.toLowerCase() === 'select') {
      options = Array.from(el.options).map(o => o.text.trim());
    }
    out.push({
      idx: i, tag: el.tagName.toLowerCase(), type: type,
      name: el.getAttribute('name') || '', id: el.id || '',
      label: labelFor(el), value: el.value || '', options: options,
    });
  });
  return out;
})()
"""


def _fill_field_js(idx: int, value: str) -> str:
    return f"""
(() => {{
  const el = document.querySelector('[data-jobbot-idx="{idx}"]');
  if (!el) return {{ok: false, reason: 'not found'}};
  const tag = el.tagName.toLowerCase();
  if (tag === 'select') {{
    const target = {json.dumps(value.lower())};
    const opt = Array.from(el.options).find(o => o.text.trim().toLowerCase() === target);
    if (!opt) return {{ok: false, reason: 'option not found'}};
    el.value = opt.value;
  }} else {{
    el.value = {json.dumps(value)};
  }}
  el.dispatchEvent(new Event('input', {{bubbles: true}}));
  el.dispatchEvent(new Event('change', {{bubbles: true}}));
  return {{ok: true}};
}})()
"""


class FormTab:
    """A second, minimal CDP connection to the page BrowserPilot already opened.

    Mirrors jev_pilot.browser.Tab's own approach (plain `Runtime.evaluate` over a
    websocket to the CDP endpoint) rather than reaching into BrowserPilot's
    private `_tab`, so it keeps working across jev_pilot internal changes as
    long as the public CDP port stays put.
    """

    def __init__(self, port: int, timeout: float = 15.0):
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list", timeout=timeout) as r:
            targets = json.load(r)
        pages = [
            t for t in targets
            if t.get("type") == "page" and not (t.get("url") or "").startswith(("devtools://", "chrome://"))
        ]
        if not pages:
            raise RuntimeError("no page target on the CDP endpoint")
        self._ws = websocket.create_connection(pages[0]["webSocketDebuggerUrl"], timeout=timeout, suppress_origin=True)
        self._id = 0

    def eval_js(self, expression: str) -> Any:
        self._id += 1
        mid = self._id
        self._ws.send(json.dumps({
            "id": mid, "method": "Runtime.evaluate",
            "params": {"expression": expression, "returnByValue": True, "awaitPromise": True},
        }))
        while True:
            message = json.loads(self._ws.recv())
            if message.get("id") == mid:
                if "error" in message:
                    raise RuntimeError(f"Runtime.evaluate: {message['error']}")
                return message.get("result", {}).get("result", {}).get("value")

    def close(self) -> None:
        try:
            self._ws.close()
        except Exception:
            pass


def read_fields(port: int) -> List[Dict[str, Any]]:
    """The visible, enabled form fields on the page right now."""
    tab = FormTab(port)
    try:
        return tab.eval_js(_READ_FIELDS_JS) or []
    finally:
        tab.close()


def fill_fields(port: int, matches: Dict[int, str]) -> Dict[int, bool]:
    """Write `matches` (field idx -> value) into the page. Returns idx -> whether it took."""
    tab = FormTab(port)
    results: Dict[int, bool] = {}
    try:
        for idx, value in matches.items():
            outcome = tab.eval_js(_fill_field_js(idx, value)) or {"ok": False}
            results[idx] = bool(outcome.get("ok"))
        return results
    finally:
        tab.close()
