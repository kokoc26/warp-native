#!/bin/bash

set -e

function info {
    echo -e "\e[1;33m[INFO]\e[0m $1"
}

function warn {
    echo -e "\e[1;31m[WARN]\e[0m $1"
}

function completed {
    echo -e "\e[1;32m[COMPLETED]\e[0m $1"
}

if [[ $EUID -ne 0 ]]; then
    warn "Скрипт должен быть запущен от root."
    exit 1
fi

if ip link show warp &>/dev/null; then
    info "Отключаем интерфейс warp..."
    wg-quick down warp &>/dev/null || true
fi

systemctl disable wg-quick@warp &>/dev/null || true

rm -f /etc/wireguard/warp.conf &>/dev/null
rm -rf /etc/wireguard &>/dev/null
rm -f /usr/local/bin/wgcf &>/dev/null
rm -f wgcf-account.toml wgcf-profile.conf &>/dev/null

info "Удаляем пакеты wireguard и resolvconf..."
DEBIAN_FRONTEND=noninteractive apt remove --purge -y wireguard &>/dev/null || true
DEBIAN_FRONTEND=noninteractive apt autoremove -y &>/dev/null || true

completed "Удаление завершено."
