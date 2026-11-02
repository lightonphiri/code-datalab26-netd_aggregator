#!/bin/bash
# EMI Drupal site: 10.6 -> 11.x on PHP 8.3 (after the 24.04 hop; session 05, November 2, 2026).
# Usage: emi-d11-update.sh <site dir>. Run emi-d10-update.sh first (contrib under Composer, blockers removed).
set -Eeuo pipefail
S=${1:?site dir}; cd "$S"
log() { echo "$(date -u +%H:%M:%S) $*"; }
D() { sudo -u www-data vendor/bin/drush "$@"; }
C() { sudo -u www-data env HOME=/var/www/.composer-home COMPOSER_HOME=/var/www/.composer-home COMPOSER_NO_INTERACTION=1 /usr/local/bin/composer "$@"; }
chown -R www-data:www-data vendor web/core web/modules web/themes composer.json composer.lock 2>/dev/null || true
log "1. Tour was removed from core in Drupal 11 (unused here)"
D pm:list --status=enabled --format=list | grep -qx tour && D pm:uninstall -y tour || true
log "2. Composer: core 11 and Drush 13"
chmod u+w web/sites/default web/sites/default/default.* 2>/dev/null || true
C config --unset platform.php || true
for kv in symfony/runtime=true tbachert/spi=false php-http/discovery=false drupal/core-recipe-unpack=true php-tuf/composer-integration=true; do C config --no-plugins allow-plugins.${kv%%=*} ${kv#*=}; done
C require -W --no-update 'drupal/core-recommended:^11.3' 'drupal/core-composer-scaffold:^11.3' 'drupal/core-project-message:^11.3' 'drush/drush:^13'
C update -W --no-progress 2>&1 | grep -vE "^\s+- (Downloading|Installing|Upgrading|Removing)" | tail -15
chmod 555 web/sites/default; chmod 444 web/sites/default/settings.php
log "3. database updates"
D updb -y
D cr
D status --fields=drupal-version,php-version,theme,db-status
D core:requirements --severity=2 --format=table 2>/dev/null || true
log "EMI D11 DONE"
