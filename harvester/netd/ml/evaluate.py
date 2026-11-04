"""Gold-standard sample and evaluation of metadata-filling models (SRS FR-53).

gold-sample writes a CSV for manual annotation: one row per record, stratified by institution, with the record's
harvested values, links to the portal page and PDF, and empty gold_* columns. Annotators fill the gold_* columns
from the PDF (several values separated by "||"; "-" when the PDF does not state the field).

evaluate compares each model's best prediction with the gold values, field by field, and prints coverage,
precision, recall and F1 at the confidence threshold given (all predictions, and at 0.8 and 0.95 by default).
With --strata it repeats the table for the newest version of each model by kind of PDF text (born-digital,
scanned and OCRed, scanned and waiting for OCR, no PDF text), so scanned and born-digital theses are reported apart.
Manual corrections made in the admin panel are another source of gold labels (table `corrections`).
"""
import csv
import json
import random
import re
import unicodedata

from .. import config

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
    if field == "degree":  # ETD-MS degree name: discipline, abbreviations and plural forms set aside
        v = re.sub(r"\(.*?\)", " ", v)
        v = re.split(r"\s+in\s+", v, maxsplit=1, flags=re.I)[0]
        v = re.sub(r"(?i)\bmasters?'?s?\b", "master", v)
        return norm(v)
    if field == "supervisor":
        raw = unicodedata.normalize("NFKD", v).encode("ascii", "ignore").decode()
        raw = re.sub(r"\b((?i:prof(?:essor)?|dr|mrs|mr|ms))\.?(?=[A-Z])", r"\1 ", raw)  # "ProfessorY.Mulla" (case-
        # sensitive lookahead: with a global (?i), "Professor" became "Prof essor" and "Mrs" became "Mr s")
        raw = re.sub(r"(?<=\.)(?=[A-Z][a-z])", " ", raw)                             # "Y.Mulla"
        raw = TITLES.sub(" ", raw).strip(" ,;.")
        if "," in raw:
            sur, given = raw.split(",", 1)
            return (norm(sur), norm(given)[:1])
        return norm_person(raw)
    return norm(v)


def sample(store, path, n=300, seed=2026, source=None, take_all=False):
    """Stratified sample for annotation (FR-53). source: only these sources (comma-separated ids); take_all: every
    record instead of a sample (e.g. ZCAS, UNILUS and MU, small enough to annotate whole). Copies of a thesis already
    in the portal under a main record (FR-19) are left out, and each row carries its duplicate group and the half
    (dev/test) of that group, so a split keeps all copies of one thesis on the same side (session 08: the 2020 gold
    standard, split by record id, put 55 pairs on both sides)."""
    import hashlib
    rng = random.Random(seed)
    wanted = set(source.split(",")) if source else None
    copies = {r[0]: r[1] for r in store.db.execute("SELECT id, primary_id FROM duplicates")} \
        if store.db.execute("SELECT name FROM sqlite_master WHERE name='duplicates'").fetchone() else {}
    by_src, skipped = {}, 0
    for rec in store.records():
        if not rec.get("pdf_url") or (wanted is not None and rec["source"] not in wanted):
            continue
        if rec["id"] in copies:
            skipped += 1
            continue
        by_src.setdefault(rec["source"], []).append(rec)
    total = sum(len(v) for v in by_src.values())
    picks = []
    for src, recs in sorted(by_src.items()):
        k = len(recs) if take_all else min(len(recs), max(20, round(n * len(recs) / total)))
        picks += rng.sample(recs, k)
    rng.shuffle(picks)
    cols = ["record_id", "institution", "title", "portal_url", "pdf_url", "split_group", "half"] + \
           ["harvested_" + f for f in GOLD_FIELDS] + ["gold_" + f for f in GOLD_FIELDS] + ["annotator", "notes"]
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(cols)
        for r in picks:
            prov = r.get("provenance", {})
            harv = [" || ".join(r.get(f) or []) if str(prov.get(f, "")).startswith(("harvested", "set", "rule"))
                    else "" for f in GOLD_FIELDS]
            group = r["id"]   # a main record is its own group; its copies were left out above
            half = "dev" if int(hashlib.sha256(group.encode()).hexdigest(), 16) % 2 == 0 else "test"
            w.writerow([r["id"], r["institution_short"], (r.get("title") or [""])[0],
                        config.base_url() + "/catalog/" + r["id"], r["pdf_url"][0], group, half] + harv +
                       [""] * (len(GOLD_FIELDS) + 2))
    print("wrote %d records to %s (%s); %d duplicate copies left out" % (len(picks), path, ", ".join(
        "%s %d" % (s, sum(1 for p in picks if p["source"] == s)) for s in sorted(by_src)), skipped))


