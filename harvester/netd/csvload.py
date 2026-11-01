"""CSV loader for HEIs without a working repository (SRS FR-10).

An HEI supplies its ETD metadata as a CSV file: one row per thesis or dissertation, with the columns in COLUMNS
(template: portal/public/netd-etd-template.csv, documented on the Developer Resources page). A source reads it from
  csv_url:  an http(s) URL the HEI keeps current (e.g. a Google Sheet published as CSV), fetched on every run, or
  csv_path: a file, or a folder of *.csv files, on the server (default /opt/netd/harvester/uploads/<source id>/).

Each valid row is stored in the raw layer as `dim` XML, like the REST and METS loaders, so the crosswalk and
everything downstream are unchanged. oai_id is "csv:<source id>:<identifier>", giving record ids
"<source id>-<identifier>". Rows that disappear from the CSV are marked deleted. Invalid rows are skipped and
reported; `python -m netd.cli csv-check FILE` lists them before a file is put in place.
"""
import csv
import glob
import io
import os
import re
import time
import urllib.request
from xml.sax.saxutils import escape

from .crosswalk import degree_level
from .rest import DIM_NS

MULTI = "||"          # separator for several values in one cell
MAX_BYTES = 50 * 1024 * 1024
UPLOADS = os.environ.get("NETD_UPLOADS", "/opt/netd/harvester/uploads")

# column -> (dim field mdschema.element[.qualifier], required, repeatable)
COLUMNS = {
    "identifier":   (None, True, False),
    "title":        ("dc.title", True, False),
    "author":       ("dc.contributor.author", True, True),
    "year":         ("dc.date.issued", True, False),
    "degree_level": ("thesis.degree.level", True, False),
    "degree":       ("thesis.degree.name", False, False),
    "supervisor":   ("dc.contributor.advisor", False, True),
    "faculty":      ("thesis.degree.faculty", False, False),
    "department":   ("thesis.degree.department", False, False),
    "discipline":   ("thesis.degree.discipline", False, False),
    "subject":      ("dc.subject", False, True),
    "abstract":     ("dc.description.abstract", False, False),
    "language":     ("dc.language.iso", False, False),
    "url":          ("dc.identifier.uri", False, False),
    "pdf_url":      (None, False, False),
    "rights":       ("dc.rights", False, False),
}
ID_PAT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_\-]{0,99}$")  # becomes part of the URL-safe record id
YEAR_PAT = re.compile(r"^(19|20)\d\d$")
URL_PAT = re.compile(r"^https?://\S+$")


def _decode(data):
    for enc in ("utf-8-sig", "cp1252"):  # Excel on Windows often saves as cp1252
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", "replace")


def read_rows(text):
    """Parse CSV text -> (rows as dicts with normalised column names, problems)."""
    sample = text[:4096]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=",;\t")
    except csv.Error:
        dialect = csv.excel
    reader = csv.reader(io.StringIO(text), dialect)
    try:
        header = [h.strip().lower().replace(" ", "_") for h in next(reader)]
    except StopIteration:
        return [], ["the file is empty"]
    problems = []
    unknown = [h for h in header if h and h not in COLUMNS]
    if unknown:
        problems.append("unknown column(s), ignored: " + ", ".join(unknown))
    missing = [c for c, (_, req, _) in COLUMNS.items() if req and c not in header]
    if missing:
        return [], problems + ["missing required column(s): " + ", ".join(missing)]
    rows = []
    for n, values in enumerate(reader, start=2):
        if not any(v.strip() for v in values):
            continue
        row = {h: (values[i].strip() if i < len(values) else "") for i, h in enumerate(header) if h in COLUMNS}
        row["_line"] = n
        rows.append(row)
    return rows, problems


def validate(row):
    """Problems with one row (empty list = valid). Normalises degree_level in place."""
    p = []
    for col, (_, req, _) in COLUMNS.items():
        if req and not row.get(col):
            p.append("%s is empty" % col)
    if row.get("identifier") and not ID_PAT.match(row["identifier"]):
        p.append("identifier %r: use letters, digits, - and _ only (at most 100 characters)" % row["identifier"])
    if row.get("year") and not YEAR_PAT.match(row["year"]):
        p.append("year %r is not a four-digit year" % row["year"])
    if row.get("degree_level"):
        lvl = degree_level([row["degree_level"]])
        if lvl in ("Masters", "Doctoral", "Postgraduate Diploma"):  # postgraduate ETDs only (FR-47)
            row["degree_level"] = lvl
        else:
            p.append("degree_level %r: use Masters, Doctoral or Postgraduate Diploma" % row["degree_level"])
    for col in ("url", "pdf_url"):
        if row.get(col) and not URL_PAT.match(row[col]):
            p.append("%s %r is not an http(s) link" % (col, row[col]))
    return p


