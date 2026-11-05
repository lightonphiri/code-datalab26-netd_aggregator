"""MkDocs hook: publish the project's specification documents in the manual site.

docs/SRS.md and docs/SDD.md stay the master copies (they are edited with every change, rule "Requirements first" in
chapter 12). At build time they are added to the site as reference/srs.md and reference/sdd.md; links that point
to other repository files become links to GitHub, and "Edit this page" opens the master copy.
"""
import pathlib
import re

from mkdocs.structure.files import File

REPO = "https://github.com/lightonphiri/code-datalab26-netd_aggregator"
DOCS = {"reference/srs.md": "docs/SRS.md", "reference/sdd.md": "docs/SDD.md"}
LINK = re.compile(r"\]\((?!https?://|mailto:|#)([^)\s]+)\)")


def _github(target, src):
    """A relative link in docs/<file> becomes a GitHub link to the same repository file."""
    path, _, anchor = target.partition("#")
    full = (pathlib.PurePosixPath(src).parent / path).as_posix()
    parts = []
    for p in full.split("/"):
        if p == "..":
            parts.pop()
        elif p not in ("", "."):
            parts.append(p)
    return f"{REPO}/blob/main/{'/'.join(parts)}" + (f"#{anchor}" if anchor else "")


def on_files(files, config):
    root = pathlib.Path(config.config_file_path).parent
    for uri, src in DOCS.items():
        text = (root / src).read_text(encoding="utf-8")
        text = LINK.sub(lambda m: f"]({_github(m.group(1), src)})", text)
        note = (f"!!! note \"Project document\"\n    Published from [`{src}`]({REPO}/blob/main/{src}), the master copy, "
                "each time the manual is built.\n\n")
        title, _, rest = text.partition("\n")
        text = f"{title}\n\n{note}{rest}" if title.startswith("# ") else note + text
        files.append(File.generated(config, uri, content=text))
    return files


def on_page_context(context, page, config, nav):
    if page.file.src_uri in DOCS:
        page.edit_url = f"{REPO}/edit/main/{DOCS[page.file.src_uri]}"
    return context
