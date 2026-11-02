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
VERSION = "10"
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
ABBREV = [  # case-sensitive: "bed space" must not read as B.Ed
    (re.compile(r"\b(?:Ph\.?\s?D|PHD|D\.?\s?Phil)\b"), "Doctoral", "Doctor of Philosophy"),
    (re.compile(r"\b(?:M\.?\s?Sc|MSC|M\.\s?Ed|M\.?\s?Phil|MBA|MPH|MMed|LL\.?M|MLIS)\b"), "Masters", None),
    (re.compile(r"\b(?:PGD|PG\.?\s?Dip)\b"), "Postgraduate Diploma", None),
    (re.compile(r"\b(?:B\.?\s?Sc|BSC|LL\.?B|B\.\s?Ed)\b"), "Bachelors", None),
]
STOP = re.compile(r"\s+(?:in\s+(?:the\s+)?(?:school|faculty|department|institute|college|multidisciplinary)|has|have|or|"
                  r"for any|chairperson|signature|computer|student|candidate|examiner|name|date|declaration|"
                  r"supervisors?|notice|copy\s?w?right|word|abstract|dedication|approval|about|i|ii|iii|iv|unza|zambia|"
                  r"dr|prof|mr|mrs|ms|at|of the|from|to|by|submitted|presented|in the|lusaka|zambia|university|copyright|"
                  r"school|faculty|department|institute|college|supervisor|the)\b.*$", re.I)

TITLE_WORDS = r"(?i:prof(?:essor)?s?|d\s?rs?|mrs|mr|ms|miss|rev|eng|assoc\.?\s+prof)(?:\s?\.)?"   # "Dr ." too
# a name part: a word, initials with dots ("K.", "W.W", "K.M"), or a bare initial before another part ("W Chakanika")
TOKEN = r"(?:[A-Z][a-zA-Z'\-]+|(?:[A-Z]\.){1,4}(?:[A-Z]\b)?|[A-Z]\b(?=\s*[A-Z][a-zA-Z'\-]))"
PERSON = r"((?:" + TITLE_WORDS + r"\s*)?" + TOKEN + r"(?:\s*" + TOKEN + r"){1,4})"
PEOPLE = PERSON[:-1] + r"(?:\s*(?:,|\b(?i:and)\b|&)\s*(?:" + TITLE_WORDS + r"\s*)?" + TOKEN + r"(?:\s*" + TOKEN + r"){1,4})?)"
_P = r"(?:" + TITLE_WORDS + r"\s*)?" + TOKEN + r"(?:\s*" + TOKEN + r"){1,4}"
PEOPLE3 = r"(" + _P + r"(?:\s*(?:,|\b(?i:and)\b|&)?\s*" + _P + r"){0,3})"   # up to four people
# "my supervisor", "my Research Supervisor", "my exemplary supervisor", "my very able supervisors"
MY_SUP = (r"\b(?i:my)\s+(?:(?:[a-z\-]+|(?i:study|research|main|principal|academic|dissertation|thesis))\s+){0,2}"
          r"(?i:(?:co-?\s?)?supervisors?)\b")
SUPERVISED = (r",?\s+(?i:for\s+(?:(?:his|her|their)\s+)?(?:[a-z\-]+\s+){0,2}(?:supervision|supervising)\b|"
              r"for\s+accepting\s+to\s+supervise|who\s+supervised)")
SUPERVISOR = [
    (re.compile(r"\b(?i:(?:main\s+|principal\s+|co-?\s?)?supervisors?)\s*[:\-–]\s*" + PEOPLE3), 0.92),
    (re.compile(r"\b(?i:supervisors?)\s+(?=" + TITLE_WORDS + r"\s*[A-Z])" + PEOPLE3), 0.9),  # "SUPERVISOR DR.D. BANDA"
    (re.compile(r"\b(?i:supervised\s+by)\s*[:\-–]?\s*" + PEOPLE3), 0.9),
    (re.compile(r"\b(?i:under\s+the\s+(?:able\s+)?(?:supervision|guidance)\s+of)\s+" + PEOPLE3), 0.88),
    (re.compile(MY_SUP + r"(?:\s+(?i:and\s+mentors?))?\s*[,;:]?\s*(?:(?i:namely)\s*,?\s*)?" + PEOPLE3), 0.86),     # acknowledgements: "my supervisor, Dr X, for ..."
    (re.compile(PERSON + r"\s*,?\s+" + MY_SUP), 0.82),      # "... Prof. X, my supervisor, for ..." ("X , my")
    (re.compile(PERSON + SUPERVISED), 0.8),                  # "Dr X for his able supervision"
    (re.compile(PERSON + r"\s*\(?\s*(?i:(?:main|principal|co)?\s?-?\s?supervisor)\)?\b"), 0.75),
]
CUE = re.compile(r"(?i)supervis")
NOT_NAMES = re.compile(r"\b(word|count|abstract|page|chapter|copyright|unza|zou|cbu|unilus|zcas|mu|zambia|supervisors?|co|visiting|senior|head|who|whose|for|from|signature|signed|date|name|department|university|school|examiner|candidate|dean|"
                       r"declaration|approval|head|chairperson|lecturer|the|of|sign|a?dissertation|thesis|submitted|report|research|"
                       r"project|in|on|to|by|at|is|was|has|public|health|surgery|medicine|ethics|applied|open|studies|science|sciences|"
                       r"education|programme|mmed|bchb|mbchb)\b", re.I)
