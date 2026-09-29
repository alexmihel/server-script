#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
init "$@"
site_user
project
repository
ask PHP_VERSION 'Версия PHP' 8.3
ask INSTALL_COMPOSER_DEPS 'Выполнить composer install (true/false)' false
apt_update
apt-get install -y git acl
[[ ! -L "$PROJECT_PATH" ]] || die 'Каталог проекта не должен быть ссылкой.'
install -d -m 755 /var/www
if [[ -e "$PROJECT_PATH" ]]; then
    [[ -d "$PROJECT_PATH/.git" && ! -L "$PROJECT_PATH/.git" ]] || die 'Каталог существует и не является обычным Git-репозиторием. Выберите другое PROJECT_NAME.'
    # Check origin before taking ownership; no global safe.directory wildcard.
    origin=$(git config --file "$PROJECT_PATH/.git/config" --get remote.origin.url)
    [[ "$origin" == "$REPO_URL" ]] || die 'Каталог принадлежит другому репозиторию.'
    printf 'Существующий репозиторий: исправляем права без изменения рабочей копии.\n'
    chown -hR "$SITE_USER:$SITE_GROUP" "$PROJECT_PATH"
else
    as_site git ls-remote "$REPO_URL" HEAD >/dev/null
    install -d -o "$SITE_USER" -g "$SITE_GROUP" -m 750 "$PROJECT_PATH"
    as_site git clone -- "$REPO_URL" "$PROJECT_PATH"
fi
[[ -f "$PROJECT_PATH/composer.json" && -d "$PROJECT_PATH/public" ]] || die 'Ожидается Laravel-проект с composer.json и public/.'
for path in storage bootstrap bootstrap/cache; do
    [[ ! -L "$PROJECT_PATH/$path" ]] || die "Нельзя настраивать ACL через ссылку $path."
done
# Preserve executable bits, keep code read-only to www-data and private to others.
find "$PROJECT_PATH" -type d -exec chmod u+rwx,go-rwx {} +
find "$PROJECT_PATH" -type f -exec chmod u+rw,go-rwx {} +
setfacl -R -P -m u:www-data:r-X "$PROJECT_PATH"
find "$PROJECT_PATH" -type d -exec setfacl -m d:u::rwx,d:u:www-data:r-x,d:g::---,d:m::r-x,d:o::--- {} +
setfacl -R -P -b "$PROJECT_PATH/.git"
find "$PROJECT_PATH/.git" -type d -exec setfacl -k {} +
chmod -R go-rwx "$PROJECT_PATH/.git"
as_site mkdir -p "$PROJECT_PATH/storage" "$PROJECT_PATH/bootstrap/cache"
for path in storage bootstrap/cache; do
    setfacl -R -P -m "u:$SITE_USER:rwX,u:www-data:rwX" "$PROJECT_PATH/$path"
    find "$PROJECT_PATH/$path" -type d -exec setfacl -m "d:u::rwx,d:u:$SITE_USER:rwx,d:u:www-data:rwx,d:g::---,d:m::rwx,d:o::---" {} +
done
if [[ "$INSTALL_COMPOSER_DEPS" == true ]]; then
    [[ -f "$PROJECT_PATH/composer.lock" ]] || die 'Для production требуется composer.lock.'
    command -v "php$PHP_VERSION" >/dev/null || die 'Выбранный PHP CLI не установлен.'
    [[ -f /usr/local/bin/composer ]] || die 'Сначала установите Composer через server_setup.sh.'
    cd "$PROJECT_PATH"
    as_site "php$PHP_VERSION" /usr/local/bin/composer check-platform-reqs --lock --no-dev
    as_site "php$PHP_VERSION" /usr/local/bin/composer install --no-dev --prefer-dist --optimize-autoloader --no-interaction
    as_site "php$PHP_VERSION" /usr/local/bin/composer check-platform-reqs --no-dev
fi
as_site git -C "$PROJECT_PATH" status --short
printf 'Репозиторий: %s, владелец: %s.\n' "$PROJECT_PATH" "$SITE_USER"
printf 'Настройте Laravel .env, APP_KEY, миграции, frontend и workers согласно проекту.\n'
printf 'Git/Composer/Artisan запускайте через sudo -H -u %s; для PHP используйте php%s.\n' "$SITE_USER" "$PHP_VERSION"
