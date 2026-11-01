"""Title-page rules: the baseline metadata-filling model (SRS FR-49).

Reads the first pages of the PDF for the statements that Zambian theses and dissertations conventionally carry:
  - the degree statement: "... submitted in partial fulfilment of the requirements for the award of the degree of
    Master of Science in Computer Science" -> degree, discipline, degree level
  - supervision: "Supervisor: Dr L. Phiri", "under the supervision of Prof. ..." -> supervisor
  - the academic unit: "Department of Library and Information Science", "School of Education" -> department, faculty
Confidence reflects how specific the evidence is (an explicit degree statement scores higher than a degree name
mentioned anywhere on the page). Later models are compared against this baseline (FR-53).
"""
import re

from ... import crosswalk

NAME = "titlepage-rules"
VERSION = "1"
FIELDS = ("degree_level", "degree", "discipline", "supervisor", "department", "faculty")
USES = ("title",)
NEEDS_TEXT = True

DEG_HEAD = r"(?:master(?:'?s)?|doctor|bachelor(?:'?s)?|post-?\s?graduate diploma)\s+(?:of|in)\s+"
STATEMENT = re.compile(
    r"(?:fulfil+ment|requirements?|award|submitted|presented|dissertation|thesis|report)[^.]{0,160}?"
    r"(?:degree|award|diploma)\s+(?:of\s+)?(?:the\s+)?(" + DEG_HEAD + r"[A-Za-z ,&()'\-]{3,120})", re.I)
DEG_ANY = re.compile(r"\b(" + DEG_HEAD + r"[A-Za-z ,&()'\-]{3,100})", re.I)
ABBREV = [
    (re.compile(r"\b(ph\.?\s?d\.?|d\.?\s?phil)\b", re.I), "Doctoral", "Doctor of Philosophy"),
    (re.compile(r"\b(m\.?\s?sc|m\.?\s?ed|m\.?\s?phil|mba|mph|mmed|ll\.?m|mlis)\b\.?", re.I), "Masters", None),
    (re.compile(r"\b(pgd|pg\.?\s?dip)\b", re.I), "Postgraduate Diploma", None),
    (re.compile(r"\b(b\.?\s?sc|ll\.?b|b\.?\s?ed)\b\.?", re.I), "Bachelors", None),
]
STOP = re.compile(r"\s+(?:at|of the|from|to|by|submitted|presented|in the|lusaka|zambia|university|copyright|"
                  r"school|faculty|department|institute|college|supervisor|the)\b.*$", re.I)

TITLE_WORDS = r"(?i:prof(?:essor)?|dr|mr|mrs|ms|rev|eng|assoc\.?\s+prof)\.?"
PERSON = r"((?:" + TITLE_WORDS + r"\s+)?(?:[A-Z][a-zA-Z'\-]+|[A-Z]\.)(?:\s+(?:[A-Z][a-zA-Z'\-]+|[A-Z]\.)){1,4})"
SUPERVISOR = [
    (re.compile(r"\b(?i:(?:main\s+|principal\s+|co-?\s?)?supervisors?)\s*[:\-–]\s*" + PERSON), 0.92),
    (re.compile(r"\b(?i:supervised\s+by)\s*[:\-–]?\s*" + PERSON), 0.9),
    (re.compile(r"\b(?i:under\s+the\s+(?:able\s+)?(?:supervision|guidance)\s+of)\s+" + PERSON), 0.88),
    (re.compile(PERSON + r"\s*\(?\s*(?i:(?:main\s+|co-?\s?)?supervisor)\)?\b"), 0.75),
]
NOT_NAMES = re.compile(r"\b(signature|signed|date|name|department|university|school|examiner|candidate|dean|"
                       r"declaration|approval|head|chairperson|lecturer|the|of)\b", re.I)
UNIT = re.compile(r"\b(department|school|faculty|institute|college)\s+of\s+(?=[A-Z])", re.I)
UNIT_STOP = re.compile(r"\s*(?:,|\.|;|:|\(|\bat\b|\bthe\b|\buniversity\b|\blusaka\b|\bzambia\b|\bin\s+partial\b|"
                       r"\bsubmitted\b|\bpresented\b|\bdepartment\b|\bschool\b|\bfaculty\b|\binstitute\b|"
                       r"\bcollege\b|\b(?:a|this)\s+(?:dissertation|thesis|report)\b|\bdissertation\b|\bthesis\b|"
                       r"\bby\b|\b(?:19|20)\d\d\b).*$", re.I)


def _flat(page):
    return re.sub(r"\s+", " ", page.replace("-\n", "")).strip()


def _degree(stmt):
    stmt = STOP.sub("", stmt.strip(" ,.;-"))
    deg, disc = crosswalk.degree_from_text(stmt)
    if not deg:
        return None, None, None
    level = crosswalk.degree_level([deg])
    return deg, disc, level


def _clean_person(p):
    p = re.sub(r"\s+", " ", p).strip(" .,")
    p = re.sub(r"^" + TITLE_WORDS + r"\s+", "", p, flags=re.I)
    return p


def predict(meta, text):
    pages = [_flat(p) for p in text.split("\f")]
    head = " ".join(pages[:3])
    allt = " ".join(pages)
    out = {}

    # degree statement, then any degree name, then abbreviations
    for rx, conf, scope in ((STATEMENT, 0.96, allt), (DEG_ANY, 0.82, head)):
        m = rx.search(scope)
        if m:
            deg, disc, level = _degree(m.group(1))
            if deg and level:
                ev = scope[max(0, m.start() - 60): m.end() + 20]
                out["degree"] = ([deg + (" in " + disc if disc else "")], conf, ev)
                out["degree_level"] = ([level], conf, ev)
                if disc:
                    out["discipline"] = ([disc], conf - 0.05, ev)
                break
    if "degree_level" not in out:
        for rx, level, deg in ABBREV:
            m = rx.search(head)
            if m:
                ev = head[max(0, m.start() - 60): m.end() + 60]
                out["degree_level"] = ([level], 0.7, ev)
                if deg:
                    out["degree"] = ([deg], 0.7, ev)
                break

    sups = []
    best, ev = 0.0, None
    for rx, conf in SUPERVISOR:
        for m in rx.finditer(allt):
            name = _clean_person(m.group(1))
            cut = NOT_NAMES.search(name)
            if cut:
                name = name[:cut.start()].strip(" .,")
            if len(name.split()) < 2 or len(name) < 5 or name in sups:
                continue
            if any(a.lower() in name.lower() for a in (meta.get("title") or [])):
                continue
            sups.append(name)
            if conf > best:
                best, ev = conf, allt[max(0, m.start() - 20): m.end() + 20]
        if sups:
            break
    if sups:
        out["supervisor"] = (sups[:3], best, ev)

    for kind, field in (("department", "department"), ("school", "faculty"), ("faculty", "faculty")):
        if field in out:
            continue
        for m in UNIT.finditer(head):
            if m.group(1).lower() != kind:
                continue
            name = UNIT_STOP.sub("", head[m.end(): m.end() + 90]).strip()
            if 3 <= len(name) <= 70:
                unit = "%s of %s" % (kind.capitalize(), crosswalk._tc(name))
                first = m.start() < len(pages[0])
                out[field] = ([unit], 0.88 if first else 0.78, head[max(0, m.start() - 20): m.end() + 10])
                break
    return out
