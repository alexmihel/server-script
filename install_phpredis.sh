#!/bin/bash

#chmod +x install_phpredis.sh
#sudo ./install_phpredis.sh

# Запрос версии PHP у пользователя с значением по умолчанию (8.2)
read -p "Введите версию PHP (по умолчанию 8.2): " PHP_VERSION
PHP_VERSION=${PHP_VERSION:-8.2}

echo "Вы выбрали PHP версии: $PHP_VERSION"

# Обновление списка пакетов
sudo apt update
sudo apt install -y lsb-release software-properties-common curl

# Проверка существования выбранной версии PHP
if ! apt-cache search php${PHP_VERSION} | grep -q php${PHP_VERSION}-fpm; then
  echo "Ошибка: PHP версии ${PHP_VERSION} недоступна в репозитории."
  exit 1
fi

# Установка необходимых пакетов
sudo apt install -y php${PHP_VERSION}-dev php${PHP_VERSION}-cli php${PHP_VERSION}-fpm build-essential redis-server

# Установка phpredis через PECL
sudo apt install -y php-pear
sudo pecl install redis

# Подключение расширения в конфигурации PHP
echo "extension=redis.so" | sudo tee /etc/php/${PHP_VERSION}/fpm/conf.d/20-redis.ini
echo "extension=redis.so" | sudo tee /etc/php/${PHP_VERSION}/cli/conf.d/20-redis.ini

# Перезапуск PHP-FPM и Nginx для применения изменений
sudo systemctl restart php${PHP_VERSION}-fpm
sudo systemctl restart nginx

# Проверка установки
php -m | grep redis && echo "phpredis установлен и активирован." || echo "Ошибка установки phpredis."
