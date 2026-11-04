# 8. Customisation

How to make a NETD installation your own: its name, look, pages, language and citation styles. Start with `config/country.yml` ([chapter 7.1](07-configuration.md)): it sets the host name, contact and sender addresses, the portal name used in e-mail and reports, and the time zone. The rest of this chapter is still edits to templates and styles; the packaging plan moves them into the same file, locale files and a theme folder, release by release.

Keep your changes on a branch of your own (or in a fork) so that upgrades can be merged; after any change below, run `deploy/deploy.sh`.

## 8.1 Name

| Where it appears | File |
|---|---|
| Browser titles and Blacklight's own labels | `application_name` in `portal/config/locales/blacklight.en.yml` |
| Header wordmark (two parts, e.g. "Zambia" and "National ETD Portal") | `portal/app/components/netd_header_component.html.erb` |
| Footer credit line | `portal/app/views/shared/_footer.html.erb` |
| Home page introduction | `portal/app/views/catalog/_home_text.html.erb` |
| Emails (problem reports, alerts), Excel and PDF reports, OAI-PMH administrator e-mail | `portal.name`, `portal.host`, `contact.email` in `config/country.yml` |
| OAI-PMH `Identify` repository name | `portal/app/controllers/oai_controller.rb` |
| REST API specification | `portal/public/api/v1/openapi.yaml` (title, contact, server) |

## 8.2 Logo and credits

Logos are in `portal/public/images/` (the developer's and the host's logos in the footer and on the About and Credits pages). Replace the files and the `<img>` references in the footer, `pages/about.html.erb` and `pages/credits.html.erb`. The site icon is `portal/public/icon.png` and `icon.svg`.

## 8.3 Colours and fonts

`portal/app/assets/stylesheets/netd.css` starts with the theme variables:

```css
:root {
  --netd-navy: #0b1f6b;       /* header and group bar */
  --netd-blue: #0071c2;       /* links, buttons, selected facets */
  --netd-blue-dark: #005a9c;  /* hover */
  --netd-muted: #5b6470;      /* secondary text */
  --netd-line: #e3e6ea;       /* rules and borders */
  --bs-body-font-family: system-ui, ...;
}
```

Change the variables (and the matching Bootstrap `--bs-*` values below them, which repeat the blue) rather than individual rules. Check contrast for text on the header colour (at least 4.5:1).

## 8.4 Static pages

| Page | Template |
|---|---|
| About (project, team, publications) | `portal/app/views/pages/about.html.erb` and `portal/config/publications.yml` |
| FAQ | `pages/faq.html.erb` |
| Developer Resources | `pages/developers.html.erb`; API reference `pages/api_docs.html.erb` |
| For Institutions (how to contribute) | `pages/contribute.html.erb` |
| Credits | `pages/credits.html.erb` |
| Metadata quality (public) | `portal/app/views/quality/index.html.erb` |

The FAQ describes what is counted in usage analytics and how long server logs are kept; update it to match your server and your country's data protection law.

## 8.5 Facets, fields and sorting

Facets, search fields, sort options and results per page are set in `portal/app/controllers/catalog_controller.rb` (`add_facet_field`, `add_search_field`, `add_sort_field`). Search field weights are in `solr/netd/conf/solrconfig.xml`. A new facet needs a Solr field written by `harvester/netd/index.py`.

## 8.6 Languages

The interface is in English. Blacklight's own texts come from `portal/config/locales/blacklight.en.yml` and `en.yml`; most NETD templates have their text written in them. To add a language today, translate the locale files (`blacklight.<lang>.yml`) and the templates; the packaging plan moves the templates' text into locale files first, so that a translation is one file per language. Metadata is shown in the language it was deposited in.

## 8.7 Citation styles

"How to cite" uses official Citation Style Language files in `portal/config/csl/`, rendered by `citeproc-ruby`; terms come from `locales-en-GB.xml`. To add a style, copy an independent `.csl` file from https://github.com/citation-style-language/styles into that folder and add a line to `Citation::STYLES` in `portal/app/models/citation.rb` (key, label, file name). To change the default, set `Citation::DEFAULT`. For another language's terms, add its locale file from https://github.com/citation-style-language/locales.

Titles written in capitals are put into sentence case; place names that must keep their capital letter are listed in `KEEP` in `citation.rb`. Add your country's place names there.

## 8.8 Time zone and dates

Dates are written as "January 3, 2027". Admin panel and quality-page times are shown in `country.time_zone` from `config/country.yml` (labelled with its city, e.g. "Lusaka time"); stored and API times are UTC; systemd timers run in the server's time zone.
