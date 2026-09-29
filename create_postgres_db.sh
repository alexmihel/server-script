#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
init "$@"
default_db=${PROJECT_NAME:-}
ask DB_NAME 'Имя базы данных' "${default_db//-/_}"
default_user=${SITE_USER:-$DB_NAME}
ask DB_USER 'Пользователь базы данных' "${default_user//-/_}"
ask DB_PORT 'Порт PostgreSQL' 5432
if ! command -v psql >/dev/null; then
    apt_update
    apt-get install -y postgresql postgresql-contrib
fi
systemctl enable --now postgresql
if [[ ${NON_INTERACTIVE:-false} == true ]]; then die 'Пароль БД вводится интерактивно и не сохраняется в конфиге.'; fi
read -r -s -p 'Пароль роли БД (для существующей роли будет обновлён): ' DB_PASS
printf '\n'
[[ -n "$DB_PASS" ]] || die 'Пустой пароль запрещён.'
# Encode the secret for psql's metacommand grammar, then decode server-side.
# It never enters argv, the shared config or a temporary file.
{
    printf "\\\\set db_pass '%s'\n" "$(printf '%s' "$DB_PASS" | base64 | tr -d '\n')"
    cat <<'SQL'
SELECT NOT EXISTS (
    SELECT FROM pg_roles WHERE rolname = :'db_user'
      AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
) AND NOT EXISTS (
    SELECT FROM pg_database WHERE datname = :'db_name'
      AND pg_get_userbyid(datdba) <> :'db_user'
) AS safe_target \gset
\if :safe_target
\else
\echo ERROR: Refusing a privileged role or a database owned by another role.
SELECT 1/0;
\endif
SELECT format('CREATE ROLE %I LOGIN', :'db_user')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'db_user') \gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'db_user', convert_from(decode(:'db_pass', 'base64'), 'UTF8')) \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'db_user')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'db_name') \gexec
SELECT pg_get_userbyid(datdba) = :'db_user' AS correct_owner
FROM pg_database WHERE datname = :'db_name' \gset
\if :correct_owner
\echo Database owner verified.
\else
\echo ERROR: Existing database belongs to another role; ownership was not changed.
-- Force ON_ERROR_STOP to exit unsuccessfully.
SELECT 1/0;
\endif
SQL
} | sudo -H -u postgres psql -X -v ON_ERROR_STOP=1 -p "$DB_PORT" -d postgres -v db_user="$DB_USER" -v db_name="$DB_NAME"
unset DB_PASS
printf 'База %s готова, владелец %s, порт %s.\n' "$DB_NAME" "$DB_USER" "$DB_PORT"
