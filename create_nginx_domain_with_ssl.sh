#!/bin/bash

read -p "Вы хотите создать новый сайт? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "Операция отменена."
    exit 0
fi

# Запрос версии PHP с установкой значения по умолчанию
read -p "Введите версию PHP (по умолчанию 8.2): " PHP_VERSION
PHP_VERSION=${PHP_VERSION:-8.2}

# Запрос имени директории проекта
read -p "Введите имя директории проекта (например, my_project): " PROJECT_DIR

PROJECT_PATH="/var/www/$PROJECT_DIR"
if [ ! -d "$PROJECT_PATH" ]; then
    echo "Указанная папка не существует. Пожалуйста, проверьте путь и повторите попытку."
    exit 1
fi

# Запрос доменного имени
read -p "Введите доменное имя (например, example.com): " DOMAIN

# Проверка PHP-FPM сокета
if ! [ -S "/var/run/php/php$PHP_VERSION-fpm.sock" ]; then
    echo "Ошибка: PHP версии $PHP_VERSION не установлен или PHP-FPM сокет недоступен."
    exit 1
fi

NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

echo "server {
    listen 80;
    listen [::]:80;

    server_name www.$DOMAIN;
    
    return 301 https://$DOMAIN\$request_uri;
}

server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN;

    root $PROJECT_PATH/public;
    index index.html index.htm index.php;

    add_header X-Frame-Options \"SAMEORIGIN\";
    add_header X-XSS-Protection \"1; mode=block\";
    add_header X-Content-Type-Options \"nosniff\";

    charset utf-8;

    location / {
         try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
            fastcgi_pass unix:/var/run/php/php$PHP_VERSION-fpm.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
            include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
            deny all;
    }

    location ~ /\.ht {
        deny all;
    }
}" | sudo tee "$NGINX_CONF"

# Проверка и создание ссылки
if [ -L "/etc/nginx/sites-enabled/$DOMAIN" ]; then
    sudo rm "/etc/nginx/sites-enabled/$DOMAIN"
fi
sudo ln -s "$NGINX_CONF" /etc/nginx/sites-enabled/

sudo nginx -t
sudo systemctl reload nginx

echo "Настройка домена $DOMAIN завершена."

# Установка Certbot, если он не установлен
if ! command -v certbot &> /dev/null; then
    echo "Установка Certbot..."
    sudo apt update
    sudo apt install -y certbot python3-certbot-nginx
fi

# Получение и настройка SSL-сертификата для домена и www-домена
sudo certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN"

if [ $? -eq 0 ]; then
    echo "SSL-сертификат успешно установлен для $DOMAIN."
    sudo systemctl enable certbot.timer
else
    echo "Ошибка установки SSL-сертификата."
fi

echo "Настройка домена $DOMAIN с SSL завершена."