UNIT = re.compile(r"\b(department|school|faculty|institute|college)\s+of\s+(?=[A-Z])", re.I)
UNIT_STOP = re.compile(r"\s*(?:,(?!\s*[A-Za-z]+(?:\s+[A-Za-z]+)?\s+(?i:and)\s)|\.|;|:|\(|\bat\b|\bthe\b|\buniversity\b|\blusaka\b|\bzambia\b|\bin\s+partial\b|"
                       r"\bsubmitted\b|\bpresented\b|\bdepartment\b|\bschool\b|\bfaculty\b|\binstitute\b|"
                       r"\bcollege\b|\b(?:a|this)\s+(?:dissertation|thesis|report)\b|\bdissertation\b|\bthesis\b|"
                       r"\bby\b|\b(?:19|20)\d\d\b).*$", re.I)


def _flat(page):
    page = page.replace("\u2019", "'").replace("\u2018", "'").replace("/g3", " ")
    page = re.sub(r"(?<=[A-Za-z])\s+-\s*(?=[A-Z])", "-", page)   # "Chama -Chiliba" -> "Chama-Chiliba"
    return re.sub(r"\s+", " ", page.replace("-\n", "")).strip()


def _unsplit(t):
    """Join words split by stray spaces in the degree statement, using the words that matter here."""
    for w in ("master", "masters", "doctor", "bachelor", "postgraduate", "graduate", "diploma", "philosophy",
              "science", "arts", "education", "administration", "management", "integrated", "communication"):
        t = re.sub(r"\b" + fz(w) + r"\b", w, t, flags=re.I)
    return t


def _rejoin(t, vocab, names=False):
    """'Li Brary and Information Studies' -> 'Library and Information Studies' when 'library' occurs intact more
    often (vocab: word counts) than the rarer of its two fragments. names=True (supervisor text, v10): one-letter
    fragments are never joined; they are not counted in vocab (count 0), so any glued form would win ("BANDA A" became
    "BANDAa", "MS G" "MSg"). Degree statements keep joining them ("E ducation")."""
    toks = t.split()
    out = []
    i = 0
    while i < len(toks):
        if i + 1 < len(toks):
            a, b = toks[i], toks[i + 1]
            merged = (a + b).lower()
            if a.isalpha() and b.isalpha() and (not names or (len(a) > 1 and len(b) > 1)) and vocab.get(merged, 0) > min(vocab.get(a.lower(), 0), vocab.get(b.lower(), 0)):
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
        return "Postgraduate Diploma", disc, "Postgraduate Diploma"
    if m:
        disc = crosswalk._tc(m.group(2))
        head = m.group(1).capitalize()
        deg = {"Master": "Master's", "Bachelor": "Bachelor's"}.get(head, "Doctorate")
        return deg, disc, crosswalk.degree_level([head])
    deg, disc = crosswalk.degree_from_text(stmt)
    if not deg:
        return None, None, None
    return deg, disc, crosswalk.degree_level([deg])  # ETD-MS: degree name and discipline are separate


DEGREES = re.compile(r"(?:\s+|,\s*)(?:MBBS|MBChB|MD|PhD|Ph\.D|MSc|BSc|MA|BA|MPH|FRSH|FRCS|FCS|MMed|DPhil)\b.*$")


def _good_name(n):
    """At least two parts; the surname (last part) a whole word of 4+ letters, not a fragment of a split word."""
    parts = n.replace(".", ". ").split()
    return len(parts) >= 2 and len(parts[-1]) >= 4 and parts[-1][0].isupper() and not parts[-1].endswith(".")


def _clean_person(p):
    p = re.sub(r"\s+", " ", p).strip(" .,")
    p = DEGREES.sub("", p)
    p = re.sub(r"-\s+", "-", p)
    p = re.sub(r"\b([A-Za-z]{2,})\.", r"\1", p)       # "AUSTIN. CHEYEKA" -> "AUSTIN CHEYEKA" (initials keep their dots)
    p = re.sub(r"^" + TITLE_WORDS + r"\s*(?=[A-Z])", "", p)
    p = re.sub(r"\s+[A-Z]$", "", p)
    if p.isupper() and len(p) > 4:
        p = " ".join(w if re.fullmatch(r"(?:[A-Z]\.)+", w) else w.capitalize() for w in p.split())
    return p.strip(" .,-")


from collections import Counter

