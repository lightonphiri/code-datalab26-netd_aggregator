"""Checks the NETD REST API v1 against its OpenAPI specification (SRS EI-6, FR-42 to FR-46; SDD section 5.3).

    pip install requests pyyaml jsonschema openapi-spec-validator
    python tests/api_conformance.py [BASE]        # default https://netd.ac.zm

Validates the specification, calls every endpoint, validates each JSON response against the schema the specification
gives for it, and checks filters, paging links, errors, CORS and the export files. Exit status 1 = problem.
"""
import csv
import io
import json
import sys

import jsonschema
import requests
import yaml
from openapi_spec_validator import validate

BASE = (sys.argv[1] if len(sys.argv) > 1 else "https://netd.ac.zm").rstrip("/")
API = BASE + "/api/v1"
S = requests.Session()
S.headers["User-Agent"] = "netd-api-conformance/1.0"
S.mount("https://", requests.adapters.HTTPAdapter(max_retries=requests.adapters.Retry(total=4, backoff_factor=2, allowed_methods=None, status_forcelist=[502, 503, 504])))
spec = yaml.safe_load(S.get(API + "/openapi.yaml", timeout=60).text)
validate(spec)
fails = []


def expect(cond, label):
    print(("ok   " if cond else "FAIL ") + label)
    if not cond:
        fails.append(label)


def nullable_to_jsonschema(node):
    """OpenAPI 3.0 `nullable` -> JSON Schema type lists; resolve local $refs."""
    if isinstance(node, dict):
        if "$ref" in node:
            name = node["$ref"].split("/")[-1]
            section = node["$ref"].split("/")[-2]
            return nullable_to_jsonschema(spec["components"][section][name])
        out = {k: nullable_to_jsonschema(v) for k, v in node.items() if k not in ("nullable", "example", "format")}
        if node.get("nullable") and "type" in out:
            out["type"] = [out["type"], "null"]
        return out
    if isinstance(node, list):
        return [nullable_to_jsonschema(x) for x in node]
    return node


def schema_for(path, status="200"):
    resp = spec["paths"][path]["get"]["responses"][status]
    resp = nullable_to_jsonschema(resp)
    return resp["content"]["application/json"]["schema"]


def check(path, url, label, status=200, schema_path=None):
    r = S.get(url, timeout=120)
    ok = r.status_code == status
    try:
        body = r.json()
        sch = schema_for(schema_path or path, str(status)) if status == 200 else nullable_to_jsonschema(
            spec["components"]["schemas"]["Error"])
        jsonschema.validate(body, sch)
    except Exception as e:  # noqa: BLE001
        ok = False
        label += " (%s)" % str(e).split("\n")[0][:150]
        body = None
    expect(ok, "%s -> %d" % (label, r.status_code))
    return body, r


# Records
b, r = check("/records", API + "/records", "records, default listing")
total = b["meta"]["total"]
expect(total > 5000 and b["meta"]["sort"] == "newest" and len(b["data"]) == 20, "  %d records, 20 per page, newest first" % total)
expect(r.headers.get("Access-Control-Allow-Origin") == "*", "  CORS header")
years = [d["year"] for d in b["data"] if d["year"]]
expect(years == sorted(years, reverse=True), "  sorted newest first")
b2, _ = check("/records", b["links"]["next"], "records, next link")
expect(b2["meta"]["page"] == 2 and b2["data"][0]["id"] != b["data"][0]["id"], "  page 2 differs from page 1")
b, _ = check("/records", API + "/records?q=malaria&per_page=5", "keyword search")
expect(b["meta"]["sort"] == "relevance" and 0 < b["meta"]["total"] < total, "  malaria: %d records, relevance" % b["meta"]["total"])
b, _ = check("/records", API + "/records?q=malaria&field=title&per_page=100", "title search")
expect(all("malaria" in (d["title"] or "").lower() for d in b["data"]), "  every title mentions malaria (%d)" % b["meta"]["total"])
b, _ = check("/records", API + "/records?level=doctoral&institution=unza&per_page=100", "doctoral at UNZA")
expect(all(d["degree_level"] == "Doctoral" and d["institution"]["id"] == "unza" for d in b["data"]), "  filters respected (%d)" % b["meta"]["total"])
b, _ = check("/records", API + "/records?year=2020-2022&sort=oldest&per_page=100", "year range, oldest first")
expect(all(2020 <= d["year"] <= 2022 for d in b["data"]) and b["data"][0]["year"] == 2020, "  years within 2020-2022")
b, _ = check("/records", API + "/records?institution=unilus,mu&full_text=true&per_page=100", "two institutions with full text")
expect(all(d["institution"]["id"] in ("unilus", "mu") and d["links"]["pdf"] for d in b["data"]), "  institutions and PDFs (%d)" % b["meta"]["total"])
b, _ = check("/records", API + "/records?updated_since=2099-01-01", "updated_since in the future")
expect(b["meta"]["total"] == 0 and b["links"]["next"] is None, "  no records, no next link")
b, _ = check("/records/{id}", API + "/records/unza-123456789-9150", "one record")
d = b["data"]
expect(d["oai_identifier"] == "oai:netd.ac.zm:unza-123456789-9150" and d["links"]["portal"].endswith("/theses/unza-9150"), "  identifiers and links")
expect(isinstance(d["cited_by"], dict) and "count" in d["cited_by"] and isinstance(d["cited_by"]["works"], list), "  cited_by present (1.7.0)")
b, _ = check("/records", API + "/records?cited=true&sort=cited&per_page=100", "cited theses, most cited first (1.7.0)")
counts = [x["cited_by"]["count"] for x in b["data"]]
expect(b["meta"]["total"] > 0 and all(c and c >= 1 for c in counts) and counts == sorted(counts, reverse=True),
       "  %d cited, sorted by citations" % b["meta"]["total"])
