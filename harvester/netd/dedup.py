"""Duplicate ETDs (SRS FR-19): the same thesis deposited twice, in one repository or in two.

Matching, after processing and over every source:
1. the same DOI;
2. otherwise titles that are the same or nearly the same (similarity >= 0.93 after folding case, accents and
   punctuation), whose authors are compatible (a shared name word of 3+ letters, or two name words that differ by
   a typing slip, e.g. "Rahael"/"Rachael"; a record with no author is compatible) and whose years are at most
   2 apart (or missing).
Matches are joined into groups. In each group one record is the main record: the admin's choice (correction
`_duplicate` = ["primary"]) or else the most complete (PDF, then filled fields, then the later deposit). The others
are "duplicate of" it: the portal lists the thesis once in search, facets and counts and links the copies (FR-19,
Lighton, November 2, 2026). A correction `_duplicate` = ["distinct"] takes a record out of matching for good.
Records are never deleted or merged: each repository's record stays as harvested.
"""
import difflib
import json
import re
import time
import unicodedata

SCHEMA = """
CREATE TABLE IF NOT EXISTS duplicates (      -- FR-19: one row per record that duplicates a main record
    id          TEXT PRIMARY KEY,
    primary_id  TEXT NOT NULL,
    method      TEXT NOT NULL,              -- doi | title+author+year
    score       REAL,                       -- title similarity
    found_at    REAL
);
"""
TITLE_MIN = 0.93
YEAR_GAP = 2
COMPLETE = ("author", "supervisor", "subject", "abstract", "faculty", "department", "degree", "degree_level",
            "discipline", "year")


def fold(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    s = re.sub(r"[^a-z0-9]+", " ", s).strip()
    return re.sub(r"^(a|an|the) ", "", s)


def names(rec):
    return {w for a in rec.get("author") or [] for w in fold(a).split() if len(w) >= 3}


def authors_compatible(a, b):
    if not a or not b or a & b:
        return True
    return any(len(x) >= 5 and difflib.SequenceMatcher(None, x, y).ratio() >= 0.85 for x in a for y in b)


def years_close(a, b):
    ya, yb = (a.get("year") or [None])[0], (b.get("year") or [None])[0]
    try:
        return ya is None or yb is None or abs(int(ya) - int(yb)) <= YEAR_GAP
    except (TypeError, ValueError):
        return True


def doi(rec):
    for v in (rec.get("doi") or []) + (rec.get("identifier") or []):
        m = re.search(r"10\.\d{4,9}/\S+", str(v))
        if m:
            return m.group(0).lower().rstrip(".")
    return None


def find(records, decisions=None):
    """records: canonical records; decisions: {record_id: "distinct"|"primary"}.
    Returns {secondary_id: (primary_id, method, score)}."""
    decisions = decisions or {}
    recs = [r for r in records if decisions.get(r["id"]) != "distinct" and r.get("title")]
    title = {r["id"]: fold(r["title"][0]) for r in recs}
    who = {r["id"]: names(r) for r in recs}
    parent = {r["id"]: r["id"] for r in recs}
    how = {}

    def root(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def join(a, b, method, score):
        ra, rb = root(a), root(b)
        if ra != rb:
            parent[rb] = ra
        how[frozenset((a, b))] = (method, score)

    by_doi = {}
    for r in recs:
        d = doi(r)
        if d:
            by_doi.setdefault(d, []).append(r["id"])
    for ids in by_doi.values():
        for other in ids[1:]:
            join(ids[0], other, "doi", 1.0)
    # blocking: records sharing a name word, or the same first three title words, are compared
    blocks = {}
    for r in recs:
        for w in who[r["id"]] or {"~" + " ".join(title[r["id"]].split()[:3])}:
            blocks.setdefault(w, []).append(r)
        blocks.setdefault("~" + " ".join(title[r["id"]].split()[:3]), []).append(r)
    seen = set()
    for block in blocks.values():
        if len(block) < 2:
            continue
        for i, a in enumerate(block):
            ta = title[a["id"]]
            for b in block[i + 1:]:
                pair = frozenset((a["id"], b["id"]))
                if a["id"] == b["id"] or pair in seen:
                    continue
                seen.add(pair)
                tb = title[b["id"]]
                if not ta or not tb or abs(len(ta) - len(tb)) > 0.1 * max(len(ta), len(tb)) + 3:
                    continue
                if ta == tb:
                    score = 1.0
                else:
                    sm = difflib.SequenceMatcher(None, ta, tb, autojunk=False)
                    score = sm.ratio() if sm.real_quick_ratio() >= TITLE_MIN and sm.quick_ratio() >= TITLE_MIN else 0.0
                if score >= TITLE_MIN and authors_compatible(who[a["id"]], who[b["id"]]) and years_close(a, b):
                    join(a["id"], b["id"], "title+author+year", round(score, 3))
    groups = {}
    for r in recs:
        groups.setdefault(root(r["id"]), []).append(r)
    out = {}
    for members in groups.values():
        if len(members) < 2:
            continue
        main = choose_primary(members, decisions)
        for r in members:
            if r["id"] != main["id"]:
                method, score = how.get(frozenset((r["id"], main["id"])), ("title+author+year", None))
                out[r["id"]] = (main["id"], method, score)
    return out


def choose_primary(members, decisions):
    chosen = [r for r in members if decisions.get(r["id"]) == "primary"]
    if chosen:
        return chosen[0]
    return max(members, key=lambda r: (bool(r.get("pdf_url")), sum(1 for f in COMPLETE if r.get(f)),
                                       r.get("datestamp") or "", r["id"]))


def decisions_from(store):
    try:
        rows = store.db.execute("SELECT record_id, value FROM corrections WHERE field='_duplicate'").fetchall()
    except Exception:  # noqa: BLE001 - no corrections table yet
        return {}
    return {r["record_id"]: (json.loads(r["value"]) or [""])[0] for r in rows}


def run(store):
    """Recompute the duplicates table from the whole store (all sources). Returns (groups, duplicate records)."""
    store.db.executescript(SCHEMA)
    found = find(list(store.records()), decisions_from(store))  # read everything first, then write (WAL)
    now = time.time()
    store.db.execute("DELETE FROM duplicates")
    store.db.executemany("INSERT INTO duplicates VALUES (?,?,?,?,?)",
                         [(rid, p, m, s, now) for rid, (p, m, s) in sorted(found.items())])
    store.commit()
    groups = len({p for p, _, _ in found.values()})
    print("duplicates: %d groups, %d records listed under a main record" % (groups, len(found)))
    return groups, len(found)


def load(store):
    """{record_id: {"duplicate_of": main id} or {"duplicates": [ids]}} for indexing."""
    store.db.executescript(SCHEMA)
    out = {}
    for r in store.db.execute("SELECT id, primary_id FROM duplicates ORDER BY id").fetchall():
        out.setdefault(r["id"], {})["duplicate_of"] = r["primary_id"]
        out.setdefault(r["primary_id"], {}).setdefault("duplicates", []).append(r["id"])
    return out