CORPUS_VOCAB = Counter()


class _Counts:
    """Corpus counts plus this document's counts, without copying the corpus table for every record."""
    def __init__(self, corpus, doc):
        self.corpus, self.doc = corpus, doc

    def get(self, w, default=0):
        return self.corpus.get(w, 0) + self.doc.get(w, 0) or default


def prepare(texts):
    """Called once per run with every cached text: word counts across the corpus, used to rejoin words that text
    extraction split ("Eco nomics")."""
    CORPUS_VOCAB.clear()
    for t in texts:
        CORPUS_VOCAB.update(w.lower() for w in re.findall(r"[A-Za-z]{2,}", t or ""))


def predict(meta, text):
    pages = [_flat(p) for p in text.split("\f")]
    vocab = _Counts(CORPUS_VOCAB, Counter(w.lower() for w in re.findall(r"[A-Za-z]{2,}", " ".join(pages))))
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
                    long_ = len(disc.split()) > 8  # probably ran into the next line: keep, but do not display
                    out["discipline"] = ([disc], 0.7 if long_ else conf - 0.05, ev)
                    if long_:
                        out["degree"] = (out["degree"][0], 0.7, ev)
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
    sup_text = re.sub(r"(?<=[A-Za-z])\s?['\u201b\u201f`]\s?(?=[a-z]{2})", "'", allt)  # "Hang ’ombe", "Ng‟andu"
    sup_text = _rejoin(sup_text, vocab, names=True)  # "Wanga W. Chakan ika" -> "Wanga W. Chakanika"
    cues = [c.start() for c in CUE.finditer(sup_text)]
    for rx, conf in SUPERVISOR:
        if rx.pattern.startswith(PERSON):   # name first: try only just before a cue (unbounded, it backtracked
            spans, found = set(), []          # for 17-29 s on one OCRed list of acronyms; v10)
            for c in cues:
                pos = max(0, c - 120)
                while True:
                    m = rx.search(sup_text, pos, c + 60)
                    if not m:
                        break
                    if m.span() not in spans:
                        spans.add(m.span())
                        found.append(m)
                    pos = m.end()
            found.sort(key=lambda m: m.start())
        else:
            found = rx.finditer(sup_text)
        for m in found:
            # several people: separated by commas, "and", "&", or a title in the middle ("X Y Dr Z W")
            for name in re.split(r"\s*(?:,|;|\b(?i:and)\b|&)\s*|\s+(?=(?i:prof(?:essor)?|d\s?r|mrs|mr|ms)\.?\s+[A-Z])", m.group(1)):
                name = _clean_person(name)
                cut = NOT_NAMES.search(name)
                if cut:
                    name = re.sub(r"\s+[A-Z]$", "", name[:cut.start()].strip(" .,"))
                if not _good_name(name) or name in sups:
                    continue
                sur = name.split()[-1].lower()
                same = [x for x in sups if x.split()[-1].lower() == sur]
                if same:  # "Gibson Sijumbila" and "G. Sijumbila": keep the fuller form
                    if len(name) > len(same[0]):
                        sups[sups.index(same[0])] = name
                    continue
                sups.append(name)
                if conf > best:
                    best, ev = conf, sup_text[max(0, m.start() - 20): m.end() + 20]
        if sups:
            break
    if sups:
        sups = [" ".join(w if re.fullmatch(r"(?:[A-Z]\.)+", w) else w.capitalize() for w in n.split())
                if n.isupper() else n for n in sups]
        out["supervisor"] = (sups[:3], best, ev)

    # units: one title-page line each ("SCHOOL OF MEDICINE" / "DEPARTMENT OF PUBLIC HEALTH"), so the thesis
    # title on the next line does not run into the name
    lines = [re.sub(r"\s+", " ", ln).strip() for p in text.split("\f")[:3] for ln in p.split("\n")]
    first = len(text.split("\f")[0].split("\n"))
    for kind, field in (("department", "department"), ("school", "faculty"), ("faculty", "faculty")):
        if field in out:
            continue
        for i, ln in enumerate(lines):
            m = UNIT.match(ln.replace("\u2019", "'"))  # title-page lines start with the unit; body text does not
            if not m or m.group(1).lower() != kind or len(ln) > 80:
                continue
            name = UNIT_STOP.sub("", ln[m.end(): m.end() + 90]).strip(" )(,.;:")
            if re.search(r"\b(and|of|&|in|for|the)$", name, re.I):
                continue  # name cut off by a line break
            if re.search(r"\b(?:post)?\s?graduate studies\b|\bresearch and graduate\b", name, re.I):
                continue  # a directorate of graduate studies, not the candidate's faculty
            if 3 <= len(name) <= 70 and not re.search(r"\d", name):
                unit = "%s of %s" % (kind.capitalize(), crosswalk._tc(_rejoin(name, vocab)))
                out[field] = ([unit], 0.88 if i < first else 0.78, ln[:160])
                break
    return out
