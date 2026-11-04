# Contributing to NETD

Thank you for helping. Issues and pull requests are welcome at https://github.com/lightonphiri/code-datalab26-netd_aggregator.

## Before you start
- Read the manual's chapter on development: [docs/manual/12-developing.md](docs/manual/12-developing.md) (local set-up, tests).
- For anything larger than a fix, open an issue first and describe the problem, the requirement it affects (`docs/SRS.md`) and the change you propose.

## How changes are made
1. **Requirements and design first.** A feature or behaviour change updates `docs/SRS.md` and `docs/SDD.md` (a requirement with its identifier, the design, and both revision histories) in the same pull request.
2. **Changelog.** Add an entry under `[Unreleased]` in `CHANGELOG.md`.
3. **Manual.** User-visible changes update `docs/manual/`; check with `mkdocs build --strict`.
4. **Tests.** Run the tests that apply (manual chapter 12): `tests/test_people.py`, and the OAI-PMH and REST API conformance tests against a local or test installation. Model changes are tuned on the dev half of a gold standard and reported on the test half.
5. **Small changes.** One topic per pull request.

## Conventions
- Every value set or changed by code records its provenance (and, when derived, its confidence); the raw harvested record is never changed.
- REST API v1 fields are only added, never renamed or removed.
- No new services without a strong reason (the design fits a shared 4 GB server).
- Usage counting keeps no IP addresses, browser details or search words.
- British English; dates written as "January 3, 2027".
- Never commit secrets (`portal.env`, keys, rclone configuration), server access files, logs with IP addresses, or gold-standard annotations.

## Licence
By contributing you agree that your contribution is released under the project's BSD 3-Clause License (see `LICENSE`).
