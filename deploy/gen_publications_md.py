"""Regenerate PUBLICATIONS.md from portal/config/publications.yml (single source)."""
import os
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
d = yaml.safe_load(open(os.path.join(ROOT, "portal", "config", "publications.yml")))
p = d["project"]
out = ["# Publications based on the Zambia National ETD Portal project", "",
       "Project: [%s](%s), %s ([%s](%s))." % (p["name"], p["url"], p["group"], p["group_url"], p["group_url"]), "",
       p["summary"], "", "## Project members", ""] + ["- [%s](%s) (%s)" % (m["name"], m["url"], m["role"]) if m.get("url") else "- %s (%s)" % (m["name"], m["role"]) for m in p["members"]] + ["", "## Publications based on the [Zambia National ETD Portal project](%s)" % p["url"], "",
        "The publications, dissertations and capstone reports below come out of the [Zambia National ETD Portal project](%s). " % p["url"] +
        "They study the visibility of Zambian research, the quality, completeness and ETD-MS compliance of ETD metadata in "
        "institutional repositories, and ways of improving it; their findings shaped how this portal harvests, cleans and "
        "presents ETD metadata.", "",
       "| Year | Type | Reference |", "|---|---|---|"]
for x in d["publications"]:
    out.append("| %s | %s | %s (%s). *%s*. %s. %s |" % (x["year"], x["type"], x["authors"], x["year"], x["title"], x["venue"], x["url"]))
out += ["", "_Generated from `portal/config/publications.yml`; the same list is shown on the portal's About page._", ""]
open(os.path.join(ROOT, "PUBLICATIONS.md"), "w").write("\n".join(out))
print("wrote PUBLICATIONS.md (%d entries)" % len(d["publications"]))
