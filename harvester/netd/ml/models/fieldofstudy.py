"""Field of study from OpenAlex Topics (SRS FR-54 to FR-57).

Every record gets standard fields of study from the OpenAlex topic taxonomy (CC0; 4 domains, 26 fields, 252
subfields), whatever its repository's own subject headings say. Title and abstract are embedded with a small
sentence-embedding model (sentence-transformers/all-MiniLM-L6-v2 through fastembed/ONNX, CPU only) and classified by a multinomial
logistic regression over the 252 subfields, trained on OpenAlex works labelled with their primary topic's subfield
(tools/openalex_training.py, tools/train_fieldofstudy.py).

Hierarchical back-off, so no record is left without a value:
  subfield  if its probability >= SUBFIELD_MIN (a second subfield is added if >= SECOND_MIN)
  field     otherwise, if the summed probability of its subfields >= FIELD_MIN
  domain    otherwise (always)
Values are OpenAlex ids ("subfields/2739", "fields/27", "domains/4"); names come from the taxonomy file.
"""
import json
import os

import numpy as np

NAME = "openalex-fos"
VERSION = "3"  # v2: thresholds tuned on held-out works; v3: subfield priors adapted to the portal (label shift)
FIELDS = ("field_of_study",)
USES = ("title", "abstract")
NEEDS_TEXT = False

HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
TAXONOMY = os.path.join(HERE, "openalex-taxonomy.json")
WEIGHTS = os.path.join(HERE, "openalex-fos-v1.npz")
PRIORS = os.path.join(HERE, "openalex-fos-priors.json")  # tools/fos_priors.py: subfield frequencies in the portal
EMBEDDER = "sentence-transformers/all-MiniLM-L6-v2"
# harvester/models (downloaded embedding model; not in git)
CACHE = os.environ.get("NETD_MODELS", os.path.join(HERE, "..", "..", "..", "..", "models"))
SUBFIELD_MIN, SECOND_MIN, FIELD_MIN = 0.30, 0.30, 0.40
MAX_CHARS = 1000  # title + start of the abstract: most of the topical signal, and fast on CPU

_state = {}


def taxonomy():
    if "tax" not in _state:
        with open(TAXONOMY) as fh:
            t = json.load(fh)
        _state["tax"] = {x["id"]: dict(x, level=k[:-1]) for k in ("domains", "fields", "subfields") for x in t[k]}
    return _state["tax"]


def text_of(meta):
    title = " ".join(meta.get("title") or [])
    abstract = " ".join(meta.get("abstract") or [])
    return (title + ". " + abstract)[:MAX_CHARS].strip(". ")


def _load():
    if "clf" not in _state:
        from fastembed import TextEmbedding
        w = np.load(WEIGHTS, allow_pickle=False)
        classes = [str(c) for c in w["classes"]]
        prior = np.ones(len(classes))
        if os.path.exists(PRIORS):  # label-shift adaptation: P(c|x) * pi_portal(c) / pi_train(c), training uniform
            pri = json.load(open(PRIORS))["priors"]
            prior = np.array([pri.get(c, 1.0 / len(classes)) for c in classes]) * len(classes)
        _state["clf"] = (w["W"], w["b"], classes)
        _state["prior"] = prior
        _state["emb"] = TextEmbedding(EMBEDDER, cache_dir=os.path.join(CACHE, "fastembed"), threads=2)
    return _state["clf"], _state["emb"]


def decide(p, classes):
    """Probabilities over subfields -> (ids, confidence, evidence) with back-off to field and domain."""
    tax = taxonomy()
    order = np.argsort(-p)
    top, second = order[0], order[1]
    if p[top] >= SUBFIELD_MIN:
        ids = [classes[top]] + ([classes[second]] if p[second] >= SECOND_MIN else [])
        return ids, float(p[top]), "subfield p=%.2f" % p[top]
    fields, domains = {}, {}
    for c, pc in zip(classes, p):
        fields[tax[c]["field"]] = fields.get(tax[c]["field"], 0.0) + float(pc)
        domains[tax[c]["domain"]] = domains.get(tax[c]["domain"], 0.0) + float(pc)
    f, pf = max(fields.items(), key=lambda kv: kv[1])
    if pf >= FIELD_MIN:
        return [f], pf, "field p=%.2f (best subfield %s p=%.2f)" % (pf, classes[top], p[top])
    d, pd = max(domains.items(), key=lambda kv: kv[1])
    return [d], pd, "domain p=%.2f (best field %s p=%.2f)" % (pd, f, pf)


def probabilities(metas, adapt=True):
    """(rows kept, P) for records with enough text; P adapted to portal priors unless adapt=False."""
    (W, b, classes), emb = _load()
    docs = [text_of(m) for m in metas]
    keep = [i for i, d in enumerate(docs) if len(d) > 20]
    if not keep:
        return keep, np.zeros((0, len(classes)))
    X = np.array(list(emb.embed([docs[i] for i in keep], batch_size=32)), dtype=np.float32)
    X /= np.linalg.norm(X, axis=1, keepdims=True) + 1e-9
    z = X @ W.T + b
    z -= z.max(axis=1, keepdims=True)
    P = np.exp(z)
    P /= P.sum(axis=1, keepdims=True)
    if adapt:
        P = P * _state["prior"]
        P /= P.sum(axis=1, keepdims=True)
    return keep, P


def predict_batch(metas, texts=None):
    (_, _, classes), _ = _load()
    out = [{} for _ in metas]
    keep, P = probabilities(metas)
    for row, i in enumerate(keep):
        ids, conf, ev = decide(P[row], classes)
        out[i] = {"field_of_study": (ids, round(conf, 3), ev)}
    return out


def predict(meta, text=None):
    return predict_batch([meta])[0]
