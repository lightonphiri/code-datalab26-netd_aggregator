"""Fallback loader for DSpace 6 XMLUI repositories with OAI-PMH and REST switched off (SRS FR-10).

Lists item handles from a collection's browse pages and reads each item's public METS export
(/metadata/handle/<handle>/mets.xml), whose embedded DSpace Intermediate Metadata (dim) block is
stored unchanged in the raw layer, so the crosswalk and everything downstream are unchanged.
"""
import re
import time
import urllib.parse
import urllib.request

from lxml import etree

DIM = "{http://www.dspace.org/xmlns/dspace/dim}dim"


def _get(url, tries=4):
    for i in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=120) as r:
                return r.read()
        except Exception:
            if i == tries - 1:
                raise
            time.sleep(10 * (i + 1))


def _item_handles(base, coll, prefix):
    seen, offset = [], 0
    while True:
        html = _get("%s/handle/%s/browse?type=dateissued&rpp=100&offset=%d" % (base, coll, offset)).decode("utf-8", "replace")
        found = [h for h in re.findall(r'<a href="%s/handle/(\d+/\d+)">' % re.escape(prefix), html)
                 if h != coll and h not in seen]
        m = re.search(r"Now showing items \d+-(\d+) of (\d+)", html)
        seen += found
        if not m or int(m.group(1)) >= int(m.group(2)) or not found:
            return seen
        offset = int(m.group(1))


def harvest_mets(store, src, log=print, limit=None):
    base = src["xmlui"].rstrip("/")                 # e.g. https://space.mu.ac.zm/xmlui
    prefix = urllib.parse.urlparse(base).path       # e.g. /xmlui
    host = urllib.parse.urlparse(base).hostname
    n, names = 0, []
    for coll in src["collections"]:
        cdoc = etree.fromstring(_get("%s/metadata/handle/%s/mets.xml" % (base, coll)))
        ctitle = cdoc.xpath("string(//*[local-name()='field'][@element='title'])").strip()
        cspec = "col_" + coll.replace("/", "_")
        names.append((cspec, ctitle))
        handles = _item_handles(base, coll, prefix)
        # the browse page also links the parent community/collection; keep only items (they have dc.title + date.issued)
        for h in handles:
            doc = etree.fromstring(_get("%s/metadata/handle/%s/mets.xml" % (base, h)))
            if doc.get("LABEL", "").startswith("DSpace Co"):   # community/collection, not an item
                continue
            dim = next(doc.iter(DIM), None)
            if dim is None:
                continue
            store.put_raw(src["id"], "oai:%s:%s" % (host, h), None, [cspec], False, "dim",
                          etree.tostring(dim, encoding="unicode"))
            n += 1
            time.sleep(1)  # politeness (NFR-10)
            if limit and n >= limit:
                break
    store.put_set_names(src["id"], names)
    return n
