#!/usr/bin/env bash
# Run ONLY in a disposable Ubuntu container (see README).
set -euo pipefail
[[ -f /.dockerenv ]] || { echo 'Disposable Docker container required.'; exit 1; }
cd /work
bash tests/unit.sh
# Reproduce installation from a directory inaccessible to the site user.
mkdir -p /root/server-script-test
chmod 700 /root
cp /work/*.sh /root/server-script-test/
cp -r /work/lib /root/server-script-test/
run_script() { (cd /root/server-script-test; bash "$1"); }
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
# Exercise the same account/OPcache functions used by server_setup.sh.
source /work/lib/common.sh
source /work/lib/server_settings.sh
init --config "$CONFIG_FILE"
site_user
if (configure_site_sudo) >/dev/null 2>&1; then exit 1; fi
if id -nG site_test | grep -qw sudo; then exit 1; fi
# Substitute only passwd's interactive entry, keeping real password storage
# and real sudo authentication. This is a disposable test password.
passwd() {
    if [[ "$1" == -S ]]; then /usr/bin/passwd "$@"; else
        printf 'site_test:Test-sudo-password-428!\n' | chpasswd
        printf 'set\n' >> /tmp/password-set-count
    fi
}
NON_INTERACTIVE=false configure_site_sudo
configure_site_sudo
[[ $(wc -l < /tmp/password-set-count) == 1 ]]
unset -f passwd
if runuser -u site_test -- sudo -k -n /usr/bin/id -u >/dev/null 2>&1; then exit 1; fi
[[ $(printf 'Test-sudo-password-428!\n' | runuser -u site_test -- sudo -k -S -p '' /usr/bin/id -u) == 0 ]]
printf 'opcache.validate_timestamps=0\nopcache.revalidate_freq=60\n' > /etc/php/8.3/fpm/conf.d/98-old-opcache.ini
configure_php_opcache
configure_php_opcache
fpm_info=$(php-fpm8.3 -i)
grep -Fx 'opcache.enable => On => On' <<< "$fpm_info"
grep -Fx 'opcache.validate_timestamps => On => On' <<< "$fpm_info"
grep -Fx 'opcache.revalidate_freq => 2 => 2' <<< "$fpm_info"
# Incoming SSH: keep an existing key, install the client key once, and log in.
ssh-keygen -q -t ed25519 -N '' -f /tmp/client-key
ssh-keygen -q -t ed25519 -N '' -f /tmp/existing-key
install -d -m 700 -o site_test -g site_test /home/site_test/.ssh
printf '%s' "$(cat /tmp/existing-key.pub)" > /home/site_test/.ssh/authorized_keys
chown site_test:site_test /home/site_test/.ssh/authorized_keys
printf 'SSH_PUBLIC_KEY=%s\n' "$(cat /tmp/client-key.pub)" >> "$CONFIG_FILE"
run_script setup_ssh_access.sh
run_script setup_ssh_access.sh
[[ $(grep -c '^ssh-ed25519 ' /home/site_test/.ssh/authorized_keys) == 2 ]]
[[ $(stat -c '%U:%a' /home/site_test/.ssh/authorized_keys) == site_test:600 ]]
cp "$CONFIG_FILE" /tmp/valid-config.env
sed -i 's/^SSH_PUBLIC_KEY=.*/SSH_PUBLIC_KEY=not-a-key/' "$CONFIG_FILE"
if run_script setup_ssh_access.sh >/dev/null 2>&1; then exit 1; fi
cp /tmp/valid-config.env "$CONFIG_FILE"
mkdir -p /run/sshd
ssh-keygen -q -t ed25519 -N '' -f /tmp/test-host-key
cat > /tmp/test-sshd.conf <<'SSHD'
Port 22222
ListenAddress 127.0.0.1
HostKey /tmp/test-host-key
PidFile /tmp/test-sshd.pid
AuthorizedKeysFile .ssh/authorized_keys
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
StrictModes yes
AllowUsers site_test
SSHD
/usr/sbin/sshd -f /tmp/test-sshd.conf -E /tmp/test-sshd.log
printf '[127.0.0.1]:22222 %s\n' "$(cat /tmp/test-host-key.pub)" > /tmp/test-known-hosts
[[ $(ssh -i /tmp/client-key -p 22222 -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/tmp/test-known-hosts site_test@127.0.0.1 id -un) == site_test ]]
kill "$(cat /tmp/test-sshd.pid)"
run_script setup_git.sh
fingerprint=$(ssh-keygen -lf /home/site_test/.ssh/id_ed25519_github.pub)
run_script setup_git.sh
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
run_script setup_laravel_project.sh
run_script setup_laravel_project.sh
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
run_script setup_laravel_project.sh
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
