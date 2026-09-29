#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
init "$@"
site_user
project
ask PHP_VERSION 'Версия PHP' 8.3
ask DOMAIN 'Домен (без www и протокола)'
ask INCLUDE_WWW 'Добавить www (true/false)' false
ask CERTBOT_EMAIL 'Email для Lets Encrypt'
[[ -d "$PROJECT_PATH/public" ]] || die 'Нет public/; сначала настройте проект.'
sudo -u www-data test -r "$PROJECT_PATH/public/index.php" || die 'www-data не может читать public/index.php; выполните setup_laravel_project.sh.'
[[ -S "/run/php/php$PHP_VERSION-fpm.sock" ]] || die 'Нет сокета выбранного PHP-FPM.'
# The generated access model expects Ubuntu’s default www-data FPM pool.
grep -Eq '^user[[:space:]]*=[[:space:]]*www-data[[:space:]]*$' "/etc/php/$PHP_VERSION/fpm/pool.d/www.conf" || die 'Ожидается FPM pool www с user=www-data.'
apt_update
apt-get install -y nginx certbot python3-certbot-nginx
conf="/etc/nginx/sites-available/$DOMAIN"
link="/etc/nginx/sites-enabled/$DOMAIN"
marker='# Managed by server-script'
if [[ -e "$conf" ]]; then
    # Preserve existing TLS configuration on subsequent runs.
    grep -Fxq "$marker" "$conf" || die 'Конфиг Nginx уже существует и не принадлежит скрипту.'
    grep -Fq "root $PROJECT_PATH/public;" "$conf" || die 'Существующий домен указывает на другой проект.'
    grep -Fq "unix:/run/php/php$PHP_VERSION-fpm.sock;" "$conf" || die 'В существующем домене другая версия PHP; измените конфиг вручную.'
else
    [[ ! -e "$link" && ! -L "$link" ]] || die 'Путь sites-enabled уже занят.'
    names="$DOMAIN"
    [[ "$INCLUDE_WWW" != true ]] || names="$names www.$DOMAIN"
    cat > "$conf" <<NGINX
$marker
server {
    listen 80;
    listen [::]:80;
    server_name $names;
    root $PROJECT_PATH/public;
    index index.php;
    charset utf-8;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt { access_log off; log_not_found off; }
    location = /index.php {
        fastcgi_pass unix:/run/php/php$PHP_VERSION-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }
    location ~ \.php$ { return 404; }
    location ~ /\.(?!well-known).* { deny all; }
}
NGINX
    ln -s "$conf" "$link"
    if ! nginx -t; then
        rm -- "$link" "$conf"
        die 'Конфиг Nginx не прошёл проверку; новые файлы удалены.'
    fi
fi
[[ -L "$link" && $(readlink "$link") == "$conf" ]] || die 'Проверьте ссылку sites-enabled для домена.'
nginx -t
systemctl reload nginx
args=(-d "$DOMAIN")
[[ "$INCLUDE_WWW" != true ]] || args+=(-d "www.$DOMAIN")
printf 'Для сертификата DNS всех выбранных имён должен указывать на сервер, порт 80 — быть доступен.\n'
certbot --nginx --non-interactive --agree-tos --email "$CERTBOT_EMAIL" --redirect --keep-until-expiring "${args[@]}"
nginx -t
systemctl enable --now certbot.timer
printf 'HTTPS настроен для %s.\n' "$DOMAIN"
