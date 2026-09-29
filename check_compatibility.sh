#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
init "$@"
ask PHP_VERSION 'Версия PHP' 8.3
apt_update
printf 'Ubuntu %s (%s), архитектура %s\n' "$VERSION_ID" "$VERSION_CODENAME" "$(dpkg --print-architecture)"
php_packages
missing=false
for package in nginx postgresql redis-server supervisor git certbot python3-certbot-nginx fail2ban python3-systemd unattended-upgrades acl "${PHP_PACKAGES[@]}"; do
    printf '\n%s\n' "$package"
    LC_ALL=C apt-cache policy "$package" | awk '/Installed:|Candidate:/ {print}'
    if ! package_candidate "$package"; then missing=true; printf 'НЕТ КАНДИДАТА\n'; fi
done
[[ "$missing" == false ]] || die 'Не все пакеты доступны. Измените PHP_VERSION или PHP_SOURCE и запустите server_setup.sh; проверка не добавляет PPA.'
apt-get --simulate install nginx postgresql redis-server supervisor git certbot python3-certbot-nginx fail2ban python3-systemd unattended-upgrades acl "${PHP_PACKAGES[@]}"
printf 'APT разрешил зависимости. Совместимость приложения проверяется по composer.lock выбранным PHP.\n'
