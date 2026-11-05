# Themes

A theme sets the portal's colours, the wordmark font and the logo files (packaging release P5; manual 8.2).
`portal.theme` in `config/country.yml` names the folder; without it the portal uses `default`.

    themes/<name>/
      stylesheets/theme.css   CSS custom properties (--netd-*, Bootstrap's --bs-*), imported after netd.css
      public/                 files served at the same addresses as portal/public/, e.g. public/images/logo.svg at
                              /images/logo.svg (the credits' logo files in country.yml are looked up there)

- `zambia`: the Zambia National ETD Portal (navy and blue, Cinzel wordmark, DataLab and ZAMREN logos).
- `default`: neutral slate and blue, system serif wordmark, no logos.

After changing the theme, run `deploy/deploy.sh` (it precompiles the assets) or restart the portal.
