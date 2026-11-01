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


def to_solr(rec):
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
    if rec.get("_updated_at"):  # last content change in the portal: OAI-PMH datestamp (UTC, seconds)
        doc["updated_dtsi"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(rec["_updated_at"]))
    if rec.get("title"):
        doc["title_ssort"] = rec["title"][0].lower()
    if rec.get("year"):
        doc["year_isi"] = int(rec["year"][0])
        doc["year_ssim"] = rec["year"]
    if rec.get("faculty") and rec.get("department"):
        doc["faculty_department_ssim"] = ["%s|%s" % (rec["faculty"][0], d) for d in rec["department"]]
    if rec.get("derived"):  # values filled by a model (SRS FR-50): field, method, confidence
        doc["derived_ssm"] = [json.dumps(dict(v, field=f), ensure_ascii=False) for f, v in sorted(rec["derived"].items())]
    if rec.get("files"):
        doc["files_ssm"] = [json.dumps(f, ensure_ascii=False) for f in rec["files"]]
    doc["full_text_ssim"] = ["PDF available" if rec.get("pdf_url") else
                             ("Other file available" if rec.get("file_url") else "Metadata only")]
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
