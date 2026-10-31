"""Regenerate PUBLICATIONS.md from portal/config/publications.yml (single source)."""
import os
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
d = yaml.safe_load(open(os.path.join(ROOT, "portal", "config", "publications.yml")))
p = d["project"]
out = ["# Publications and related work", "",
       "Project: [%s](%s), %s ([%s](%s))." % (p["name"], p["url"], p["group"], p["group_url"], p["group_url"]), "",
       p["summary"], "", "**Project members:** " + ", ".join(p["members"]) + ".", "",
       "| Year | Type | Reference |", "|---|---|---|"]
for x in d["publications"]:
    out.append("| %s | %s | %s (%s). *%s*. %s. %s |" % (x["year"], x["type"], x["authors"], x["year"], x["title"], x["venue"], x["url"]))
out += ["", "_Generated from `portal/config/publications.yml`; the same list is shown on the portal's About page._", ""]
open(os.path.join(ROOT, "PUBLICATIONS.md"), "w").write("\n".join(out))
print("wrote PUBLICATIONS.md (%d entries)" % len(d["publications"]))
