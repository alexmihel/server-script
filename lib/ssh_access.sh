#!/usr/bin/env bash
# Requires common.sh and site_user(). Only the public key from the client belongs here.
setup_ssh_access() {
    command -v ssh-keygen >/dev/null || die 'Установите openssh-client для проверки публичного ключа.'
    if [[ -z ${SSH_PUBLIC_KEY:-} ]]; then
        printf 'Настройка входа с вашего компьютера под пользователем %s.\n' "$SITE_USER"
        printf 'На Mac/Linux выполните: cat ~/.ssh/id_ed25519.pub\n'
        printf 'Если ключа нет: ssh-keygen -t ed25519 (на вашем компьютере).\n'
        printf 'Нужна одна строка публичного .pub ключа; приватный ключ и Git-ключ сервера не подходят.\n'
    fi
    ask SSH_PUBLIC_KEY 'Вставьте публичный SSH-ключ вашего компьютера'
    # Run filesystem operations as the owner, never follow a user-controlled link as root.
    as_site bash -s -- "$SSH_PUBLIC_KEY" <<'SSHACCESS'
set -euo pipefail
key=$1
[[ ! -L "$HOME/.ssh" && ! -L "$HOME/.ssh/authorized_keys" ]] || {
    echo 'Отказ: .ssh или authorized_keys является символической ссылкой.' >&2
    exit 1
}
umask 077
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys"
chmod 600 "$HOME/.ssh/authorized_keys"
read -r _ blob _ <<< "$key"
# Match key material even when the comment changed. Preserve restrictions on
# existing entries (do not append an unrestricted copy of a restricted key).
if ! awk -v blob="$blob" '!/^[[:space:]]*#/ {for (i=1; i<=NF; i++) if ($i==blob) found=1} END {exit !found}' "$HOME/.ssh/authorized_keys"; then
    # A leading newline also handles an existing file with no final newline.
    printf '\n%s\n' "$key" >> "$HOME/.ssh/authorized_keys"
fi
# StrictModes also rejects a group/world-writable home directory.
chmod go-w "$HOME"
SSHACCESS
    printf 'Публичный ключ добавлен в %s/.ssh/authorized_keys.\n' "$SITE_HOME"
    printf 'Проверьте вход в новом терминале: ssh %s@АДРЕС_СЕРВЕРА (для нестандартного порта добавьте -p ПОРТ).\n' "$SITE_USER"
    printf 'Настройки sshd и административные права не изменялись.\n'
}
