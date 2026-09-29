#!/usr/bin/env bash
# Shared by all entry points. Configuration is data, never shell code.
set -Eeuo pipefail
umask 022
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_KEYS='SITE_USER PROJECT_NAME REPO_URL GIT_PROVIDER PHP_VERSION PHP_SOURCE SSH_PORT DOMAIN INCLUDE_WWW CERTBOT_EMAIL DB_NAME DB_USER DB_PORT INSTALL_COMPOSER_DEPS NON_INTERACTIVE'
die() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }
known_key() { [[ " $CONFIG_KEYS " == *" $1 "* ]]; }
load_config() {
    local line key value
    [[ ! -L "$CONFIG_FILE" ]] || die 'Конфиг не должен быть символической ссылкой.'
    [[ -f "$CONFIG_FILE" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%$'\r'}
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]] || die 'В конфиге ожидается KEY=value.'
        key=${BASH_REMATCH[1]}; value=${BASH_REMATCH[2]}
        known_key "$key" || die "Неизвестный параметр: $key"
        if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then value=${value:1:${#value}-2}; fi
        printf -v "$key" '%s' "$value"
    done < "$CONFIG_FILE"
}
save_config() {
    local key tmp
    [[ -d "$(dirname -- "$CONFIG_FILE")" && ! -L "$CONFIG_FILE" ]] || die 'Некорректный путь конфига.'
    tmp=$(mktemp "${CONFIG_FILE}.XXXXXX")
    chmod 600 "$tmp"
    printf '# Server setup configuration. Literal values, no shell expansion.\n' > "$tmp"
    for key in $CONFIG_KEYS; do
        [[ ${!key-} != *$'\n'* && ${!key-} != *$'\r'* ]] || die "Перенос строки в $key"
        printf '%s=%s\n' "$key" "${!key-}" >> "$tmp"
    done
    mv -f -- "$tmp" "$CONFIG_FILE"
}
init() {
    [[ $EUID -eq 0 ]] || die "Запустите: sudo bash $0"
    CONFIG_FILE=${CONFIG_FILE:-$ROOT_DIR/.env}
    if [[ ${1-} == --config && $# == 2 ]]; then CONFIG_FILE=$2
    elif [[ $# != 0 ]]; then die 'Использование: script.sh [--config /absolute/path.env]'; fi
    [[ "$CONFIG_FILE" == /* ]] || CONFIG_FILE="$PWD/$CONFIG_FILE"
    export CONFIG_FILE
    # Trusted OS metadata, not the uploaded config.
    . /etc/os-release
    [[ ${ID:-} == ubuntu && ${VERSION_CODENAME:-} =~ ^[a-z]+$ ]] || die 'Поддерживается только Ubuntu.'
    load_config
    [[ ${NON_INTERACTIVE:-false} =~ ^(true|false)$ ]] || die 'NON_INTERACTIVE: true или false.'
    save_config
}
validate() {
    local key=$1 value=$2
    case "$key" in
        SITE_USER) [[ "$value" =~ ^[a-z_][a-z0-9_-]{0,31}$ && "$value" != root && "$value" != www-data && "$value" != postgres ]] ;;
        PROJECT_NAME) [[ "$value" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$ ]] ;;
        PHP_VERSION) [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]] ;;
        PHP_SOURCE) [[ "$value" =~ ^(auto|ubuntu|ondrej)$ ]] ;;
        GIT_PROVIDER) [[ "$value" =~ ^(github|bitbucket)$ ]] ;;
        SSH_PORT|DB_PORT) [[ "$value" =~ ^[0-9]{1,5}$ ]] && ((10#$value > 0 && 10#$value <= 65535)) ;;
        INCLUDE_WWW|INSTALL_COMPOSER_DEPS) [[ "$value" =~ ^(true|false)$ ]] ;;
        DB_NAME|DB_USER) [[ "$value" =~ ^[a-z_][a-z0-9_]{0,62}$ && "$value" != postgres ]] ;;
        DOMAIN) [[ ${#value} -le 253 && "$value" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]([a-z0-9-]*[a-z0-9])?$ ]] ;;
        CERTBOT_EMAIL) [[ "$value" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] ;;
        REPO_URL) [[ "$value" =~ ^git@(github.com|bitbucket.org):[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+(\.git)?$ ]] ;;
        *) return 1 ;;
    esac
}
ask() {
    local key=$1 label=$2 default=${3-} answer
    if [[ -z ${!key:-} ]]; then
        answer=''
        if [[ ${NON_INTERACTIVE:-false} != true ]]; then
            read -r -p "$label${default:+ [$default]}: " answer || die "Не получен $key"
        fi
        printf -v "$key" '%s' "${answer:-$default}"
    fi
    validate "$key" "${!key}" || die "Некорректное значение $key (исправьте $CONFIG_FILE)."
    save_config
}
site_user() {
    ask SITE_USER 'Пользователь сайта'
    id "$SITE_USER" >/dev/null 2>&1 || die 'Сначала создайте пользователя через server_setup.sh.'
    [[ $(id -u "$SITE_USER") -ge 1000 ]] || die 'Нельзя использовать системного пользователя.'
    SITE_HOME=$(getent passwd "$SITE_USER" | cut -d: -f6)
    SITE_GROUP=$(id -gn "$SITE_USER")
    [[ "$SITE_HOME" == /* && "$SITE_HOME" != / && -d "$SITE_HOME" ]] || die 'Некорректный домашний каталог.'
}
as_site() { sudo -H -u "$SITE_USER" -- "$@"; }
apt_update() { apt-get update -o APT::Update::Error-Mode=any; }
package_candidate() {
    local candidate
    candidate=$(LC_ALL=C apt-cache policy "$1" | awk '/Candidate:/ {print $2; exit}')
    [[ -n "$candidate" && "$candidate" != '(none)' ]]
}
php_packages() {
    PHP_PACKAGES=()
    local ext
    for ext in cli fpm mbstring xml curl pgsql zip gd intl bcmath soap redis; do PHP_PACKAGES+=("php${PHP_VERSION}-$ext"); done
}
php_available() {
    php_packages
    local pkg
    for pkg in "${PHP_PACKAGES[@]}"; do package_candidate "$pkg" || return 1; done
}
select_php() {
    ask PHP_VERSION 'Версия PHP' 8.3
    ask PHP_SOURCE 'Источник PHP: auto, ubuntu, ondrej' auto
    if [[ "$PHP_SOURCE" == ondrej ]] || { [[ "$PHP_SOURCE" == auto ]] && ! php_available; }; then
        apt-get install -y ca-certificates curl software-properties-common
        # Never substitute another Ubuntu release's codename.
        if curl --fail --silent --show-error --location --max-time 30 --output /dev/null "https://ppa.launchpadcontent.net/ondrej/php/ubuntu/dists/$VERSION_CODENAME/Release"; then
            LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
            apt_update
        else
            printf 'PPA недоступен для Ubuntu %s (%s).\n' "$VERSION_ID" "$VERSION_CODENAME" >&2
        fi
    fi
    while ! php_available; do
        printf 'PHP %s со всеми расширениями недоступен для Ubuntu %s (%s, %s).\n' "$PHP_VERSION" "$VERSION_ID" "$VERSION_CODENAME" "$(dpkg --print-architecture)" >&2
        printf 'Версии FPM в индексах APT (наличие всех расширений проверяется после выбора):\n'
        apt-cache pkgnames | sort -u | awk '/^php[0-9]+\.[0-9]+-fpm$/ {print}'
        [[ ${NON_INTERACTIVE:-false} != true ]] || die 'Укажите доступную PHP_VERSION в конфиге; автоматическая замена запрещена.'
        PHP_VERSION=''
        ask PHP_VERSION 'Введите другую версию PHP (Ctrl+C — отмена)'
    done
    apt-get --simulate install "${PHP_PACKAGES[@]}" >/dev/null
    save_config
}
project() { ask PROJECT_NAME 'Имя каталога проекта'; PROJECT_PATH="/var/www/$PROJECT_NAME"; }
repository() {
    ask GIT_PROVIDER 'Git-провайдер: github или bitbucket' github
    ask REPO_URL 'SSH URL репозитория (git@host:owner/repository.git)'
    case "$GIT_PROVIDER:$REPO_URL" in
        github:git@github.com:*|bitbucket:git@bitbucket.org:*) ;;
        *) die 'REPO_URL не соответствует GIT_PROVIDER.' ;;
    esac
}