def to_dim(row):
    out = ['<dim:dim xmlns:dim="%s">' % DIM_NS]
    for col, (field, _, repeatable) in COLUMNS.items():
        if not field or not row.get(col):
            continue
        parts = field.split(".")
        qual = ' qualifier="%s"' % parts[2] if len(parts) > 2 else ""
        vals = [v.strip() for v in row[col].split(MULTI)] if repeatable else [row[col]]
        for v in vals:
            if v:
                out.append('<dim:field mdschema="%s" element="%s"%s>%s</dim:field>'
                           % (parts[0], parts[1], qual, escape(v)))
    out.append("</dim:dim>")
    return "".join(out)


def fetch(src):
    """[(name, text, datestamp)] for the source's CSV file(s)."""
    if src.get("csv_url"):
        req = urllib.request.Request(src["csv_url"], headers={"User-Agent": "NETD harvester (+https://netd.ac.zm)"})
        with urllib.request.urlopen(req, timeout=120) as r:
            data = r.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            raise ValueError("CSV larger than %d MB" % (MAX_BYTES // 1048576))
        return [(src["csv_url"], _decode(data), time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))]
    path = src.get("csv_path") or os.path.join(UPLOADS, src["id"])
    files = sorted(glob.glob(os.path.join(path, "*.csv"))) if os.path.isdir(path) else [path]
    if not files or not os.path.exists(files[0]):
        raise FileNotFoundError("no CSV file at %s" % path)
    out = []
    for f in files:
        with open(f, "rb") as fh:
            stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(os.path.getmtime(f)))
            out.append((os.path.basename(f), _decode(fh.read()), stamp))
    return out


def harvest_csv(store, src, log=print, limit=None):
    seen, n, skipped = set(), 0, 0
    for name, text, stamp in fetch(src):
        rows, problems = read_rows(text)
        for pr in problems:
            log("  %s: %s: %s" % (src["id"], name, pr))
        for row in rows:
            p = validate(row)
            oai_id = "csv:%s:%s" % (src["id"], row.get("identifier", ""))
            if p or oai_id in seen:
                skipped += 1
                log("  %s: %s line %d skipped: %s" % (src["id"], name, row["_line"],
                                                      "; ".join(p) or "duplicate identifier"))
                continue
            seen.add(oai_id)
            store.put_raw(src["id"], oai_id, stamp, [], False, "dim", to_dim(row))
            files = [{"url": row["pdf_url"], "mime": "application/pdf", "name": None, "size": None}] \
                if row.get("pdf_url") else []
            store.put_bitstreams(src["id"], oai_id, files)
            n += 1
            if limit and n >= limit:
                break
    if not seen:
        raise ValueError("no valid rows (%d skipped)" % skipped)
    if not limit:  # rows removed from the CSV -> deleted
        for r in store.raw_records(src["id"]):
            if r["oai_id"] not in seen and not r["deleted"]:
                store.put_raw(src["id"], r["oai_id"], r["datestamp"], [], True, "dim", "")
    store.commit()
    if skipped:
        log("  %s: %d row(s) skipped; run `netd.cli csv-check` on the file for details" % (src["id"], skipped))
    return n


def check_file(path):
    """Print every problem in a CSV file; return the number of invalid rows (-1 if unusable)."""
    with open(path, "rb") as fh:
        rows, problems = read_rows(_decode(fh.read()))
    for pr in problems:
        print("file: " + pr)
    if not rows:
        print("no rows")
        return -1
    bad, ids = 0, set()
    for row in rows:
        p = validate(row)
        if row.get("identifier") in ids:
            p.append("duplicate identifier %r" % row["identifier"])
        ids.add(row.get("identifier"))
        if p:
            bad += 1
            print("line %d: %s" % (row["_line"], "; ".join(p)))
    print("%d rows, %d valid, %d with problems" % (len(rows), len(rows) - bad, bad))
    return bad
