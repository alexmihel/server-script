#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
init "$@"
apt_update
select_php
apt-get install -y "php${PHP_VERSION}-cli" "php${PHP_VERSION}-fpm" "php${PHP_VERSION}-redis" redis-server
phpenmod -v "$PHP_VERSION" -s ALL redis
systemctl enable --now redis-server "php${PHP_VERSION}-fpm"
systemctl restart "php${PHP_VERSION}-fpm"
"php$PHP_VERSION" -r 'exit(extension_loaded("redis") ? 0 : 1);'
printf 'Redis extension установлен для PHP %s.\n' "$PHP_VERSION"
