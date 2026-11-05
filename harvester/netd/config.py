"""The installation's country configuration (config/country.yml; SRS NFR-15, SDD "Country configuration").

Read once, on first use. Set NETD_COUNTRY to read another file. A missing file or a missing required key stops
with a message naming the file and the key.

    python -m netd.config --env     # the deployment settings as shell assignments (deploy/site.env)
"""
import os
import pathlib
import shlex
import sys
from functools import lru_cache
from zoneinfo import ZoneInfo

import yaml

REQUIRED = ("country.name", "country.adjective", "country.time_zone", "portal.name", "portal.wordmark", "portal.host",
            "regulator.name", "regulator.short_name", "regulator.url", "contact.email", "contact.reports_to",
            "mail.from", "mail.sender")


def path():
    return pathlib.Path(os.environ.get("NETD_COUNTRY") or pathlib.Path(__file__).resolve().parents[2] / "config" / "country.yml")


def _dig(data, key):
    for part in key.split("."):
        data = data.get(part) if isinstance(data, dict) else None
    return data


@lru_cache(maxsize=1)
def load():
    p = path()
    if not p.is_file():
        raise SystemExit(f"NETD: country configuration not found at {p} (copy one from config/examples/; manual chapter 7)")
    data = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    missing = [k for k in REQUIRED if _dig(data, k) in (None, "", [])]
    if missing:
        raise SystemExit(f"NETD: {p} lacks {', '.join(missing)}")
    try:
        ZoneInfo(_dig(data, "country.time_zone"))
    except Exception:
        raise SystemExit(f"NETD: {p}: country.time_zone {_dig(data, 'country.time_zone')!r} is not an IANA time zone name")
    return data


def get(key):
    return _dig(load(), key)


def host():
    return get("portal.host")


def base_url():
    return "https://" + host()


def portal_name():
    return get("portal.name")


def country_name():
    return get("country.name")


def time_zone():
    return get("country.time_zone")


def site_env():
    """Settings for the shell scripts in deploy/ (probe, alerts, upgrade check), one NAME=value per line."""
    values = {
        "NETD_HOST": host(),
        "NETD_BASE_URL": base_url(),
        "NETD_PORTAL_NAME": portal_name(),
        "NETD_CONTACT_EMAIL": get("contact.email"),
        "NETD_TIME_ZONE": time_zone(),
    }
    head = f"# Written by deploy/deploy.sh from {path()}; do not edit (edit country.yml and deploy again).\n"
    return head + "".join(f"{k}={shlex.quote(str(v))}\n" for k, v in values.items())


if __name__ == "__main__":
    if sys.argv[1:] == ["--env"]:
        sys.stdout.write(site_env())
    else:
        sys.exit(__doc__)
