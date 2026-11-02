#!/bin/bash
# EMI Drupal site: 10.1.1 -> latest 10.x on PHP 8.1, all contrib under Composer at Drupal 11-ready versions,
# unused/blocking modules removed (session 05, November 2, 2026). Usage: emi-d10-update.sh <site dir>
set -Eeuo pipefail
S=${1:?site dir}; cd "$S"
log() { echo "$(date -u +%H:%M:%S) $*"; }
D() { sudo -u www-data vendor/bin/drush "$@"; }
C() { sudo -u www-data env HOME=/var/www/.composer-home COMPOSER_HOME=/var/www/.composer-home COMPOSER_NO_INTERACTION=1 /usr/local/bin/composer "$@"; }
mkdir -p /var/www/.composer-home && chown www-data:www-data /var/www/.composer-home
chown -R www-data:www-data vendor web/core web/modules web/themes web/profiles composer.json composer.lock 2>/dev/null || true
if D pm:list --status=enabled --format=list | grep -qx html_head; then
VERIF=$(D config:get html_head.header.settings html_header --format=string | sed -E 's/.*content="([^"]+)".*/\1/')
log "verification tag: $VERIF"

log "1. site verification tag to Metatag, then uninstall unused or Drupal-11-blocking modules"
D en -y metatag_verification
D php:eval "\$c=\Drupal::configFactory()->getEditable('metatag.metatag_defaults.global'); \$t=\$c->get('tags'); \$t['google']='$VERIF'; \$c->set('tags',\$t)->save(); echo 'google verification set', PHP_EOL;"
D pm:uninstall -y ckeditor_bootstrap_table ckeditor bootstrap_quicktabs quicktabs html_head
else log "step 1 already done"; fi

log "2. hand-installed modules out of web/modules (Composer installs them into web/modules/contrib)"
mkdir -p /var/backups/emi-removed-modules-$(date -u +%Y%m%d)
for m in backup_migrate bootstrap_layouts bootstrap_quicktabs bootstrap_table checklistapi ckeditor ckeditor_bootstrap_table content_entity_clone easy_breadcrumb editor_advanced_link google_analytics google_index_api honeypot html_head insert_view_adv metatag metatag_google_scholar name pathauto quicktabs search404 security_review seo_checklist sitemap smtp views_bootstrap; do
  [ -d web/modules/$m ] && rsync -a --remove-source-files web/modules/$m /var/backups/emi-removed-modules-$(date -u +%Y%m%d)/ && find web/modules/$m -depth -type d -empty -delete
done

log "3. Composer: core to latest 10.x and contrib to Drupal 11-ready releases"
COMPOSER_ALLOW_SUPERUSER=1 /usr/local/bin/composer self-update -q || true
chmod u+w web/sites/default web/sites/default/default.* 2>/dev/null || true
C config platform.php 8.1.27
C require -W --no-update \
  'drupal/core-recommended:^10.5' 'drupal/core-composer-scaffold:^10.5' 'drupal/core-project-message:^10.5' 'drush/drush:^12.5' \
  'drupal/backup_migrate:^5.1' 'drupal/bootstrap_layouts:^5.7' 'drupal/bootstrap_table:^1.0' 'drupal/checklistapi:^2.1' \
  'drupal/content_entity_clone:^1.1' 'drupal/easy_breadcrumb:^2.0' 'drupal/editor_advanced_link:^2.3' \
  'drupal/google_analytics:^4.0' 'drupal/google_index_api:^2.0' 'drupal/honeypot:2.1.4' 'drupal/insert_view_adv:^2.0' \
  'drupal/metatag:^2.2' 'drupal/metatag_google_scholar:^1.2' 'drupal/name:^1.5' 'drupal/pathauto:^1.15' 'drupal/search404:^2.2@RC' \
  'drupal/security_review:^3.1' 'drupal/seo_checklist:^5.2' 'drupal/sitemap:^2.6' 'drupal/smtp:^1.4' \
  'drupal/views_bootstrap:^5.5' 'drupal/token:^1.15' 'drupal/entity:^1.5' 'drupal/bibcite:^3.1' \
  'drupal/edux:^11.0' 'drupal/thex:^11.0'
C update -W --no-progress 2>&1 | grep -vE "^\s+- (Downloading|Installing|Upgrading|Removing)" | tail -25

chmod 555 web/sites/default; chmod 444 web/sites/default/settings.php
log "4. database updates"
D updb -y
log "4b. Honeypot: its 2.1.x updates first (8103, 8104 were never run), then 2.2"
chmod u+w web/sites/default
C require -W 'drupal/honeypot:^2.2' 2>&1 | grep -vE "^\s+- " | tail -3
chmod 555 web/sites/default
D updb -y
D cr
D status --fields=drupal-version,php-version,theme,db-status
D core:requirements --severity=2 --format=table 2>/dev/null || true
D watchdog:show --severity=Error --count=10 2>/dev/null || true
log "EMI UPDATE DONE"
