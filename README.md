# EcoFlow AC Monitor (Telegram Notify)

Скрипт для мониторинга наличия питания (AC) у EcoFlow (RIVER 2 Pro)  
с отправкой уведомлений в Telegram **только при изменении состояния**.

Используется:
- официальный EcoFlow Cloud API
- systemd service + timer (вместо cron)
- конфигурация через .env

---

## 1) Требования

- Linux с systemd
- Python 3
- curl
- доступ в интернет
- Telegram bot + chat_id

---

## 2) Файлы проекта

/srv/ecoflow/
- ecoflow_ac_only.py        — Проверка AC (exit 0/1)
- ecoflow_ac_notify.sh     — Уведомления Telegram
- .env                     — Секреты (chmod 600)
- ac_state.txt             — Последнее уведомлённое состояние
- README.md

Systemd:
/etc/systemd/system/
- ecoflow-ac-notify.service
- ecoflow-ac-notify.timer

---

## 3) Установка systemd

### Service
Файл: /etc/systemd/system/ecoflow-ac-notify.service

[Unit]
Description=EcoFlow AC notify (Telegram on state change)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/srv/ecoflow/ecoflow_ac_notify.sh

### Timer
Файл: /etc/systemd/system/ecoflow-ac-notify.timer

[Unit]
Description=Run EcoFlow AC notify every minute

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
Persistent=true

[Install]
WantedBy=timers.target

Включить:
sudo systemctl daemon-reload
sudo systemctl enable --now ecoflow-ac-notify.timer

---

## 4) Проверить работу systemd timer

### 4.1 Проверить, что timer активен
systemctl list-timers | grep ecoflow

### 4.2 Проверить статус timer и service
systemctl status ecoflow-ac-notify.timer
systemctl status ecoflow-ac-notify.service

- Active: active (waiting) — для timer
- inactive (dead) — для service (нормально, oneshot)

### 4.3 Запустить вручную (не ждать таймера)
sudo systemctl start ecoflow-ac-notify.service

### 4.4 Посмотреть логи
journalctl -u ecoflow-ac-notify.service -n 50 --no-pager

Онлайн:
journalctl -u ecoflow-ac-notify.service -f

### 4.5 Принудительно проверить отправку уведомления
sudo rm -f /srv/ecoflow/ac_state.txt
sudo systemctl start ecoflow-ac-notify.service

Проверка:
cat /srv/ecoflow/ac_state.txt

### 4.6 Проверить AC напрямую
python3 /srv/ecoflow/ecoflow_ac_only.py
echo $?

- exit 0 → AC есть
- exit 1 → AC нет

### 4.7 Если уведомления не приходят
journalctl -u ecoflow-ac-notify.service | grep TG_RESP

### 4.8 Остановить и отключить timer
sudo systemctl disable --now ecoflow-ac-notify.timer

---

## 5) Безопасность

- .env должен иметь права 600
- секреты не хранятся в скриптах
- Telegram сообщение отправляется через data-urlencode

---

## 6) Принцип работы

- AC определяется по inv.inputWatts > 0
- уведомление отправляется только при смене состояния
- ошибки API/сети не вызывают ложных тревог

---

## 7) Готово

После настройки система:
- работает после reboot
- не спамит
- пишет только при изменениях
- логируется через systemd
