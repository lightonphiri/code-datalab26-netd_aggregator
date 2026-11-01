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
VERSION = "2"
FIELDS = ("degree_level", "degree", "discipline", "supervisor", "department", "faculty")
USES = ("title",)
NEEDS_TEXT = True

def fz(word):
    """Regex for a word that PDF text extraction may have split with stray spaces ("M aster", "Zambi a")."""
    return r"\s?".join(re.escape(c) for c in word)


DEG_HEAD = (r"(?:" + fz("master") + r"(?:'?s)?|" + fz("doctor") + r"|" + fz("bachelor") + r"(?:'?s)?|post-?\s?"
            + fz("graduate") + r"\s+" + fz("diploma") + r")\s+(?:of|in)\s+")
STATEMENT = re.compile(r"(?:" + fz("fulfil") + r"|" + fz("requirement") + r"|" + fz("submitted") + r"|award)"
                       r"[^.]{0,200}?\b(" + DEG_HEAD + r"[A-Za-z ,&()'\-]{3,120})", re.I)
DEG_ANY = re.compile(r"\b(" + DEG_HEAD + r"[A-Za-z ,&()'\-]{3,100})", re.I)
ABBREV = [
    (re.compile(r"\b(ph\.?\s?d\.?|d\.?\s?phil)\b", re.I), "Doctoral", "Doctor of Philosophy"),
    (re.compile(r"\b(m\.?\s?sc|m\.?\s?ed|m\.?\s?phil|mba|mph|mmed|ll\.?m|mlis)\b\.?", re.I), "Masters", None),
    (re.compile(r"\b(pgd|pg\.?\s?dip)\b", re.I), "Postgraduate Diploma", None),
    (re.compile(r"\b(b\.?\s?sc|ll\.?b|b\.?\s?ed)\b\.?", re.I), "Bachelors", None),
]
STOP = re.compile(r"\s+(?:in\s+(?:the\s+)?(?:school|faculty|department|institute|college|multidisciplinary)|has|have|or|"
                  r"for any|chairperson|signature|computer|student|candidate|examiner|name|date|declaration|"
                  r"dr|prof|mr|mrs|ms|at|of the|from|to|by|submitted|presented|in the|lusaka|zambia|university|copyright|"
                  r"school|faculty|department|institute|college|supervisor|the)\b.*$", re.I)

TITLE_WORDS = r"(?i:prof(?:essor)?s?|drs?|mr|mrs|ms|rev|eng|assoc\.?\s+prof)\.?"
TOKEN = r"(?:[A-Z][a-zA-Z'\-]+|(?:[A-Z]\.){1,4})"
PERSON = r"((?:" + TITLE_WORDS + r"\s*)?" + TOKEN + r"(?:\s*" + TOKEN + r"){1,4})"
PEOPLE = PERSON[:-1] + r"(?:\s*(?:,|\band\b|&)\s*(?:" + TITLE_WORDS + r"\s*)?" + TOKEN + r"(?:\s*" + TOKEN + r"){1,4})?)"
MY_SUP = r"\b(?i:my\s+(?:study\s+|research\s+|main\s+|principal\s+|academic\s+)?(?:co-?\s?)?supervisors?)"
SUPERVISOR = [
    (re.compile(r"\b(?i:(?:main\s+|principal\s+|co-?\s?)?supervisors?)\s*[:\-–]\s*" + PERSON), 0.92),
    (re.compile(r"\b(?i:supervised\s+by)\s*[:\-–]?\s*" + PERSON), 0.9),
    (re.compile(r"\b(?i:under\s+the\s+(?:able\s+)?(?:supervision|guidance)\s+of)\s+" + PERSON), 0.88),
    (re.compile(MY_SUP + r",?\s+" + PEOPLE), 0.86),          # acknowledgements: "my supervisor, Dr X, for ..."
    (re.compile(PERSON + r",?\s+" + MY_SUP), 0.82),          # "... Prof. X, my supervisor, for ..."
    (re.compile(PERSON + r"\s*\(?\s*(?i:(?:main\s+|co-?\s?)?supervisor)\)?\b"), 0.75),
]
NOT_NAMES = re.compile(r"\b(supervisors?|co|signature|signed|date|name|department|university|school|examiner|candidate|dean|"
                       r"declaration|approval|head|chairperson|lecturer|the|of)\b", re.I)
UNIT = re.compile(r"\b(department|school|faculty|institute|college)\s+of\s+(?=[A-Z])", re.I)
UNIT_STOP = re.compile(r"\s*(?:,|\.|;|:|\(|\bat\b|\bthe\b|\buniversity\b|\blusaka\b|\bzambia\b|\bin\s+partial\b|"
                       r"\bsubmitted\b|\bpresented\b|\bdepartment\b|\bschool\b|\bfaculty\b|\binstitute\b|"
                       r"\bcollege\b|\b(?:a|this)\s+(?:dissertation|thesis|report)\b|\bdissertation\b|\bthesis\b|"
                       r"\bby\b|\b(?:19|20)\d\d\b).*$", re.I)


