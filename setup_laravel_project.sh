#/root/setup_laravel_project.sh                                                                                                                                                                                                                       2243/2243              100%
#!/bin/bash

#2 действия добавить под пользователем сделать composer install
# скопировать .env файл (или создать с nano)

# Запрос имени пользователя
read -p "Введите имя пользователя для настройки прав доступа: " USERNAME

# Проверка, существует ли указанный пользователь
if id "$USERNAME" &>/dev/null; then
    echo "Пользователь $USERNAME найден."
else
    echo "Пользователь $USERNAME не существует. Проверьте правильность ввода."
    exit 1
fi

# Запрос URL репозитория Bitucket
read -p "Введите URL репозитория : " REPO_URL

# Запрос названия проекта для создания подкаталога
read -p "Введите название проекта для установки: " PROJECT_NAME

# Папка для установки проекта
INSTALL_DIR="/var/www/$PROJECT_NAME"

# Проверка, пустая ли указанная директория
if [ -d "$INSTALL_DIR" ] && [ "$(ls -A $INSTALL_DIR)" ]; then
    echo "Директория $INSTALL_DIR не пуста. Укажите пустую директорию или удалите её содержимое."
    exit 1
fi

# Клонирование репозитория
echo "Клонирование репозитория..."

sudo mkdir -p "$INSTALL_DIR" || exit 1
sudo chown "$USERNAME:$(id -gn "$USERNAME")" "$INSTALL_DIR" || exit 1

if ! sudo -u "$USERNAME" -H git clone "$REPO_URL" "$INSTALL_DIR"; then
    echo "Ошибка клонирования. Проверьте SSH-ключ пользователя $USERNAME и доступ к репозиторию." >&2
    exit 1
fi

# Переход в папку проекта
cd "$INSTALL_DIR" || exit

echo "Настройка базовых прав доступа..."
# 1. Устанавливаем владельца на всё (и пользователя, и группу)
sudo chown -R "$USERNAME":"$USERNAME" "$INSTALL_DIR"

# 2. Стандартные права для веба (755 для папок, 644 для файлов)
sudo find "$INSTALL_DIR" -type d -exec chmod 755 {} \;
sudo find "$INSTALL_DIR" -type f -exec chmod 644 {} \;

echo "Настройка продвинутых прав доступа (ACL)..."
# Установка утилиты (на случай если это чистый сервер)
sudo apt update && sudo apt install -y acl

# 3. ACL для storage и cache: 
# Даем полные права (rwx) пользователю сайта и группе веб-сервера (www-data)
# Применяем рекурсивно к текущим файлам (-R)
sudo setfacl -R -m u:www-data:rwx,u:"$USERNAME":rwx "$INSTALL_DIR/storage" "$INSTALL_DIR/bootstrap/cache"

# 4. Наследуемые права (Default ACL):
# Все новые файлы в этих папках будут автоматически получать rwx для обоих
sudo setfacl -dR -m u:www-data:rwx,u:"$USERNAME":rwx "$INSTALL_DIR/storage" "$INSTALL_DIR/bootstrap/cache"

echo "Установка завершена. Права настроены корректно."

echo "Установка завершена. Проект Laravel настроен и готов к использованию."