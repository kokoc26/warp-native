#!/bin/bash

function ok {
    echo -e "\e[1;32m[OK]\e[0m $1"
}

function warn {
    echo -e "\e[1;33m[WARN]\e[0m $1"
}

function fail {
    echo -e "\e[1;31m[FAIL]\e[0m $1"
}

function info {
    echo -e "\e[1;34m[INFO]\e[0m $1"
}

function error_exit {
    fail "$1"
    exit 1
}

if [[ $EUID -ne 0 ]]; then
    fail "Этот скрипт должен быть запущен от имени root"
    exit 1
fi

echo -e "\n\e[1;35m╭─────────────────────────────────────╮"
echo -e "│      \e[1;36m  W A R P - N A T I V E        \e[1;35m│"
echo -e "│     \e[2;37m       by distillium            \e[1;35m│"
echo -e "╰─────────────────────────────────────╯\e[0m"
sleep 2

info "Начинаем установку и настройку Cloudflare WARP"
echo ""

info "1. Установка WireGuard..."
if grep -qE "ID=(debian|ubuntu)" /etc/os-release; then
    apt update -qq &>/dev/null || error_exit "Не удалось обновить список пакетов."
    apt install wireguard -y &>/dev/null || error_exit "Не удалось установить WireGuard."
elif grep -qE "ID_LIKE=.*(rhel|centos|fedora).*" /etc/os-release; then
    dnf install -y wireguard-tools &>/dev/null || error_exit "Не удалось установить WireGuard."
fi
ok "WireGuard установлен."
echo ""

info "2. Назначение временных DNS (1.1.1.1 + 8.8.8.8), чтобы гарантировать установку и регистрацию wgcf..."
cp /etc/resolv.conf /etc/resolv.conf.backup
echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > /etc/resolv.conf || error_exit "Не удалось настроить временные DNS-серверы."
ok "Временные DNS-серверы установлены."
echo ""

info "3. Скачивание и установка wgcf..."
WGCF_RELEASE_URL="https://api.github.com/repos/ViRb3/wgcf/releases/latest"
WGCF_VERSION=$(curl -s "$WGCF_RELEASE_URL" | grep tag_name | cut -d '"' -f 4)

if [ -z "$WGCF_VERSION" ]; then
    error_exit "Не удалось получить последнюю версию wgcf"
fi

WGCF_DOWNLOAD_URL="https://github.com/ViRb3/wgcf/releases/download/${WGCF_VERSION}/wgcf_${WGCF_VERSION#v}_linux_amd64"
WGCF_BINARY_NAME="wgcf_${WGCF_VERSION#v}_linux_amd64"

wget -q "$WGCF_DOWNLOAD_URL" -O "$WGCF_BINARY_NAME" || error_exit "Не удалось скачать wgcf."

chmod +x "$WGCF_BINARY_NAME" || error_exit "Не удалось сделать wgcf исполняемым."
mv "$WGCF_BINARY_NAME" /usr/local/bin/wgcf || error_exit "Не удалось переместить wgcf в /usr/local/bin."
ok "wgcf $WGCF_VERSION установлен в /usr/local/bin/wgcf."
echo ""

info "4. Регистрация и генерация конфигурации wgcf..."
yes | wgcf register &>/dev/null || error_exit "Ошибка при регистрации wgcf."
wgcf generate &>/dev/null || error_exit "Ошибка при генерации конфигурации wgcf."
ok "Конфигурация wgcf успешно сгенерирована."
echo ""

info "5. Редактирование конфигурации WARP..."
WGCF_CONF_FILE="wgcf-profile.conf"

if [ ! -f "$WGCF_CONF_FILE" ]; then
    error_exit "Файл $WGCF_CONF_FILE не найден."
fi

sed -i '/^DNS =/d' "$WGCF_CONF_FILE" || error_exit "Не удалось удалить строку DNS из конфигурации."

if ! grep -q "Table = off" "$WGCF_CONF_FILE"; then
    sed -i '/^MTU =/aTable = off' "$WGCF_CONF_FILE" || error_exit "Не удалось добавить Table = off."
fi

