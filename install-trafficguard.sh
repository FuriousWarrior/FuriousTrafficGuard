#!/bin/bash
# 🔥 TrafficGuard PRO INSTALLER v13.0 (Ban/Unban Feature)
# Описание:
# - Меню "Тест блокировки" заменено на "Управление IP".
# - Добавлена возможность удалять (разбанивать) IP из списка.

MANAGER_PATH="/opt/trafficguard-manager.sh"
LINK_PATH="/usr/local/bin/rknpidor"

rm -f "$MANAGER_PATH" "$LINK_PATH"

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

check_firewall_safety() {
    # (Код проверки Firewall без изменений из v12.0)
    echo -e "${BLUE}[CHECK] Проверка конфигурации Firewall...${NC}"
    if command -v ufw >/dev/null; then
        UFW_STATUS=$(ufw status | grep "Status" | awk '{print $2}')
        UFW_RULES=$(ufw show added 2>/dev/null)
        if [[ "$UFW_STATUS" == "inactive" ]]; then
            if [[ "$UFW_RULES" != *"22"* ]] && [[ "$UFW_RULES" != *"SSH"* ]] && [[ "$UFW_RULES" != *"OpenSSH"* ]]; then
                echo -e "\n${RED}⛔ АВАРИЙНАЯ ОСТАНОВКА!${NC}"
                echo -e "${YELLOW}UFW выключен и нет правил SSH.${NC}"
                echo "Выполните: ufw allow ssh"
                exit 1
            fi
        fi
    else
        if ! dpkg -l | grep -q netfilter-persistent; then
            echo -e "${CYAN}Устанавливаем iptables-persistent...${NC}"
            DEBIAN_FRONTEND=noninteractive apt-get update -qq && \
            DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent netfilter-persistent
        fi
    fi
}

uninstall_process() {
    echo -e "\n${RED}=== УДАЛЕНИЕ TRAFFICGUARD ===${NC}"
    read -p "Вы уверены? (y/N): " confirm < /dev/tty
    [[ "$confirm" != "y" ]] && return

    systemctl stop antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null
    systemctl disable antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null
    
    rm -f /usr/local/bin/traffic-guard /usr/local/bin/antiscan-aggregate-logs.sh
    rm -f /etc/systemd/system/antiscan-* /etc/rsyslog.d/10-iptables-scanners.conf /etc/logrotate.d/iptables-scanners
    rm -f /usr/local/bin/rknpidor /opt/trafficguard-manager.sh
    
    iptables -D INPUT -j SCANNERS-BLOCK 2>/dev/null
    iptables -F SCANNERS-BLOCK 2>/dev/null
    iptables -X SCANNERS-BLOCK 2>/dev/null
    
    ipset flush SCANNERS-BLOCK-V4 2>/dev/null
    ipset destroy SCANNERS-BLOCK-V4 2>/dev/null
    ipset flush SCANNERS-BLOCK-V6 2>/dev/null
    ipset destroy SCANNERS-BLOCK-V6 2>/dev/null
    
    systemctl restart rsyslog
    echo -e "${GREEN}✅ Удалено.${NC}"
    exit 0
}

# --- 🧪 УПРАВЛЕНИЕ IP (BAN/UNBAN) ---
manage_test_ip() {
    while true; do
        clear
        echo -e "${YELLOW}=== 🧪 УПРАВЛЕНИЕ IP (Ручной режим) ===${NC}"
        echo "Здесь можно вручную добавить IP в бан или убрать его."
        echo ""
        echo -e " ${RED}1.${NC} ⛔ ЗАБАНИТЬ IP (Add)"
        echo -e " ${GREEN}2.${NC} ✅ РАЗБАНИТЬ IP (Delete)"
        echo -e " ${CYAN}0.${NC} ↩️  Назад в меню"
        echo ""
        echo -ne "${YELLOW}👉 Действие:${NC} "
        read -r action < /dev/tty

        case $action in
            1)
                echo -e "\nВведите IP для БЛОКИРОВКИ:"
                read -p "IP: " ip < /dev/tty
                [[ -z "$ip" ]] && continue
                
                OUTPUT=$(ipset add SCANNERS-BLOCK-V4 "$ip" 2>&1)
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✅ IP $ip ЗАБЛОКИРОВАН!${NC}"
                else
                    echo -e "${RED}❌ Ошибка:${NC} $OUTPUT"
                fi
                read -p "[Enter] продолжить..." < /dev/tty
                ;;
            2)
                echo -e "\nВведите IP для РАЗБЛОКИРОВКИ:"
                read -p "IP: " ip < /dev/tty
                [[ -z "$ip" ]] && continue
                
                OUTPUT=$(ipset del SCANNERS-BLOCK-V4 "$ip" 2>&1)
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✅ IP $ip РАЗБЛОКИРОВАН (Удален из списка)!${NC}"
                else
                    echo -e "${RED}❌ Ошибка:${NC} $OUTPUT (Возможно IP не был в списке)"
                fi
                read -p "[Enter] продолжить..." < /dev/tty
                ;;
            0) return ;;
            *) ;;
        esac
    done
}

update_lists() {
    echo -e "\n${CYAN}🔄 Обновление списков...${NC}"
    traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging
    echo -e "${GREEN}✅ Готово!${NC}"
    sleep 2
}

install_process() {
    trap 'exit 1' INT
    clear
    echo -e "${CYAN}🚀 УСТАНОВКА TRAFFICGUARD PRO${NC}"
    check_firewall_safety
    
    echo -e "\n${BLUE}[INFO] Установка...${NC}"
    apt-get update
    apt-get install -y curl wget rsyslog ipset ufw grep sed coreutils whois
    systemctl enable --now rsyslog

    if command -v curl >/dev/null; then curl -fsSL "$TG_URL" | bash; else wget -qO- "$TG_URL" | bash; fi

    echo -e "\n${BLUE}[INFO] Настройка правил...${NC}"
    traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging

    if [ $? -ne 0 ]; then
        echo -e "\n${RED}❌ ОШИБКА УСТАНОВКИ!${NC}"
        exit 1
    fi

    mkdir -p /var/log
    touch /var/log/iptables-scanners-{ipv4,ipv6}.log
    LOG_GROUP="syslog"; getent group adm >/dev/null && LOG_GROUP="adm"
    chown syslog:$LOG_GROUP /var/log/iptables-scanners-*.log
    chmod 640 /var/log/iptables-scanners-*.log
    
    systemctl restart rsyslog
    systemctl restart antiscan-aggregate.service 2>/dev/null || true
    systemctl restart antiscan-aggregate.timer
    
    echo -e "\n${GREEN}✅ Установка завершена!${NC}"
    sleep 2
}

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
        echo -e " ${GREEN}4.${NC} 🧪 Управление IP (Ban/Unban)"
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
            4) manage_test_ip ;;
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

if [[ ! -f /usr/local/bin/traffic-guard ]]; then
    /opt/trafficguard-manager.sh install
fi

/opt/trafficguard-manager.sh monitor
