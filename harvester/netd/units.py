"""Department name variants (SRS FR-62): one name per department within an institution.

Repositories, collection names and title pages spell the same department in several ways ("Plant Science" /
"Plant Sciences", "Pathology & Microbiology" / "Microbiology and Pathology", "Para -clinical Studies"), and title
pages add typos ("Commuhity Medicine"). Applied when indexing, per institution, over all its records: values are
cleaned, grouped by a spelling-insensitive key, and each group is shown under its most frequent spelling. Rare
values within a small edit distance of a much more frequent group join it. The staging store and the model
predictions are not changed (the evaluated metadata-filling figures do not depend on this step); the value as
harvested or predicted is kept in Solr (`department_orig_ssm`) when it is shown differently.
"""
import difflib
import re
from collections import Counter, defaultdict

STOP = {"and", "of", "the", "in", "for", "department", "dept"}
FUZZY_RATIO = 0.92   # SequenceMatcher ratio of the keys
FUZZY_FACTOR = 3     # the group joined must hold at least this many times as many records
FUZZY_MAX = 2        # only values seen at most this often are joined by edit distance


def clean(name):
    """Spelling fixes that need no corpus: '&' -> 'and', 'Para -clinical' -> 'Para-clinical', trailing junk."""
    s = re.sub(r"\s+", " ", (name or "").replace("&", " and ")).strip()
    s = re.sub(r"\s*-\s*", "-", s)
    s = re.sub(r"[\s|/,;:.\-]+$", "", s)            # "Department of Mathematics |"
    s = re.sub(r"(\w{3,}) [a-z]$", r"\1", s)         # "Department of Surgery a"
    return s


def _stem(w):
    if len(w) > 4 and w.endswith("ies"):
        return w[:-3] + "y"
    if len(w) > 3 and w.endswith("s") and not w.endswith("ss"):
        return w[:-1]
    return w


def key(name):
    words = re.findall(r"[a-z]+", clean(name).lower().replace("-", ""))
    return " ".join(sorted(_stem(w) for w in words if w not in STOP))


def canonical(counts):
    """{value: number of records} -> {value: name to show}; only values shown differently are returned."""
    groups = defaultdict(Counter)
    for v, n in counts.items():
        if key(v):
            groups[key(v)][clean(v)] += n
    size = {k: sum(c.values()) for k, c in groups.items()}
    target = {k: k for k in groups}
    for k in sorted(groups, key=lambda k: size[k]):
        if size[k] > FUZZY_MAX:
            continue
        best = max((o for o in groups if o != k and size[o] >= FUZZY_FACTOR * size[k]
                    and difflib.SequenceMatcher(None, k, o).ratio() >= FUZZY_RATIO),
                   key=lambda o: (difflib.SequenceMatcher(None, k, o).ratio(), size[o]), default=None)
        if best:
            target[k] = best
    merged = defaultdict(Counter)
    for k, c in groups.items():
        t = target[k]
        while target[t] != t:
            t = target[t]
        merged[t].update(c)
    show = {t: sorted(c.items(), key=lambda kv: (-kv[1], len(kv[0]), kv[0]))[0][0] for t, c in merged.items()}
    out = {}
    for v in counts:
        if not key(v):
            continue
        t = target[key(v)]
        while target[t] != t:
            t = target[t]
        if show[t] != v:
            out[v] = show[t]
    return out


def apply(rec, mapping):
    """Replace a record's department values using `canonical`'s mapping (order kept, duplicates removed)."""
    vals = rec.get("department") or []
    new = list(dict.fromkeys(mapping.get(v, v) for v in vals))
    return new if new != vals else None
