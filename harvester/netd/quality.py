"""Metadata quality per institution (SRS FR-28): completeness and ETD-MS compliance, by origin of each value.

For every record in the portal and every element, the value's provenance (crosswalk.py) is put in one of four groups:
  repository  - in the repository's own metadata element (harvested; or harvested and tidied by a rule)
  elsewhere   - present in the repository, but only in another place: the collection hierarchy or free text
                (e.g. the degree read from "submitted in partial fulfilment of the degree of ..." in dc.description)
  portal      - filled by the portal (models reading the PDF, admin corrections)
  missing     - no value
"ETD-MS compliance" is the mean share of the ETD-MS 1.1 elements below that the repository supplies in their own
element. Faculty and department are not ETD-MS elements; for them the collection hierarchy counts as the repository's
own place. Written as JSON for the public quality page; computed after every scheduled run.
"""
import datetime
import json
import os

# (element shown, canonical field, ETD-MS 1.1 element or None, advice to the institution when it is weak at source)
ELEMENTS = [
    ("Title", "title", "dc.title", "Record the title in dc.title."),
    ("Author", "author", "dc.creator", "Record the author in dc.contributor.author (DSpace) as Surname, Given names."),
    ("Supervisor", "supervisor", "dc.contributor (role: advisor)",
     "Record supervisors in dc.contributor.advisor, one per value, as Surname, Given names."),
    ("Subject / keywords", "subject", "dc.subject", "Add keywords in dc.subject."),
    ("Abstract", "abstract", "dc.description.abstract", "Include the abstract in dc.description.abstract."),
    ("Year", "year", "dc.date", "Record the year of award in dc.date.issued."),
    ("Type", "type", "dc.type", "Set dc.type to Thesis or Dissertation."),
    ("Language", "language", "dc.language", "Record the language in dc.language.iso (e.g. en)."),
    ("Identifier (record link)", "url", "dc.identifier", "Make each record's handle or URL public in dc.identifier.uri."),
    ("Degree name", "degree", "thesis.degree.name",
     "Record the degree (e.g. Master of Public Health) in thesis.degree.name or dc.description.degree."),
    ("Degree level", "degree_level", "thesis.degree.level",
     "Record the level (Masters, Doctoral) in thesis.degree.level, or keep Master's and PhD work in separate collections."),
    ("Discipline", "discipline", "thesis.degree.discipline", "Record the discipline in thesis.degree.discipline."),
    ("Faculty / school", "faculty", None, "Organise ETD collections by school or faculty, or record it in the item."),
    ("Department", "department", None, "Record the department (e.g. in thesis.degree.grantor or dc.description)."),
    ("Full-text PDF", "pdf_url", None, "Attach the full text (or at least the preliminary pages) as a public PDF."),
]
GROUPS = ("repository", "elsewhere", "portal", "missing")


def origin(rec, field):
    if not rec.get(field):
        return "missing"
    p = (rec.get("provenance") or {}).get(field, "harvested")
    kind = p.split(":", 1)[0]
    if kind in ("harvested", "rule") or (kind == "set" and field in ("faculty", "department")):
        return "repository"
    if kind in ("set", "text"):
        return "elsewhere"
    return "portal"  # model:..., corrected:..., anything added after harvesting


def compute(rows, names):
    """rows: iterable of (source, record dict); names: {source id: institution name}."""
    per = {}
    for src, rec in rows:
        for key in (src, "_all"):
            d = per.setdefault(key, {"records": 0, "counts": {f: dict.fromkeys(GROUPS, 0) for _, f, _, _ in ELEMENTS}})
            d["records"] += 1
            for _, f, _, _ in ELEMENTS:
                d["counts"][f][origin(rec, f)] += 1
    out = []
    for key, d in per.items():
        n = d["records"]
        el = []
        for label, f, etdms, advice in ELEMENTS:
            pct = {g: round(100.0 * d["counts"][f][g] / n, 1) for g in GROUPS}
            el.append({"label": label, "field": f, "etdms": etdms, "advice": advice, **pct})
        etd = [e for e in el if e["etdms"]]
        out.append({
            "id": None if key == "_all" else key,
            "name": "All institutions" if key == "_all" else names.get(key, key),
            "records": n,
            "etdms_compliance": round(sum(e["repository"] for e in etd) / len(etd), 1),
            "complete_after_portal": round(sum(100 - e["missing"] for e in el) / len(el), 1),
            "elements": el,
            "to_improve": [e["advice"] for e in el if e["repository"] < 50 and e["repository"] + e["elsewhere"] < 90]
                          if key != "_all" else [],
        })
    out.sort(key=lambda r: (r["id"] is None, -r["records"]))
    return out


def run(store, sources, out_path, log=print):
    names = {s["id"]: s.get("name", s["id"]) for s in sources}
    rows = [(src, json.loads(data)) for src, data in store.db.execute("SELECT source, data FROM records").fetchall()]
    doc = {"generated_at": datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
           "groups": list(GROUPS), "institutions": compute(rows, names)}
    tmp = out_path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(doc, fh, indent=1)
    os.replace(tmp, out_path)
    for i in doc["institutions"]:
        log("quality: %-32s %5d records, ETD-MS compliance at source %5.1f%%, complete after portal %5.1f%%" % (
            i["name"][:32], i["records"], i["etdms_compliance"], i["complete_after_portal"]))
    return doc
