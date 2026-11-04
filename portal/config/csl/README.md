# Citation styles for "How to cite" (SRS FR-65)

Official Citation Style Language (CSL) files, rendered by `citeproc-ruby` in `app/models/citation.rb`. They are the
same styles that OJS offers in its "How to Cite" block, so a thesis on the portal is cited in the same way as an
article in a Zambian OJS journal.

Source: https://github.com/citation-style-language/styles and https://github.com/citation-style-language/locales
(fetched November 4, 2026). Licence: Creative Commons Attribution-ShareAlike 3.0 Unported
(https://creativecommons.org/licenses/by-sa/3.0/); authors and contributors are named in each file's `<info>` block.

| Key | Label | File | Style |
|---|---|---|---|
| acm | ACM | `acm-sig-proceedings.csl` | ACM SIG Proceedings |
| acs | ACS | `american-chemical-society.csl` | ACS Guide |
| apa | APA (default) | `apa.csl` | APA 7th edition |
| abnt | ABNT | `associacao-brasileira-de-normas-tecnicas.csl` | ABNT |
| chicago | Chicago | `chicago-author-date.csl` | Chicago Manual of Style 18th edition (author-date) |
| harvard | Harvard | `harvard-cite-them-right.csl` | Cite Them Right 12th edition (Harvard) |
| ieee | IEEE | `ieee.csl` | IEEE Reference Guide |
| mla | MLA | `modern-language-association.csl` | MLA Handbook 9th edition |
| turabian | Turabian | `turabian.csl` | `chicago-notes-bibliography-subsequent-author-title-17th-edition.csl`, the parent of the official `turabian-notes-bibliography` (Turabian 9th edition) dependent style |
| vancouver | Vancouver | `vancouver.csl` | `nlm-citation-sequence.csl` (NLM/Vancouver, Citing Medicine 2nd edition), which the CSL project's `vancouver` name now points to |

Terms come from `locales-en-GB.xml` (British English). To add a style: copy an independent `.csl` file here and add a
line to `Citation::STYLES`.
