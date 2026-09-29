#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
init "$@"
site_user
ask GIT_PROVIDER 'Git-провайдер: github или bitbucket' github
apt_update
apt-get install -y git openssh-client
case "$GIT_PROVIDER" in
    github) host=github.com; url=https://github.com/settings/ssh/new ;;
    bitbucket) host=bitbucket.org; url=https://bitbucket.org/account/settings/ssh-keys/ ;;
esac
# An isolated key per provider; never overwrite existing private keys or SSH config.
as_site mkdir -p "$SITE_HOME/.ssh"
as_site chmod 700 "$SITE_HOME/.ssh"
key="$SITE_HOME/.ssh/id_ed25519_$GIT_PROVIDER"
if [[ ! -e "$key" ]]; then
    as_site ssh-keygen -t ed25519 -N '' -C "$SITE_USER@$host" -f "$key"
fi
as_site chmod 600 "$key"
# Regenerate the public part from the existing key if necessary.
as_site sh -c 'ssh-keygen -y -f "$1" > "$1.pub"' sh "$key"
as_site chmod 644 "$key.pub"
# Place managed Host section first, preserving all existing settings below it.
config="$SITE_HOME/.ssh/config"
begin="# BEGIN server-script $GIT_PROVIDER"
end="# END server-script $GIT_PROVIDER"
as_site bash -s -- "$config" "$begin" "$end" "$host" "$key" <<'SSHCONFIG'
set -euo pipefail
config=$1; begin=$2; end=$3; host=$4; key=$5
[[ ! -L "$config" ]] || { echo 'SSH config is a symlink; refusing overwrite.' >&2; exit 1; }
tmp=$(mktemp "${config}.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
{
    printf '%s\nHost %s\n    HostName %s\n    User git\n    IdentityFile %s\n    IdentitiesOnly yes\nHost *\n%s\n' "$begin" "$host" "$host" "$key" "$end"
    if [[ -f "$config" ]]; then awk -v b="$begin" -v e="$end" '$0==b {skip=1; next} $0==e {skip=0; next} !skip' "$config"; fi
} > "$tmp"
chmod 600 "$tmp"
mv -- "$tmp" "$config"
SSHCONFIG
printf '\nДобавьте этот ПУБЛИЧНЫЙ ключ: %s\n' "$url"
as_site cat "$key.pub"
printf '\nДля одного репозитория можно использовать Deploy/Access key в его настройках (чтение).\n'
printf 'Отпечатки серверов: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints\n'
printf 'Bitbucket: https://support.atlassian.com/bitbucket-cloud/docs/configure-ssh-and-two-step-verification/\n'
if [[ ${NON_INTERACTIVE:-false} == true ]]; then
    printf 'Ключ подготовлен. Добавьте его провайдеру, затем выполните проверку доступа/клонирование.\n'
    exit 0
fi
read -r -p 'После добавления ключа нажмите Enter для проверки репозитория: ' _
repository
# Checking repository access also handles GitHub ssh -T's successful exit status 1.
as_site git ls-remote "$REPO_URL" HEAD >/dev/null
printf 'Доступ к репозиторию от пользователя %s подтверждён.\n' "$SITE_USER"
