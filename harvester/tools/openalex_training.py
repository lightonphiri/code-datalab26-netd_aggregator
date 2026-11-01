"""Fetch the OpenAlex topic taxonomy and a labelled training sample (SRS FR-54).

  python tools/openalex_training.py OUT_DIR [--per-subfield 120] [--api-key KEY] [--mailto EMAIL]

Writes OUT_DIR/taxonomy.json (domains, fields, subfields with descriptions) and OUT_DIR/works.jsonl (one OpenAlex
work per line: id, title, abstract, subfield id), sampled per subfield from works with abstracts, using
OpenAlex's own `primary_topic` labels. OpenAlex data is CC0. Without an API key OpenAlex allows a small daily
budget per address; this needs about 260 requests.
"""
import argparse
import json
import os
import time
import urllib.parse
import urllib.request

API = "https://api.openalex.org"


def get(path, params, key, mailto):
    if key:
        params["api_key"] = key
    if mailto:
        params["mailto"] = mailto
    url = "%s/%s?%s" % (API, path, urllib.parse.urlencode(params))
    for attempt in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "NETD (+https://netd.ac.zm)"}),
                                        timeout=60) as r:
                return json.load(r)
        except Exception:
            if attempt == 4:
                raise
            time.sleep(5 * (attempt + 1))


def short(oid):
    """https://openalex.org/subfields/2739 -> subfields/2739"""
    return oid.split("openalex.org/")[-1]


def abstract(inv):
    if not inv:
        return ""
    pos = {}
    for word, idx in inv.items():
        for i in idx:
            pos[i] = word
    return " ".join(pos[i] for i in sorted(pos))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("out")
    p.add_argument("--per-subfield", type=int, default=120)
    p.add_argument("--api-key", default=os.environ.get("OPENALEX_API_KEY"))
    p.add_argument("--mailto")
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    tax = {"source": "OpenAlex Topics (https://openalex.org, CC0)", "fetched": time.strftime("%Y-%m-%d"),
           "domains": [], "fields": [], "subfields": []}
    for kind in ("domains", "fields", "subfields"):
        page = 1
        while True:
            res = get(kind, {"per_page": 200, "page": page}, a.api_key, a.mailto)
            for x in res["results"]:
                item = {"id": short(x["id"]), "name": x["display_name"], "description": x.get("description") or ""}
                if kind == "fields":
                    item["domain"] = short(x["domain"]["id"])
                if kind == "subfields":
                    item["field"] = short(x["field"]["id"])
                    item["domain"] = short(x["domain"]["id"])
                tax[kind].append(item)
            if len(res["results"]) < 200:
                break
            page += 1
    with open(os.path.join(a.out, "taxonomy.json"), "w") as fh:
        json.dump(tax, fh, ensure_ascii=False, indent=1)
    print("taxonomy: %d domains, %d fields, %d subfields" % tuple(len(tax[k]) for k in ("domains", "fields", "subfields")))
    n = 0
    with open(os.path.join(a.out, "works.jsonl"), "w") as fh:
        for i, sf in enumerate(tax["subfields"]):
            sid = sf["id"].split("/")[-1]
            res = get("works", {"filter": "primary_topic.subfield.id:%s,has_abstract:true,language:en" % sid,
                                "sample": a.per_subfield, "seed": 2026, "per_page": min(200, a.per_subfield),
                                "select": "id,title,abstract_inverted_index"}, a.api_key, a.mailto)
            for w in res["results"]:
                text = abstract(w.get("abstract_inverted_index"))
                if w.get("title") and len(text) > 200:
                    fh.write(json.dumps({"id": short(w["id"]), "title": w["title"], "abstract": text[:3000],
                                         "subfield": sf["id"]}, ensure_ascii=False) + "\n")
                    n += 1
            if i % 25 == 0:
                print("%d/%d subfields, %d works" % (i, len(tax["subfields"]), n), flush=True)
            time.sleep(0.2)
    print("works: %d" % n)


if __name__ == "__main__":
    main()