def _flat(page):
    page = page.replace("\u2019", "'").replace("\u2018", "'").replace("/g3", " ")
    return re.sub(r"\s+", " ", page.replace("-\n", "")).strip()


def _unsplit(t):
    """Join words split by stray spaces in the degree statement, using the words that matter here."""
    for w in ("master", "masters", "doctor", "bachelor", "postgraduate", "graduate", "diploma", "philosophy",
              "science", "arts", "education", "administration", "management", "integrated", "communication"):
        t = re.sub(r"\b" + fz(w) + r"\b", w, t, flags=re.I)
    return t


def _rejoin(t, vocab):
    """'Li Brary and Information Studies' -> 'Library and Information Studies' when 'library' occurs intact more
    often (vocab: word counts) than the rarer of its two fragments."""
    toks = t.split()
    out = []
    i = 0
    while i < len(toks):
        if i + 1 < len(toks):
            a, b = toks[i], toks[i + 1]
            merged = (a + b).lower()
            if a.isalpha() and b.isalpha() and vocab.get(merged, 0) > min(vocab.get(a.lower(), 0), vocab.get(b.lower(), 0)):
                out.append(a + b.lower())
                i += 2
                continue
        out.append(toks[i])
        i += 1
    return " ".join(out)


def _tidy(t):
    t = re.sub(r"\s*\([A-Z]{2,10}\)", "", t)          # "(IWRM)"
    t = re.sub(r"(\s+[A-Za-z])+$", "", t.strip())      # stray trailing letters
    return t.strip(" ,.;-")


def _degree(stmt):
    """'Master of Science in Computer Science at the University ...' -> ('Master of Science in Computer Science',
    'Computer Science', 'Masters'); also 'Masters in X', 'Postgraduate Diploma in X', 'Master of Science (Physics)'."""
    stmt = _tidy(STOP.sub("", _unsplit(re.sub(r"\s+", " ", stmt)).strip(" ,.;-")))
    stmt = re.sub(r"(?i)\s+degree\b|\s+\(?m\.?\s?sc\.?\)?(?=\s+in\b)", "", stmt)  # "... Degree in", "Science Msc in" 
    stmt = re.sub(r"\s*\(\s*([A-Za-z][A-Za-z ,&'\-]+)\s*\)\s*$", r" in \1", stmt)  # "(Physics)" -> "in Physics"
    m = re.match(r"(?i)^(master|doctor|bachelor)(?:'?s)?\s+in\s+(.+)$", stmt)
    pg = re.match(r"(?i)^post-?\s?graduate\s+diploma\s+(?:in|of)\s+(.+)$", stmt)
    if pg:
        disc = crosswalk._tc(pg.group(1))
        return "Postgraduate Diploma in " + disc, disc, "Postgraduate Diploma"
    if m:
        disc = crosswalk._tc(m.group(2))
        head = m.group(1).capitalize()
        deg = {"Master": "Master's", "Bachelor": "Bachelor's"}.get(head, "Doctorate") + " in " + disc
        return deg, disc, crosswalk.degree_level([head])
    deg, disc = crosswalk.degree_from_text(stmt)
    if not deg:
        return None, None, None
    return deg + (" in " + disc if disc else ""), disc, crosswalk.degree_level([deg])


def _clean_person(p):
    p = re.sub(r"\s+", " ", p).strip(" .,")
    p = re.sub(r"-\s+", "-", p)
    p = re.sub(r"^" + TITLE_WORDS + r"\s*(?=[A-Z])", "", p)
    if p.isupper() and len(p) > 4:
        p = " ".join(w if re.fullmatch(r"(?:[A-Z]\.)+", w) else w.capitalize() for w in p.split())
    return p.strip(" .,")


from collections import Counter

CORPUS_VOCAB = Counter()


def prepare(texts):
    """Called once per run with every cached text: word counts across the corpus, used to rejoin words that text
    extraction split ("Eco nomics")."""
    CORPUS_VOCAB.clear()
    for t in texts:
        CORPUS_VOCAB.update(w.lower() for w in re.findall(r"[A-Za-z]{2,}", t or ""))


def predict(meta, text):
    pages = [_flat(p) for p in text.split("\f")]
    vocab = CORPUS_VOCAB + Counter(w.lower() for w in re.findall(r"[A-Za-z]{2,}", " ".join(pages)))
    head = " ".join(pages[:3])
    allt = " ".join(pages)
    out = {}

    # degree statement, then any degree name, then abbreviations
    for rx, conf, scope in ((STATEMENT, 0.96, allt), (DEG_ANY, 0.82, head)):
        m = rx.search(scope)
        if m:
            deg, disc, level = _degree(_rejoin(m.group(1), vocab))
            if deg and level:
                ev = scope[max(0, m.start() - 60): m.end() + 20]
                out["degree"] = ([deg], conf, ev)
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
            for name in re.split(r"\s*(?:,|\band\b|&)\s*", m.group(1)):
                name = _clean_person(name)
                cut = NOT_NAMES.search(name)
                if cut:
                    name = name[:cut.start()].strip(" .,")
                if len(name.replace(".", ". ").split()) < 2 or len(name) < 5 or name in sups:
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
