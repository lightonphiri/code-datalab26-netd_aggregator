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
    "openalex-fos": "netd.ml.models.fieldofstudy",
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
        if hasattr(m, "prepare"):  # corpus-level preparation, e.g. a vocabulary
            m.prepare(t for t, _ in texts.values())
        seen = {} if everything else cache.known_hashes(store, m.NAME)
        n = changed = 0
        # read everything first: in WAL mode a read transaction cannot be upgraded to a write once another
        # writer (e.g. text extraction) has committed, so no read may stay open while predictions are written
        inputs = [(rec["id"], harvested_view(rec, m.USES)) for rec in store.records(source)]
        todo = []
        for rid, meta in inputs:
            text, th = texts.get(rid, (None, None))
            if text is None and getattr(m, "NEEDS_TEXT", True):
                continue
            h = cache.input_hash(th if getattr(m, "NEEDS_TEXT", True) else None,
                                 json.dumps(meta, sort_keys=True), m.VERSION)
            n += 1
            if seen.get(rid) != h:
                todo.append((rid, meta, text, h))
        step = 256 if hasattr(m, "predict_batch") else 1  # batch models (e.g. embeddings) predict in chunks
        for i in range(0, len(todo), step):
            chunk = todo[i:i + step]
            outs = (m.predict_batch([c[1] for c in chunk], [c[2] for c in chunk]) if step > 1
                    else [m.predict(chunk[0][1], chunk[0][2]) or {}])
            for (rid, meta, text, h), out in zip(chunk, outs):
                for f in m.FIELDS:
                    vals, conf, ev = (out or {}).get(f, ([], None, None))
                    cache.put_prediction(store, rid, f, m.NAME, m.VERSION, vals, conf, h, ev)
                changed += 1
            if step > 1 or changed % 500 == 0:
                store.commit()
        store.commit()
        print("predict %s-%s: %d records with input, %d (re)predicted" % (m.NAME, m.VERSION, n, changed))
