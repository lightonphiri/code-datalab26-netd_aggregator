"""Conformance tests for the NETD OAI-PMH data provider (SRS EI-4; SDD section 5.1).

    pip install sickle lxml
    python tests/oai_conformance.py [BASE_URL] [EXPECTED_RECORD_COUNT]

Defaults: https://netd.ac.zm/oai and the number of records reported by the REST API with duplicates included. Responses are validated
against the OAI-PMH, oai-identifier and oai_dc schemas (downloaded once into ~/.cache/netd-oai-xsd). The ETD-MS v1.1
schema host was not reachable when this was written, so etdms records are checked for element order and required
elements instead. A full run harvests every record three times and takes about five minutes. Exit status 1 = problem.
"""
import copy
import json
import os
import sys
import time
import urllib.parse
import urllib.request

from lxml import etree
from sickle import Sickle

BASE = sys.argv[1] if len(sys.argv) > 1 else "https://netd.ac.zm/oai"
if len(sys.argv) > 2:
    EXPECTED = int(sys.argv[2])
else:
    # OAI-PMH lists every record, duplicate copies included (FR-19); search pages show each thesis once
    api = BASE.rsplit("/oai", 1)[0] + "/api/v1/records?per_page=1&duplicates=include"
    EXPECTED = json.load(urllib.request.urlopen(api, timeout=60))["meta"]["total"]
XSD = os.path.expanduser("~/.cache/netd-oai-xsd")
XSD_FILES = {
    "OAI-PMH.xsd": "https://www.openarchives.org/OAI/2.0/OAI-PMH.xsd",
    "oai_dc.xsd": "https://www.openarchives.org/OAI/2.0/oai_dc.xsd",
    "oai-identifier.xsd": "https://www.openarchives.org/OAI/2.0/oai-identifier.xsd",
    "simpledc20021212.xsd": "https://dublincore.org/schemas/xmls/simpledc20021212.xsd",
    "xml.xsd": "https://www.w3.org/2001/xml.xsd",
}
WRAPPER = """<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:netd:all">
  <xs:import namespace="http://www.openarchives.org/OAI/2.0/" schemaLocation="OAI-PMH.xsd"/>
  <xs:import namespace="http://www.openarchives.org/OAI/2.0/oai_dc/" schemaLocation="oai_dc.xsd"/>
  <xs:import namespace="http://www.openarchives.org/OAI/2.0/oai-identifier" schemaLocation="oai-identifier.xsd"/>
</xs:schema>"""


def load_schema():
    os.makedirs(XSD, exist_ok=True)
    for name, url in XSD_FILES.items():
        path = os.path.join(XSD, name)
        if not os.path.exists(path):
            req = urllib.request.Request(url, headers={"User-Agent": "netd-oai-conformance/1.0 (+https://netd.ac.zm)"})
            text = urllib.request.urlopen(req, timeout=60).read().decode("utf-8")
            text = text.replace("http://dublincore.org/schemas/xmls/simpledc20021212.xsd", "simpledc20021212.xsd")
            text = text.replace("http://www.w3.org/2001/03/xml.xsd", "xml.xsd")
            with open(path, "w") as fh:
                fh.write(text)
    path = os.path.join(XSD, "all.xsd")
    with open(path, "w") as fh:
        fh.write(WRAPPER)
    return etree.XMLSchema(etree.parse(path))


NS = {"o": "http://www.openarchives.org/OAI/2.0/", "e": "http://www.ndltd.org/standards/metadata/etdms/1.1/"}
SCHEMA = load_schema()
ETDMS_ORDER = ["title", "alternativeTitle", "creator", "subject", "description", "publisher", "contributor", "date",
               "type", "format", "identifier", "language", "coverage", "rights", "degree"]
fails = []


def get(params, post=False):
    data = urllib.parse.urlencode(params)
    req = urllib.request.Request(BASE, data=data.encode()) if post else urllib.request.Request(BASE + "?" + data)
    return etree.fromstring(urllib.request.urlopen(req, timeout=120).read())


def raw(query):
    return etree.fromstring(urllib.request.urlopen(BASE + "?" + query, timeout=60).read())


def validate(doc, label):
    d = copy.deepcopy(doc)
    for m in d.iterfind(".//o:metadata", NS):  # etdms: own checks, then validate the envelope only
        if m[0].tag.startswith("{%s}" % NS["e"]):
            check_etdms(m[0], label)
            m.remove(m[0])
            etree.SubElement(m, "{http://www.openarchives.org/OAI/2.0/oai_dc/}dc")
    if not SCHEMA.validate(d):
        fails.append("%s: schema: %s" % (label, SCHEMA.error_log.last_error))


def check_etdms(thesis, label):
    pos = [ETDMS_ORDER.index(etree.QName(c).localname) for c in thesis]
    if pos != sorted(pos):
        fails.append("%s: ETD-MS elements out of order" % label)
    for need in ("title", "identifier"):
        if thesis.find("e:" + need, NS) is None:
            fails.append("%s: ETD-MS missing %s" % (label, need))


def expect(cond, label):
    print(("ok   " if cond else "FAIL ") + label)
    if not cond:
        fails.append(label)


def error_code(doc):
    e = doc.find("o:error", NS)
    return e.get("code") if e is not None else None


