"""Apply cached predictions and manual corrections to a canonical record (SRS FR-14, FR-49 to FR-52).

Order of precedence for each field: manual correction > harvested value > prediction (>= show threshold).
A predicted value is recorded in record["derived"][field] = {"method": "model:<name>-<version>", "confidence": c}
so the portal and the API can mark it as derived. Predicted degree levels below postgraduate are used only at or
above `level_auto_exclude` (the record is then excluded under FR-47 with the model named in the reason); between
`level_review_min` and that threshold the record stays in the portal and is queued for review in the admin panel.
"""
from .. import crosswalk

FACET_FIELDS = ("supervisor", "faculty", "department", "discipline", "subject")


class Overlay:
    def __init__(self, store, cfg):
        from . import cache
        cache.init(store)
        self.store = store
        self.preds = cache.predictions(store)
        self.corr = cache.corrections(store)
        self.show = float(cfg.get("show_threshold", 0.8))
        self.thresholds = {k: float(v) for k, v in (cfg.get("thresholds") or {}).items()}  # per-field overrides
        self.auto_exclude = float(cfg.get("level_auto_exclude", 0.95))
        self.review_min = float(cfg.get("level_review_min", 0.6))
        self.min_conf = float(cfg.get("min_confidence", 0.6))
        self.review = []  # (record_id, level, confidence, method, evidence)

    def apply(self, rec):
        """Returns (record, scope): scope is None or the admin's "_scope" correction {"value": ["include"|"exclude"], ...}."""
        rid = rec["id"]
        corr = self.corr.get(rid, {})
        if rid not in self.preds and not corr:
            return rec, None  # nothing to apply: the record stays byte-identical (OAI-PMH datestamps unchanged)
        rec.setdefault("provenance", {})
        had_conf = "confidence" in rec
        rec.setdefault("confidence", {})
        derived = {}
        for field, cands in self.preds.get(rid, {}).items():
            if rec.get(field) or field in corr:
                continue
            conf, value, model, version, evidence = cands[0]
            method = "model:%s-%s" % (model, version)
            if field == "degree_level" and value[0] not in crosswalk.POSTGRADUATE:
                if conf < self.auto_exclude:
                    if conf >= self.review_min and "_scope" not in corr:
                        self.review.append((rid, value[0], conf, method, evidence))
                    continue
            elif conf < self.thresholds.get(field, self.show):
                continue
            rec[field] = value
            rec["provenance"][field] = method
            rec["confidence"][field] = conf
            derived[field] = {"method": method, "confidence": round(conf, 3)}
        for field, c in corr.items():
            if field == "_scope":
                continue
            if c["value"]:
                rec[field] = c["value"]
            else:
                rec.pop(field, None)
            rec["provenance"][field] = "corrected:%s" % (c["by"] or "admin")
            rec["confidence"][field] = 1.0
            derived.pop(field, None)
        if derived:
            rec["derived"] = derived
        if not rec["confidence"] and not had_conf:
            del rec["confidence"]
        rec["facetable"] = {f: rec.get("confidence", {}).get(f, 1.0) >= self.min_conf for f in FACET_FIELDS}
        return rec, corr.get("_scope")

    def save_review(self, sources):
        """Rebuild the pending review list for the processed sources; decided entries are kept."""
        for s in sources:
            self.store.db.execute("DELETE FROM level_review WHERE status='pending' AND record_id LIKE ?", (s + "-%",))
        import time
        self.store.db.executemany(
            "INSERT OR IGNORE INTO level_review (record_id, predicted, confidence, model, evidence, status, updated_at) "
            "VALUES (?,?,?,?,?,'pending',?)", [r + (time.time(),) for r in self.review])
        return len(self.review)
