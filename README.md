## Скрипт автоматической установки и удобного просмотра логов/статистики

Скрипт устанавливает и настраивает защиту на основе проекта  
[dotX12/traffic-guard](https://github.com/dotX12/traffic-guard).

Используется свой форк и форки листов без изменений на случай удаления оригинала.
[FuriousWarrior/traffic-guard](https://github.com/FuriousWarrior/traffic-guard).
После установки в любом месте достаточно выполнить:

```bash
tfgm
```

Включены в сборку листы [SKIPA](https://github.com/tread-lightly/CyberOK_Skipa_ips) по умолчанию,
возможно позже перепишу установку с выбором листов, спасибо за оригинал [DonMatteo](https://github.com/DonMatteoVPN/TrafficGuard-auto)

Команда запустит интерактивное меню с:
- текущим статусом защиты (ipset, iptables, таймеры);
- топом сканеров по количеству срабатываний;
- live‑логами IPv4/IPv6;
- возможностью обновить списки и очистить логи.

***

### Установка

#### Вариант 1: через `sudo`

```bash
curl -fsSL https://raw.githubusercontent.com/FuriousWarrior/FuriousTrafficGuard/refs/heads/main/install-trafficguard.sh | sudo bash
```


#### Вариант 2: уже под `root`

```bash
curl -fsSL https://raw.githubusercontent.com/FuriousWarrior/FuriousTrafficGuard/refs/heads/main/install-trafficguard.sh | bash
```

После успешной установки:

- для запуска меню мониторинга используйте:

```bash
tfgm
```