# Identify, formats, sets
d = get({"verb": "Identify"}); validate(d, "Identify")
expect(d.findtext(".//o:repositoryName", namespaces=NS) == "Zambia National ETD Portal", "Identify repositoryName")
earliest = d.findtext(".//o:earliestDatestamp", namespaces=NS)
d = get({"verb": "Identify"}, post=True); expect(error_code(d) is None, "Identify via POST")
d = get({"verb": "ListMetadataFormats"}); validate(d, "ListMetadataFormats")
expect(sorted(d.xpath("//o:metadataPrefix/text()", namespaces=NS)) == ["etdms", "oai_dc"], "ListMetadataFormats prefixes")
d = get({"verb": "ListSets"}); validate(d, "ListSets")
sets = d.xpath("//o:setSpec/text()", namespaces=NS)
expect("level:masters" in sets and "level:doctoral" in sets and "inst:unza" in sets, "ListSets: %s" % ", ".join(sets))

# Full harvests through resumption tokens
sk = Sickle(BASE, max_retries=2, timeout=120)
for verb, prefix in (("ListRecords", "oai_dc"), ("ListRecords", "etdms"), ("ListIdentifiers", "oai_dc")):
    t = time.time()
    it = (sk.ListRecords if verb == "ListRecords" else sk.ListIdentifiers)(metadataPrefix=prefix)
    ids = [(r.header if verb == "ListRecords" else r).identifier for r in it]
    expect(len(ids) == EXPECTED and len(set(ids)) == len(ids),
           "%s %s: %d records, %d unique (%.0f s)" % (verb, prefix, len(ids), len(set(ids)), time.time() - t))

# First page of each prefix and a resumption page validate
for prefix in ("oai_dc", "etdms"):
    d = get({"verb": "ListRecords", "metadataPrefix": prefix}); validate(d, "ListRecords %s p1" % prefix)
    tok = d.find(".//o:resumptionToken", NS)
    expect(tok is not None and tok.get("completeListSize") == str(EXPECTED) and tok.get("expirationDate"),
           "%s resumptionToken attributes" % prefix)
    d2 = get({"verb": "ListRecords", "resumptionToken": tok.text}); validate(d2, "ListRecords %s p2" % prefix)
    expect(d2.find(".//o:resumptionToken", NS).get("cursor") == "100", "%s page 2 cursor=100" % prefix)

# Sets
total = 0
for s in sets:
    n = sum(1 for _ in sk.ListIdentifiers(metadataPrefix="oai_dc", set=s))
    print("     set %-16s %5d" % (s, n))
    if s.startswith("inst:"):
        expect(n > 0, "set %s non-empty" % s)
    if s.startswith("inst:"):
        total += n
expect(total == EXPECTED, "institution sets add up to %d (%d)" % (EXPECTED, total))

# Dates
n = sum(1 for _ in sk.ListIdentifiers(metadataPrefix="oai_dc", **{"from": earliest}))
expect(n == EXPECTED, "from=earliestDatestamp returns all (%d)" % n)
n = sum(1 for _ in sk.ListIdentifiers(metadataPrefix="oai_dc", **{"from": earliest[:10], "until": earliest[:10]}))
expect(n > 0, "from/until day granularity on %s (%d)" % (earliest[:10], n))
expect(error_code(get({"verb": "ListRecords", "metadataPrefix": "oai_dc", "from": "2099-01-01"})) == "noRecordsMatch",
       "from in the future -> noRecordsMatch")
expect(error_code(get({"verb": "ListRecords", "metadataPrefix": "oai_dc", "until": "2000-01-01"})) == "noRecordsMatch",
       "until before earliest -> noRecordsMatch")

# GetRecord
oid = "oai:netd.ac.zm:unza-123456789-9150"
for prefix in ("oai_dc", "etdms"):
    d = get({"verb": "GetRecord", "identifier": oid, "metadataPrefix": prefix}); validate(d, "GetRecord " + prefix)
    expect(error_code(d) is None and d.findtext(".//o:identifier", namespaces=NS) == oid, "GetRecord " + prefix)
d = get({"verb": "ListMetadataFormats", "identifier": oid}); expect(error_code(d) is None, "ListMetadataFormats identifier")

# Errors
cases = [
    ("verb=Nonsense", "badVerb"), ("", "badVerb"), ("verb=Identify&verb=Identify", "badArgument"),
    ("verb=Identify&foo=bar", "badArgument"), ("verb=ListRecords", "badArgument"),
    ("verb=ListRecords&metadataPrefix=marc", "cannotDisseminateFormat"),
    ("verb=GetRecord&identifier=oai:netd.ac.zm:nope&metadataPrefix=oai_dc", "idDoesNotExist"),
    ("verb=GetRecord&identifier=%s&metadataPrefix=mods" % oid, "cannotDisseminateFormat"),
    ("verb=ListMetadataFormats&identifier=oai:other:1", "idDoesNotExist"),
    ("verb=ListRecords&resumptionToken=garbage", "badResumptionToken"),
    ("verb=ListRecords&resumptionToken=x&metadataPrefix=oai_dc", "badArgument"),
    ("verb=ListSets&resumptionToken=x", "badResumptionToken"),
    ("verb=ListRecords&metadataPrefix=oai_dc&from=2026-01-01&until=2026-12-31T00:00:00Z", "badArgument"),
    ("verb=ListRecords&metadataPrefix=oai_dc&from=2026-12-01&until=2026-01-01", "badArgument"),
    ("verb=ListRecords&metadataPrefix=oai_dc&from=31-10-2026", "badArgument"),
    ("verb=ListRecords&metadataPrefix=oai_dc&set=inst:nowhere", "noRecordsMatch"),
]
for q, code in cases:
    d = raw(q)
    validate(d, "error " + q)
    expect(error_code(d) == code, "%-70s -> %s" % (q or "(no arguments)", code))
    if code in ("badVerb", "badArgument"):
        expect(not d.find("o:request", NS).attrib, "   request element has no attributes")

print("\n%d problem(s)" % len(fails))
for f in fails:
    print("  " + f)
sys.exit(1 if fails else 0)
