#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
CONFIG_FILE="$tmp/config.env"
cat > "$CONFIG_FILE" <<'CONFIG'
SITE_USER=deploy
PROJECT_NAME=demo
REPO_URL=$(touch /tmp/server-script-injection)
PHP_VERSION="8.3"
NON_INTERACTIVE=true
CONFIG
load_config
[[ "$SITE_USER" == deploy && "$PHP_VERSION" == 8.3 ]]
[[ "$REPO_URL" == '$(touch /tmp/server-script-injection)' ]]
validate REPO_URL "$REPO_URL" && exit 1
save_config
unset SITE_USER PHP_VERSION
load_config
[[ "$SITE_USER" == deploy && "$PHP_VERSION" == 8.3 ]]
[[ $(stat -c %a "$CONFIG_FILE") == 600 ]]
for bad in root www-data ../test 'test;id'; do if validate SITE_USER "$bad"; then exit 1; fi; done
for bad in 0 65536 22/tcp; do if validate SSH_PORT "$bad"; then exit 1; fi; done
validate SSH_PORT 2222
validate DOMAIN example.org
if validate DOMAIN 'example.org;'; then exit 1; fi
if validate PROJECT_NAME ../other; then exit 1; fi
printf 'PATH=/tmp\n' > "$CONFIG_FILE"
if (load_config) 2>/dev/null; then exit 1; fi
printf 'SITE_USER=deploy\n' > "$CONFIG_FILE"
# Exact candidate lookup: a package name alone and Candidate:(none) must fail.
# shellcheck disable=SC2317
apt-cache() { printf 'php8.3-fpm:\n  Candidate: (none)\n'; }
if package_candidate php8.3-fpm; then exit 1; fi
# shellcheck disable=SC2317
apt-cache() { printf 'php8.3-fpm:\n  Candidate: 8.3.1-1ubuntu1\n'; }
package_candidate php8.3-fpm
apt-cache() {
    case "$*" in
        'policy php8.3-redis') printf 'Candidate: (none)\n' ;;
        policy*) printf 'Candidate: 8.3.1\n' ;;
        pkgnames) printf 'php8.3-fpm\nphp8.5-fpm\n' ;;
    esac
}
PHP_VERSION=8.3
if php_available; then exit 1; fi
PHP_SOURCE=ubuntu
NON_INTERACTIVE=true
VERSION_ID=26.04
VERSION_CODENAME=resolute
if (select_php) >/dev/null 2>&1; then exit 1; fi
[[ "$PHP_VERSION" == 8.3 ]]
printf 'Unit checks passed.\n'
