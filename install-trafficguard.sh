#!/bin/bash
# 🔥 TrafficGuard PRO INSTALLER v4.1 (Stable Menu Fix)
# Описание: Фикс мигания меню. Статистика обновляется только при входе в меню.

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

# --- ФУНКЦИИ ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Запустите через sudo!${NC}"
        exit 1
    fi
}

install_process() {
    clear
    log_info "Установка зависимостей..."
    apt-get update -qq >/dev/null
    apt-get install -y curl wget rsyslog ipset ufw grep sed coreutils >/dev/null 2>&1
    systemctl enable --now rsyslog >/dev/null 2>&1

    log_info "Установка TrafficGuard..."
    if command -v curl >/dev/null; then
        curl -fsSL "$TG_URL" | bash
    else
        wget -qO- "$TG_URL" | bash
    fi

    log_info "Загрузка правил..."
    traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging

    log_info "Настройка прав..."
    mkdir -p /var/log
    touch /var/log/iptables-scanners-{ipv4,ipv6}.log
    
    # Smart group detection
    LOG_GROUP="syslog"
    getent group adm >/dev/null && LOG_GROUP="adm"
    
    chown syslog:$LOG_GROUP /var/log/iptables-scanners-*.log
    chmod 640 /var/log/iptables-scanners-*.log
    systemctl restart rsyslog
    
    log_ok "Готово!"
}

# --- МЕНЮ (ИСПРАВЛЕННОЕ) ---
show_menu() {
    # Блокируем Ctrl+C чтобы не вылетало, а просто перезагружало цикл
    trap '' INT

    while true; do
        clear
        
        # 1. Сбор статистики (только при отрисовке)
        IPSET_CNT=$(ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep "Number of entries" | awk '{print $4}')
        [[ -z "$IPSET_CNT" ]] && IPSET_CNT="${RED}0${NC}"
        
        PKTS_CNT=$(iptables -vnL SCANNERS-BLOCK 2>/dev/null | grep "LOG" | awk '{print $1}')
        [[ -z "$PKTS_CNT" ]] && PKTS_CNT="0"

        RSYSLOG_STATUS=$(systemctl is-active rsyslog >/dev/null && echo "${GREEN}OK${NC}" || echo "${RED}FAIL${NC}")

        # 2. Отрисовка
        echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║           🛡️  TRAFFICGUARD PRO MONITOR              ║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
        echo -e "║  📊 В базе (IPv4):   ${GREEN}${IPSET_CNT}${NC} подсетей              "
        echo -e "║  🔥 Отбито атак:     ${RED}${PKTS_CNT}${NC} пакетов               "
        echo -e "║  ⚙️  Статус rsyslog:  ${RSYSLOG_STATUS}                 "
        echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e " ${GREEN}1.${NC} 📈 Топ сканеров (таблица)"
        echo -e " ${GREEN}2.${NC} 🪵 Логи IPv4 (Live) ${YELLOW}[Ctrl+C = назад]${NC}"
        echo -e " ${GREEN}3.${NC} 🪵 Логи IPv6 (Live) ${YELLOW}[Ctrl+C = назад]${NC}"
        echo -e " ${GREEN}4.${NC} 🔄 Обновить базы блокировок"
        echo -e " ${GREEN}5.${NC} 🛠️  Переустановить"
        echo -e " ${RED}0.${NC} ❌ Выход"
        echo ""
        
        # 3. Ожидание ввода (БЛОКИРУЮЩЕЕ - не мигает)
        read -p "👉 Ваш выбор: " choice

        # 4. Обработка
        case $choice in
            1)
                echo -e "\n${GREEN}=== ТОП АКТИВНОСТИ ===${NC}"
                if [ -s /var/log/iptables-scanners-aggregate.csv ]; then
                    tail -20 /var/log/iptables-scanners-aggregate.csv
                else
                    echo "Нет данных (подождите 5-10 мин)..."
                fi
                read -p $'\n[Нажмите Enter для возврата]'
                ;;
            2)
                echo -e "\nLOGS V4 (Нажмите Ctrl+C для выхода)..."
                # Включаем обработку INT только для tail
                trap 'break' INT
                tail -f /var/log/iptables-scanners-ipv4.log
                # Возвращаем игнор INT для меню
                trap '' INT
                ;;
            3)
                echo -e "\nLOGS V6 (Нажмите Ctrl+C для выхода)..."
                trap 'break' INT
                tail -f /var/log/iptables-scanners-ipv6.log
                trap '' INT
                ;;
            4)
                echo -e "\nОбновление..."
                traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging
                log_ok "Готово"
                sleep 2
                ;;
            5)
                install_process
                read -p "Enter..."
                ;;
            0)
                echo "Выход."
                exit 0
                ;;
            *)
                echo -e "${RED}Неверный выбор!${NC}"
                sleep 1
                ;;
        esac
    done
}

check_root
case "${1:-}" in
    install) install_process ;;
    monitor) show_menu ;;
    *) echo "Usage: $0 {install|monitor}" ;;
esac
EOF

chmod +x "$MANAGER_PATH"

# Обновляем symlink
rm -f /usr/local/bin/rknpidor
ln -s "$MANAGER_PATH" /usr/local/bin/rknpidor

# Запуск
if [[ "${1:-}" == "install" ]]; then
    rknpidor install
    echo -e "\n${GREEN}Установка завершена!${NC}"
    sleep 2
    rknpidor monitor
else
    # Если запустили через curl без аргументов, считаем это переустановкой менеджера
    echo -e "${GREEN}✅ Менеджер обновлен!${NC}"
    echo -e "Запустите команду: ${CYAN}rknpidor${NC}"
fi
