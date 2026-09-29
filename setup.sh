#!/bin/bash

#настройка дступа к файлам 
#chmod +x setup.sh setup_laravel_project.sh server_setup.sh create_nginx_domain_with_ssl.sh install_phpredis.sh remove_apache.sh create_postgres_db.sh

#sudo bash ./setup.sh

# Проверка наличия каждого скрипта и запрос на выполнение

# Функция для проверки и запуска скрипта
function run_script_if_confirmed() {
    local SCRIPT_NAME=$1
    local SCRIPT_PATH="./$SCRIPT_NAME"

    # Проверка существования скрипта
    if [ -f "$SCRIPT_PATH" ]; then
        read -p "Запустить скрипт $SCRIPT_NAME? (y/n): " CONFIRM
        if [[ "$CONFIRM" == "y" ]]; then
            echo "Запуск $SCRIPT_NAME..."
            sudo bash "$SCRIPT_PATH"
        else
            echo "Пропуск $SCRIPT_NAME."
        fi
    else
        echo "Скрипт $SCRIPT_NAME не найден."
    fi
}

# Последовательный запуск каждого скрипта с подтверждением
run_script_if_confirmed "server_setup.sh"
run_script_if_confirmed "install_phpredis.sh"
run_script_if_confirmed "setup_laravel_project.sh"
run_script_if_confirmed "create_nginx_domain_with_ssl.sh"

echo "Все операции завершены."
