"""Run metadata-filling models over the PDF text cache, writing to the prediction cache (SRS FR-49).

A model is a module exposing NAME, VERSION, FIELDS (the fields it predicts), USES (the harvested record fields it
reads) and predict(record, text) -> {field: (values, confidence, evidence)}. A model runs again for a record only
when its input hash (PDF text, the harvested fields it uses, its version) has changed, unless everything=True.
Models only ever see harvested values, never other models' output, so results do not feed back on themselves.
"""
import importlib
import json

from . import cache

MODELS = {
    "titlepage-rules": "netd.ml.models.titlepage",
}


def harvested_view(rec, fields):
    """The record's harvested values for `fields` (derived and corrected values removed)."""
    prov = rec.get("provenance", {})
    return {f: rec.get(f) for f in fields
            if rec.get(f) and not str(prov.get(f, "")).startswith(("model:", "corrected:"))}


def run(store, source=None, model=None, everything=False):
    names = [model] if model else list(MODELS)
    texts = {r["record_id"]: (r["text"], r["text_hash"]) for r in
             store.db.execute("SELECT record_id, text, text_hash FROM pdf_text WHERE status IN ('ok', 'ocr')")}
    for name in names:
        m = importlib.import_module(MODELS[name])
        seen = {} if everything else cache.known_hashes(store, m.NAME)
        n = changed = 0
        for rec in store.records(source):
            text, th = texts.get(rec["id"], (None, None))
            meta = harvested_view(rec, m.USES)
            if text is None and getattr(m, "NEEDS_TEXT", True):
                continue
            h = cache.input_hash(th, json.dumps(meta, sort_keys=True), m.VERSION)
            n += 1
            if seen.get(rec["id"]) == h:
                continue
            out = m.predict(meta, text) or {}
            for f in m.FIELDS:
                vals, conf, ev = out.get(f, ([], None, None))
                cache.put_prediction(store, rec["id"], f, m.NAME, m.VERSION, vals, conf, h, ev)
            changed += 1
            if changed % 500 == 0:
                store.commit()
        store.commit()
        print("predict %s-%s: %d records with input, %d (re)predicted" % (m.NAME, m.VERSION, n, changed))
