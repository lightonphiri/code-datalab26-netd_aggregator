"""Command line:  python -m netd.cli <command> [options]

  harvest  [--source ID] [--full] [--limit N]   fetch OAI-PMH records into the raw store
  process  [--source ID]                        crosswalk + enrichers -> canonical records
  index    [--source ID]                        push canonical records to Solr
  run      [--source ID] [--full]               harvest + process + index (scheduled job)
  report                                        field completeness per institution
  csv-check FILE                                list problems in an HEI's CSV file before it is loaded (FR-10)
  check    [--max-age-hours H]                  health check after the scheduled run, incl. OAI-PMH Identify (exit 1 = problem)
"""
import argparse
import os
import sys

import yaml

from . import crosswalk, enrich, harvest, index
from .store import Store

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def cfg_load(name):
    path = os.environ.get("NETD_" + name.upper().split(".")[0], os.path.join(HERE, name))
    if not os.path.exists(path):
        return {}
    with open(path) as fh:
        return yaml.safe_load(fh) or {}


def selected(sources, sid):
    return [s for s in sources if not sid or s["id"] == sid]


def exclusion(rec, src, scope):
    """Reason to leave a record out of the portal (SRS FR-47), or None. The raw record is kept either way."""
    for e in src.get("exclude_records") or []:
        if e.get("oai_id") == rec["oai_id"]:
            return "listed in sources.yml: %s" % (e.get("reason") or "excluded by the portal team")
    levels = scope.get("degree_levels") or list(crosswalk.POSTGRADUATE)
    lvl = (rec.get("degree_level") or [None])[0]
    if lvl and lvl not in levels:  # unknown level: kept (ETD collections are postgraduate)
        return "degree level %s is out of scope (%s from %s)" % (
            lvl, "only " + ", ".join(levels), rec.get("provenance", {}).get("degree_level", "?"))
    return None


def do_process(store, srcs, ecfg, scope=None):
    fns = enrich.load(ecfg.get("enrichers"))
    minc = float(ecfg.get("min_confidence", 0.0))
    n = x = 0
    for src in srcs:
        names = store.set_names(src["id"])
        files = store.bitstreams(src["id"])
        store.clear_excluded(src["id"])
        for row in store.raw_records(src["id"]):
            rec = crosswalk.to_canonical(row, src, names, files.get(row["oai_id"]))
            rid = crosswalk.record_id(src["id"], row["oai_id"])
            if rec is None:
                store.delete_record(rid)
                continue
            rec = enrich.run(rec, fns, minc)
            why = exclusion(rec, src, scope or {})
            if why:
                store.delete_record(rid)
                store.put_excluded(rid, src["id"], row["oai_id"], (rec.get("title") or [""])[0], why)
                x += 1
                continue
            store.put_record(rec)
            n += 1
    store.commit()
    print("processed %d records; %d excluded (see netd.cli report)" % (n, x))


def do_index(store, srcs, solr):
    for src in srcs:
        batch = []
        for rec in store.records(src["id"]):
            batch.append(index.to_solr(rec))
            if len(batch) >= 500:
                index.post(solr, batch)
                batch = []
        if batch:
            index.post(solr, batch)
        # remove from Solr whatever the store no longer holds (deleted at source, excluded, or renamed)
        index.delete_ids(solr, sorted(index.ids(solr, src["id"]) - store.record_ids(src["id"])))
    index.post(solr, [], commit=True)
    print("indexed into %s" % solr)


def do_report(store):
    fields = ["title", "author", "supervisor", "subject", "faculty", "department", "discipline", "degree",
              "degree_level", "year", "pdf_url"]
    stats = {}
    for rec in store.records():
        s = stats.setdefault(rec["institution_short"], {"n": 0, **{f: 0 for f in fields}})
        s["n"] += 1
        for f in fields:
            s[f] += bool(rec.get(f))
    print("institution  records  " + "  ".join(fields))
    for r in store.excluded():
        print("excluded: %s  %s  (%s)" % (r["id"], (r["title"] or "")[:70], r["reason"]))
    for inst, s in sorted(stats.items()):
        print("%-11s %8d  " % (inst, s["n"]) + "  ".join(
            "%*.0f%%" % (len(f) - 1, 100.0 * s[f] / max(s["n"], 1)) for f in fields))


