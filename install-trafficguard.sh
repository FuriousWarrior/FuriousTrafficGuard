#!/bin/bash
# 🔥 TrafficGuard PRO INSTALLER v3.0 (rknpidor + AutoFix + Красивое меню)
# 1 команда = полная защита + мониторинг навсегда!

SELF_PATH="/opt/trafficguard-manager.sh"

cat > "$SELF_PATH" << 'EOF'
#!/bin/bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

INSTALL_URL="https://raw.githubusercontent.com/dotX12/traffic-guard/master/install.sh"
LIST1="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/government_networks.list"
LIST2="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/antiscanner.list"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    [[ $EUID -ne 0 ]] && { log_err "Нужен sudo/root!"; exit 1; }
}

header() {
    clear
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              🚀 TRAFFICGUARD PRO MONITOR v3.0               ║"
    echo "║                    Защита от 2523+ сетей сканеров           ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  ${CYAN}rknpidor${NC}  - запуск мониторинга везде!                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝${NC}"
}

install_deps() {
    log_info "📦 Зависимости..."
    apt update -qq >/dev/null
    apt install -y rsyslog ipset ufw curl wget procps lsof htop 2>/dev/null || true
    systemctl enable --now rsyslog 2>/dev/null || true
    log_ok "Готово"
}

install_trafficguard() {
    log_info "🔧 TrafficGuard..."
    command -v curl >/dev/null && curl -fsSL "$INSTALL_URL" | bash || wget -qO- "$INSTALL_URL" | bash
    log_ok "v0.0.2 установлен"
}

run_trafficguard() {
    log_info "🚀 Запуск защиты (2523 сети)..."
    traffic-guard full -u "$LIST1" -u "$LIST2" --enable-logging
}

smart_chown() {
    log_info "🔐 Права (Debian 12+)..."
    mkdir -p /var/log/iptables-scanners
    touch /var/log/iptables-scanners-{ipv4,ipv6}.log
    if getent group adm >/dev/null 2>&1; then
        chown syslog:adm /var/log/iptables-scanners-*.log
    else
        chown syslog:syslog /var/log/iptables-scanners-*.log
    fi
    chmod 640 /var/log/iptables-scanners-*.log
    chmod +x /usr/local/bin/antiscan-aggregate-logs.sh 2>/dev/null || true
    systemctl daemon-reload
    systemctl restart rsyslog antiscan-aggregate.timer antiscan-ipset-restore.service 2>/dev/null || true
    log_ok "Права OK"
}

check_status() {
    echo -e "\n${GREEN}✅ СТАТУС ЗАЩИТЫ${NC}"
    echo "  📊 IPSET: $(ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep 'Number of entries' | awk '{print $4}' || echo '❌')"
    echo "  🛡️  IPv6: $(ipset list SCANNERS-BLOCK-V6 2>/dev/null | grep 'Number of entries' | awk '{print $4}' || echo '❌')"
    echo "  🔥 IPv4 pkts: $(iptables -vnL SCANNERS-BLOCK 2>/dev/null | awk 'NR==2{print $1}' || echo '0')"
    echo "  ⚙️  Timer: $(systemctl is-active antiscan-aggregate.timer 2>/dev/null && echo '✅' || echo '❌')"
    echo "  📈 CSV строк: $(wc -l < /var/log/iptables-scanners-aggregate.csv 2>/dev/null || echo 1)"
}

full_install() {
    header
    install_deps
    install_trafficguard
    run_trafficguard
    smart_chown
    
    # Retry если пусто
    sleep 3
    if ! ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep -q "Number of entries: [1-9]"; then
        log_warn "Повтор запуска..."
        run_trafficguard
        smart_chown
    fi
    
    check_status
    log_ok "🎉 ТРАФИКГААРД АКТИВЕН!"
}

trap_menu() {
    echo -e "\n${YELLOW}Ctrl+C = назад в меню...${NC}"
    sleep 1
}

