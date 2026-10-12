# Подготовка Ubuntu-сервера для Laravel

Набор Bash-скриптов для развёртывания Laravel-проекта на VPS или выделенном
сервере с Ubuntu. Автоматизирует установку окружения, клонирование проекта,
создание базы данных и настройку домена с HTTPS.

Полезен Laravel-разработчикам и небольшим командам, которые самостоятельно
размещают приложения и хотят сократить ручную настройку сервера.

## Что делает

- Устанавливает Nginx, PHP-FPM с расширениями, Composer 2, PostgreSQL, Redis и Supervisor.
- Создаёт пользователя сайта с sudo по паролю, добавляет ваш публичный ключ для SSH-входа, настраивает UFW, Fail2ban и автоматические обновления Ubuntu.
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

При создании пользователя вставьте публичный ключ **вашего компьютера**:
на Mac/Linux его можно показать командой `cat ~/.ssh/id_ed25519.pub`.
Если ключа нет, сначала выполните `ssh-keygen -t ed25519` на компьютере.
Можно заранее заполнить `SSH_PUBLIC_KEY=ssh-ed25519 AAAA... ваш-комментарий`
в серверном `.env`, чтобы больше не вводить ключ вручную. Приватный ключ
на сервер передавать не нужно. Это отдельный ключ от создаваемого для GitHub.

Скрипт добавляет ключ в `authorized_keys` пользователя, сохраняет существующие
ключи, не дублирует повторно добавленный ключ и выставляет права `700`/`600`.
Вход по ключу не требует пароля пользователя. В новом терминале проверьте
`ssh ИМЯ_ПОЛЬЗОВАТЕЛЯ@АДРЕС_СЕРВЕРА` (с `-p ПОРТ`, если порт нестандартный).
Настройки sshd не меняются: нестандартные AllowUsers/AuthorizedKeysFile и другие
ограничения администратора сохраняются.

При установке окружения пользователь добавляется в группу `sudo`. Если пароль
ещё не задан или заблокирован, скрипт запускает `passwd` для его установки;
существующий действующий пароль при повторном запуске сохраняется. Пароль не
попадает в `.env` или аргументы команд. Для применения новой группы войдите заново.
Используется стандартное правило Ubuntu для группы sudo с запросом пароля;
существующие собственные правила sudoers скрипт не меняет. В автоматическом режиме
пользователь с действующим паролем должен быть подготовлен заранее.

Для уже созданного пользователя без переустановки окружения:

```bash
bash /root/server-script/setup_ssh_access.sh
```

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

Установка окружения явно включает OPcache для PHP-FPM и записывает
`opcache.validate_timestamps=1`, `opcache.revalidate_freq=2` в
`/etc/php/ВЕРСИЯ/fpm/conf.d/99-server-script-opcache.ini`, затем проверяет конфиг
и перезагружает FPM. Изменённые PHP-файлы перепроверяются при запросах с интервалом
две секунды. Кэш Laravel и долгоживущие процессы очередей обслуживаются отдельно.

Любой шаг можно выполнить отдельно с правами root или через sudo.
Для нескольких проектов используйте отдельные конфиги:

```bash
sudo bash server_setup.sh --config /root/site-a.env
sudo bash setup_ssh_access.sh --config /root/site-a.env
sudo bash setup_git.sh --config /root/site-a.env
sudo bash create_postgres_db.sh --config /root/site-a.env
sudo bash setup_laravel_project.sh --config /root/site-a.env
sudo bash create_nginx_domain_with_ssl.sh --config /root/site-a.env
```

Проверить доступность пакетов без установки можно через
`sudo bash check_compatibility.sh`. Проверка обновляет APT-индексы, но не добавляет PPA.

Elasticsearch в базовое окружение не входит. Поставить одноузловой
Elasticsearch 9.1.5 на localhost (PHP-клиент сайта — elasticsearch-php 9):

```bash
sudo bash /root/server-script/install_elasticsearch.sh
```

Скрипт идемпотентен, одинаков для stage и продакшена, Laravel `.env` и
Artisan не трогает. Если рядом со скриптом лежит
`elasticsearch-9.1.5-amd64.deb`, ставится он (удобно, когда
`artifacts.elastic.co` с сервера отвечает 403). Иначе используется APT-репозиторий Elastic 9.x. После установки выполните шаги
из раздела «Подключение Laravel к Elasticsearch».

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

## Подключение Laravel к Elasticsearch

Скрипт `install_elasticsearch.sh` только ставит сервис. Ниже — шаги
приложения. На каждом сервере подставьте свой каталог проекта и
пользователя сайта.

В `.env` Laravel:

```dotenv
SCOUT_DRIVER=elastic
ELASTIC_HOST=http://127.0.0.1:9200
ELASTIC_MIGRATIONS_DEFAULT_PATH=database/elastic/migrations
SCOUT_QUEUE=true
QUEUE_CONNECTION=redis
```

`SCOUT_QUEUE=true` — булево включение очереди Scout. В `config/scout.php`
должно быть `'queue' => env('SCOUT_QUEUE', false)`. Если `queue` задан
массивом, значение `true` станет именем очереди Redis, и `scout:import`
не попадёт в `queue:work` на `default`. Перед импортом воркер уже должен
работать, либо временно поставьте `SCOUT_QUEUE=false` для синхронной загрузки.

Уберите docker-хосты и драйвер Matchish, если они ещё указаны:

```dotenv
SCOUT_DRIVER=Matchish\ScoutElasticSearch\Engines\ElasticSearchEngine
ELASTICSEARCH_HOST=elasticsearch:9200
ELASTIC_HOST=http://bs.prj.loc-elasticsearch:9200
```

От пользователя сайта, из каталога проекта:

```bash
sudo -iu SITE_USER
cd /var/www/PROJECT_NAME
php8.3 artisan config:clear
php8.3 artisan elastic:migrate
php8.3 artisan scout:import 'App\Models\Report'
php8.3 artisan scout:import 'App\Models\Page'
php8.3 artisan scout:import 'App\Models\Post'
php8.3 artisan scout:import 'App\Models\News'
php8.3 artisan scout:import 'App\Models\TeamMember'
```

Если воркера очереди ещё нет, создайте программу Supervisor. Имя файла,
пользователь и путь к `artisan` зависят от сервера. Пример для stage
(`bs-site-user`, `/var/www/site-stage.businesstat.ru`):

```ini
[program:bs-site-worker]
process_name=%(program_name)s
command=php8.3 /var/www/site-stage.businesstat.ru/artisan queue:work redis --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=bs-site-user
numprocs=1
redirect_stderr=true
stdout_logfile=/var/www/site-stage.businesstat.ru/storage/logs/worker.log
stopwaitsecs=3600
```

Сохраните как `/etc/supervisor/conf.d/bs-site-worker.conf`, затем:

```bash
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl status
```
