#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
init "$@"
[[ ${NON_INTERACTIVE:-false} != true ]] || die 'Удаление Apache требует интерактивного подтверждения.'
read -r -p 'Удалить пакеты Apache? Содержимое сайтов сохранится. [y/N]: ' answer
[[ "$answer" =~ ^[Yy]$ ]] || exit 0
packages=()
for package in apache2 apache2-bin apache2-data apache2-utils; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'ok installed'; then packages+=("$package"); fi
done
if (( ${#packages[@]} )); then
    apt-get purge -y "${packages[@]}"
fi
printf 'Готово. Каталоги сайтов, журналы и посторонние зависимости не удалялись.\n'
