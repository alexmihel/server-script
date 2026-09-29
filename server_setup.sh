#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
init "$@"
ask SITE_USER 'Пользователь сайта'
apt_update
select_php
PACKAGES=(sudo ufw nginx postgresql postgresql-contrib redis-server supervisor git mc certbot python3-certbot-nginx acl unzip openssh-client fail2ban python3-systemd unattended-upgrades ca-certificates curl)
# Resolve the full transaction before changing firewall/users/services.
apt-get --simulate install "${PACKAGES[@]}" "${PHP_PACKAGES[@]}" >/dev/null
apt-get install -y "${PACKAGES[@]}" "${PHP_PACKAGES[@]}"
if ! id "$SITE_USER" >/dev/null 2>&1; then
    useradd --create-home --user-group --shell /bin/bash "$SITE_USER"
fi
site_user
printf 'Пользователь сайта: %s. Административные права не добавляются.\n' "$SITE_USER"

# Keep existing SSH configuration and firewall rules; allow every active SSH port.
SSH_PORTS=()
if [[ -x /usr/sbin/sshd ]]; then
    ssh_config=$(/usr/sbin/sshd -T)
    while read -r port; do [[ -n "$port" ]] && SSH_PORTS+=("$port"); done < <(awk '$1 == "port" {print $2}' <<< "$ssh_config")
fi
if [[ -n ${SSH_CONNECTION:-} ]]; then SSH_PORTS+=("${SSH_CONNECTION##* }"); fi
if [[ -z ${SSH_PORT:-} ]]; then ask SSH_PORT 'Текущий порт SSH' "${SSH_PORTS[0]:-22}"; else validate SSH_PORT "$SSH_PORT" || die 'Неверный SSH_PORT'; fi
SSH_PORTS+=("$SSH_PORT")
for port in "${SSH_PORTS[@]}"; do validate SSH_PORT "$port" || die 'Неверный порт SSH'; ufw allow "$port/tcp"; done
ufw allow 80/tcp
ufw allow 443/tcp
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

cat > /etc/fail2ban/jail.d/server-setup.local <<JAIL
[sshd]
enabled = true
backend = systemd
port = $(IFS=,; echo "${SSH_PORTS[*]}")
JAIL
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'APT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT
for service in nginx "php${PHP_VERSION}-fpm" postgresql redis-server supervisor fail2ban; do
    systemctl enable --now "$service"
done
systemctl restart fail2ban

# Use the selected PHP explicitly; verify the Composer installer before execution.
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT
curl -fsSL --max-time 60 https://composer.github.io/installer.sig -o "$tmp_dir/installer.sig"
curl -fsSL --max-time 60 https://getcomposer.org/installer -o "$tmp_dir/installer.php"
expected=$(cat "$tmp_dir/installer.sig")
actual=$("php$PHP_VERSION" -r 'echo hash_file("sha384", $argv[1]);' "$tmp_dir/installer.php")
[[ "$expected" == "$actual" ]] || die 'Контрольная сумма установщика Composer не совпала.'
"php$PHP_VERSION" "$tmp_dir/installer.php" --2 --install-dir=/usr/local/bin --filename=composer
"php$PHP_VERSION" /usr/local/bin/composer --version
"php$PHP_VERSION" -v
ufw status
printf 'Окружение установлено. SSH-настройки сохранены; настройте вход пользователя отдельно, если он требуется.\n'
