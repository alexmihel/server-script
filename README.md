# Подготовка Ubuntu-сервера для Laravel

Набор Bash-скриптов для развёртывания Laravel-проекта на VPS или выделенном
сервере с Ubuntu. Автоматизирует установку окружения, клонирование проекта,
создание базы данных и настройку домена с HTTPS.

Полезен Laravel-разработчикам и небольшим командам, которые самостоятельно
размещают приложения и хотят сократить ручную настройку сервера.

## Что делает

- Устанавливает Nginx, PHP-FPM с расширениями, Composer 2, PostgreSQL, Redis и Supervisor.
- Создаёт пользователя сайта без sudo, настраивает UFW, Fail2ban и автоматические обновления Ubuntu.
- Создаёт SSH-ключ для GitHub или Bitbucket и проверяет доступ к репозиторию.
- Создаёт базу и пользователя PostgreSQL.
- Клонирует проект в `/var/www/PROJECT_NAME` и настраивает права Laravel.
- Настраивает Nginx, сертификат Let's Encrypt, перенаправление на HTTPS и автопродление.

## Перед запуском

Нужны Ubuntu с systemd, доступ root или sudo и Laravel-проект в GitHub либо
Bitbucket Cloud. Репозиторий указывается в SSH-формате:
`git@github.com:owner/repository.git`.

Для HTTPS направьте DNS домена на сервер и откройте порты 80/443, в том числе
в панели хостинга. При использовании `www` настройте DNS и для него.
Если Apache занимает эти порты, предварительно освободите их.

## Быстрый старт

На сервере **под root** выполните:

```bash
apt-get update -o APT::Update::Error-Mode=any &&
apt-get install -y git ca-certificates &&
git clone https://github.com/alexmihel/server-script.git /root/server-script &&
cd /root/server-script &&
bash setup.sh
```

Скрипт предложит по порядку установить окружение, настроить Git, создать БД,
склонировать проект и подключить HTTPS. Для нужных шагов отвечайте `y`.
При ошибке выполнение останавливается.

Настройки запрашиваются при первом использовании и сохраняются в `.env` рядом
со скриптами. При настройке Git добавьте показанный публичный SSH-ключ в GitHub
или Bitbucket с доступом к репозиторию, затем продолжите. Пароль БД вводится
отдельно и в конфиг не сохраняется.

Повторный запуск:

```bash
cd /root/server-script && bash setup.sh
```

Повторная настройка проекта исправляет права, но не выполняет `git pull`.
Повторное создание БД обновляет пароль её пользователя.

## Настройки и отдельные шаги

Можно заранее скопировать `.env.example` в `.env`, выдать файлу права `600`
и заполнить значения. Это конфиг установки сервера; Laravel `.env` настраивается
отдельно. Для изменения сохранённых ответов отредактируйте конфиг.

Пустые параметры запрашиваются при первом использовании; следующие шаги получают
введённые ответы автоматически. При неверном интерактивном вводе вопрос повторяется.
Имя каталога `PROJECT_NAME` может содержать точки, например `site-stage.businesstat.ru`.

Основные параметры: `SITE_USER`, `PROJECT_NAME`, `REPO_URL`, `PHP_VERSION`,
`DOMAIN`, `CERTBOT_EMAIL`, `DB_NAME` и `DB_USER`. `SSH_PORT` — текущий порт SSH,
скрипты его не меняют. `DB_PORT` — порт существующего кластера PostgreSQL.

По умолчанию используется PHP 8.3. Доступность пакетов проверяется при запуске;
`PHP_SOURCE=auto` при необходимости пытается подключить PPA Ondřej.
`INSTALL_COMPOSER_DEPS=true` включает установку зависимостей по `composer.lock`.
Если Composer scripts требуют Laravel `.env`, подготовьте его заранее.

Любой шаг можно выполнить отдельно с правами root или через sudo.
Для нескольких проектов используйте отдельные конфиги:

```bash
sudo bash server_setup.sh --config /root/site-a.env
sudo bash setup_git.sh --config /root/site-a.env
sudo bash create_postgres_db.sh --config /root/site-a.env
sudo bash setup_laravel_project.sh --config /root/site-a.env
sudo bash create_nginx_domain_with_ssl.sh --config /root/site-a.env
```

Проверить доступность пакетов без установки можно через
`sudo bash check_compatibility.sh`. Проверка обновляет APT-индексы, но не добавляет PPA.

## После установки

Подготовьте Laravel `.env` с параметрами БД и секретами, установите зависимости,
если пропустили этот шаг, настройте `APP_KEY`, выполните миграции и сборку frontend.
Cron и процессы очередей в Supervisor также настраиваются под конкретный проект.

Git, Composer и Artisan запускайте от пользователя сайта, указав выбранную
версию PHP. Например, для пользователя `deploy` и проекта `my_project`:

```bash
sudo -iu deploy
cd /var/www/my_project
php8.3 /usr/local/bin/composer install --no-dev --optimize-autoloader
php8.3 artisan about
```

Если Laravel `.env` создан с правами `600`, разрешите PHP-FPM читать его
командой от администратора:

```bash
sudo setfacl -m u:www-data:r-- /var/www/my_project/.env
```
