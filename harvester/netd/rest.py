"""Fallback loader for DSpace 7+ repositories whose OAI-PMH index is empty or broken (SRS FR-10).

Reads items from the public REST API (/server/api) and stores them in the raw layer as `dim`
XML, so the crosswalk and everything downstream are unchanged. Records get oai_id
"oai:<host>:<handle>" and set_specs [col_<handle>, com_<parent handle>] like OAI-PMH would give.
"""
import json
import time
import urllib.parse
import urllib.request
from xml.sax.saxutils import escape

DIM_NS = "http://www.dspace.org/xmlns/dspace/dim"


def _get(url, tries=4):
    for i in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=120) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception:
            if i == tries - 1:
                raise
            time.sleep(10 * (i + 1))


def _spec(kind, handle):
    return "%s_%s" % (kind, handle.replace("/", "_"))


def _dim(metadata):
    out = ['<dim:dim xmlns:dim="%s">' % DIM_NS]
    for key, vals in sorted(metadata.items()):
        parts = key.split(".")
        schema, element = parts[0], parts[1] if len(parts) > 1 else ""
        qual = parts[2] if len(parts) > 2 else None
        for v in vals:
            q = ' qualifier="%s"' % escape(qual) if qual else ""
            out.append('<dim:field mdschema="%s" element="%s"%s>%s</dim:field>'
                       % (escape(schema), escape(element), q, escape(v.get("value") or "")))
    out.append("</dim:dim>")
    return "".join(out)


def harvest_rest(store, src, log=print, limit=None):
    api = src["rest_api"].rstrip("/")
    host = urllib.parse.urlparse(api).hostname
    n = 0
    names = []
    for handle in src["collections"]:
        coll = _get(api + "/pid/find?id=" + urllib.parse.quote(handle, safe="/"))
        cuuid = coll["uuid"]
        parent = _get("%s/core/collections/%s/parentCommunity" % (api, cuuid))
        cspec, pspec = _spec("col", handle), _spec("com", parent["handle"])
        names += [(cspec, coll["name"]), (pspec, parent["name"])]
        page = 0
        while True:
            q = "%s/discover/search/objects?scope=%s&dsoType=ITEM&size=100&page=%d" % (api, cuuid, page)
            res = _get(q)["_embedded"]["searchResult"]
            for obj in res["_embedded"]["objects"]:
                item = obj["_embedded"]["indexableObject"]
                md = dict(item.get("metadata", {}))
                if item.get("handle") and "dc.identifier.uri" not in md:
                    md["dc.identifier.uri"] = [{"value": "https://hdl.handle.net/" + item["handle"]}]
                oai_id = "oai:%s:%s" % (host, item.get("handle") or item["uuid"])
                store.put_raw(src["id"], oai_id, item.get("lastModified"), [cspec, pspec],
                              item.get("withdrawn", False), "dim", _dim(md))
                n += 1
                if limit and n >= limit:
                    break
            if (limit and n >= limit) or page + 1 >= res["page"]["totalPages"]:
                break
            page += 1
            time.sleep(1)  # politeness (NFR-10)
    store.put_set_names(src["id"], names)
    return n
