#!/bin/bash
# 🔥 TrafficGuard PRO INSTALLER v5.0 (Ctrl+C Fix & Launcher)
# Описание: Исправлен выход по Ctrl+C и добавлено стартовое меню.

MANAGER_PATH="/opt/trafficguard-manager.sh"

# ==============================================================================
# 1. СОЗДАНИЕ СКРИПТА УПРАВЛЕНИЯ
# ==============================================================================
cat > "$MANAGER_PATH" << 'EOF'
#!/bin/bash
set -u

# --- ЦВЕТА ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
TG_URL="https://raw.githubusercontent.com/dotX12/traffic-guard/master/install.sh"
LIST_GOV="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/government_networks.list"
LIST_SCAN="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/antiscanner.list"

# --- ПРОВЕРКИ ---
check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}Нужен sudo!${NC}"; exit 1; }
}

# --- УСТАНОВКА ---
install_process() {
    clear
    echo -e "${CYAN}📦 Установка компонентов...${NC}"
    apt-get update -qq >/dev/null
    apt-get install -y curl wget rsyslog ipset ufw grep sed coreutils >/dev/null 2>&1
    systemctl enable --now rsyslog >/dev/null 2>&1

    echo -e "${CYAN}🔧 TrafficGuard...${NC}"
    if command -v curl >/dev/null; then curl -fsSL "$TG_URL" | bash; else wget -qO- "$TG_URL" | bash; fi

    echo -e "${CYAN}🛡️ Загрузка правил (это быстро)...${NC}"
    traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging >/dev/null

    # FIX ПРАВ
    mkdir -p /var/log
    touch /var/log/iptables-scanners-{ipv4,ipv6}.log
    LOG_GROUP="syslog"; getent group adm >/dev/null && LOG_GROUP="adm"
    chown syslog:$LOG_GROUP /var/log/iptables-scanners-*.log
    chmod 640 /var/log/iptables-scanners-*.log
    systemctl restart rsyslog
    
    echo -e "${GREEN}✅ Готово!${NC}"
    sleep 1
}

# --- ФУНКЦИЯ ПРОСМОТРА ЛОГОВ (БЕЗОПАСНАЯ) ---
view_log() {
    local file=$1
    echo -e "\n${YELLOW}=== РЕЖИМ ПРОСМОТРА (Нажмите Ctrl+C для возврата) ===${NC}"
    
    # 1. Разрешаем прерывание (SIGINT) для tail
    trap - INT
    
    # 2. Запускаем tail (он заблокирует скрипт, пока работает)
    tail -f "$file"
    
    # 3. Как только нажали Ctrl+C, tail умирает, и мы попадаем сюда:
    echo -e "\n${CYAN}Возврат в меню...${NC}"
    sleep 1
    
    # 4. Возвращаем игнор прерывания для самого меню
    trap '' INT
}

# --- МЕНЮ МОНИТОРИНГА ---
show_menu() {
    # Глобально в меню ИГНОРИРУЕМ Ctrl+C (чтобы не вылетал скрипт)
    trap '' INT

    while true; do
        clear
        # Статистика
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
        echo -e " ${GREEN}2.${NC} 🪵 Логи IPv4 (Live)"
        echo -e " ${GREEN}3.${NC} 🪵 Логи IPv6 (Live)"
        echo -e " ${GREEN}4.${NC} 🔄 Обновить базы"
        echo -e " ${GREEN}5.${NC} 🛠️  Переустановить"
        echo -e " ${RED}0.${NC} ❌ Выход"
        echo ""
        
        read -p "👉 Ваш выбор: " choice

        case $choice in
            1)
                echo -e "\n${GREEN}ТОП 20:${NC}"
                [ -f /var/log/iptables-scanners-aggregate.csv ] && tail -20 /var/log/iptables-scanners-aggregate.csv || echo "Нет данных"
                read -p $'\n[Enter] назад...'
                ;;
            2) view_log "/var/log/iptables-scanners-ipv4.log" ;;
            3) view_log "/var/log/iptables-scanners-ipv6.log" ;;
            4) traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging; echo "OK"; sleep 1 ;;
            5) install_process ;;
            0) exit 0 ;;
            *) echo "Неверно"; sleep 1 ;;
        esac
    done
}

# --- МИНИ-МЕНЮ ЗАПУСКА (ЕСЛИ НЕТ АРГУМЕНТОВ) ---
show_launcher() {
    clear
    echo -e "${CYAN}🚀 TRAFFICGUARD LAUNCHER${NC}"
    echo "1. Запустить мониторинг"
    echo "2. Установить / Переустановить"
    echo "0. Выход"
    echo ""
    read -p "Выбор: " lchoice
    case $lchoice in
        1) show_menu ;;
        2) install_process; show_menu ;;
        0) exit 0 ;;
        *) show_menu ;; # По дефолту монитор
    esac
}

# --- ТОЧКА ВХОДА ---
check_root

case "${1:-}" in
    install) install_process ;;
    monitor) show_menu ;;
    *) show_launcher ;; 
esac
EOF

chmod +x "$MANAGER_PATH"

# Обновляем symlink
rm -f /usr/local/bin/rknpidor
ln -s "$MANAGER_PATH" /usr/local/bin/rknpidor

# ЛОГИКА ПЕРВОГО ЗАПУСКА
# Если скрипт запущен через pipe (curl | bash) и без аргументов install/monitor,
# мы делаем тихую установку и сразу открываем монитор.
if [[ -z "${1:-}" ]]; then
    echo -e "${GREEN}✅ Скрипт обновлен!${NC}"
    echo -e "Теперь введите команду: ${CYAN}rknpidor${NC}"
    echo -e "Или используйте меню ниже:"
    sleep 1
    # При первом запуске curl сразу кидаем в установку, потом в меню
    if [[ ! -f /usr/local/bin/traffic-guard ]]; then
        /opt/trafficguard-manager.sh install
    fi
    /opt/trafficguard-manager.sh monitor
else
    # Если вызван rknpidor install
    /opt/trafficguard-manager.sh "$1"
fi