if ! grep -q "PersistentKeepalive = 25" "$WGCF_CONF_FILE"; then
    sed -i '/^Endpoint =/aPersistentKeepalive = 25' "$WGCF_CONF_FILE" || error_exit "Не удалось добавить PersistentKeepalive = 25."
fi

mkdir -p /etc/wireguard || error_exit "Не удалось создать директорию /etc/wireguard."
mv -Z "$WGCF_CONF_FILE" /etc/wireguard/warp.conf || error_exit "Не удалось переместить конфигурацию."
ok "Конфигурация сохранена в /etc/wireguard/warp.conf."
echo ""

info "6. Проверка включён ли IPv6 и настройка конфигурации WARP..."

is_ipv6_enabled() {
    sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null | grep -q ' = 0' || return 1
    sysctl net.ipv6.conf.default.disable_ipv6 2>/dev/null | grep -q ' = 0' || return 1
    ip -6 addr show scope global | grep -qv 'inet6 .*fe80::' || return 1
    return 0
}

if is_ipv6_enabled; then
    ok "IPv6 включён на сервере — оставляем IPv6-адрес в конфигурации WARP."
else
    warn "IPv6 отключён или не настроен на сервере — удаляем IPv6-адрес из конфигурации WARP."
    sed -i 's/,\s*[0-9a-fA-F:]\+\/128//' /etc/wireguard/warp.conf
    sed -i '/Address = [0-9a-fA-F:]\+\/128/d' /etc/wireguard/warp.conf
    ok "IPv6-адрес удалён из конфигурации."
fi
echo ""

info "7. Подключение интерфейса WARP..."
systemctl start wg-quick@warp &>/dev/null || error_exit "Не удалось подключить интерфейс."
ok "Интерфейс WARP успешно подключен."
echo ""

info "8. Проверка статуса подключения WARP..."

if ! wg show warp &>/dev/null; then
    fail "Интерфейс WARP не найден — туннель не работает."
    exit 1
fi

for i in {1..10}; do
    handshake=$(wg show warp | grep "latest handshake" | awk -F': ' '{print $2}')
    if [[ "$handshake" == *"second"* || "$handshake" == *"minute"* ]]; then
        ok "Получен handshake → $handshake"
        ok "WARP подключён и активно обменивается трафиком."
        break
    fi
    sleep 1
done

if [[ -z "$handshake" || "$handshake" == "0 seconds ago" ]]; then
    warn "Не удалось получить handshake в течении 10 секунд. Возможны проблемы с подключением."
fi

curl_result=$(curl -m 20 -s --interface warp https://www.cloudflare.com/cdn-cgi/trace | grep "warp=" | cut -d= -f2)

if [[ "$curl_result" == "on" ]]; then
    ok "Ответ от Cloudflare: warp=on"
else
    warn "Cloudflare не подтвердил warp=on, но интерфейс работает. Это нормально."
fi
echo ""

info "9. Включение автозапуска WARP при старте..."
systemctl enable wg-quick@warp &>/dev/null || error_exit "Не удалось настроить автозапуск."
ok "Автозапуск включен."
echo ""

cp /etc/resolv.conf.backup /etc/resolv.conf
ok "DNS возвращены к заводскому состоянию"
ok "Установка и настройка Cloudflare WARP завершены!"
echo ""
echo -e "\e[1;36m➤ Проверить статус службы: \e[0msystemctl status wg-quick@warp"
echo -e "\e[1;36m➤ Посмотреть информацию (WG): \e[0mwg show warp"
echo -e "\e[1;36m➤ Остановить интерфейс: \e[0msystemctl stop wg-quick@warp"
echo -e "\e[1;36m➤ Запустить интерфейс: \e[0msystemctl start wg-quick@warp"
echo -e "\e[1;36m➤ Перезапустить интерфейс: \e[0msystemctl restart wg-quick@warp"
echo -e "\e[1;36m➤ Отключить автозапуск: \e[0msystemctl disable wg-quick@warp"
echo -e "\e[1;36m➤ Включить автозапуск: \e[0msystemctl enable wg-quick@warp"
echo ""