def do_check(store, srcs, solr, max_age_hours):
    """Fail (exit 1) if any source's latest harvest failed or is stale, or Solr disagrees with the store."""
    import json
    import time
    import urllib.request
    problems = []
    for src in srcs:
        r = store.db.execute("SELECT status, message, started_at FROM harvest_runs WHERE source=? "
                             "ORDER BY started_at DESC LIMIT 1", (src["id"],)).fetchone()
        if r is None:
            problems.append("%s: never harvested" % src["id"])
            continue
        if r["status"] != "ok":
            problems.append("%s: latest harvest status=%s %s" % (src["id"], r["status"], r["message"] or ""))
        age = (time.time() - r["started_at"]) / 3600.0
        if age > max_age_hours:
            problems.append("%s: latest harvest is %.0f hours old" % (src["id"], age))
    stored = {r["source"]: r["n"] for r in store.db.execute("SELECT source, count(*) n FROM records GROUP BY source")}
    try:
        q = solr + "/select?q=*:*&rows=0&facet=true&facet.field=source_ssi&facet.limit=-1&wt=json"
        res = json.load(urllib.request.urlopen(q, timeout=60))
        f = res["facet_counts"]["facet_fields"]["source_ssi"]
        indexed = dict(zip(f[::2], f[1::2]))
        total = res["response"]["numFound"]
    except Exception as e:
        problems.append("Solr not answering: %s" % e)
        indexed, total = {}, 0
    if indexed or total:
        for src in srcs:
            a, b = stored.get(src["id"], 0), indexed.get(src["id"], 0)
            if a == 0:
                problems.append("%s: no records in the staging store" % src["id"])
            elif b < 0.9 * a:
                problems.append("%s: %d records stored but only %d in the search index" % (src["id"], a, b))
    print("check: %d records indexed; sources %s" % (total, ", ".join(
        "%s=%d" % (s["id"], indexed.get(s["id"], 0)) for s in srcs)))
    oai = os.environ.get("NETD_OAI", "http://127.0.0.1:3010/oai")
    try:
        body = urllib.request.urlopen(oai + "?verb=Identify", timeout=30).read().decode("utf-8", "replace")
        if "<repositoryName>" not in body or "<error" in body:
            problems.append("OAI-PMH Identify did not return a valid response")
    except Exception as e:
        problems.append("OAI-PMH data provider not answering: %s" % e)
    for p in problems:
        print("PROBLEM: " + p)
    if problems:
        sys.exit(1)
    print("check: OK")


def main(argv=None):
    p = argparse.ArgumentParser(prog="netd")
    p.add_argument("command", choices=["harvest", "process", "index", "run", "report", "check", "csv-check"])
    p.add_argument("file", nargs="?", help="CSV file (csv-check)")
    p.add_argument("--source")
    p.add_argument("--full", action="store_true")
    p.add_argument("--limit", type=int)
    p.add_argument("--max-age-hours", type=float, default=30)
    p.add_argument("--db", default=os.environ.get("NETD_DB", os.path.join(HERE, "netd.sqlite3")))
    p.add_argument("--solr", default=os.environ.get("NETD_SOLR", "http://127.0.0.1:8983/solr/netd"))
    a = p.parse_args(argv)
    if a.command == "csv-check":
        from .csvload import check_file
        if not a.file:
            sys.exit("usage: netd.cli csv-check FILE")
        sys.exit(1 if check_file(a.file) else 0)
    scfg = cfg_load("sources.yml")
    sources = scfg.get("sources", [])
    # sources added from the admin panel (CSV institutions), kept on the server only
    local = os.environ.get("NETD_SOURCES_LOCAL", os.path.join(HERE, "sources.local.yml"))
    if os.path.exists(local):
        with open(local) as fh:
            sources += (yaml.safe_load(fh) or {}).get("sources", [])
    srcs = selected(sources, a.source)
    if not srcs and a.command != "report":
        sys.exit("unknown source %r" % a.source)
    store = Store(a.db)
    if a.command in ("harvest", "run"):
        for s in srcs:
            harvest.harvest_source(store, s, full=a.full, limit=a.limit)
    if a.command in ("process", "run"):
        do_process(store, srcs, cfg_load("enrichers.yml"), scfg.get("scope"))
    if a.command in ("index", "run"):
        do_index(store, srcs, a.solr)
    if a.command == "report":
        do_report(store)
    if a.command == "check":
        do_check(store, srcs, a.solr, a.max_age_hours)


if __name__ == "__main__":
    main()
