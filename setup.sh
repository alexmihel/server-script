#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
init "$@"
[[ ${NON_INTERACTIVE:-false} != true ]] || die 'В автоматическом режиме запускайте нужные шаги отдельно.'
for script in server_setup.sh setup_git.sh create_postgres_db.sh setup_laravel_project.sh create_nginx_domain_with_ssl.sh; do
    read -r -p "Запустить $script? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then bash "$ROOT_DIR/$script" --config "$CONFIG_FILE"; fi
done
printf 'Выбранные шаги завершены. Конфиг: %s\n' "$CONFIG_FILE"
