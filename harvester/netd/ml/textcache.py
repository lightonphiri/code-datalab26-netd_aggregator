"""Cache of text from the first pages of each record's PDF (SRS FR-48).

Title, declaration, approval and abstract pages carry the evidence the models use ("submitted ... in partial
fulfilment of the requirements for the award of the degree of Master of ...", "Supervisor: ...", the department).
Only the first `pages` pages are kept. A PDF is fetched again only when the record's PDF link changes or a
previous attempt failed and `retry_failed` is set.
"""
import hashlib
import sys
import tempfile
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

UA = "NETD metadata enrichment (+https://netd.ac.zm)"

SCHEMA = """
CREATE TABLE IF NOT EXISTS pdf_text (
    record_id  TEXT PRIMARY KEY,
    url        TEXT NOT NULL,
    status     TEXT NOT NULL,      -- ok | no_text (scanned, needs OCR) | too_large | error
    pages      INTEGER,            -- pages in the PDF
    text       TEXT,               -- text of the first pages, pages separated by form feeds
    text_hash  TEXT,               -- sha256 of text: models' input hash starts from this
    message    TEXT,
    fetched_at REAL
);
"""


def extract(path, pages):
    from pypdf import PdfReader  # imported here so the rest of the harvester runs without it
    r = PdfReader(path, strict=False)
    out = []
    for p in r.pages[:pages]:
        try:
            out.append(p.extract_text() or "")
        except Exception:  # a broken page should not lose the others
            out.append("")
    return len(r.pages), "\f".join(out)


def fetch_one(url, pages, max_mb, timeout):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as resp, tempfile.NamedTemporaryFile(suffix=".pdf") as tmp:
        size, limit = 0, max_mb * 1024 * 1024
        while True:
            chunk = resp.read(1 << 16)
            if not chunk:
                break
            size += len(chunk)
            if size > limit:
                return "too_large", None, None, "larger than %d MB" % max_mb
            tmp.write(chunk)
        tmp.flush()
        n, text = extract(tmp.name, pages)
    if len(text.replace("\f", "").strip()) < 80:
        return "no_text", n, text, "no text layer (scanned?)"
    return "ok", n, text, None


def pending(store, source=None, retry_failed=False, limit=None):
    """(record_id, url) for records whose PDF text is missing, out of date, or (optionally) failed before."""
    have = {r["record_id"]: (r["url"], r["status"]) for r in store.db.execute("SELECT record_id, url, status FROM pdf_text")}
    out = []
    for rec in store.records(source):
        url = (rec.get("pdf_url") or [None])[0]
        if not url:
            continue
        old = have.get(rec["id"])
        if old is None or old[0] != url or (retry_failed and old[1] in ("error", "too_large")):
            out.append((rec["id"], url))
    return out[:limit] if limit else out


def run(store, source=None, pages=8, max_mb=60, timeout=180, workers=2, pause=1.0, retry_failed=False, limit=None):
    store.db.executescript(SCHEMA)
    todo = pending(store, source, retry_failed, limit)
    print("extract-text: %d PDFs to fetch" % len(todo), flush=True)
    done = ok = 0

    def work(item):
        rid, url = item
        try:
            status, n, text, msg = fetch_one(url, pages, max_mb, timeout)
        except Exception as e:  # network errors, broken PDFs
            status, n, text, msg = "error", None, None, str(e)[:300]
        time.sleep(pause)
        return rid, url, status, n, text, msg

    with ThreadPoolExecutor(max_workers=workers) as ex:  # threads only fetch; SQLite is written here
        for rid, url, status, n, text, msg in ex.map(work, todo):
            h = hashlib.sha256(text.encode("utf-8")).hexdigest() if text else None
            store.db.execute("INSERT OR REPLACE INTO pdf_text VALUES (?,?,?,?,?,?,?,?)",
                             (rid, url, status, n, text, h, msg, time.time()))
            done += 1
            ok += status == "ok"
            if done % 25 == 0:
                store.commit()
                print("extract-text: %d/%d (%d with text)" % (done, len(todo), ok), flush=True)
    store.commit()
    print("extract-text: finished %d (%d with text)" % (done, ok), flush=True)


def summary(store):
    store.db.executescript(SCHEMA)
    rows = store.db.execute("SELECT substr(record_id,1,instr(record_id,'-')-1) src, status, count(*) n "
                            "FROM pdf_text GROUP BY src, status ORDER BY src, status").fetchall()
    for r in rows:
        print("%-8s %-10s %6d" % (r["src"], r["status"], r["n"]))
    if not rows:
        print("no PDF text cached yet", file=sys.stderr)
