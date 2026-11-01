"""Cache of text from the first pages of each record's PDF (SRS FR-48).

Title, declaration, approval and abstract pages carry the evidence the models use ("submitted ... in partial
fulfilment of the requirements for the award of the degree of Master of ...", "Supervisor: ...", the department).
Only the first `pages` pages are kept. A PDF is fetched again only when the record's PDF link changes or a
previous attempt failed and `retry_failed` is set.
"""
import hashlib
import re
import sys
import tempfile
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

UA = "NETD metadata enrichment (+https://netd.ac.zm)"

SCHEMA = """
CREATE TABLE IF NOT EXISTS pdf_text (
    record_id  TEXT PRIMARY KEY,
    url        TEXT NOT NULL,      -- the PDFs read, space-separated, front matter first
    status     TEXT NOT NULL,      -- ok | ocr (text from OCR) | no_text (scanned, not yet OCRed) | ocr_failed
                                   -- | too_large | error
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


FRONT = re.compile(r"cover|prelim|title|front|abstract|declaration|approval|certificat", re.I)


def front_urls(rec, most=3):
    """The PDFs to read for a record, front matter first. Some repositories split a thesis into several files
    ("Cover page.pdf", "Preliminary pages.pdf", "Main Document.pdf"); the cover and preliminary pages carry the
    degree statement and supervisors, so they are read before the main document."""
    pdfs = list(rec.get("pdf_url") or [])
    if len(pdfs) < 2:
        return pdfs
    names = {f.get("url"): f.get("name") or "" for f in rec.get("files") or []}
    rank = lambda u: (0 if re.search(r"cover|title", names.get(u, ""), re.I) else
                      1 if FRONT.search(names.get(u, "")) else 2)
    ordered = sorted(pdfs, key=lambda u: (rank(u), pdfs.index(u)))
    if rank(ordered[0]) == 2:
        return ordered[:1]  # no front-matter file: the first PDF holds the whole thesis
    return ordered[:most]


def fetch_text(urls, pages, max_mb, timeout):
    """Read each PDF in turn (front matter first); pages of different files are separated by form feeds."""
    texts, notes, statuses, n_pages = [], [], [], 0
    for url in urls.split():
        try:
            status, n, text, msg = fetch_one(url, pages, max_mb, timeout)
        except Exception as e:  # network errors, broken PDFs
            status, n, text, msg = "error", None, None, str(e)[:200]
        statuses.append(status)
        n_pages += n or 0
        if text and status == "ok":
            texts.append(text)
        if msg:
            notes.append(msg)
    if texts:
        return "ok", n_pages, "\f".join(texts), "; ".join(notes) or None
    for st in ("no_text", "too_large", "error"):
        if st in statuses:
            return st, n_pages or None, None, "; ".join(notes)[:300]
    return "error", None, None, "no PDF"


def pending(store, source=None, retry_failed=False, limit=None):
    """(record_id, urls) for records whose PDF text is missing, out of date, or (optionally) failed before.
    The url column holds the PDFs read, space-separated, so a change in the record's files triggers a re-read."""
    have = {r["record_id"]: (r["url"], r["status"]) for r in store.db.execute("SELECT record_id, url, status FROM pdf_text")}
    out = []
    for rec in store.records(source):
        url = " ".join(front_urls(rec))
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
        status, n, text, msg = fetch_text(url, pages, max_mb, timeout)
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


def ocr_one(url, pages, max_mb, timeout, dpi=200):
    """Rasterise the first pages with pdftoppm and read them with Tesseract (poppler-utils, tesseract-ocr)."""
    import glob
    import subprocess
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with tempfile.TemporaryDirectory() as d:
        path = d + "/f.pdf"
        with urllib.request.urlopen(req, timeout=timeout) as resp, open(path, "wb") as fh:
            size = 0
            while True:
                chunk = resp.read(1 << 16)
                if not chunk:
                    break
                size += len(chunk)
                if size > max_mb * 1024 * 1024:
                    return "too_large", None, "larger than %d MB" % max_mb
                fh.write(chunk)
        subprocess.run(["nice", "-n", "19", "pdftoppm", "-r", str(dpi), "-gray", "-f", "1", "-l", str(pages),
                        "-png", path, d + "/p"], check=True, timeout=300, capture_output=True)
        out = []
        for img in sorted(glob.glob(d + "/p*.png")):
            r = subprocess.run(["nice", "-n", "19", "tesseract", img, "-", "-l", "eng", "--psm", "3"],
                               timeout=300, capture_output=True)
            out.append(r.stdout.decode("utf-8", "replace"))
    text = "\f".join(out)
    if len(text.replace("\f", "").strip()) < 80:
        return "ocr_failed", text, "OCR found no text"
    return "ocr", text, None


def run_ocr(store, source=None, pages=5, max_mb=150, timeout=300, limit=None):
    """OCR the PDFs that have no text layer (status no_text), one at a time at low priority (FR-48)."""
    store.db.executescript(SCHEMA)
    q = "SELECT record_id, url FROM pdf_text WHERE status='no_text'" + (" AND record_id LIKE ?" if source else "")
    todo = store.db.execute(q, (source + "-%",) if source else ()).fetchall()[:limit or None]
    print("ocr-text: %d PDFs to OCR" % len(todo), flush=True)
    done = ok = 0
    for r in todo:
        try:
            status, text, msg = ocr_one(r["url"].split()[0], pages, max_mb, timeout)
        except Exception as e:
            status, text, msg = "ocr_failed", None, str(e)[:300]
        h = hashlib.sha256(text.encode("utf-8")).hexdigest() if text else None
        store.db.execute("UPDATE pdf_text SET status=?, text=coalesce(?, text), text_hash=coalesce(?, text_hash), "
                         "message=?, fetched_at=? WHERE record_id=?", (status, text, h, msg, time.time(), r["record_id"]))
        store.commit()
        done += 1
        ok += status == "ocr"
        if done % 10 == 0:
            print("ocr-text: %d/%d (%d with text)" % (done, len(todo), ok), flush=True)
    print("ocr-text: finished %d (%d with text)" % (done, ok), flush=True)


def summary(store):
    store.db.executescript(SCHEMA)
    rows = store.db.execute("SELECT substr(record_id,1,instr(record_id,'-')-1) src, status, count(*) n "
                            "FROM pdf_text GROUP BY src, status ORDER BY src, status").fetchall()
    for r in rows:
        print("%-8s %-10s %6d" % (r["src"], r["status"], r["n"]))
    if not rows:
        print("no PDF text cached yet", file=sys.stderr)
