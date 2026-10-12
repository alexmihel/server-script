#!/usr/bin/env bash
# Requires common.sh and site_user().
configure_site_sudo() {
    local password_status
    password_status=$(LC_ALL=C passwd -S "$SITE_USER" | awk '{print $2}')
    if [[ "$password_status" != P ]]; then
        [[ ${NON_INTERACTIVE:-false} != true ]] || die "Для $SITE_USER требуется пароль: запустите настройку интерактивно или предварительно выполните passwd $SITE_USER."
        printf 'Задайте пароль пользователя %s для sudo (в конфиг он не записывается).\n' "$SITE_USER"
        passwd "$SITE_USER"
        password_status=$(LC_ALL=C passwd -S "$SITE_USER" | awk '{print $2}')
        [[ "$password_status" == P ]] || die 'Пароль пользователя не установлен.'
    fi
    usermod -aG sudo "$SITE_USER"
    printf 'Пользователь %s добавлен в sudo. Существующий пароль сохранён; для применения группы войдите заново.\n' "$SITE_USER"
}

configure_php_opcache() {
    local ini_dir="/etc/php/$PHP_VERSION/fpm/conf.d"
    [[ -d "$ini_dir" ]] || die 'Каталог настроек PHP-FPM не найден.'
    cat > "$ini_dir/99-server-script-opcache.ini" <<'INI'
; Managed by server-script: refresh modified PHP files automatically.
opcache.enable=1
opcache.validate_timestamps=1
opcache.revalidate_freq=2
INI
    "php-fpm$PHP_VERSION" -t
}
