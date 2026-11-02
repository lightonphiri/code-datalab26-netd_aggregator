"""Push canonical records to Solr using Blacklight's dynamic-field naming conventions."""
import json
import time
import urllib.request

# canonical field -> Solr fields
SOLR = {
    "title": ["title_tsim", "title_ssm"],
    "author": ["author_tsim", "author_ssim"],
    "supervisor": ["supervisor_tsim", "supervisor_ssim"],
    "subject": ["subject_tsim", "subject_ssim"],
    "faculty": ["faculty_tsim", "faculty_ssim"],
    "department": ["department_tsim", "department_ssim"],
    "discipline": ["discipline_tsim", "discipline_ssim"],
    "degree": ["degree_ssim"],
    "degree_level": ["degree_level_ssim"],
    "abstract": ["abstract_tesim"],
    "url": ["url_ssm"],
    "pdf_url": ["pdf_url_ssm"],
    "file_url": ["file_url_ssm"],
    "rights": ["rights_ssm"],
    "language": ["language_ssim"],
    "type": ["type_ssim"],
}
FACETED = {"supervisor", "faculty", "department", "discipline", "subject"}
_TAX = {}


def fos_docs(ids):
    """OpenAlex ids -> Solr fields for the hierarchical Field of study facets (FR-55)."""
    if not _TAX:
        from .ml.models import fieldofstudy
        _TAX.update(fieldofstudy.taxonomy())
    doc = {"fos_domain_ssim": [], "fos_field_ssim": [], "fos_subfield_ssim": [], "fos_ssm": [], "fos_tsim": []}
    for i in ids:
        node = _TAX.get(i)
        if not node:
            continue
        chain = {"domain": _TAX.get(node.get("domain", i if node["level"] == "domain" else "")),
                 "field": _TAX.get(node.get("field", i if node["level"] == "field" else ""))}
        if node["level"] == "field":
            chain["field"] = node
        if node["level"] == "domain":
            chain["domain"] = node
        for lvl in ("domain", "field"):
            if chain[lvl] and chain[lvl]["name"] not in doc["fos_%s_ssim" % lvl]:
                doc["fos_%s_ssim" % lvl].append(chain[lvl]["name"])
        if node["level"] == "subfield":
            doc["fos_subfield_ssim"].append(node["name"])
        doc["fos_ssm"].append(json.dumps({"id": i, "name": node["name"], "level": node["level"],
                                          "field": (chain["field"] or {}).get("name"),
                                          "domain": (chain["domain"] or {}).get("name")}, ensure_ascii=False))
        doc["fos_tsim"].append(node["name"])
    return {k: v for k, v in doc.items() if v}


def to_solr(rec, dup=None):
    doc = {"id": rec["id"], "institution_ssim": [rec["institution"]],
           "institution_short_ssim": [rec["institution_short"]], "source_ssi": rec["source"],
           "oai_id_ssi": rec["oai_id"], "datestamp_ssi": rec.get("datestamp") or "",
           "provenance_ssm": ["%s=%s" % kv for kv in sorted(rec.get("provenance", {}).items())]}
    ok = rec.get("facetable", {})
    for f, targets in SOLR.items():
        vals = rec.get(f)
        if not vals:
            continue
        for t in targets:
            if t.endswith("_ssim") and f in FACETED and not ok.get(f, True):
                continue  # low-confidence value: searchable, not facetable
            doc[t] = vals
    if rec.get("_added_at"):  # first appearance in the portal: "Newest additions" sort and feeds (FR-60)
        doc["added_dtsi"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(rec["_added_at"]))
    if rec.get("_updated_at"):  # last content change in the portal: OAI-PMH datestamp (UTC, seconds)
        doc["updated_dtsi"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(rec["_updated_at"]))
    if rec.get("title"):
        doc["title_ssort"] = rec["title"][0].lower()
    if rec.get("year"):
        doc["year_isi"] = int(rec["year"][0])
        doc["year_ssim"] = rec["year"]
    if rec.get("faculty") and rec.get("department"):
        doc["faculty_department_ssim"] = ["%s|%s" % (rec["faculty"][0], d) for d in rec["department"]]
    if rec.get("field_of_study"):
        doc.update(fos_docs(rec["field_of_study"]))
    if rec.get("derived"):  # values filled by a model (SRS FR-50): field, method, confidence
        doc["derived_ssm"] = [json.dumps(dict(v, field=f), ensure_ascii=False) for f, v in sorted(rec["derived"].items())]
    if rec.get("files"):
        doc["files_ssm"] = [json.dumps(f, ensure_ascii=False) for f in rec["files"]]
    doc["full_text_ssim"] = ["PDF available" if rec.get("pdf_url") else
                             ("Other file available" if rec.get("file_url") else "Metadata only")]
    if dup and dup.get("duplicate_of"):  # FR-19: listed once in search; this copy links to the main record
        doc["duplicate_of_ssi"] = dup["duplicate_of"]
    if dup and dup.get("duplicates"):
        doc["duplicates_ssim"] = dup["duplicates"]
    doc["completeness_isi"] = sum(1 for f in ("title", "author", "supervisor", "subject", "faculty",
                                              "department") if rec.get(f))
    return doc


def post(solr_url, docs, commit=False):
    url = solr_url.rstrip("/") + "/update" + ("?commit=true" if commit else "")
    req = urllib.request.Request(url, data=json.dumps(docs).encode("utf-8"),
                                 headers={"Content-Type": "application/json"})
    urllib.request.urlopen(req, timeout=300).read()


def ids(solr_url, source):
    """Ids of the source's documents currently in Solr."""
    url = solr_url.rstrip("/") + "/select?q=*:*&fq=source_ssi:%s&fl=id&rows=1000000&wt=json" % source
    with urllib.request.urlopen(url, timeout=300) as r:
        return {d["id"] for d in json.load(r)["response"]["docs"]}


def delete_ids(solr_url, ids):
    if ids:
        post(solr_url, {"delete": ids})
