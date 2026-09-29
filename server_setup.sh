#!/bin/bash

##################################
#         Настройка UFW
##################################

# Настраиваемые переменные
SSH_PORT="22"  # Порт для SSH. Измените, если используется нестандартный порт.

# Убедитесь, что UFW установлен и включен
echo "Установка и активация UFW..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y ufw
sudo ufw --force reset

# Отключаем все входящие соединения по умолчанию и разрешаем все исходящие
echo "Настройка политики по умолчанию..."
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Разрешаем SSH на указанном порту
echo "Разрешаем SSH на порту $SSH_PORT..."
sudo ufw allow $SSH_PORT/tcp

# Разрешаем HTTP и HTTPS (если сервер используется для веб-сервиса)
echo "Разрешаем HTTP и HTTPS..."
sudo ufw allow http
sudo ufw allow https

# Разрешаем другие популярные службы (опционально)
# echo "Разрешаем FTP..."
# sudo ufw allow 21/tcp
# echo "Разрешаем SMTP..."
# sudo ufw allow 25/tcp
# echo "Разрешаем IMAP и IMAPS..."
# sudo ufw allow 143/tcp
# sudo ufw allow 993/tcp

# Включаем UFW
echo "Активируем UFW..."
sudo ufw --force enable

# Отображаем статус UFW
echo "Текущие правила UFW:"
sudo ufw status verbose

echo "Настройка брандмауэра завершена."


##################################
#  Настройка пользователя и SSH
##################################

# Запрашиваем имя нового пользователя
read -p "Введите имя нового пользователя (или нажмите Enter, чтобы пропустить): " NEW_USER
PUBLIC_KEY_PATH="$HOME/.ssh/id_rsa.pub"  # Путь к вашему публичному ключу

# Создаем нового пользователя, если имя указано
if [ -n "$NEW_USER" ]; then
    echo "Создаем пользователя $NEW_USER и добавляем в sudo..."
    sudo adduser $NEW_USER --gecos ""
    sudo usermod -aG sudo $NEW_USER

    # Настраиваем SSH для нового пользователя
    echo "Настройка SSH-доступа для $NEW_USER..."
    sudo mkdir -p /home/$NEW_USER/.ssh
    if [ -f "$PUBLIC_KEY_PATH" ]; then
        sudo cp $PUBLIC_KEY_PATH /home/$NEW_USER/.ssh/authorized_keys
    else
        echo "Файл публичного ключа не найден по пути $PUBLIC_KEY_PATH"
    fi
    sudo chmod 700 /home/$NEW_USER/.ssh
    sudo chmod 600 /home/$NEW_USER/.ssh/authorized_keys
    sudo chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
else
    echo "Создание нового пользователя пропущено."
fi

# Обновляем настройки SSH
echo "Настройка SSH..."
sudo sed -i "s/#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
sudo sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin no/" /etc/ssh/sshd_config
sudo sed -i "s/#PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config

# Перезапускаем SSH для применения изменений
sudo systemctl restart ssh

# Настройка брандмауэра (UFW)
echo "Настройка UFW..."
sudo ufw allow OpenSSH
sudo ufw allow $SSH_PORT/tcp
sudo ufw enable

# Добавляем правило для HTTP и HTTPS (если это веб-сервер)
sudo ufw allow http
sudo ufw allow https

# Проверка статуса UFW
sudo ufw status

# Установка Fail2ban для защиты от атак
echo "Установка и настройка Fail2ban..."
sudo apt install -y fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Настройка автоматических обновлений безопасности
echo "Настройка автоматических обновлений..."
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades

echo "Первоначальная настройка сервера завершена."
echo "Git, mc и Certbot успешно установлены."
echo "Вы можете войти на сервер с новым пользователем $NEW_USER по SSH."

##################################
#  Установка серверных программ
##################################

# Устанавливаем Nginx
echo "Устанавливаем Nginx..."
sudo apt install -y nginx

# Настройка брандмауэра UFW
echo "Настройка брандмауэра для разрешения HTTP и HTTPS трафика..."
sudo ufw allow 'Nginx Full'

# Запускаем и добавляем Nginx в автозагрузку
echo "Запуск Nginx и добавление в автозагрузку..."
sudo systemctl start nginx
sudo systemctl enable nginx

# Проверка статуса Nginx
echo "Проверка статуса Nginx..."
sudo systemctl status nginx | head -n 10

# Устанавливаем PHP 8.2 и необходимые модули для Laravel
echo "Устанавливаем PHP 8.2 и модули..."
sudo apt install -y software-properties-common

# Добавляем репозиторий Ondřej Surý для установки более новой версии PHP
echo "Добавление PPA-репозитория Ondřej Surý для PHP..."
sudo add-apt-repository -y ppa:ondrej/php
sudo apt update

# Запрос версии PHP с установкой значения по умолчанию
read -p "Введите версию PHP (по умолчанию 8.2): " PHP_VERSION
PHP_VERSION=${PHP_VERSION:-8.2}
echo "Установка PHP-FPM версии $PHP_VERSION..."
sudo apt install -y php${PHP_VERSION} php${PHP_VERSION}-fpm php${PHP_VERSION}-cli php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-curl php${PHP_VERSION}-pgsql php${PHP_VERSION}-zip php${PHP_VERSION}-gd php${PHP_VERSION}-intl php${PHP_VERSION}-bcmath php${PHP_VERSION}-soap php${PHP_VERSION}-redis

# Подтверждаем установку и выводим установленную версию PHP
echo "PHP-FPM успешно установлен. Текущая версия:"
php-fpm${PHP_VERSION} -v

# Запускаем и добавляем Nginx и PHP-FPM в автозагрузку
sudo systemctl enable nginx
sudo systemctl start nginx
sudo systemctl enable php${PHP_VERSION}-fpm
sudo systemctl start php${PHP_VERSION}-fpm

# Устанавливаем PostgreSQL
echo "Устанавливаем PostgreSQL..."
sudo apt install -y postgresql postgresql-contrib

# Запускаем и добавляем PostgreSQL в автозагрузку
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Устанавливаем Redis
echo "Устанавливаем Redis..."
sudo apt install -y redis-server

# Настраиваем Redis для работы в фоновом режиме и добавляем в автозагрузку
sudo systemctl enable redis-server
sudo systemctl start redis-server

# Устанавливаем Composer
echo "Устанавливаем Composer..."
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm composer-setup.php

# Обновляем список пакетов и устанавливаем необходимые программы
echo "Установка Supervisor, Git, Midnight Commander (mc) и Certbot..."
sudo apt install -y supervisor git mc certbot python3-certbot-nginx

# Запускаем и добавляем Supervisor в автозагрузку
echo "Запуск Supervisor и добавление в автозагрузку..."
sudo systemctl enable supervisor
sudo systemctl start supervisor

# Проверяем установленные версии для подтверждения
echo "Проверка установленных версий:"
composer --version
git --version
mc --version
certbot --version
supervisord --version
php --version

# Выводим сообщение об успешной установке
echo "Все необходимые пакеты установлены!"
