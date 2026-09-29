#!/usr/bin/env bash
set -e

echo "=== PostgreSQL Database Creation Script ==="

# Проверяем, установлен ли PostgreSQL
if ! command -v psql >/dev/null 2>&1; then
    echo "PostgreSQL не найден. Установить? [y/n]"
    read -r install_pg
    if [[ "$install_pg" =~ ^[Yy]$ ]]; then
        sudo apt update
        sudo apt install -y postgresql postgresql-contrib
        echo "PostgreSQL установлен."
    else
        echo "Прервано. Установите PostgreSQL вручную и запустите скрипт снова."
        exit 1
    fi
fi

# Запрос параметров
read -rp "Введите название новой базы данных: " DB_NAME
read -rp "Введите имя пользователя: " DB_USER
read -rsp "Введите пароль для пользователя: " DB_PASS
echo ""
read -rp "Введите порт PostgreSQL (по умолчанию 5432): " DB_PORT
DB_PORT=${DB_PORT:-5432}

# Проверим, запущен ли PostgreSQL
if ! sudo systemctl is-active --quiet postgresql; then
    echo "PostgreSQL не запущен. Запускаем..."
    sudo systemctl start postgresql
fi

# Определяем системного пользователя postgres
PG_SUPERUSER="postgres"

echo "Создание пользователя и базы данных..."

sudo -u $PG_SUPERUSER psql <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASS}';
        RAISE NOTICE 'Пользователь создан.';
    ELSE
        RAISE NOTICE 'Пользователь уже существует, пропускаем создание.';
    END IF;
END
\$\$;

CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
SQL

echo "✅ База данных '${DB_NAME}' создана и принадлежит пользователю '${DB_USER}'."
echo "Порт: ${DB_PORT}"
echo "----------------------------------------"
echo "Проверка подключения:"
echo "psql -U ${DB_USER} -d ${DB_NAME} -h localhost -p ${DB_PORT}"
