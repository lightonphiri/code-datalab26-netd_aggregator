"""Metadata filling (SRS FR-14, FR-48 to FR-52).

Model outputs are never written straight into records. They go into a prediction cache (table `predictions`),
keyed by record, field and model, together with the confidence and a hash of the model's input, so a model only
runs again for records whose input changed. When records are processed, `overlay.apply` fills empty fields from
the cache (above a confidence threshold, marked as derived) and then applies manual corrections from the admin
panel, which override both harvested and predicted values and survive re-harvests.

  textcache  first pages of each record's PDF, as text (table `pdf_text`)
  cache      predictions, corrections and level-review decisions
  overlay    applies predictions and corrections to a canonical record during `netd.cli process`
  models/    the models themselves; each exposes NAME, VERSION and predict(record, text) -> {field: (value, conf)}
  evaluate   gold-standard sample export and precision/recall/F1 per field
"""
