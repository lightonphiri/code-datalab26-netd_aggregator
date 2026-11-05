# NETD manual

NETD is open-source software for a **national aggregator of electronic theses and dissertations (ETDs)**: it harvests thesis metadata from university repositories, cleans and completes it, and offers one search portal, an OAI-PMH data provider and a REST API over the whole collection. It runs the Zambia National ETD Portal at https://netd.ac.zm/, and is written so that another country can install it and adapt it.

This manual describes the software in general. The Zambian installation's own runbook (its server, schedules, accounts and history) is [`docs/OPERATIONS.md`](https://github.com/lightonphiri/code-datalab26-netd_aggregator/blob/main/docs/OPERATIONS.md); the requirements and design are in [`docs/SRS.md`](https://github.com/lightonphiri/code-datalab26-netd_aggregator/blob/main/docs/SRS.md) and [`docs/SDD.md`](https://github.com/lightonphiri/code-datalab26-netd_aggregator/blob/main/docs/SDD.md).

The structure follows the DSpace documentation (Introduction, Release Notes, Installing, Upgrading, Using, System Administration, Configuration, Customisation, Architecture, Interfaces, Development), so that repository managers who know DSpace find things where they expect them.

| Chapter | For | Contents |
|---|---|---|
| [1. Introduction and functional overview](01-introduction.md) | everyone | what an ETD aggregator does; the data flow |
| [2. Release notes](02-release-notes.md) | everyone | versions and what changed |
| [3. Installing](03-installing.md) | system administrators | prerequisites; a clean server step by step; first harvest |
| [4. Upgrading](04-upgrading.md) | system administrators | new releases; operating system upgrades |
| [5. Using the portal](05-using.md) | readers, librarians | search, facets, browsing, record pages, citing, feeds, the API |
| [6. System administration](06-administration.md) | portal team | admin panel, sources, harvesting, exclusions, duplicates, corrections, reports, usage, accounts, backups, alerts |
| [7. Configuration reference](07-configuration.md) | system administrators | every file and setting |
| [8. Customisation](08-customisation.md) | portal team, developers | name, logo, colours, pages, languages, citation styles |
| [9. Metadata filling](09-metadata-filling.md) | portal team, researchers | models, thresholds, evaluation with a gold standard, adding a model |
| [10. Interfaces](10-interfaces.md) | developers, other aggregators | REST API, OAI-PMH, sitemap, feeds |
| [11. Architecture and directory layout](11-architecture.md) | developers | components, data stores, layout |
| [12. Developing and contributing](12-developing.md) | developers | local set-up, tests, releases, conventions |

**Status of this manual (November 5, 2026).** The software was built for one country first. The installation's identity (country, portal name and host, regulator, contacts, credits, time zone) is now read from one file, `config/country.yml` ([chapter 7.1](07-configuration.md)); other wording, the theme and the deployment files still carry Zambian details, and [`docs/PACKAGING-PLAN.md`](https://github.com/lightonphiri/code-datalab26-netd_aggregator/blob/main/docs/PACKAGING-PLAN.md) moves them release by release. The requirements and design documents are under Reference ([SRS](reference/srs.md), [SDD](reference/sdd.md)).

**Licence.** BSD 3-Clause ([`LICENSE`](https://github.com/lightonphiri/code-datalab26-netd_aggregator/blob/main/LICENSE)); third-party material is listed in [`NOTICE`](https://github.com/lightonphiri/code-datalab26-netd_aggregator/blob/main/NOTICE).
