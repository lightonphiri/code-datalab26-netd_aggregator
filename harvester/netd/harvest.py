"""OAI-PMH harvesting (Sickle). Stores raw metadata XML; no cleaning happens here."""
import datetime
import json
import time

from lxml import etree
from sickle import Sickle
from sickle.oaiexceptions import NoRecordsMatch

OAI_NS = "{http://www.openarchives.org/OAI/2.0/}"


def client(src):
    return Sickle(src["base_url"], max_retries=4, default_retry_after=20, timeout=120,
                  retry_status_codes=(500, 502, 503, 504))


def choose_format(sickle, src):
    offered = [f.metadataPrefix for f in sickle.ListMetadataFormats()]
    for f in src.get("formats", ["oai_dc"]):
        if f in offered:
            return f
    return "oai_dc"


def harvest_sets(sickle, store, src):
    pairs = [(s.setSpec, s.setName) for s in sickle.ListSets()]
    store.put_set_names(src["id"], pairs)
    return dict(pairs)


def harvest_source(store, src, full=False, limit=None, log=print):
    """Harvest one source. Incremental (from= last successful run) unless full=True."""
    started = time.time()
    sickle = client(src)
    prefix = choose_format(sickle, src)
    harvest_sets(sickle, store, src)
    last = None if full else store.last_success(src["id"])
    from_date = (datetime.datetime.utcfromtimestamp(last - 86400).strftime("%Y-%m-%d")
                 if last else None)
    n = d = 0
    status, message = "ok", ""
    try:
        for set_spec in src.get("sets") or [None]:
            params = {"metadataPrefix": prefix, "ignore_deleted": False}
            if set_spec:
                params["set"] = set_spec
            if from_date:
                params["from"] = from_date
            try:
                for rec in sickle.ListRecords(**params):
                    h = rec.header
                    xml = ""
                    if not h.deleted:
                        md = rec.xml.find(OAI_NS + "metadata")
                        xml = etree.tostring(md[0], encoding="unicode") if md is not None and len(md) else ""
                    store.put_raw(src["id"], h.identifier, h.datestamp, h.setSpecs, h.deleted, prefix, xml)
                    n += 1
                    d += int(h.deleted)
                    if n % 500 == 0:
                        store.commit()
                        log("  %s: %d records" % (src["id"], n))
                    if limit and n >= limit:
                        raise StopIteration
            except NoRecordsMatch:
                log("  %s set %s: no new records" % (src["id"], set_spec))
    except StopIteration:
        message = "stopped at limit %d" % limit
    except Exception as e:  # keep what we have; mark run as failed
        status, message = "error", repr(e)[:500]
    store.log_run(source=src["id"], started_at=started, finished_at=time.time(), from_date=from_date,
                  records=n, deleted=d, status=status, message=message)
    store.commit()
    log("%s: %d records (%d deleted) via %s, status=%s %s" % (src["id"], n, d, prefix, status, message))
    return n
