#!/bin/bash
# 🔥 TrafficGuard PRO INSTALLER v11.0 (Firewall Safety & Management)
# Описание:
# - Проверка UFW перед установкой (защита от потери SSH).
# - Команды: uninstall, update.
# - Полное логирование установки.

MANAGER_PATH="/opt/trafficguard-manager.sh"
LINK_PATH="/usr/local/bin/rknpidor"

# 1. ЧИСТКА СТАРОЙ ВЕРСИИ
rm -f "$MANAGER_PATH" "$LINK_PATH"

# 2. ЗАПИСЬ НОВОГО СКРИПТА
cat > "$MANAGER_PATH" << 'EOF'
#!/bin/bash
set -u

# --- ЦВЕТА ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

TG_URL="https://raw.githubusercontent.com/dotX12/traffic-guard/master/install.sh"
LIST_GOV="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/government_networks.list"
LIST_SCAN="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/antiscanner.list"

check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}Запуск только от root!${NC}"; exit 1; }
}

# --- 🛡️ ПРОВЕРКА БЕЗОПАСНОСТИ FIREWALL ---
check_firewall_safety() {
    echo -e "${BLUE}[CHECK] Проверка конфигурации Firewall...${NC}"
    
    # 1. Проверка UFW
    if command -v ufw >/dev/null; then
        UFW_STATUS=$(ufw status | grep "Status" | awk '{print $2}')
        # Получаем список добавленных правил (даже если ufw выключен)
        UFW_RULES=$(ufw show added 2>/dev/null)
        
        # Если UFW выключен И нет правил на 22 порт (SSH)
        if [[ "$UFW_STATUS" == "inactive" ]]; then
            if [[ "$UFW_RULES" != *"22"* ]] && [[ "$UFW_RULES" != *"SSH"* ]] && [[ "$UFW_RULES" != *"OpenSSH"* ]]; then
                echo -e "\n${RED}⛔ ОПАСНОСТЬ БЛОКИРОВКИ SSH!${NC}"
                echo -e "${YELLOW}Обнаружен UFW в статусе 'inactive' без правил для SSH.${NC}"
                echo "Если продолжить, firewall может включиться и заблокировать ваш доступ к серверу."
                echo ""
                echo -e "РЕШЕНИЕ: Выполните команду: ${GREEN}ufw allow ssh${NC} и запустите установку снова."
                echo ""
                exit 1
            fi
        fi
        echo -e "${GREEN}[OK] UFW корректен (или активен с правилами).${NC}"
    else
        # 2. Если UFW нет, проверяем iptables-persistent
        echo -e "${YELLOW}[INFO] UFW не найден. Проверяем iptables-persistent...${NC}"
        if ! dpkg -l | grep -q netfilter-persistent; then
            echo -e "${CYAN}Устанавливаем iptables-persistent (стандартное поведение)...${NC}"
            apt-get update -qq && apt-get install -y iptables-persistent netfilter-persistent
        fi
    fi
}

# --- 🗑️ УДАЛЕНИЕ ---
uninstall_process() {
    echo -e "\n${RED}=== УДАЛЕНИЕ TRAFFICGUARD ===${NC}"
    read -p "Вы уверены? (y/N): " confirm
    [[ "$confirm" != "y" ]] && return

    echo "Остановка сервисов..."
    systemctl stop antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null
    systemctl disable antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null
    
    echo "Удаление файлов..."
    rm -f /usr/local/bin/traffic-guard
    rm -f /usr/local/bin/antiscan-aggregate-logs.sh
    rm -f /etc/systemd/system/antiscan-*
    rm -f /etc/rsyslog.d/10-iptables-scanners.conf
    rm -f /etc/logrotate.d/iptables-scanners
    rm -f /usr/local/bin/rknpidor
    rm -f /opt/trafficguard-manager.sh
    
    echo "Очистка правил..."
    ipset destroy SCANNERS-BLOCK-V4 2>/dev/null
    ipset destroy SCANNERS-BLOCK-V6 2>/dev/null
    # Очищаем цепочки (упрощенно, полная чистка iptables может быть опасной, удаляем только ссылки)
    iptables -D INPUT -j SCANNERS-BLOCK 2>/dev/null
    iptables -F SCANNERS-BLOCK 2>/dev/null
    iptables -X SCANNERS-BLOCK 2>/dev/null
    
    systemctl restart rsyslog
    systemctl daemon-reload
    
    echo -e "${GREEN}✅ TrafficGuard полностью удален.${NC}"
    exit 0
}

# --- 🔄 ОБНОВЛЕНИЕ СПИСКОВ ---
update_lists() {
    echo -e "\n${CYAN}🔄 Обновление списков блокировки...${NC}"
    traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging
    echo -e "${GREEN}✅ Списки обновлены!${NC}"
    sleep 2
}

# --- 🧪 ТЕСТ БЛОКИРОВКИ ---
test_blocking() {
    echo -e "\n${YELLOW}=== 🧪 ТЕСТ БЛОКИРОВКИ ===${NC}"
    read -p "Введите IP для бана (тест): " test_ip
    [[ -z "$test_ip" ]] && return

    if ipset add SCANNERS-BLOCK-V4 "$test_ip" 2>/dev/null; then
        echo -e "${GREEN}✅ IP $test_ip добавлен в бан! Проверяйте пинг.${NC}"
    else
        echo -e "${RED}❌ Ошибка добавления (возможно уже в бане).${NC}"
    fi
    read -p "[Enter] назад..."
}

