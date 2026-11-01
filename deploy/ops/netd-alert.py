#!/usr/bin/env python3
"""Email the NETD maintainer.

  netd-alert.py UNIT        a systemd unit failed (called by netd-alert@UNIT.service via OnFailure=)
  netd-alert.py --weekly    weekly "all well" summary, so a silent alert path is noticed
  netd-alert.py --recovered TEXT   the public site is serving again (sent by netd-probe.sh)

Uses the SMTP account in /opt/netd/portal.env (SMTP_USER/SMTP_PASSWORD, optional SMTP_ADDRESS/SMTP_PORT);
recipient is ALERT_TO in portal.env, else SMTP_USER.
"""
import json
import smtplib
import socket
import subprocess
import sys
import urllib.request
from email.message import EmailMessage

ENV = "/opt/netd/portal.env"


def env():
    e = {}
    for line in open(ENV):
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.strip().split("=", 1)
            e[k] = v.strip().strip('"')
    return e


def sh(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout.strip()
    except Exception as ex:  # never let the alert itself fail on diagnostics
        return "(%s)" % ex


def repo_check():
    """Summary of the weekly repository check (netd.cli check-repositories, SRS FR-58)."""
    try:
        d = json.load(open("/opt/netd/logs/repository-check.json"))
    except Exception as ex:  # noqa: BLE001
        return "(no repository check: %s)" % ex
    rows = d.get("repositories", [])
    up = [r["name"] for r in rows if r.get("reachable")]
    lines = ["Checked %s: %d of %d not-yet-harvested repositories reachable." % (d.get("checked_at"), len(up), len(rows))]
    lines += ["CHANGE: " + c for c in d.get("changes", [])] or ["No changes since the previous check."]
    lines += ["  %s: OAI-PMH records %s, in ETD sets %s" % (r["name"], r.get("records"), r.get("etd_records"))
              for r in rows if r.get("oai_ok")]
    return "\n".join(lines)


def send(subject, body):
    e = env()
    m = EmailMessage()
    m["From"] = "NETD portal <%s>" % e["SMTP_USER"]
    m["To"] = e.get("ALERT_TO", e["SMTP_USER"])
    m["Subject"] = subject
    m.set_content(body)
    with smtplib.SMTP(e.get("SMTP_ADDRESS", "smtp.gmail.com"), int(e.get("SMTP_PORT", 587)), timeout=60) as s:
        s.starttls()
        s.login(e["SMTP_USER"], e["SMTP_PASSWORD"])
        s.send_message(m)


def solr_count():
    try:
        r = json.load(urllib.request.urlopen("http://127.0.0.1:8983/solr/netd/select?q=*:*&rows=0&wt=json", timeout=30))
        return str(r["response"]["numFound"])
    except Exception as ex:
        return "not answering (%s)" % ex


def main():
    host = socket.gethostname()
    if sys.argv[1:] == ["--weekly"]:
        body = "\n".join([
            "Weekly status of https://netd.ac.zm/ (%s)" % host, "",
            "Search index documents: " + solr_count(), "",
            "Services:", sh("systemctl", "is-active", "netd-solr", "netd-portal", "apache2"), "",
            "Latest harvest check:", sh("journalctl", "-u", "netd-harvest", "-n", "8", "--no-pager", "-o", "cat"), "",
            "Backups (last 7 lines of /var/log/netd-backup.log):", sh("tail", "-7", "/var/log/netd-backup.log"), "",
            "Institution repositories (weekly check):", repo_check(), "",
            "Disk: " + sh("df", "-h", "/").splitlines()[-1],
            "OS: " + sh("lsb_release", "-ds"),
        ])
        send("NETD weekly status: index %s documents" % solr_count(), body)
        return
    if sys.argv[1:2] == ["--recovered"]:
        send("NETD recovered: https://netd.ac.zm/ is serving again",
             "https://netd.ac.zm/ is serving search results again (%s; %s).\nSearch index documents: %s\n"
             % (" ".join(sys.argv[2:]), host, solr_count()))
        return
    unit = sys.argv[1]
    body = "\n".join([
        "%s failed on %s." % (unit, host), "",
        sh("systemctl", "status", unit, "--no-pager", "-n", "0"), "",
        "Last 60 log lines:", sh("journalctl", "-u", unit, "-n", "60", "--no-pager", "-o", "short-iso"), "",
        "Search index documents now: " + solr_count(), "",
        "See docs/OPERATIONS.md in the repository for what to do.",
    ])
    send("NETD ALERT: %s failed" % unit, body)


if __name__ == "__main__":
    main()