show_menu() {
    while true; do
        header
        check_status
        echo -e "\n${CYAN}МЕНЮ:${NC}"
        echo " ${GREEN}1.${NC} 📊 Детальный статус"
        echo " ${GREEN}2.${NC} 📈 Топ-20 сканеров"
        echo " ${GREEN}3.${NC} 🪵 LIVE IPv4 логи ${YELLOW}(Ctrl+C назад)${NC}"
        echo " ${GREEN}4.${NC} 🪵 LIVE IPv6 логи ${YELLOW}(Ctrl+C назад)${NC}"
        echo " ${GREEN}5.${NC} 🔥 LIVE ТОП каждые 5с"
        echo " ${GREEN}6.${NC} 🔄 Обновить списки"
        echo " ${GREEN}7.${NC} 🧹 Очистить логи"
        echo " ${GREEN}8.${NC} 📤 Экспорт статистики"
        echo " ${RED}0.${NC} ❌ Выход"
        echo -n "${CYAN}►${NC} "
        read -r choice
        
        case $choice in
            1) check_status; read -p $'\n'"${YELLOW}Enter...${NC}";;
            2) echo -e "\n📈 ${GREEN}ТОП СКАНЕРОВ:${NC}"; tail -20 /var/log/iptables-scanners-aggregate.csv 2>/dev/null || echo "Пока пусто..."; read -p $'\n'"Enter...";;
            3) trap '' INT; echo -e "\n🪵 ${GREEN}IPv4 логи (Ctrl+C назад)${NC}"; tail -f /var/log/iptables-scanners-ipv4.log; trap_menu; trap - INT; read -p $'\n'"Enter...";;
            4) trap '' INT; echo -e "\n🪵 ${GREEN}IPv6 логи (Ctrl+C назад)${NC}"; tail -f /var/log/iptables-scanners-ipv6.log; trap_menu; trap - INT; read -p $'\n'"Enter...";;
            5) watch -n 5 "echo '🔥 LIVE ТОП:'; tail -15 /var/log/iptables-scanners-aggregate.csv";;
            6) run_trafficguard; smart_chown; check_status; read -p $'\n'"Enter...";;
            7) > /var/log/iptables-scanners-* 2>/dev/null; log_ok "Очищено!"; read -p $'\n'"Enter...";;
            8) cp /var/log/iptables-scanners-aggregate.csv /tmp/tg-stats-$(date +%Y%m%d-%H%M).csv; log_ok "Экспорт: /tmp/tg-stats-*.csv"; read -p $'\n'"Enter...";;
            0) log_ok "До свидания! Используй: rknpidor"; exit 0;;
            *) echo -e "${RED}❌${NC}"; sleep 1;;
        esac
    done
}

check_root
case "${1:-}" in
    install|setup|-i)
        full_install
        echo -e "\n${GREEN}══════════════════════════════════════════${NC}"
        echo -e "${PURPLE}🎉 УСТАНОВКА ЗАВЕРШЕНА!${NC}"
        echo -e "${CYAN}📱 Мониторинг:${NC} ${GREEN}rknpidor${NC} ${CYAN}(везде!)${NC}"
        echo -e "${CYAN}📱 Меню:${NC} ${GREEN}sudo /opt/trafficguard-manager.sh monitor${NC}"
        echo -e "${GREEN}══════════════════════════════════════════${NC}"
        sleep 3
        show_menu
        ;;
    monitor|-m) show_menu ;;
    *) echo "Использование: $0 install | monitor"; exit 1 ;;
esac
EOF

chmod +x "$SELF_PATH"

# 🔥 ГЛОБАЛЬНЫЙ АЛИАС rknpidor
mkdir -p /etc/profile.d
cat > /etc/profile.d/rknpidor.sh << EOF
#!/bin/bash
alias rknpidor='sudo /opt/trafficguard-manager.sh monitor'
export rknpidor
EOF
chmod +x /etc/profile.d/rknpidor.sh

# Для текущей сессии
export rknpidor="sudo /opt/trafficguard-manager.sh monitor"

echo -e "${GREEN}🚀 /opt/trafficguard-manager.sh + ${CYAN}rknpidor${GREEN} (глобально!) ГОТОВЫ!${NC}"
echo -e "${PURPLE}Запуск полной установки...${NC}"
exec "$SELF_PATH" install
