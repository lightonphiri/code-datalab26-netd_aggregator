# OpenAlex field-of-study classifier: held-out evaluation

Training works: 23384; held-out works: 4127; subfields: 252; C=10.0

| Measure | Value |
|---|---|
| Subfield top-1 accuracy | 0.530 |
| Subfield top-3 accuracy | 0.753 |
| Field accuracy (from top subfield) | 0.707 |
| Domain accuracy (from top subfield) | 0.852 |

Back-off (thresholds subfield 0.40, field 0.50):

| Level assigned | Share of works | Precision at that level |
|---|---|---|
| subfield | 63.3% | 0.686 |
| field | 15.5% | 0.718 |
| domain | 21.2% | 0.719 |

## Threshold tuning (November 1, 2026; model version 2, same weights)

Held-out works, C = 10 (C = 50 and 200 lowered top-1 accuracy to 0.498 and 0.475):

| Subfield ≥ | Field ≥ | Subfield share / precision | Field share / precision | Domain only |
|---|---|---|---|---|
| 0.40 | 0.50 | 63% / 0.686 | 15% / 0.718 | 21% |
| 0.35 | 0.40 | 70% / 0.656 | 19% / 0.648 | 11% |
| **0.30** | **0.40** | **78% / 0.622** | **13% / 0.630** | **10%** (chosen) |
| 0.25 | 0.40 | 85% / 0.591 | 7% / 0.611 | 7% |
| 0.20 | 0.40 | 91% / 0.567 | 3% / 0.556 | 5% |

## Label-shift adaptation (version 3, withdrawn the same day)

`tools/fos_priors.py` re-estimated subfield priors on the portal's 5,921 records with EM (Saerens, Latinne & Decaestecker 2002, https://doi.org/10.1162/089976602753284446; smoothing 0.1). Estimated most common subfields: Political Science and International Relations 0.126, Education 0.100, Safety Research 0.093, General Health Professions 0.077. Applied to the portal, Education rose from 231 to 847 records, but Safety Research rose to 627 and Political Science to 923, which is implausible for Zambian theses: EM assumes pure label shift, while theses also differ from journal papers in style (concept shift), so the classifier's systematic confusions were amplified. Version 4 returns to version 2 behaviour. Next: in-domain labels (discipline names mapped to subfields, an annotated sample of portal records) to retrain or calibrate.