# --- 📦 УСТАНОВКА ---
install_process() {
    trap 'exit 1' INT
    clear
    echo -e "${CYAN}🚀 УСТАНОВКА TRAFFICGUARD PRO${NC}"
    
    # 1. ПРОВЕРКА FIREWALL (CRITICAL)
    check_firewall_safety
    
    # 2. Зависимости
    echo -e "\n${BLUE}[INFO] Установка зависимостей...${NC}"
    apt-get update
    apt-get install -y curl wget rsyslog ipset ufw grep sed coreutils whois
    systemctl enable --now rsyslog

    # 3. Скачивание
    echo -e "\n${BLUE}[INFO] Скачивание бинарника...${NC}"
    if command -v curl >/dev/null; then curl -fsSL "$TG_URL" | bash; else wget -qO- "$TG_URL" | bash; fi

    # 4. Запуск
    echo -e "\n${BLUE}[INFO] Применение правил...${NC}"
    traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging

    # 5. Проверка успеха
    if [ $? -ne 0 ]; then
        echo -e "\n${RED}❌ ОШИБКА! TrafficGuard не смог применить правила.${NC}"
        echo "Смотрите вывод выше (скорее всего проблема в UFW/Iptables)."
        exit 1
    fi

    # 6. Фиксы
    echo -e "\n${BLUE}[INFO] Настройка логов...${NC}"
    mkdir -p /var/log
    touch /var/log/iptables-scanners-{ipv4,ipv6}.log
    LOG_GROUP="syslog"; getent group adm >/dev/null && LOG_GROUP="adm"
    chown syslog:$LOG_GROUP /var/log/iptables-scanners-*.log
    chmod 640 /var/log/iptables-scanners-*.log
    
    systemctl restart rsyslog
    systemctl restart antiscan-aggregate.service 2>/dev/null || true
    systemctl restart antiscan-aggregate.timer
    
    echo -e "\n${GREEN}✅ Установка завершена успешно!${NC}"
    sleep 2
}

# --- 📊 МЕНЮ ---
view_log() {
    local file=$1
    echo -e "\n${YELLOW}=== LIVE LOG (Ctrl+C для возврата) ===${NC}"
    trap ':' INT
    tail -f "$file"
    trap 'exit 0' INT
}

show_menu() {
    trap 'exit 0' INT
    while true; do
        clear
        IPSET_CNT=$(ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep "Number of entries" | awk '{print $4}')
        [[ -z "$IPSET_CNT" ]] && IPSET_CNT="${RED}0${NC}"
        PKTS_CNT=$(iptables -vnL SCANNERS-BLOCK 2>/dev/null | grep "LOG" | awk '{print $1}')
        [[ -z "$PKTS_CNT" ]] && PKTS_CNT="0"
        
        echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║           🛡️  TRAFFICGUARD PRO MANAGER              ║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
        echo -e "║  📊 Подсетей:       ${GREEN}${IPSET_CNT}${NC}                             "
        echo -e "║  🔥 Атак отбито:    ${RED}${PKTS_CNT}${NC}                             "
        echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e " ${GREEN}1.${NC} 📈 Топ атак (CSV)"
        echo -e " ${GREEN}2.${NC} 🪵 Логи IPv4 (Live)"
        echo -e " ${GREEN}3.${NC} 🪵 Логи IPv6 (Live)"
        echo -e " ${GREEN}4.${NC} 🧪 Тест блокировки IP"
        echo -e " ${GREEN}5.${NC} 🔄 Обновить списки (Update)"
        echo -e " ${GREEN}6.${NC} 🛠️  Переустановить (Reinstall)"
        echo -e " ${RED}7.${NC} 🗑️  Удалить (Uninstall)"
        echo -e " ${RED}0.${NC} ❌ Выход"
        echo ""
        
        echo -ne "${CYAN}👉 Ваш выбор:${NC} "
        read -r choice < /dev/tty

        case $choice in
            1)
                echo -e "\n${GREEN}ТОП 20:${NC}"
                [ -f /var/log/iptables-scanners-aggregate.csv ] && tail -20 /var/log/iptables-scanners-aggregate.csv || echo "Нет данных"
                read -p $'\n[Enter] назад...' < /dev/tty
                ;;
            2) view_log "/var/log/iptables-scanners-ipv4.log" ;;
            3) view_log "/var/log/iptables-scanners-ipv6.log" ;;
            4) test_blocking ;;
            5) update_lists ;;
            6) 
                rm -f /var/log/iptables-scanners-aggregate.csv
                install_process 
                ;;
            7) uninstall_process ;;
            0) exit 0 ;;
            *) echo "Неверно"; sleep 1 ;;
        esac
    done
}

# --- 🚀 ЗАПУСК ---
check_root

case "${1:-}" in
    install) install_process ;;
    monitor) show_menu ;;
    update) update_lists ;;
    uninstall) uninstall_process ;;
    *) show_menu ;; 
esac
EOF

chmod +x "$MANAGER_PATH"
ln -s "$MANAGER_PATH" "$LINK_PATH"

# ПЕРВЫЙ ЗАПУСК
if [[ ! -f /usr/local/bin/traffic-guard ]]; then
    /opt/trafficguard-manager.sh install
fi

/opt/trafficguard-manager.sh monitor
