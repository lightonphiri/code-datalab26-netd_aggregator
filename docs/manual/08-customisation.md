# 8. Customisation

How to make a NETD installation your own: its name, look, pages, language and citation styles. Start with `config/country.yml` ([chapter 7.1](07-configuration.md)): it sets the host name, contact and sender addresses, the portal name used in e-mail and reports, and the time zone. The rest of this chapter is still edits to templates and styles; the packaging plan moves them into the same file, locale files and a theme folder, release by release.

Keep your changes on a branch of your own (or in a fork) so that upgrades can be merged; after any change below, run `deploy/deploy.sh`.

## 8.1 Name

| Where it appears | File |
|---|---|
| Browser titles and Blacklight's own labels, OAI-PMH `Identify` repository name, RIS exports | `portal.name` in `config/country.yml` |
| Header wordmark (two parts, e.g. "Zambia" and "National ETD Portal") | `portal.wordmark` in `config/country.yml` |
| Footer credit line, header group bar | `credits` in `config/country.yml` (sentence built in `portal/app/views/shared/_footer.html.erb`) |
| Home page introduction | `portal.name`, `country.adjective` and `regulator` in `config/country.yml`; the rest of the text in `portal/app/views/catalog/_home_text.html.erb` |
| Emails (problem reports, alerts), Excel and PDF reports, OAI-PMH administrator e-mail | `portal.name`, `portal.host`, `contact.email` in `config/country.yml` |
| REST API specification | `portal/public/api/v1/openapi.yaml` (title, contact, server) |

## 8.2 Logo and credits

Credits are listed in `credits` in `config/country.yml` ([chapter 7.1](07-configuration.md)): the header bar and footer name the entry with role `developed by`, and the About and Credits pages show every entry's logo, in order. Put the logo files in `portal/public/images/` and name them in `logo` (with `logo_height` in pixels); `class` is the style class of the logo link (`datalab-credit` and `zamren-credit` are styled in `netd.css`; a theme folder follows in release P5). The site icon is `portal/public/icon.png` and `icon.svg`.

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

The interface is in English. Its wording is being moved out of the templates into `portal/config/locales/en.yml`, a few pages per release: the header, footer and home page are there now (keys under `netd.header`, `netd.footer` and `netd.home`); the other pages still have their text in their templates. Blacklight's own texts (search form, pagination, facet buttons) come from the Blacklight gem, and the portal name from `config/country.yml` through `portal/config/locales/netd_country.rb`.

To change a sentence, edit its key in `en.yml` and restart the portal (`sudo systemctl restart netd-portal`). Names come from `config/country.yml`: write `%{portal}`, `%{country}`, `%{country_adjective}`, `%{regulator}` or `%{regulator_short}` rather than the name itself, so the text stays right for another installation. Keys ending in `_html` may contain HTML (write `&` as `&amp;`); the comments in the file say which keys take extra values such as `%{n}` or `%{link}`.

To add a language, copy `en.yml` to, for example, `fr.yml`, change the first line to `fr:` and translate the values (keep the keys and the `%{...}` names), translate Blacklight's texts the same way (`blacklight.fr.yml`, from the gem's own file), and set the locale in `portal/config/application.rb` (`config.i18n.default_locale = :fr`). Metadata is shown in the language it was deposited in. Metadata is shown in the language it was deposited in.

## 8.7 Citation styles

"How to cite" uses official Citation Style Language files in `portal/config/csl/`, rendered by `citeproc-ruby`; terms come from `locales-en-GB.xml`. To add a style, copy an independent `.csl` file from https://github.com/citation-style-language/styles into that folder and add a line to `Citation::STYLES` in `portal/app/models/citation.rb` (key, label, file name). To change the default, set `Citation::DEFAULT`. For another language's terms, add its locale file from https://github.com/citation-style-language/locales.

Titles written in capitals are put into sentence case; words that must keep their capital letter are a general list (`KEEP_GENERAL` in `citation.rb`: continents, directions, diseases, international bodies, Roman numerals) plus `citation.keep_capitals` in `config/country.yml`. Add your country's place names, institutions and bodies there.

## 8.8 Time zone and dates

Dates are written as "January 3, 2027". Admin panel and quality-page times are shown in `country.time_zone` from `config/country.yml` (labelled with its city, e.g. "Lusaka time"); stored and API times are UTC; systemd timers run in the server's time zone.
