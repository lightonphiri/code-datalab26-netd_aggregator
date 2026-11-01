"""Gold-standard sample and evaluation of metadata-filling models (SRS FR-53).

gold-sample writes a CSV for manual annotation: one row per record, stratified by institution, with the record's
harvested values, links to the portal page and PDF, and empty gold_* columns. Annotators fill the gold_* columns
from the PDF (several values separated by "||"; "-" when the PDF does not state the field).

evaluate compares each model's best prediction with the gold values, field by field, and prints coverage,
precision, recall and F1 at the confidence threshold given (all predictions, and at 0.8 and 0.95 by default).
Manual corrections made in the admin panel are another source of gold labels (table `corrections`).
"""
import csv
import json
import random
import re
import unicodedata

GOLD_FIELDS = ("degree_level", "degree", "discipline", "supervisor", "department", "faculty")
TITLES = re.compile(r"\b(prof(essor)?|dr|mr|mrs|ms|rev|eng)\b\.?", re.I)


def norm(v):
    v = unicodedata.normalize("NFKD", v).encode("ascii", "ignore").decode().lower()
    v = TITLES.sub(" ", v)
    v = re.sub(r"\b(department|school|faculty|of|the|and|&)\b", " ", v)
    return re.sub(r"[^a-z0-9]+", " ", v).strip()


def norm_person(v):
    """'Phiri, Lighton' and 'Dr L. Phiri' both -> ('phiri', 'l')."""
    v = norm(v)
    parts = v.split()
    if not parts:
        return ("", "")
    return (parts[-1], parts[0][:1]) if len(parts) > 1 else (parts[0], "")


def _key(field, v):
    if field == "supervisor":
        raw = unicodedata.normalize("NFKD", v).encode("ascii", "ignore").decode()
        raw = TITLES.sub(" ", raw)
        if "," in raw:
            sur, given = raw.split(",", 1)
            return (norm(sur), norm(given)[:1])
        return norm_person(raw)
    return norm(v)


def sample(store, path, n=300, seed=2026):
    rng = random.Random(seed)
    by_src = {}
    for rec in store.records():
        if rec.get("pdf_url"):
            by_src.setdefault(rec["source"], []).append(rec)
    total = sum(len(v) for v in by_src.values())
    picks = []
    for src, recs in sorted(by_src.items()):
        k = min(len(recs), max(20, round(n * len(recs) / total)))
        picks += rng.sample(recs, k)
    rng.shuffle(picks)
    cols = ["record_id", "institution", "title", "portal_url", "pdf_url"] + \
           ["harvested_" + f for f in GOLD_FIELDS] + ["gold_" + f for f in GOLD_FIELDS] + ["annotator", "notes"]
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(cols)
        for r in picks:
            prov = r.get("provenance", {})
            harv = [" || ".join(r.get(f) or []) if str(prov.get(f, "")).startswith(("harvested", "set", "rule"))
                    else "" for f in GOLD_FIELDS]
            w.writerow([r["id"], r["institution_short"], (r.get("title") or [""])[0],
                        "https://netd.ac.zm/catalog/" + r["id"], r["pdf_url"][0]] + harv + [""] * (len(GOLD_FIELDS) + 2))
    print("wrote %d records to %s (%s)" % (len(picks), path, ", ".join(
        "%s %d" % (s, sum(1 for p in picks if p["source"] == s)) for s in sorted(by_src))))


def read_gold(path):
    gold = {}
    with open(path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            g = {}
            for f in GOLD_FIELDS:
                v = (row.get("gold_" + f) or "").strip()
                if v:
                    g[f] = [] if v == "-" else [x.strip() for x in v.split("||") if x.strip()]
            if g:
                gold[row["record_id"]] = g
    return gold


def evaluate(store, path, thresholds=(0.0, 0.8, 0.95)):
    gold = read_gold(path)
    preds = {}
    for r in store.db.execute("SELECT * FROM predictions"):
        preds.setdefault((r["model"], r["version"]), {}).setdefault(r["record_id"], {})[r["field"]] = (
            json.loads(r["value"]), r["confidence"] or 0.0)
    print("gold records: %d" % len(gold))
    print("%-24s %-13s %5s  %4s %5s %6s %6s %6s" % ("model", "field", "thr", "n", "cover", "prec", "recall", "F1"))
    for (model, version), recs in sorted(preds.items()):
        for f in GOLD_FIELDS:
            for t in thresholds:
                tp = fp = fn = predicted = n = 0
                for rid, g in gold.items():
                    if f not in g:
                        continue
                    n += 1
                    gv = {_key(f, v) for v in g[f]}
                    pv, conf = recs.get(rid, {}).get(f, ([], 0.0))
                    pv = {_key(f, v) for v in pv} if pv and conf >= t else set()
                    predicted += bool(pv)
                    tp += len(pv & gv)
                    fp += len(pv - gv)
                    fn += len(gv - pv)
                if not n or not any(f in r for r in recs.values()):
                    continue
                p = tp / (tp + fp) if tp + fp else 0.0
                r_ = tp / (tp + fn) if tp + fn else 0.0
                f1 = 2 * p * r_ / (p + r_) if p + r_ else 0.0
                print("%-24s %-13s %5.2f  %4d %5.0f%% %6.3f %6.3f %6.3f" % (
                    "%s-%s" % (model, version), f, t, n, 100.0 * predicted / n, p, r_, f1))
