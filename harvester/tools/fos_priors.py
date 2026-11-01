"""Estimate how common each OpenAlex subfield is in the portal (label-shift adaptation, SRS FR-57).

  python tools/fos_priors.py [--db netd.sqlite3] [--iterations 50] [--smoothing 0.1]

The field-of-study classifier is trained with about the same number of works per subfield, i.e. a uniform prior,
whereas Zambian theses are dominated by a few subfields (education, public health, ...). Following Saerens,
Latinne & Decaestecker (2002, Neural Computation 14(1), https://doi.org/10.1162/089976602753284446), the EM
algorithm re-estimates the subfield priors from the classifier's unadapted probabilities on the portal's own,
unlabelled records; predictions then use P(c|x) * pi_portal(c) / pi_train(c). The priors are mixed with a uniform
prior (--smoothing) so that no subfield becomes impossible. Writes netd/ml/models/data/openalex-fos-priors.json.
"""
import argparse
import json
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    from netd.ml.models import fieldofstudy as fos
    from netd.ml.predict import harvested_view
    from netd.store import Store
    p = argparse.ArgumentParser()
    p.add_argument("--db", default=os.environ.get("NETD_DB", "netd.sqlite3"))
    p.add_argument("--iterations", type=int, default=50)
    p.add_argument("--smoothing", type=float, default=0.1)
    a = p.parse_args()
    store = Store(a.db)
    metas = [harvested_view(r, fos.USES) for r in store.records()]
    t = time.time()
    keep, P = fos.probabilities(metas, adapt=False)
    (_, _, classes), _ = fos._load()
    k = len(classes)
    pi = np.full(k, 1.0 / k)
    for _ in range(a.iterations):  # EM (Saerens et al. 2002), training prior uniform
        Q = P * (pi * k)
        Q /= Q.sum(axis=1, keepdims=True)
        new = Q.mean(axis=0)
        if np.abs(new - pi).max() < 1e-6:
            pi = new
            break
        pi = new
    pi = (1 - a.smoothing) * pi + a.smoothing / k
    tax = fos.taxonomy()
    top = np.argsort(-pi)[:15]
    print("records: %d (%.0f s); most common subfields in the portal:" % (len(keep), time.time() - t))
    for i in top:
        print("  %.3f  %s" % (pi[i], tax[classes[i]]["name"]))
    out = {"method": "EM label-shift adaptation (Saerens, Latinne & Decaestecker 2002)", "records": len(keep),
           "smoothing": a.smoothing, "estimated": time.strftime("%Y-%m-%d"),
           "priors": {c: float(x) for c, x in zip(classes, pi)}}
    with open(fos.PRIORS, "w") as fh:
        json.dump(out, fh, indent=0)
    print("wrote", fos.PRIORS)


if __name__ == "__main__":
    main()
