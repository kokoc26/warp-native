<p aling="center"><a href="https://github.com/distillium/warp-native">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="./media/logo.png" />
   <source media="(prefers-color-scheme: light)" srcset="./media/logo-black.png" />
   <img alt="Warp Native" src="https://github.com/distillium/warp-native" />
 </picture>
</a></p>

Этот скрипт устанавливает Cloudflare WARP в "нативном" режиме через `WireGuard`, как интерфейс, без использования `warp-cli`.

Он автоматизирует:
- Установку необходимых пакетов
- Скачивание и настройку `wgcf`
- Проверку наличия ipv6 в системе
- Генерацию и модификацию WireGuard-конфигурации
- Подключение и проверку статуса
- Включение автозапуска интерфейса `warp`

---

## Установка (производится на каждую нужную ноду):

```bash
curl -sL https://raw.githubusercontent.com/distillium/warp-native/main/install.sh | bash
```

## Шаблоны для конфигурации Xray
<details>
  <summary>📝 Показать пример outbound</summary>

```json
{
  "tag": "warp-out",
  "protocol": "freedom",
  "settings": {},
  "streamSettings": {
    "sockopt": {
      "interface": "warp",
      "tcpFastOpen": true
    }
  }
}
```
</details>

<details>
  <summary>📝 Показать пример routing rule</summary>

```json
{
  "type": "field",
  "domain": [
    "netflix.com",
    "youtube.com",
    "twitter.com"
  ],
  "inboundTag": [
    "Node-1",
    "Node-2"
  ],
  "outboundTag": "warp-out"
}

```
</details>

## Управление интерфейсом WARP

| Операция                    | Команда                             |
|----------------------------|--------------------------------------|
| Проверить статус службы     | `systemctl status wg-quick@warp`     |
| Посмотреть информацию (wg) | `wg show warp`                       |
| Остановить интерфейс        | `systemctl stop wg-quick@warp`       |
| Запустить интерфейс         | `systemctl start wg-quick@warp`      |
| Перезапустить интерфейс     | `systemctl restart wg-quick@warp`    |
| Отключить автозапуск        | `systemctl disable wg-quick@warp`    |
| Включить автозапуск         | `systemctl enable wg-quick@warp`     |


## Удаление:
```bash
curl -sL https://raw.githubusercontent.com/distillium/warp-native/main/uninstall.sh | bash
```
