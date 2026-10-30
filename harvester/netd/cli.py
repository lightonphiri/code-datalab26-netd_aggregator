"""Command line:  python -m netd.cli <command> [options]

  harvest  [--source ID] [--full] [--limit N]   fetch OAI-PMH records into the raw store
  process  [--source ID]                        crosswalk + enrichers -> canonical records
  index    [--source ID]                        push canonical records to Solr
  run      [--source ID] [--full]               harvest + process + index (scheduled job)
  report                                        field completeness per institution
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


def do_process(store, srcs, ecfg):
    fns = enrich.load(ecfg.get("enrichers"))
    minc = float(ecfg.get("min_confidence", 0.0))
    n = 0
    for src in srcs:
        names = store.set_names(src["id"])
        for row in store.raw_records(src["id"]):
            rec = crosswalk.to_canonical(row, src, names)
            rid = crosswalk.record_id(src["id"], row["oai_id"])
            if rec is None:
                store.delete_record(rid)
                continue
            store.put_record(enrich.run(rec, fns, minc))
            n += 1
    store.commit()
    print("processed %d records" % n)


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
        gone = [crosswalk.record_id(src["id"], r["oai_id"]) for r in store.raw_records(src["id"]) if r["deleted"]]
        index.delete_ids(solr, gone)
    index.post(solr, [], commit=True)
    print("indexed into %s" % solr)


def do_report(store):
    fields = ["title", "author", "supervisor", "subject", "faculty", "department", "degree_level", "year"]
    stats = {}
    for rec in store.records():
        s = stats.setdefault(rec["institution_short"], {"n": 0, **{f: 0 for f in fields}})
        s["n"] += 1
        for f in fields:
            s[f] += bool(rec.get(f))
    print("institution  records  " + "  ".join(fields))
    for inst, s in sorted(stats.items()):
        print("%-11s %8d  " % (inst, s["n"]) + "  ".join(
            "%*.0f%%" % (len(f) - 1, 100.0 * s[f] / max(s["n"], 1)) for f in fields))


def main(argv=None):
    p = argparse.ArgumentParser(prog="netd")
    p.add_argument("command", choices=["harvest", "process", "index", "run", "report"])
    p.add_argument("--source")
    p.add_argument("--full", action="store_true")
    p.add_argument("--limit", type=int)
    p.add_argument("--db", default=os.environ.get("NETD_DB", os.path.join(HERE, "netd.sqlite3")))
    p.add_argument("--solr", default=os.environ.get("NETD_SOLR", "http://127.0.0.1:8983/solr/netd"))
    a = p.parse_args(argv)
    sources = cfg_load("sources.yml").get("sources", [])
    srcs = selected(sources, a.source)
    if not srcs and a.command != "report":
        sys.exit("unknown source %r" % a.source)
    store = Store(a.db)
    if a.command in ("harvest", "run"):
        for s in srcs:
            harvest.harvest_source(store, s, full=a.full, limit=a.limit)
    if a.command in ("process", "run"):
        do_process(store, srcs, cfg_load("enrichers.yml"))
    if a.command in ("index", "run"):
        do_index(store, srcs, a.solr)
    if a.command == "report":
        do_report(store)


if __name__ == "__main__":
    main()
