"""Weekly check of every institution repository in institutions.yml (SRS FR-58).

For each registry entry (and `other_repositories`) with a `repository` page or an `oai` endpoint, records whether
the page answers, whether OAI-PMH Identify answers, how many records the OAI-PMH index lists, and how many are in
the ETD sets (`etd_sets`). The result is written as JSON for the admin panel and the weekly status email; changes
since the previous check (a repository coming back, ETDs appearing in a set) are listed under "changes", so
an institution can be onboarded as soon as its repository is ready. One request at a time per repository.
"""
import datetime
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request

UA = {"User-Agent": "NETD repository check (+https://netd.ac.zm)"}


def _get(url, timeout=30):
    req = urllib.request.Request(url, headers=UA)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read(2_000_000).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, ""
    except Exception as e:  # noqa: BLE001 - DNS, refused, timeout, TLS: all mean "not reachable"
        return None, type(e).__name__ + ": " + str(e)[:120]


def _count(oai, set_spec=None):
    """Records listed by ListIdentifiers (completeListSize, else the first page), or None on error."""
    q = {"verb": "ListIdentifiers", "metadataPrefix": "oai_dc"}
    if set_spec:
        q["set"] = set_spec
    code, body = _get(oai + "?" + urllib.parse.urlencode(q), timeout=90)
    if code != 200:
        return None
    if 'code="noRecordsMatch"' in body:
        return 0
    m = re.search(r'completeListSize="(\d+)"', body)
    return int(m.group(1)) if m else body.count("<header")


def check_one(entry):
    out = {"name": entry["name"], "status": entry.get("status"), "repository": entry.get("repository"),
           "oai": entry.get("oai"), "etd_sets": entry.get("etd_sets") or []}
    if entry.get("repository"):
        code, _ = _get(entry["repository"])
        out["page"] = code
    if entry.get("oai"):
        code, body = _get(entry["oai"] + "?verb=Identify")
        out["oai_ok"] = code == 200 and "<repositoryName>" in body
        if out["oai_ok"]:
            out["records"] = _count(entry["oai"])
            if out["etd_sets"]:
                counts = [_count(entry["oai"], s) for s in out["etd_sets"]]
                out["etd_records"] = sum(c or 0 for c in counts)
    out["reachable"] = bool(out.get("oai_ok") or (out.get("page") and out["page"] < 400))
    return out


def _changes(prev, cur):
    before = {r["name"]: r for r in prev}
    msgs = []
    for r in cur:
        p = before.get(r["name"])
        if not p:
            continue
        if r["reachable"] != p.get("reachable"):
            msgs.append("%s: repository %s" % (r["name"], "now reachable" if r["reachable"] else "no longer reachable"))
        if (r.get("etd_records") or 0) != (p.get("etd_records") or 0):
            msgs.append("%s: ETD sets list %s records (was %s)" % (r["name"], r.get("etd_records"), p.get("etd_records")))
        elif r.get("records") is not None and p.get("records") is not None and r["records"] != p["records"]:
            msgs.append("%s: OAI-PMH lists %s records (was %s)" % (r["name"], r["records"], p["records"]))
    return msgs


def run(registry_path, out_path, log=print):
    with open(registry_path) as fh:
        import yaml
        reg = yaml.safe_load(fh) or {}
    entries = [e for e in (reg.get("institutions") or []) + (reg.get("other_repositories") or [])
               if (e.get("repository") or e.get("oai")) and e.get("status") != "harvested"]
    cur = []
    for e in entries:
        r = check_one(e)
        cur.append(r)
        log("%-45s %-11s page=%s oai=%s records=%s etd=%s" % (
            r["name"][:45], "reachable" if r["reachable"] else "UNREACHABLE", r.get("page"),
            r.get("oai_ok"), r.get("records"), r.get("etd_records")))
    prev = []
    if os.path.exists(out_path):
        try:
            prev = json.load(open(out_path)).get("repositories", [])
        except (ValueError, OSError):
            prev = []
    changes = _changes(prev, cur)
    for c in changes:
        log("CHANGE: " + c)
    doc = {"checked_at": datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
           "repositories": cur, "changes": changes}
    tmp = out_path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(doc, fh, indent=1)
    os.replace(tmp, out_path)
    return doc
