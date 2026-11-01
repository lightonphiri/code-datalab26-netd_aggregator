"""Prediction cache, manual corrections and degree-level review decisions (SRS FR-49 to FR-52)."""
import csv
import hashlib
import json
import time

SCHEMA = """
CREATE TABLE IF NOT EXISTS predictions (
    record_id  TEXT NOT NULL,
    field      TEXT NOT NULL,
    model      TEXT NOT NULL,      -- model name, e.g. "titlepage-rules"
    version    TEXT NOT NULL,
    value      TEXT,               -- JSON list of values; [] = the model found nothing
    confidence REAL,
    input_hash TEXT,               -- hash of the model's input (PDF text + metadata it used) and version
    evidence   TEXT,               -- the text the value was taken from, for reviewers and error analysis
    created_at REAL,
    PRIMARY KEY (record_id, field, model)
);
CREATE TABLE IF NOT EXISTS corrections (    -- entered in the admin panel; override harvested and predicted values
    record_id  TEXT NOT NULL,
    field      TEXT NOT NULL,      -- a canonical field, or "_scope" with value ["include"] or ["exclude"]
    value      TEXT NOT NULL,      -- JSON list; [] clears the field
    note       TEXT,
    made_by    TEXT,
    created_at REAL,
    PRIMARY KEY (record_id, field)
);
CREATE TABLE IF NOT EXISTS level_review (   -- degree-level predictions below the auto-exclusion threshold
    record_id  TEXT PRIMARY KEY,
    predicted  TEXT, confidence REAL, model TEXT, evidence TEXT,
    status     TEXT DEFAULT 'pending',      -- pending | decided (the decision itself is a "_scope" correction)
    updated_at REAL
);
"""

FIELDS = ("degree_level", "degree", "discipline", "supervisor", "department", "faculty", "subject", "year")


def init(store):
    store.db.executescript(SCHEMA)


def input_hash(*parts):
    return hashlib.sha256("\x1e".join(str(p) for p in parts).encode("utf-8")).hexdigest()[:32]


def put_prediction(store, record_id, field, model, version, value, confidence, ihash, evidence=None):
    store.db.execute("INSERT OR REPLACE INTO predictions VALUES (?,?,?,?,?,?,?,?,?)",
                     (record_id, field, model, version, json.dumps(value, ensure_ascii=False),
                      None if confidence is None else float(confidence), ihash, (evidence or "")[:500] or None,
                      time.time()))


def known_hashes(store, model):
    return {r["record_id"]: r["h"] for r in store.db.execute(
        "SELECT record_id, max(input_hash) h FROM predictions WHERE model=? GROUP BY record_id", (model,))}


def predictions(store):
    """{record_id: {field: [(confidence, value, model, version, evidence), ...best first]}} (non-empty only)."""
    out = {}
    for r in store.db.execute("SELECT * FROM predictions WHERE value != '[]'"):
        out.setdefault(r["record_id"], {}).setdefault(r["field"], []).append(
            (r["confidence"] or 0.0, json.loads(r["value"]), r["model"], r["version"], r["evidence"]))
    for fields in out.values():
        for lst in fields.values():
            lst.sort(key=lambda t: -t[0])
    return out


def corrections(store):
    out = {}
    for r in store.db.execute("SELECT * FROM corrections"):
        out.setdefault(r["record_id"], {})[r["field"]] = {"value": json.loads(r["value"]), "by": r["made_by"],
                                                         "note": r["note"], "at": r["created_at"]}
    return out


def put_correction(store, record_id, field, value, made_by, note=None):
    store.db.execute("INSERT OR REPLACE INTO corrections VALUES (?,?,?,?,?,?)",
                     (record_id, field, json.dumps(value, ensure_ascii=False), note, made_by, time.time()))
    if field == "_scope":
        store.db.execute("UPDATE level_review SET status='decided', updated_at=? WHERE record_id=?",
                         (time.time(), record_id))


def delete_correction(store, record_id, field):
    store.db.execute("DELETE FROM corrections WHERE record_id=? AND field=?", (record_id, field))


def load_batch(store, path):
    """Load predictions computed elsewhere (e.g. a Colab notebook), as JSON Lines:
    {"record_id", "field", "model", "version", "value": [...], "confidence", "input_hash"(optional)}."""
    init(store)
    n = 0
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if not line.strip():
                continue
            p = json.loads(line)
            v = p["value"] if isinstance(p["value"], list) else [p["value"]]
            put_prediction(store, p["record_id"], p["field"], p["model"], str(p["version"]), v,
                           p.get("confidence"), p.get("input_hash") or "batch", p.get("evidence"))
            n += 1
    store.commit()
    print("loaded %d predictions from %s" % (n, path))


def export_predictions(store, path):
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["record_id", "field", "model", "version", "value", "confidence"])
        for r in store.db.execute("SELECT * FROM predictions ORDER BY record_id, field"):
            w.writerow([r["record_id"], r["field"], r["model"], r["version"],
                        " || ".join(json.loads(r["value"])), r["confidence"]])
