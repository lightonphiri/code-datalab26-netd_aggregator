"""SQLite storage: raw harvested XML (never edited) and canonical cleaned records."""
import json
import sqlite3
import time

SCHEMA = """
CREATE TABLE IF NOT EXISTS raw_records (
    source      TEXT NOT NULL,
    oai_id      TEXT NOT NULL,
    datestamp   TEXT,
    set_specs   TEXT,              -- JSON list of setSpec values from the OAI header
    deleted     INTEGER DEFAULT 0,
    metadata_prefix TEXT,
    xml         TEXT,              -- original <metadata> payload, untouched
    harvested_at REAL,
    PRIMARY KEY (source, oai_id)
);
CREATE TABLE IF NOT EXISTS set_names (
    source TEXT NOT NULL, set_spec TEXT NOT NULL, set_name TEXT,
    PRIMARY KEY (source, set_spec)
);
CREATE TABLE IF NOT EXISTS records (
    id          TEXT PRIMARY KEY,  -- "<source>:<oai_id>"
    source      TEXT NOT NULL,
    data        TEXT NOT NULL,     -- JSON canonical record incl. provenance
    updated_at  REAL
);
CREATE TABLE IF NOT EXISTS bitstreams (
    source TEXT NOT NULL, oai_id TEXT NOT NULL, url TEXT NOT NULL,
    mime TEXT, name TEXT, size INTEGER,
    PRIMARY KEY (source, oai_id, url)
);
CREATE TABLE IF NOT EXISTS harvest_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT, started_at REAL, finished_at REAL,
    from_date TEXT, records INTEGER, deleted INTEGER, status TEXT, message TEXT
);
"""


class Store:
    def __init__(self, path):
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(SCHEMA)

    # --- raw layer -------------------------------------------------------
    def put_raw(self, source, oai_id, datestamp, set_specs, deleted, prefix, xml):
        self.db.execute(
            "INSERT OR REPLACE INTO raw_records VALUES (?,?,?,?,?,?,?,?)",
            (source, oai_id, datestamp, json.dumps(set_specs), int(deleted), prefix, xml, time.time()))

    def raw_records(self, source=None):
        q = "SELECT * FROM raw_records" + (" WHERE source=?" if source else "")
        return self.db.execute(q, (source,) if source else ()).fetchall()

    def put_set_names(self, source, pairs):
        self.db.executemany("INSERT OR REPLACE INTO set_names VALUES (?,?,?)",
                            [(source, s, n) for s, n in pairs])

    def set_names(self, source):
        return {r["set_spec"]: r["set_name"] for r in
                self.db.execute("SELECT * FROM set_names WHERE source=?", (source,))}

    def put_bitstreams(self, source, oai_id, files):
        """files: list of dicts {url, mime, name, size}; replaces what was stored for the item."""
        self.db.execute("DELETE FROM bitstreams WHERE source=? AND oai_id=?", (source, oai_id))
        self.db.executemany("INSERT OR REPLACE INTO bitstreams VALUES (?,?,?,?,?,?)",
                            [(source, oai_id, f["url"], f.get("mime"), f.get("name"), f.get("size")) for f in files])

    def bitstreams(self, source):
        out = {}
        for r in self.db.execute("SELECT * FROM bitstreams WHERE source=?", (source,)):
            out.setdefault(r["oai_id"], []).append(dict(r))
        return out

    # --- canonical layer ---------------------------------------------------
    def put_record(self, rec):
        """Store a canonical record. updated_at changes only when the record's content changes, so it can
        serve as the OAI-PMH datestamp of the portal's own data provider (incremental harvesting)."""
        data = json.dumps(rec, ensure_ascii=False)
        old = self.db.execute("SELECT data FROM records WHERE id=?", (rec["id"],)).fetchone()
        if old is not None and old["data"] == data:
            return
        self.db.execute("INSERT OR REPLACE INTO records VALUES (?,?,?,?)",
                        (rec["id"], rec["source"], data, time.time()))

    def delete_record(self, rec_id):
        self.db.execute("DELETE FROM records WHERE id=?", (rec_id,))

    def records(self, source=None):
        """Canonical records; each carries "_updated_at" (epoch seconds of its last content change)."""
        q = "SELECT data, updated_at FROM records" + (" WHERE source=?" if source else "")
        for r in self.db.execute(q, (source,) if source else ()):
            rec = json.loads(r["data"])
            rec["_updated_at"] = r["updated_at"]
            yield rec

    # --- harvest bookkeeping ---------------------------------------------
    def last_success(self, source):
        r = self.db.execute("SELECT max(started_at) m FROM harvest_runs WHERE source=? AND status='ok'",
                            (source,)).fetchone()
        return r["m"]

    def log_run(self, **kw):
        cols = ",".join(kw)
        self.db.execute("INSERT INTO harvest_runs (%s) VALUES (%s)" % (cols, ",".join("?" * len(kw))),
                        tuple(kw.values()))

    def commit(self):
        self.db.commit()
