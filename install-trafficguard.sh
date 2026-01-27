#!/bin/bash
# 🎯 TrafficGuard SELF-INSTALLER (Автоустановка + запуск)
# Сохраняет себя, chmod, запускает install автоматически!

SELF_PATH="/opt/trafficguard-manager.sh"

# Создаём себя в /opt
cat > "$SELF_PATH" << 'EOF'
#!/bin/bash

# 🎯 TrafficGuard Auto-Installer + Monitor (Интерактивный)
# Устанавливает, фиксит ошибки, мониторит логи

set -euo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# URL'ы
INSTALL_URL="https://raw.githubusercontent.com/dotX12/traffic-guard/master/install.sh"
LIST1="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/government_networks.list"
LIST2="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/antiscanner.list"

# Функции
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_err "Запуск от root/sudo обязателен!"
        exit 1
    fi
}

install_trafficguard() {
    log_info "🔧 Установка TrafficGuard..."
    if command -v curl >/dev/null; then
        curl -fsSL "$INSTALL_URL" | bash
    else
        wget -qO- "$INSTALL_URL" | bash
    fi
    log_ok "TrafficGuard установлен"
}

install_deps() {
    log_info "📦 Установка зависимостей..."
    apt update -qq
    apt install -y rsyslog ipset ufw curl wget
    systemctl enable --now rsyslog
    log_ok "Зависимости установлены"
}

run_trafficguard() {
    local cmd="traffic-guard full -u $LIST1 -u $LIST2 --enable-logging"
    log_info "🚀 Запуск: $cmd"
    $cmd
}

fix_permissions() {
    log_info "🔧 Фикс прав..."
    touch /var/log/iptables-scanners-{ipv4,ipv6}.log
    chown syslog:adm /var/log/iptables-scanners-*.log
    chmod 640 /var/log/iptables-scanners-*.log
    chmod +x /usr/local/bin/antiscan-aggregate-logs.sh 2>/dev/null || true
    systemctl daemon-reload
    systemctl restart rsyslog antiscan-aggregate.timer 2>/dev/null || true
    log_ok "Права исправлены"
}

check_status() {
    echo -e "\n${GREEN}✅ СТАТУС${NC}\n"
    echo "📊 IPSET:"
    ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep -E "(Number|Members)" | head -3 || echo "❌ V4 отсутствует"
    ipset list SCANNERS-BLOCK-V6 2>/dev/null | grep "Number" || echo "❌ V6 отсутствует"
    
    echo -e "\n🔥 Iptables:"
    iptables -vnL SCANNERS-BLOCK 2>/dev/null | head -4 || echo "❌ Цепочка отсутствует"
    
    echo -e "\n⚙️ Systemd:"
    systemctl is-active antiscan-aggregate.timer >/dev/null && echo "✅ Timer OK" || echo "❌ Timer FAIL"
    
    echo -e "\n📈 Логи:"
    ls -la /var/log/iptables-scanners* 2>/dev/null || echo "❌ Файлы отсутствуют"
    echo "CSV: $(wc -l < /var/log/iptables-scanners-aggregate.csv 2>/dev/null || echo 0) строк"
}

full_install() {
    log_info "🎯 ПОЛНАЯ УСТАНОВКА"
    install_deps
    install_trafficguard
    run_trafficguard
    sleep 2
    fix_permissions
    
    if ! ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep -q "Number of entries: [1-9]"; then
        log_warn "IPSET пустой, повтор..."
        run_trafficguard
        fix_permissions
    fi
    
    check_status
    log_ok "✅ ГОТОВО!"
}

show_menu() {
    while true; do
        clear
        echo -e "${GREEN}🚀 TrafficGuard Monitor${NC}"
        echo "======================"
        echo "1. 📊 Статус"
        echo "2. 📈 Топ сканеров"
        echo "3. 🪵 Логи IPv4"
        echo "4. 🪵 Логи IPv6"
        echo "5. 🔥 LIVE топ"
        echo "6. 🔄 Обновить"
        echo "7. 🧹 Очистить"
        echo "8. ❌ Выход"
        echo -n "► "
        read -r choice
        
        case $choice in
            1) check_status; read -p "Enter..." ;;
            2) tail -20 /var/log/iptables-scanners-aggregate.csv 2>/dev/null || echo "Пусто"; read -p "Enter..." ;;
            3) tail -f /var/log/iptables-scanners-ipv4.log ;;
            4) tail -f /var/log/iptables-scanners-ipv6.log ;;
            5) watch -n 5 "tail -15 /var/log/iptables-scanners-aggregate.csv" ;;
            6) run_trafficguard; fix_permissions; check_status; read -p "Enter..." ;;
            7) > /var/log/iptables-scanners-*; log_ok "Очищено"; read -p "Enter..." ;;
            8) exit 0 ;;
            *) echo "❌"; sleep 1 ;;
        esac
    done
}

check_root
case "${1:-}" in
    install|setup|-i)
        full_install
        echo -e "\n${GREEN}🎉 Мониторинг...${NC}"
        sleep 2
        show_menu
        ;;
    monitor|-m)
        check_status
        show_menu
        ;;
    *)
        echo "Использование: $0 install | monitor"
        exit 1
        ;;
esac
EOF

chmod +x "$SELF_PATH"

echo -e "${GREEN}🎉 СКРИПТ СОЗДАН В /opt/trafficguard-manager.sh${NC}"
echo -e "${BLUE}Запуск установки...${NC}"
exec "$SELF_PATH" install