expect(all(x["openalex_id"] and len(x["cited_by"]["works"]) == x["cited_by"]["count"] for x in b["data"]), "  works listed match the count")
fac = d["faculty"][0] if d["faculty"] else None
if fac:
    b, _ = check("/records", API + "/records?" + requests.compat.urlencode({"faculty": fac, "per_page": 100}), "exact faculty")
    expect(all(fac in x["faculty"] for x in b["data"]), "  every record in %s" % fac)

# Errors
for q, st in [("/records?foo=1", 400), ("/records?level=phd", 400), ("/records?per_page=101", 400), ("/records?page=101&per_page=100", 400),
              ("/records?sort=best", 400), ("/records?cited=yes", 400), ("/records?year=99", 400), ("/records/no-such-record", 404), ("/nothing", 404)]:
    check("/records", API + q, "error " + q, status=st)

# Institutions and stats
b, _ = check("/institutions", API + "/institutions", "institutions")
expect(b["meta"]["total"] >= 34 and b["data"][0]["id"] == "unza", "  %d institutions, UNZA first" % b["meta"]["total"])
harvested = {i["id"]: i["records"] for i in b["data"] if i["id"]}
b, _ = check("/stats", API + "/stats", "stats")
st = b["data"]
expect(st["total_records"] == total and sum(i["records"] for i in st["by_institution"]) == total, "  totals agree (%d)" % total)
expect(sum(st["by_degree_level"].values()) == total, "  degree levels add up: %s" % st["by_degree_level"])
expect({i["id"]: i["records"] for i in st["by_institution"]} == harvested, "  per-institution counts match /institutions")
print("     completeness: %s" % st["completeness"])

# Export: every record, other copies of duplicates included (API 1.5.0)
every = S.get(API + "/records?duplicates=include&per_page=1", timeout=60).json()["meta"]["total"]
r = S.get(API + "/export.csv", timeout=300)
rows = list(csv.reader(io.StringIO(r.content.decode("utf-8"))))
expect(r.status_code == 200 and rows[0][0] == "id" and len(rows) - 1 == every and rows[0][-2:] == ["openalex_id", "cited_by_count"], "export.csv: %d rows" % (len(rows) - 1))
r = S.get(API + "/export.jsonl", timeout=300)
lines = r.content.decode("utf-8").splitlines()
rec_schema = nullable_to_jsonschema(spec["components"]["schemas"]["Record"])
bad = 0
for ln in lines:
    try:
        jsonschema.validate(json.loads(ln), rec_schema)
    except Exception:  # noqa: BLE001
        bad += 1
expect(r.status_code == 200 and len(lines) == every and bad == 0, "export.jsonl: %d lines, %d failing the Record schema" % (len(lines), bad))
r = S.options(API + "/records", headers={"Origin": "https://example.org", "Access-Control-Request-Method": "GET"}, timeout=30)
expect(r.status_code == 204 and r.headers.get("Access-Control-Allow-Methods") == "GET, OPTIONS", "CORS preflight")
r = S.get(BASE + "/developers/api", timeout=30)
expect(r.status_code == 200 and "swagger-ui-bundle.js" in r.text, "interactive reference page")

print("\n%d problem(s)" % len(fails))
for f in fails:
    print("  " + f)
sys.exit(1 if fails else 0)
