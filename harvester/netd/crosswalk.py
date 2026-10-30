"""Crosswalks: raw metadata XML (dim / etdms / oai_dc) -> canonical ETD record.

Each canonical field is stored with its provenance in record["provenance"][field]:
  "harvested:<source field>"  value taken directly from the harvested metadata
  "set:<setSpec>"             derived from the repository's community/collection hierarchy
  "text:<source field>"       extracted by a pattern from a free-text field
Enrichers (enrich.py) may add their own origins, e.g. "model:<name>".
"""
import json
import re

from lxml import etree

FIELDS = ["title", "author", "supervisor", "subject", "faculty", "department",
          "degree", "degree_level", "year", "abstract", "url", "language", "type"]


def flatten(xml, prefix):
    """Return {"dc.contributor.advisor": [..], ...} for any supported format."""
    out = {}
    if not xml:
        return out
    root = etree.fromstring(xml.encode("utf-8"))

    def add(key, val):
        val = (val or "").strip()
        if val:
            out.setdefault(key, []).append(val)

    if prefix == "dim":
        for f in root.iter("{http://www.dspace.org/xmlns/dspace/dim}field"):
            key = ".".join(x for x in (f.get("mdschema"), f.get("element"), f.get("qualifier")) if x)
            add(key, f.text)
    else:  # etdms / oai_dc: element local-name, plus role attribute for contributors
        for el in root.iter():
            if not isinstance(el.tag, str) or el is root or len(el):
                continue
            name = etree.QName(el).localname
            parent = etree.QName(el.getparent()).localname if el.getparent() is not root else ""
            key = ("thesis.degree." + name) if parent == "degree" else "dc." + name
            if name == "contributor" and el.get("role"):
                key += "." + el.get("role").lower()
            add(key, el.text)
    return out


def first(flat, keys):
    for k in keys:
        if flat.get(k):
            return k, flat[k]
    return None, []


# Candidate source fields per canonical field, in priority order.
MAP = {
    "title": ["dc.title"],
    "author": ["dc.contributor.author", "dc.creator"],
    "supervisor": ["dc.contributor.advisor", "dc.contributor.supervisor", "dc.contributor.promoter"],
    "subject": ["dc.subject", "dc.subject.other", "dc.subject.lcsh", "dc.subject.ddc"],
    "faculty": ["thesis.degree.faculty", "dc.description.faculty", "local.faculty", "dc.contributor.faculty"],
    "department": ["thesis.degree.department", "dc.description.department", "local.department",
                   "dc.contributor.department"],
    "degree": ["thesis.degree.name", "dc.description.degree", "dc.type.degree"],
    "degree_level": ["thesis.degree.level"],
    "year": ["dc.date.issued", "dc.date"],
    "abstract": ["dc.description.abstract"],
    "url": ["dc.identifier.uri", "dc.identifier"],
    "language": ["dc.language.iso", "dc.language"],
    "type": ["dc.type"],
}

DEGREE_PAT = [
    (r"\b(ph\.?\s?d|doctor of philosophy|doctoral|d\.?b\.?a|doctor of)\b", "Doctoral"),
    (r"\b(master|m\.?\s?sc|m\.?\s?a\b|m\.?\s?ed|mba|m\.?\s?phil|mph|mmed|llm|mlis)", "Masters"),
    (r"\b(bachelor|b\.?\s?sc|honours|undergraduate)\b", "Bachelors"),
]
FAC_PAT = re.compile(r"\b(school|faculty|college|institute)\s+of\b", re.I)
DEPT_TXT = re.compile(r"department of ([A-Z][\w ,&\-]+?)(?:[.,;]| in | at | of the|$)", re.I)


def degree_level(texts):
    blob = " ".join(texts).lower()
    for pat, level in DEGREE_PAT:
        if re.search(pat, blob):
            return level
    return None


def to_canonical(row, src, set_names):
    """row: a raw_records row. Returns canonical dict or None for deleted records."""
    if row["deleted"]:
        return None
    flat = flatten(row["xml"], row["metadata_prefix"])
    rec = {"id": "%s:%s" % (src["id"], row["oai_id"]), "source": src["id"],
           "institution": src["name"], "institution_short": src.get("short_name", src["id"].upper()),
           "oai_id": row["oai_id"], "datestamp": row["datestamp"], "provenance": {},
           "raw_fields": sorted(flat)}
    for field, keys in MAP.items():
        k, vals = first(flat, keys)
        if vals:
            rec[field] = vals
            rec["provenance"][field] = "harvested:" + k

    # year: 4-digit year only
    if rec.get("year"):
        m = re.search(r"(1[89]|20)\d\d", rec["year"][0])
        rec["year"] = [m.group(0)] if m else []
    # url: prefer an http(s) identifier
    if rec.get("url"):
        urls = [u for u in rec["url"] if u.startswith("http")]
        rec["url"] = urls[:1] or rec["url"][:1]

    # Faculty/Department from the community/collection hierarchy (setSpecs in the OAI header)
    ignore = set(n.lower() for n in src.get("ignore_set_names", []))
    names, all_names = [], []
    for spec in json.loads(row["set_specs"] or "[]"):
        n = (set_names.get(spec) or "").strip()
        all_names.append(n)
        if n and n.lower() not in ignore and spec not in (src.get("sets") or []):
            names.append((spec, n))
    role = src.get("collections_are")  # per-source override: "faculty" or "department"
    if role in ("faculty", "department") and not rec.get(role):
        cols = [(s, n) for s, n in names if s.startswith("col_")]
        if cols:
            rec[role] = sorted(set(n for _, n in cols))
            rec["provenance"][role] = "set:" + cols[0][0]
    if not rec.get("faculty"):
        fac = [(s, n) for s, n in names if FAC_PAT.search(n)]
        if fac:
            rec["faculty"] = sorted(set(n for _, n in fac))
            rec["provenance"]["faculty"] = "set:" + fac[0][0]
    if not rec.get("department"):
        dept = [(s, n) for s, n in names if role != "faculty" and not FAC_PAT.search(n)
                and s.startswith("col_")
                and not re.search(r"thes|dissert|master|phd|dba", n, re.I)]
        if dept:
            rec["department"] = sorted(set(n for _, n in dept))
            rec["provenance"]["department"] = "set:" + dept[0][0]
        else:  # text pattern in descriptions
            for k in ("dc.description", "dc.description.note", "dc.publisher"):
                for v in flat.get(k, []):
                    m = DEPT_TXT.search(v)
                    if m:
                        rec["department"] = ["Department of " + m.group(1).strip()]
                        rec["provenance"]["department"] = "text:" + k
                        break
                if rec.get("department"):
                    break

    # Degree level from degree name / type / description text
    if not rec.get("degree_level"):
        texts = rec.get("degree", []) + rec.get("type", []) + flat.get("dc.description", []) + all_names
        lvl = degree_level(texts)
        if lvl:
            rec["degree_level"] = [lvl]
            rec["provenance"]["degree_level"] = "text:degree/type/description"
    return rec
