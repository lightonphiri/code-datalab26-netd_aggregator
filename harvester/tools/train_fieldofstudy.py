"""Train the OpenAlex field-of-study classifier (SRS FR-54, FR-57).

  python tools/train_fieldofstudy.py DATA_DIR OUT_NPZ [--report REPORT.md]

DATA_DIR holds taxonomy.json and works.jsonl from tools/openalex_training.py. Embeds title + abstract with
sentence-transformers/all-MiniLM-L6-v2 (fastembed, CPU), trains a multinomial logistic regression over subfields on 85% of the works
(stratified), and reports on the other 15%: subfield top-1/top-3 accuracy, field and domain accuracy, and precision
and coverage of the hierarchical back-off used by netd/ml/models/fieldofstudy.py. Saves W, b and classes (npz).
"""
import argparse
import json
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("data")
    p.add_argument("out")
    p.add_argument("--report")
    p.add_argument("--C", type=float, default=10.0)
    p.add_argument("--per-subfield", type=int, default=80)
    p.add_argument("--cache", default=os.environ.get("NETD_MODELS", "models"))
    a = p.parse_args()
    from fastembed import TextEmbedding
    from sklearn.linear_model import LogisticRegression
    from sklearn.model_selection import train_test_split

    tax = json.load(open(os.path.join(a.data, "taxonomy.json")))
    sub = {s["id"]: s for s in tax["subfields"]}
    works = [json.loads(line) for line in open(os.path.join(a.data, "works.jsonl"))]
    works = [w for w in works if w["subfield"] in sub]
    per = {}
    works = [w for w in works if per.setdefault(w["subfield"], []).append(1) or len(per[w["subfield"]]) <= a.per_subfield]
    from netd.ml.models.fieldofstudy import MAX_CHARS
    texts = [(w["title"] + ". " + w["abstract"])[:MAX_CHARS] for w in works]
    y = np.array([w["subfield"] for w in works])
    t = time.time()
    emb = TextEmbedding("sentence-transformers/all-MiniLM-L6-v2", cache_dir=os.path.join(a.cache, "fastembed"), threads=os.cpu_count())
    cached = os.path.join(a.data, "embeddings-%d.npy" % len(texts))  # reuse when only the classifier changes
    if os.path.exists(cached):
        X = np.load(cached)
    else:
        X = np.array(list(emb.embed(texts, batch_size=32)), dtype=np.float32)
        np.save(cached, X)
    X /= np.linalg.norm(X, axis=1, keepdims=True) + 1e-9
    print("embedded %d works in %.0f s" % (len(X), time.time() - t), flush=True)

    Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.15, random_state=2026, stratify=y)
    clf = LogisticRegression(C=a.C, max_iter=2000)
    clf.fit(Xtr, ytr)
    classes = list(clf.classes_)
    P = clf.predict_proba(Xte)
    order = np.argsort(-P, axis=1)
    top1 = np.array([classes[i] for i in order[:, 0]])
    lines = ["# OpenAlex field-of-study classifier: held-out evaluation", "",
             "Training works: %d; held-out works: %d; subfields: %d; C=%s" % (len(Xtr), len(Xte), len(classes), a.C), ""]
    f_of = lambda s: sub[s]["field"]
    d_of = lambda s: sub[s]["domain"]
    acc1 = float(np.mean(top1 == yte))
    acc3 = float(np.mean([yte[i] in [classes[j] for j in order[i, :3]] for i in range(len(yte))]))
    accf = float(np.mean([f_of(a_) == f_of(b_) for a_, b_ in zip(top1, yte)]))
    accd = float(np.mean([d_of(a_) == d_of(b_) for a_, b_ in zip(top1, yte)]))
    lines += ["| Measure | Value |", "|---|---|",
              "| Subfield top-1 accuracy | %.3f |" % acc1, "| Subfield top-3 accuracy | %.3f |" % acc3,
              "| Field accuracy (from top subfield) | %.3f |" % accf, "| Domain accuracy (from top subfield) | %.3f |" % accd, ""]
    # hierarchical back-off as used in production
    from netd.ml.models import fieldofstudy as fos
    fos._state["tax"] = {x["id"]: dict(x, level=k[:-1]) for k in ("domains", "fields", "subfields") for x in tax[k]}
    lv = {"subfield": [0, 0], "field": [0, 0], "domain": [0, 0]}
    for i in range(len(yte)):
        ids, conf, _ = fos.decide(P[i], classes)
        level = ids[0].split("/")[0][:-1]
        truth = {"subfield": yte[i], "field": f_of(yte[i]), "domain": d_of(yte[i])}[level]
        lv[level][0] += 1
        lv[level][1] += ids[0] == truth
    lines += ["Back-off (thresholds subfield %.2f, field %.2f):" % (fos.SUBFIELD_MIN, fos.FIELD_MIN), "",
              "| Level assigned | Share of works | Precision at that level |", "|---|---|---|"]
    for k, (n, ok) in lv.items():
        lines.append("| %s | %.1f%% | %.3f |" % (k, 100.0 * n / len(yte), ok / n if n else 0.0))
    report = "\n".join(lines) + "\n"
    print(report)
    if a.report:
        open(a.report, "w").write(report)
    np.savez_compressed(a.out, W=clf.coef_.astype(np.float32), b=clf.intercept_.astype(np.float32),
                        classes=np.array(classes))
    print("saved", a.out)


if __name__ == "__main__":
    main()
