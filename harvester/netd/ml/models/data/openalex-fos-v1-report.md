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