def read_gold(path):
    gold = {}
    with open(path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            g = {}
            for f in GOLD_FIELDS:
                v = (row.get("gold_" + f) or "").strip()
                if v:
                    sep = r"\|\||\s+and\s+|\s*&\s*" if f == "supervisor" else r"\|\|"
                    g[f] = [] if v == "-" else [x.strip() for x in re.split(sep, v) if x.strip()]
            if g:
                gold[row["record_id"]] = g
    return gold


STRATA = (("born-digital", ("ok",)), ("scanned, OCRed", ("ocr",)),
          ("scanned, not yet OCRed", ("no_text", "ocr_failed")), ("no PDF text", ("error", "too_large", None)))


def _vkey(v):
    return (0, int(v), "") if str(v).isdigit() else (1, 0, str(v))


def _person(v):
    """Surname and the initials of every given name: 'Dr. Ndonyo Likwa' -> ('likwa', {'n'})."""
    sur, given = person_words(v)
    return sur, {w[0] for w in given}


def person_words(v):
    """Surname and the given names or initials in order: 'Dr. Ndonyo Likwa' -> ('likwa', ['ndonyo'])
    (also used by netd.people, FR-64)."""
    v = re.sub(r"\s?['\u2018\u2019\u201b\u201f`]\s?(?=[a-z])", "", v)      # "Ng’andu", "Ng'andu", "Hang ’ombe"
    v = re.sub(r"(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])|(?<=\.)(?=[A-Za-z])", " ", v)  # "Dr.BeatriceMatafwali"
    sur, _ = _key("supervisor", v)
    raw = unicodedata.normalize("NFKD", v).encode("ascii", "ignore").decode()
    raw = re.sub(r"\b((?i:prof(?:essor)?|dr|mrs|mr|ms))\.?(?=[A-Z])", r"\1 ", raw)
    raw = re.sub(r"(?<=\.)(?=[A-Z])", " ", raw)
    raw = TITLES.sub(" ", raw)
    if "," in raw:
        raw = raw.split(",", 1)[1]
    words = norm(raw).split()
    if len(sur) == 1 and len(words) > 1 and len(words[-1]) == 1:   # "Dr Mapoma C", "Dr. Zyaambo C." (surname first)
        long_ = [w for w in words if len(w) > 1]
        if long_:
            sur = long_[-1]
    given = [w for w in words if w != sur]
    if len(given) == 1 and len(given[0]) > 1 and given[0].isalpha() and given[0] == given[0].lower() and \
            re.fullmatch(r"[A-Z]{2,3}", re.sub(r"[^A-Za-z]", "", raw.split()[0]) or ""):
        given = list(given[0])                     # "MM Kabemba": initials run together
    return sur, given


def _same_person(a, b):
    """Same surname, and the given names do not contradict: one side has none, or they share an initial. The 2020
    annotators wrote supervisors with or without given names and in either order ("Prof Siziya", "Ndonyo Likwa")."""
    return a[0] == b[0] and (not a[1] or not b[1] or bool(a[1] & b[1]))


def _people_tp(gv, pv):
    left, tp = list(pv), 0
    for g in gv:
        for p in left:
            if _same_person(g, p):
                left.remove(p)
                tp += 1
                break
    return tp


def _scores(gold, recs, f, t, ids):
    tp = fp = fn = predicted = n = 0
    for rid in ids:
        g = gold[rid]
        if f not in g:
            continue
        n += 1
        pv, conf = recs.get(rid, {}).get(f, ([], 0.0))
        if f == "supervisor":   # people: one-to-one matching on surname and compatible initials
            gv = list({(a, frozenset(b)) for a, b in map(_person, g[f]) if a})
            pv = list({(a, frozenset(b)) for a, b in map(_person, pv) if a}) if pv and conf >= t else []
            k = _people_tp(gv, pv)
            predicted += bool(pv)
            tp += k
            fp += len(pv) - k
            fn += len(gv) - k
            continue
        gv = {_key(f, v) for v in g[f]}
        pv = {_key(f, v) for v in pv} if pv and conf >= t else set()
        predicted += bool(pv)
        tp += len(pv & gv)
        fp += len(pv - gv)
        fn += len(gv - pv)
    p = tp / (tp + fp) if tp + fp else 0.0
    r_ = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * p * r_ / (p + r_) if p + r_ else 0.0
    return n, predicted, p, r_, f1


def _table(gold, preds, ids, thresholds):
    print("%-24s %-13s %5s  %4s %5s %6s %6s %6s" % ("model", "field", "thr", "n", "cover", "prec", "recall", "F1"))
    for (model, version), recs in preds:
        for f in GOLD_FIELDS:
            if not any(f in r for r in recs.values()):
                continue
            for t in thresholds:
                n, predicted, p, r_, f1 = _scores(gold, recs, f, t, ids)
                if n:
                    print("%-24s %-13s %5.2f  %4d %5.0f%% %6.3f %6.3f %6.3f" % (
                        "%s-%s" % (model, version), f, t, n, 100.0 * predicted / n, p, r_, f1))


def evaluate(store, path, thresholds=(0.0, 0.8, 0.95), strata=False):
    """All gold records, then (strata=True) the newest version of each model by kind of PDF text (FR-53):
    born-digital, scanned and OCRed, scanned and still waiting for OCR, and records with no PDF text."""
    gold = read_gold(path)
    preds = {}
    for r in store.db.execute("SELECT * FROM predictions"):
        preds.setdefault((r["model"], r["version"]), {}).setdefault(r["record_id"], {})[r["field"]] = (
            json.loads(r["value"]), r["confidence"] or 0.0)
    print("gold records: %d" % len(gold))
    _table(gold, sorted(preds.items()), list(gold), thresholds)
    if not strata:
        return
    status = {}
    try:
        status = dict(store.db.execute("SELECT record_id, status FROM pdf_text").fetchall())
    except Exception:  # noqa: BLE001 - no text cache yet: every record falls in "no PDF text"
        pass
    newest = {}
    for (model, version), recs in preds.items():
        if model not in newest or _vkey(version) > _vkey(newest[model][0][1]):
            newest[model] = ((model, version), recs)
    for name, states in STRATA:
        ids = [rid for rid in gold if status.get(rid) in states]
        print("\n== %s: %d gold records ==" % (name, len(ids)))
        if ids:
            _table(gold, sorted(newest.values()), ids, thresholds)
