"""OpenAlex client refusals (FR-69, November 5, 2026). Run from the repository root: python3 -I tests/test_citedby_client.py

No network: urlopen is replaced by a script of answers.
"""
import email.message
import io
import json
import os
import sys
import urllib.error

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "harvester"))
from netd import citedby  # noqa: E402


def http_error(code, **headers):
    h = email.message.Message()
    for k, v in headers.items():
        h[k.replace("_", "-")] = str(v)
    return urllib.error.HTTPError(citedby.API, code, "refused", h, io.BytesIO(b"{}"))


class Ok:
    def __init__(self, remaining="0.09"):
        self.headers = {"X-RateLimit-Remaining-USD": remaining}

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def read(self, *a):
        return json.dumps({"results": [], "meta": {}}).encode()


def client_with(answers, key=None, max_wait=300):
    seen, slept = [], []

    def fake(req, timeout=60):
        seen.append(req.full_url)
        a = answers.pop(0)
        if isinstance(a, Exception):
            raise a
        return a

    citedby.urllib.request.urlopen = fake
    c = citedby.Client(key=key, max_wait=max_wait, sleep=slept.append)
    return c, seen, slept


def check():
    # busy: 429 with Retry-After, then an answer
    c, seen, slept = client_with([http_error(429, Retry_After=38), Ok()])
    assert c.get(filter="x") == {"results": [], "meta": {}} and c.calls == 1 and c.waited == 38 and slept == [39]

    # busy for longer than MAX_WAIT: RateLimited, which is also a Budget for the callers
    c, seen, slept = client_with([http_error(429, Retry_After=100)] * 5, max_wait=250)
    try:
        c.get(filter="x")
        raise AssertionError("expected RateLimited")
    except citedby.RateLimited:
        pass
    assert c.waited == 200 and len(seen) == 3
    assert citedby.why(citedby.RateLimited(), c).startswith(", stopped: rate-limited")

    # allowance used up: 429 without Retry-After, or with the remaining budget below the minimum: no waiting
    for e in (http_error(429), http_error(429, Retry_After=30, X_RateLimit_Remaining_USD="0.0"), http_error(402)):
        c, seen, slept = client_with([e])
        try:
            c.get(filter="x")
            raise AssertionError("expected Budget")
        except citedby.RateLimited:
            raise AssertionError("budget mistaken for busy")
        except citedby.Budget as b:
            assert citedby.why(b, c) == ", stopped at the daily budget"
        assert slept == []

    # a rejected key: carry on without it
    c, seen, slept = client_with([http_error(401), Ok()], key="k-123")
    c.get(filter="x")
    assert "api_key=k-123" in seen[0] and "api_key" not in seen[1] and c.key is None and c.key_rejected

    # a good key is sent
    c, seen, slept = client_with([Ok()], key="k-123")
    c.get(filter="x")
    assert "api_key=k-123" in seen[0]
    print("test_citedby_client: OK")


if __name__ == "__main__":
    check()
