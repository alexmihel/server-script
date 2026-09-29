#!/usr/bin/env bash
# Run ONLY in a disposable Ubuntu container (see README).
set -euo pipefail
[[ -f /.dockerenv ]] || { echo 'Disposable Docker container required.'; exit 1; }
cd /work
bash tests/unit.sh
mkdir -p /tmp/test-bin
# Only host services, package installation and ACME are mocked.
for command in apt-get systemctl certbot; do
    printf '#!/bin/sh\nexit 0\n' > "/tmp/test-bin/$command"
    chmod +x "/tmp/test-bin/$command"
done
export PATH="/tmp/test-bin:$PATH"
CONFIG_FILE=/tmp/server-test.env
export CONFIG_FILE
cat > "$CONFIG_FILE" <<'CONFIG'
SITE_USER=site_test
PROJECT_NAME=server_script_test
GIT_PROVIDER=github
REPO_URL=git@github.com:example/project.git
PHP_VERSION=8.3
PHP_SOURCE=ubuntu
DOMAIN=example.org
INCLUDE_WWW=false
CERTBOT_EMAIL=admin@example.org
DB_NAME=server_script_test
DB_USER=site_test
DB_PORT=55432
INSTALL_COMPOSER_DEPS=false
NON_INTERACTIVE=true
CONFIG
useradd -m -U -s /bin/bash site_test
bash setup_git.sh
fingerprint=$(ssh-keygen -lf /home/site_test/.ssh/id_ed25519_github.pub)
bash setup_git.sh
[[ "$fingerprint" == "$(ssh-keygen -lf /home/site_test/.ssh/id_ed25519_github.pub)" ]]
[[ $(grep -c '^Host github.com$' /home/site_test/.ssh/config) == 1 ]]
[[ $(stat -c '%U:%a' /home/site_test/.ssh/id_ed25519_github) == site_test:600 ]]
# Existing root-owned repository: correct ownership, preserve executable bits.
project=/var/www/server_script_test
mkdir -p "$project"/{public,storage,bootstrap/cache}
/usr/bin/git init "$project"
/usr/bin/git -C "$project" remote add origin git@github.com:example/project.git
printf '{}\n' > "$project/composer.json"
printf '<?php echo "ok";\n' > "$project/public/index.php"
printf '#!/bin/sh\nexit 0\n' > "$project/run.sh"
chmod +x "$project/run.sh"
bash setup_laravel_project.sh
bash setup_laravel_project.sh
sudo -H -u site_test git -C "$project" status --short >/dev/null
sudo -H -u site_test test -x "$project/run.sh"
sudo -H -u www-data test -r "$project/public/index.php"
if sudo -H -u www-data test -w "$project/public/index.php"; then exit 1; fi
if sudo -H -u www-data test -r "$project/.git/config"; then exit 1; fi
sudo -H -u www-data touch "$project/storage/from-web"
sudo -H -u site_test sh -c 'echo ok >> "$1"' sh "$project/storage/from-web"
sudo -H -u site_test touch "$project/storage/from-cli"
sudo -H -u www-data sh -c 'echo ok >> "$1"' sh "$project/storage/from-cli"
# Newly deployed code inherits read permissions, but no write access for FPM.
sudo -H -u site_test sh -c 'umask 077; echo test > "$1"' sh "$project/new-file"
sudo -H -u www-data test -r "$project/new-file"
if sudo -H -u www-data test -w "$project/new-file"; then exit 1; fi
# Exercise the first clone with a local Git transport replacing the hosted URL.
sudo -H -u site_test git -C "$project" add .
sudo -H -u site_test git -C "$project" -c user.name=Test -c user.email=test@example.org commit -m fixture
mkdir -p /tmp/server-fixtures
chmod 777 /tmp/server-fixtures
sudo -H -u site_test git clone --bare "$project" /tmp/server-fixtures/project.git
sudo -H -u site_test git config --global url.file:///tmp/server-fixtures/.insteadOf git@github.com:example/
sed -i 's/PROJECT_NAME=server_script_test/PROJECT_NAME=cloned_project/' "$CONFIG_FILE"
bash setup_laravel_project.sh
[[ $(stat -c %U /var/www/cloned_project/.git/config) == site_test ]]
sudo -H -u site_test git -C /var/www/cloned_project status --short
sed -i 's/PROJECT_NAME=cloned_project/PROJECT_NAME=server_script_test/' "$CONFIG_FILE"
# Real PostgreSQL, a non-default port, metacharacter password and repeat run.
pg_createcluster 16 integration --port=55432 --start
sed -i 's/NON_INTERACTIVE=true/NON_INTERACTIVE=false/' "$CONFIG_FILE"
password="quote' slash\\ dollar\$ backtick\` ; SELECT 1;"
printf '%s\n' "$password" | bash create_postgres_db.sh
printf '%s\n' "$password" | bash create_postgres_db.sh
PGPASSWORD="$password" psql -h 127.0.0.1 -p 55432 -U site_test -d server_script_test -c 'SELECT 1' >/dev/null
# Actual FPM socket and nginx parser; ACME and reload calls are mocked.
mkdir -p /run/php
php-fpm8.3 -D
bash create_nginx_domain_with_ssl.sh
bash create_nginx_domain_with_ssl.sh
nginx -t
printf 'Integration checks passed.\n'
