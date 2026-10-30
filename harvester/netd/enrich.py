"""Cleaning/enrichment pipeline. This is the plug-in point for DataLab's ML models.

An enricher is any Python callable  f(record: dict) -> dict  registered in
enrichers.yml as "package.module:function". It may change field values, but must
record what it did in record["provenance"][field], e.g. "model:title-normaliser-v2",
and may set record["confidence"][field] (0..1). Low-confidence values
(< min_confidence in enrichers.yml) are kept in the record but not used for facets.
"""
import importlib
import re

SMALL = {"a", "an", "and", "as", "at", "by", "for", "from", "in", "of", "on", "or", "the", "to",
         "with", "via", "into", "among", "between", "towards"}


def _clean(s):
    return re.sub(r"\s+", " ", s).strip(" .;,") if isinstance(s, str) else s


def whitespace(rec):
    for k, v in list(rec.items()):
        if isinstance(v, list) and k not in ("raw_fields",):
            rec[k] = [_clean(x) for x in v if _clean(x)]
    return rec


def _title_case(t):
    words = t.lower().split(" ")
    out = []
    for i, w in enumerate(words):
        out.append(w if (i and w in SMALL) else w[:1].upper() + w[1:])
    return " ".join(out)


def title_case(rec):
    """Only rewrites titles that are ALL CAPS; original kept in title_original."""
    t = rec.get("title")
    if t and t[0].isupper() and len(t[0]) > 12:
        rec["title_original"] = list(t)
        rec["title"] = [_title_case(t[0])] + t[1:]
        rec["provenance"]["title"] = "rule:title-case"
    return rec


def person_names(rec):
    """'PHIRI, LIGHTON' -> 'Phiri, Lighton'; strip titles (Dr, Prof) from supervisors."""
    for f in ("author", "supervisor"):
        names = []
        for n in rec.get(f, []):
            n = re.sub(r"^(prof(essor)?|dr|mr|mrs|ms)\.?\s+", "", n, flags=re.I)
            if n.isupper():
                n = " ".join(p.capitalize() for p in n.lower().split(" "))
                n = re.sub(r"(?<=[-'])\w", lambda m: m.group(0).upper(), n)
            names.append(n)
        if names:
            rec[f] = list(dict.fromkeys(names))
    return rec


def unit_case(rec):
    """Normalise ALL-CAPS faculty/department names coming from collection names."""
    for f in ("faculty", "department"):
        if rec.get(f):
            rec[f] = [_title_case(x) if x.isupper() else x for x in rec[f]]
    return rec


BUILTIN = [whitespace, title_case, person_names, unit_case]


def load(spec_list):
    fns = list(BUILTIN)
    for spec in spec_list or []:
        mod, fn = spec.split(":")
        fns.append(getattr(importlib.import_module(mod), fn))
    return fns


def run(rec, fns, min_confidence=0.0):
    for fn in fns:
        rec = fn(rec) or rec
    rec["facetable"] = {f: (rec.get("confidence", {}).get(f, 1.0) >= min_confidence)
                        for f in ("supervisor", "faculty", "department", "subject")}
    return rec
