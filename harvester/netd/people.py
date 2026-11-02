"""Supervisor name variants (SRS FR-64): one name per person within an institution.

Repositories and title pages write the same supervisor in several ways ("J. Phiri", "Jackson Phiri", "Dr Phiri J",
"Phiri, Jackson"). Applied when indexing, per institution, over all its records, like department names (FR-62,
`netd/units.py`). Names are read with the evaluator's parser (`ml.evaluate.person_words`: surname, then the given
names or initials in order, titles removed). Two spellings are the same person when the surnames are equal and the
given names do not conflict: position by position, initials must agree and full names must be equal (or one a
prefix of the other, "Chris" / "Christopher"); a spelling with no given names conflicts with nothing.

Common surnames (Phiri, Banda, Mwale) need care, because "J. Phiri" may be any of several people. Spellings are
grouped from the most specific (full given name) to the least (initials only). A spelling joins a group only when
it agrees with every spelling already in that group and either exactly one group of that surname qualifies, or
exactly one of the qualifying groups shares a department (failing that, a faculty) with the spelling's records.
Otherwise it stays on its own. A bare surname ("Mweemba") is never joined: one such spelling stands for records of
different people (in the 2020 gold standard, bare "Mweemba" and "Mwansa" read from title pages were L. Mweemba and
L. Mwansa, while joining by department sent them to Oliver Mweemba and Joseph M Mwansa). Each group is shown under
its fullest spelling in ordinary capitals ("Austin Mumba Cheyeka" rather than "Austin Cheyeka" or "A. M. Cheyeka").

Display only: the staging store and the model predictions are not changed (the evaluated figures do not depend on
this step); the value as harvested or predicted is kept in Solr (`supervisor_orig_ssm`) and stays searchable.
"""
import re
from collections import Counter, defaultdict

from .ml.evaluate import person_words


def _parse(v):
    try:
        sur, given = person_words(v)
    except Exception:  # noqa: BLE001 - an odd value is left as it is
        return None
    if not sur or len(sur) < 2 or not sur.isalpha():
        return None
    return sur, [g for g in given if g.isalpha()]


def _agree(a, b):
    """Given names in order: initials agree, full names equal or one a prefix (at least 3 letters) of the other.
    The same full names in another order also agree ("Elijah Mwewa Mutambanshiku" / "Elijah Mutambanshiku Mwewa")."""
    if len(a) > 1 and all(len(x) > 1 for x in a + b) and sorted(a) == sorted(b):
        return True
    for x, y in zip(a, b):
        if x[0] != y[0]:
            return False
        if len(x) > 1 and len(y) > 1 and x != y and not (min(len(x), len(y)) >= 3 and
                                                         (x.startswith(y) or y.startswith(x))):
            return False
    return True


def _rank(v, given, n):
    """Spelling shown for a group: ordinary capitals, a full given name, the most given names (initials count), the
    most written out in full, then the most records and tidier forms."""
    full = any(len(g) > 1 for g in given)
    words = re.findall(r"[A-Za-z]+", v)
    shouting = any(len(w) > 1 and (w.isupper() or any(c.isupper() for c in w[1:])) for w in words)  # "TEMBO", "ROBert"
    title = bool(re.match(r"(?i)\s*(prof(essor)?|dr|mrs?|ms|rev|eng)\b", v))
    return (shouting, not full, -len(given), -sum(len(g) > 1 for g in given), -n, title, "," in v, len(v), v)


def canonical(records):
    """records: iterable of (supervisor values, departments, faculties) for one institution.
    Returns {value: name to show} for the values shown differently."""
    count, units = Counter(), defaultdict(lambda: (set(), set()))
    for sups, depts, facs in records:
        for v in sups or []:
            count[v] += 1
            units[v][0].update(depts or [])
            units[v][1].update(facs or [])
    parsed = {v: p for v in count if (p := _parse(v))}
    by_sur = defaultdict(list)
    for v, (sur, given) in parsed.items():
        by_sur[sur].append(v)
    out = {}
    for sur, vals in by_sur.items():
        if len(vals) < 2:
            continue
        # most specific first: full given names, then more initials, then more records
        vals.sort(key=lambda v: (-sum(len(g) > 1 for g in parsed[v][1]), -len(parsed[v][1]), -count[v], v))
        groups = []   # each: {"vals": [...], "dept": set, "fac": set}
        for v in vals:
            g = parsed[v][1]
            ok = [c for c in groups if all(_agree(g, parsed[w][1]) for w in c["vals"])]
            if not g:
                ok = []        # bare surname: left on its own
            pick = ok[0] if len(ok) == 1 else None
            if len(ok) > 1:
                d, f = units[v]
                for key, mine in (("dept", d), ("fac", f)):
                    hit = [c for c in ok if mine & c[key]] if mine else []
                    if len(hit) == 1:
                        pick = hit[0]
                        break
                    if hit:
                        break      # several groups share the unit: still ambiguous
            if pick is None:
                pick = {"vals": [], "dept": set(), "fac": set()}
                groups.append(pick)
            pick["vals"].append(v)
            pick["dept"] |= units[v][0]
            pick["fac"] |= units[v][1]
        for c in groups:
            if len(c["vals"]) < 2:
                continue
            show = min(c["vals"], key=lambda w: _rank(w, parsed[w][1], count[w]))
            for w in c["vals"]:
                if w != show:
                    out[w] = show
    return out


def apply(rec, mapping):
    """Replace a record's supervisor values using `canonical`'s mapping (order kept, duplicates removed)."""
    vals = rec.get("supervisor") or []
    new = list(dict.fromkeys(mapping.get(v, v) for v in vals))
    return new if new != vals else None
