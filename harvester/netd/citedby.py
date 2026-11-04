"""Cited by (SRS FR-69): match portal theses to OpenAlex works and keep the works that cite them.

Run daily before the nightly harvest (`netd.cli cited-by`, under run.lock); each thesis is checked again after
`max_age_days`, so the whole collection is refreshed about weekly within OpenAlex's free daily allowance.

Matching (Lighton, November 4, 2026): normalised title and year. OpenAlex is asked for up to 40 theses in one call
(an OR of title phrases, the first ten words of each title), which costs one list call ($0.001 in November 2026)
instead of 40. A work matches a thesis when the word sets of the two titles overlap by at least 0.8 (Jaccard), the
years differ by at most one, and the work is a dissertation (or an untyped item with no DOI), never an article: a
work whose primary location is a journal is not the thesis even when OpenAlex calls it a dissertation (an article
derived from a thesis, or the two merged). A work that matches two theses is left unmatched for both.

Citing works are fetched for matched works with citations (`cites:` filter, up to 50 works per call); a citing work
whose title is the thesis's own title (another copy of it) is left out. Results are kept in the store table
`openalex_citations` and indexed into Solr by `index` (`openalex_id_ssi`, `cited_by_isi`, `cited_by_ssm`).

An API key (free OpenAlex account) is read from OPENALEX_API_KEY; without one OpenAlex allows $0.10 a day.
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.openalex.org/works"
BATCH = 40          # theses per title query (URL about 4,000 characters)
CITES_BATCH = 50    # works per cites: query
MIN_WORDS = 4       # shorter titles are too ambiguous to match on
SIM = 0.8
UA = "netd.ac.zm cited-by (Zambia National ETD Portal)"

SCHEMA = """
CREATE TABLE IF NOT EXISTS openalex_citations (
    record_id      TEXT PRIMARY KEY,
    openalex_id    TEXT,               -- W..., NULL when no work matched
    cited_by_count INTEGER,            -- OpenAlex's count for the work
    citing         TEXT,               -- JSON list of citing works shown on the record page
    checked_at     REAL NOT NULL
);
"""


def norm(s):
    return re.sub(r"[^a-z0-9 ]", " ", (s or "").lower()).split()


def jaccard(a, b):
    a, b = set(a), set(b)
    return len(a & b) / len(a | b) if a and b else 0.0


class Budget(Exception):
    pass


class Client:
    def __init__(self, key=None, max_calls=80, min_usd=0.01):
        self.key, self.max_calls, self.min_usd, self.calls = key, max_calls, min_usd, 0
        self.remaining = None

    def get(self, **q):
        if self.calls >= self.max_calls or (self.remaining is not None and self.remaining < self.min_usd):
            raise Budget()
        if self.key:
            q["api_key"] = self.key
        req = urllib.request.Request(API + "?" + urllib.parse.urlencode(q), headers={"User-Agent": UA})
        for attempt in range(3):
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    self.calls += 1
                    try:
                        self.remaining = float(r.headers.get("X-RateLimit-Remaining-USD"))
                    except (TypeError, ValueError):
                        pass
                    return json.load(r)
            except urllib.error.HTTPError as e:
                if e.code in (402, 409, 429):  # allowance used up for today
                    raise Budget() from e
                if attempt == 2 or e.code < 500:
                    raise
            except OSError:
                if attempt == 2:
                    raise
            time.sleep(5 * (attempt + 1))

    def all_pages(self, max_pages=3, **q):
        q.update({"per-page": 200, "cursor": "*"})
        out = []
        for _ in range(max_pages):
            r = self.get(**q)
            out += r.get("results") or []
            q["cursor"] = (r.get("meta") or {}).get("next_cursor")
            if not q["cursor"] or len(r.get("results") or []) < 200:
                break
        return out


def acceptable(work):
    src = ((work.get("primary_location") or {}).get("source") or {})
    if src.get("type") == "journal":
        return False
    return work.get("type") == "dissertation" or (work.get("type") == "other" and not work.get("doi"))


def best_match(title, year, works):
    t = norm(title)
    best = None
    for w in works:
        s = jaccard(t, norm(w.get("display_name")))
        if s < SIM or not acceptable(w):
            continue
        wy = w.get("publication_year")
        if year and wy and abs(int(year) - int(wy)) > 1:
            continue
        rank = (w.get("type") == "dissertation", s)
        if best is None or rank > best[0]:
            best = (rank, w)
    return best[1] if best else None


def theses(solr):
    """Main records (other copies of duplicates left out): id, title, year."""
    out, start = [], 0
    while True:
        q = urllib.parse.urlencode({"q": "*:*", "fq": "-duplicate_of_ssi:[* TO *]", "fl": "id,title_tsim,year_ssim",
                                    "rows": 2000, "start": start, "sort": "id asc", "wt": "json"})
        docs = json.load(urllib.request.urlopen(solr + "/select?" + q, timeout=60))["response"]["docs"]
        out += [(d["id"], (d.get("title_tsim") or [""])[0], (d.get("year_ssim") or [""])[0][:4]) for d in docs]
        start += len(docs)
        if len(docs) < 2000:
            return out


def citing_works(client, by_work):
    """{work id: thesis title} -> {work id: [citing work, ...]}."""
    ids = sorted(by_work)
    out = {w: [] for w in ids}
    for i in range(0, len(ids), CITES_BATCH):
        part = ids[i:i + CITES_BATCH]
        for c in client.all_pages(max_pages=5, filter="cites:" + "|".join(part),
                                  select="id,doi,display_name,publication_year,type,referenced_works"):
            refs = {r.rsplit("/", 1)[-1] for r in c.get("referenced_works") or []}
            for w in part:
                if w in refs and jaccard(norm(by_work[w]), norm(c.get("display_name"))) < SIM:
                    out[w].append({"id": c["id"].rsplit("/", 1)[-1], "title": c.get("display_name") or "",
                                   "year": c.get("publication_year"), "type": c.get("type"),
                                   "url": c.get("doi") or c["id"]})
    for w in out:
        out[w].sort(key=lambda c: (-(c["year"] or 0), c["title"]))
    return out


def run(store, solr, max_calls=80, max_age_days=7, key=None):
    db = store.db
    db.executescript(SCHEMA)
    key = key or os.environ.get("OPENALEX_API_KEY") or None
    client = Client(key=key, max_calls=max_calls)
    checked = {r[0]: r[1] for r in db.execute("SELECT record_id, checked_at FROM openalex_citations").fetchall()}
    cutoff = time.time() - max_age_days * 86400
    todo = sorted((t for t in theses(solr) if checked.get(t[0], 0) < cutoff), key=lambda t: checked.get(t[0], 0))
    done, matched, stopped = 0, {}, False
    try:
        for i in range(0, len(todo), BATCH):
            part = todo[i:i + BATCH]
            usable = [t for t in part if len(norm(t[1])) >= MIN_WORDS]
            works = []
            if usable:
                q = " OR ".join('"%s"' % " ".join(norm(t[1])[:10]) for t in usable)
                works = client.all_pages(filter="title.search:" + q,
                                         select="id,doi,display_name,type,publication_year,cited_by_count,primary_location")
            now = time.time()
            rows = []
            for rid, title, year in part:
                w = best_match(title, year, works) if len(norm(title)) >= MIN_WORDS else None
                wid = w["id"].rsplit("/", 1)[-1] if w else None
                if w:
                    matched[rid] = (wid, w.get("cited_by_count") or 0, title)
                rows.append((rid, wid, (w or {}).get("cited_by_count"), now))
            # read nothing while writing (WAL rule): rows are complete before the write
            db.executemany("""INSERT INTO openalex_citations (record_id, openalex_id, cited_by_count, citing, checked_at)
                              VALUES (?, ?, ?, '[]', ?) ON CONFLICT(record_id) DO UPDATE SET
                              openalex_id = excluded.openalex_id, cited_by_count = excluded.cited_by_count,
                              citing = '[]', checked_at = excluded.checked_at""", rows)
            db.commit()
            done += len(part)
    except Budget:
        stopped = True
    # citing works for the theses matched in this run that OpenAlex says are cited
    cited = {wid: title for rid, (wid, n, title) in matched.items() if n > 0}
    try:
        lists = citing_works(client, cited) if cited else {}
        rows = [(json.dumps(lists[wid], ensure_ascii=False), rid) for rid, (wid, n, t) in matched.items() if wid in lists]
        db.executemany("UPDATE openalex_citations SET citing = ? WHERE record_id = ?", rows)
        db.commit()
    except Budget:
        stopped = True  # the counts stay; the lists are fetched on the next check of those theses
        db.executemany("UPDATE openalex_citations SET checked_at = 0 WHERE record_id = ?",
                       [(rid,) for rid, (wid, n, t) in matched.items() if n > 0])
        db.commit()
    # one work, two theses: ambiguous, leave both unmatched
    dup = [r[0] for r in db.execute("""SELECT record_id FROM openalex_citations WHERE openalex_id IN
             (SELECT openalex_id FROM openalex_citations WHERE openalex_id IS NOT NULL
              GROUP BY openalex_id HAVING count(*) > 1)""").fetchall()]
    if dup:
        db.executemany("UPDATE openalex_citations SET openalex_id = NULL, cited_by_count = NULL, citing = '[]' "
                       "WHERE record_id = ?", [(r,) for r in dup])
        db.commit()
    tot = db.execute("""SELECT count(*), count(openalex_id), sum(json_array_length(citing) > 0)
                        FROM openalex_citations""").fetchone()
    print("cited-by: %d theses checked in %d OpenAlex calls (%s key)%s; %d ambiguous; store: %d checked, %d matched, "
          "%d cited" % (done, client.calls, "with" if key else "no", ", stopped at the daily budget" if stopped else "",
                        len(dup), tot[0], tot[1], tot[2] or 0), file=sys.stderr)


def load(store):
    """record id -> (OpenAlex id, citing works) for indexing; empty if the job has never run."""
    if not store.db.execute("SELECT 1 FROM sqlite_master WHERE name='openalex_citations'").fetchone():
        return {}
    return {r[0]: (r[1], json.loads(r[2] or "[]")) for r in store.db.execute(
        "SELECT record_id, openalex_id, citing FROM openalex_citations WHERE openalex_id IS NOT NULL").fetchall()}
