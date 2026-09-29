#!/bin/bash

# chmod +x remove_apache.sh

# Остановка службы Apache
echo "Остановка службы Apache..."
sudo systemctl stop apache2

# Отключение автозапуска
echo "Отключение автозапуска Apache..."
sudo systemctl disable apache2

# Удаление пакетов Apache
echo "Удаление пакетов Apache..."
sudo apt-get purge -y apache2 apache2-utils apache2-bin apache2.2-common

# Очистка зависимостей
echo "Очистка неиспользуемых пакетов..."
sudo apt-get autoremove -y
sudo apt-get autoclean

# Удаление оставшихся конфигурационных файлов
echo "Удаление оставшихся конфигурационных файлов..."
sudo rm -rf /etc/apache2
sudo rm -rf /var/www/html
sudo rm -rf /var/log/apache2

echo "Apache успешно удалён из системы."
