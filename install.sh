#!/bin/bash

function error_exit {
    echo "Ошибка: $1" >&2
    exit 1
}

if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт должен быть запущен от имени root"
   exit 1
fi

echo ""
echo -e "\e[1;35m╭─────────────────────────────────────╮\e[0m"
echo -e "\e[1;35m│      \e[1;36m  W A R P - N A T I V E        \e[1;35m│\e[0m"
echo -e "\e[1;35m│     \e[2;37m       by distillium            \e[1;35m│\e[0m"
echo -e "\e[1;35m╰─────────────────────────────────────╯\e[0m"
sleep 3
echo "" 

echo "Начинаем установку и настройку Cloudflare WARP"
echo ""

echo "1. Обновление списка пакетов и установка WireGuard, resolvconf..."
apt update &>/dev/null || error_exit "[FAIL] Не удалось обновить список пакетов."
apt install wireguard resolvconf -y &>/dev/null || error_exit "[FAIL] Не удалось установить WireGuard и resolvconf."
echo "[OK] WireGuard и resolvconf установлены."
echo ""

echo "2. Установка временных DNS-серверов (Cloudflare и Google) для обеспечения стабильной загрузки..."
echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > /etc/resolv.conf || error_exit "[FAIL] Не удалось настроить временные DNS-серверы."
echo "[OK] Временные DNS-серверы установлены."
echo ""

echo "3. Скачивание и установка wgcf..."
WGCF_RELEASE_URL="https://api.github.com/repos/ViRb3/wgcf/releases/latest"
WGCF_VERSION=$(curl -s "$WGCF_RELEASE_URL" | grep tag_name | cut -d '"' -f 4)

if [ -z "$WGCF_VERSION" ]; then
    error_exit "[FAIL] Не удалось получить последнюю версию wgcf"
fi

WGCF_DOWNLOAD_URL="https://github.com/ViRb3/wgcf/releases/download/${WGCF_VERSION}/wgcf_${WGCF_VERSION#v}_linux_amd64"
WGCF_BINARY_NAME="wgcf_${WGCF_VERSION#v}_linux_amd64"

echo "   Скачиваем wgcf версии: $WGCF_VERSION с $WGCF_DOWNLOAD_URL"
wget -q "$WGCF_DOWNLOAD_URL" -O "$WGCF_BINARY_NAME" || error_exit "[FAIL] Не удалось скачать wgcf."

chmod +x "$WGCF_BINARY_NAME" || error_exit "[FAIL] Не удалось сделать wgcf исполняемым."
mv "$WGCF_BINARY_NAME" /usr/local/bin/wgcf || error_exit "[FAIL] Не удалось переместить wgcf в /usr/local/bin."
echo "[OK] wgcf успешно установлен в /usr/local/bin/wgcf."
echo ""

echo "4. Регистрация wgcf и генерация конфигурации WARP..."
echo "   Выполняем wgcf регистрацию (автоматически)..."
yes | wgcf register &>/dev/null || error_exit "[FAIL] Ошибка при регистрации wgcf. Возможно, есть проблемы с подключением или Cloudflare."
echo "   Выполняем wgcf генерацию..."
wgcf generate &>/dev/null || error_exit "[FAIL] Ошибка при генерации конфигурации wgcf. Убедитесь, что регистрация прошла успешно."
echo "[OK] Конфигурация сгенерирована."
echo ""

echo "5. Редактирование конфигурации для успешной работы..."
WGCF_CONF_FILE="wgcf-profile.conf"

if [ ! -f "$WGCF_CONF_FILE" ]; then
    error_exit "[FAIL] Файл $WGCF_CONF_FILE не найден. Ожидается, что он был сгенерирован."
fi

sed -i '/^DNS =/d' "$WGCF_CONF_FILE" || error_exit "[FAIL] Не удалось удалить строку DNS из конфига."

if ! grep -q "Table = off" "$WGCF_CONF_FILE"; then
    sed -i '/^MTU =/aTable = off' "$WGCF_CONF_FILE" || error_exit "[FAIL] Не удалось добавить Table = off в конфиг."
fi

if ! grep -q "PersistentKeepalive = 25" "$WGCF_CONF_FILE"; then
    sed -i '/^Endpoint =/aPersistentKeepalive = 25' "$WGCF_CONF_FILE" || error_exit "[FAIL] Не удалось добавить PersistentKeepalive = 25 в конфиг."
fi

echo "[OK] Конфигурация готова к работе."
echo ""

mkdir -p /etc/wireguard || error_exit "[FAIL] Не удалось создать директорию /etc/wireguard."
mv "$WGCF_CONF_FILE" /etc/wireguard/warp.conf || error_exit "[FAIL] Не удалось переместить файл в /etc/wireguard/warp.conf."
echo "[OK] Файл сохранен как /etc/wireguard/warp.conf."
echo ""

echo "6. Подъем интерфейса WireGuard (WARP)..."
wg-quick up warp || error_exit "[FAIL] Не удалось поднять интерфейс WireGuard. Проверьте лог выше на ошибки."
echo "[OK] Интерфейс WARP поднят."
echo ""

echo "7. Проверка работы Cloudflare WARP..."
check_warp=$(curl -s --interface warp https://www.cloudflare.com/cdn-cgi/trace | grep "warp=")

if echo "$check_warp" | grep -q "warp=on"; then
    echo "[OK] WARP работает! ($check_warp)"
else
    echo "[WARN] WARP не активен или проверка не дала ожидаемого результата."
    echo "Вывод проверки: $check_warp"
fi
sleep 2
echo ""

echo "8. Настройка автозапуска интерфейса WARP при загрузке системы..."
systemctl enable wg-quick@warp || error_exit "[FAIL] Не удалось настроить автозапуск интерфейса WARP."
echo "[OK] Автозапуск WARP включен."
echo ""

echo "[COMPLETED] Установка и настройка Cloudflare WARP завершены!"
echo "Проверить статус интерфейса: wg show warp"
echo "Для отключения интерфейса: wg-quick down warp"
echo "Для перезапуска: systemctl restart wg-quick@warp"
echo "Отключить автозапуск: systemctl disable wg-quick@warp"
echo ""
