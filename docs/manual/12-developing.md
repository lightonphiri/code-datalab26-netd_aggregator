# 12. Developing and contributing

## 12.1 Local set-up

You need Python 3.12 (with `uv` or `venv`), Ruby 3.3 with Bundler, Java 11 or later, and a Solr 9 core made from `solr/netd/conf`.

**Solr:**

```bash
curl -fsSLO https://dlcdn.apache.org/solr/solr/9.11.0/solr-9.11.0-slim.tgz && tar xzf solr-9.11.0-slim.tgz
mkdir -p solr-home/netd && cp solr-9.11.0-slim/server/solr/solr.xml solr-home/
cp -r solr/netd/conf solr-home/netd/conf && echo "name=netd" > solr-home/netd/core.properties
solr-9.11.0-slim/bin/solr start -p 8983 -s "$PWD/solr-home"
```

**Harvester** (a small sample from one repository):

```bash
cd harvester
uv venv --python 3.12 .venv && uv pip install --python .venv/bin/python -r requirements.txt
.venv/bin/python -m netd.cli harvest --source unza --full --limit 50
.venv/bin/python -m netd.cli process
.venv/bin/python -m netd.cli report
NETD_SOLR=http://127.0.0.1:8983/solr/netd .venv/bin/python -m netd.cli index
```

**Portal:**

```bash
cd portal
bundle install
bin/rails db:prepare
SOLR_URL=http://127.0.0.1:8983/solr/netd bin/rails server     # http://127.0.0.1:3000
```

Create an admin account for local work with the rake task behind `deploy/ops/netd-user.sh` (`portal/lib/tasks/netd_users.rake`).

## 12.2 Tests

| Test | Run | Checks |
|---|---|---|
| `tests/test_people.py` | `python3 -I tests/test_people.py` | supervisor name merging (FR-64) |
| `tests/oai_conformance.py` | `python tests/oai_conformance.py [BASE_URL]` | the OAI-PMH provider against the schemas, every verb and error (about five minutes on 5,000 records) |
| `tests/api_conformance.py` | `python tests/api_conformance.py [BASE]` | every REST API endpoint against the OpenAPI specification |
| `netd.cli evaluate` | see [chapter 9](09-metadata-filling.md) | model quality on a gold standard |
| `netd.cli check` | on any installation | sources fresh, index in step with the store, OAI-PMH answering |

When testing a live installation, add `check` to the user agent (for example `Mozilla/5.0 (X11; Linux x86_64) Firefox/140.0 netd-check`) so that test requests are not counted as usage.

## 12.3 How changes are made

1. **Requirements first.** Every feature or behaviour change updates `docs/SRS.md` (a requirement with an identifier, and the revision history) and `docs/SDD.md` (the design and the revision history) in the same change. Both are published in this site under Reference ([requirements](reference/srs.md), [design](reference/sdd.md)) each time it is built.
2. **Data changes are dry-run** on a copy of the store before they reach the live one; model changes are tuned on the dev half of the gold standard and reported on the test half.
3. **Small releases.** Each release is one commit (or a few) that can be deployed and checked on its own.
4. **Changelog and tags.** Add the change under `[Unreleased]` in `CHANGELOG.md`. A release moves those entries under a new version heading and gets an annotated tag `vX.Y.Z` on its commit (Semantic Versioning: a new feature raises Y, a fix raises Z). Commit dates and published tags are never rewritten.
5. **Documentation.** User-visible changes update this manual; installation-specific operations go in the installation's own runbook (for Zambia, `docs/OPERATIONS.md`).

## 12.4 Conventions

- **Provenance on every value.** Code that sets or changes a field records how (`record["provenance"][field]`) and, when derived, how sure (`record["confidence"][field]`). Never overwrite harvested data in the raw layer.
- **Models see harvested values only** and carry a `VERSION` that changes whenever their output can change.
- **Store access:** the SQLite store is in WAL mode; read everything you need first, then write (never keep a read cursor open while writing in the same connection); only the `netd` user opens it.
- **No new services** without a strong reason: the design fits a shared server with 4 GB of memory.
- **Interfaces are contracts:** REST API v1 fields are only added; OAI-PMH output follows the schemas (run the conformance tests).
- **Language and dates:** British English in code comments, documents and the interface; dates written as "January 3, 2027".
- **Privacy:** usage counting keeps no IP addresses, browser details or search words; keep it that way.

## 12.5 Contributing

Issues and pull requests are welcome on GitHub: https://github.com/lightonphiri/code-datalab26-netd_aggregator. Describe the problem or the change, the requirement it affects, and how you tested it. The rules are also in [`CONTRIBUTING.md`](https://github.com/lightonphiri/code-datalab26-netd_aggregator/blob/main/CONTRIBUTING.md); security problems are reported privately as described in [`SECURITY.md`](https://github.com/lightonphiri/code-datalab26-netd_aggregator/blob/main/SECURITY.md).
