#!/bin/bash
# 🔥 TrafficGuard PRO INSTALLER v9.0 (Added whois support)
# Описание: Добавлен пакет whois для корректного определения ASN/Netname в логах.

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

install_process() {
    trap 'exit 1' INT
    clear
    echo -e "${CYAN}♻️  Обновление компонентов...${NC}"
    
    # 1. Установка зависимостей (Добавлен WHOIS)
    apt-get update -qq >/dev/null
    # whois нужен для определения ASN и имени сети в логах
    apt-get install -y curl wget rsyslog ipset ufw grep sed coreutils whois >/dev/null 2>&1
    systemctl enable --now rsyslog >/dev/null 2>&1

    echo -e "${CYAN}⬇️  Скачивание TrafficGuard...${NC}"
    if command -v curl >/dev/null; then curl -fsSL "$TG_URL" | bash; else wget -qO- "$TG_URL" | bash; fi

    echo -e "${CYAN}🛡️  Загрузка баз блокировки...${NC}"
    traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging >/dev/null

    # Настройка логов и прав
    mkdir -p /var/log
    touch /var/log/iptables-scanners-{ipv4,ipv6}.log
    LOG_GROUP="syslog"; getent group adm >/dev/null && LOG_GROUP="adm"
    chown syslog:$LOG_GROUP /var/log/iptables-scanners-*.log
    chmod 640 /var/log/iptables-scanners-*.log
    systemctl restart rsyslog
    
    echo -e "${GREEN}✅ Система обновлена! (whois установлен)${NC}"
    sleep 1
}

view_log() {
    local file=$1
    echo -e "\n${YELLOW}=== LIVE LOG (Нажмите Ctrl+C для возврата в меню) ===${NC}"
    trap ':' INT
    tail -f "$file"
    echo -e "\n${CYAN}🔄 Возврат в меню...${NC}"
    sleep 1
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
        RSYSLOG=$(systemctl is-active rsyslog >/dev/null && echo "${GREEN}OK${NC}" || echo "${RED}FAIL${NC}")

        echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║           🛡️  TRAFFICGUARD PRO MONITOR              ║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
        echo -e "║  📊 В базе (IPv4):   ${GREEN}${IPSET_CNT}${NC} подсетей              "
        echo -e "║  🔥 Отбито атак:     ${RED}${PKTS_CNT}${NC} пакетов               "
        echo -e "║  ⚙️  Статус rsyslog:  ${RSYSLOG}                 "
        echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e " ${GREEN}1.${NC} 📈 Топ сканеров"
        echo -e " ${GREEN}2.${NC} 🪵 Логи IPv4 (Live) ${YELLOW}[Ctrl+C = Назад]${NC}"
        echo -e " ${GREEN}3.${NC} 🪵 Логи IPv6 (Live) ${YELLOW}[Ctrl+C = Назад]${NC}"
        echo -e " ${GREEN}4.${NC} 🔄 Обновить базы"
        echo -e " ${GREEN}5.${NC} 🛠️  Переустановить"
        echo -e " ${RED}0.${NC} ❌ Выход ${YELLOW}[или Ctrl+C]${NC}"
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
            4) 
                traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging
                echo -e "${GREEN}Обновлено!${NC}"
                sleep 2 
                ;;
            5) install_process ;;
            0) exit 0 ;;
            *) echo "Неверный выбор"; sleep 1 ;;
        esac
    done
}

check_root
case "${1:-}" in
    install) install_process ;;
    monitor) show_menu ;;
    *) show_menu ;; 
esac
EOF

chmod +x "$MANAGER_PATH"
ln -s "$MANAGER_PATH" "$LINK_PATH"

if [[ ! -f /usr/local/bin/traffic-guard ]]; then
    /opt/trafficguard-manager.sh install
fi

/opt/trafficguard-manager.sh monitor
