#!/bin/bash
# 🔥 TrafficGuard PRO INSTALLER v4.0 (Final Stable)
# Автор: DonMatteo | Fixes: Gemini
# Описание: Полная автоустановка, автофикс прав, красивое меню, мгновенный доступ.

# Путь установки
MANAGER_PATH="/opt/trafficguard-manager.sh"

# ==============================================================================
# 1. СОЗДАНИЕ ОСНОВНОГО СКРИПТА УПРАВЛЕНИЯ
# ==============================================================================
cat > "$MANAGER_PATH" << 'EOF'
#!/bin/bash
set -u

# --- ЦВЕТА И ПЕРЕМЕННЫЕ ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
TG_URL="https://raw.githubusercontent.com/dotX12/traffic-guard/master/install.sh"
LIST_GOV="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/government_networks.list"
LIST_SCAN="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/antiscanner.list"

# --- ФУНКЦИИ ЛОГИРОВАНИЯ ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- ФУНКЦИИ СИСТЕМЫ ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_err "Запустите через sudo!"
        exit 1
    fi
}

# --- УСТАНОВКА ---
install_process() {
    clear
    echo -e "${CYAN}🚀 НАЧАЛО УСТАНОВКИ TRAFFICGUARD...${NC}"
    
    log_info "Установка зависимостей..."
    apt-get update -qq >/dev/null
    apt-get install -y curl wget rsyslog ipset ufw grep sed coreutils >/dev/null 2>&1
    systemctl enable --now rsyslog >/dev/null 2>&1
    log_ok "Зависимости готовы"

    log_info "Установка TrafficGuard..."
    if command -v curl >/dev/null; then
        curl -fsSL "$TG_URL" | bash
    else
        wget -qO- "$TG_URL" | bash
    fi

    log_info "Применение правил блокировки (2500+ сетей)..."
    traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging

    # --- AUTO FIX (ИСПРАВЛЕНИЕ ОШИБОК) ---
    log_info "🔧 Авто-исправление прав и конфигураций..."
    
    # 1. Создаем файлы логов, если нет
    mkdir -p /var/log
    touch /var/log/iptables-scanners-ipv4.log
    touch /var/log/iptables-scanners-ipv6.log
    
    # 2. Умное определение группы (Fix для Debian 12)
    LOG_GROUP="syslog"
    if getent group adm >/dev/null; then
        LOG_GROUP="adm"
    fi
    chown syslog:$LOG_GROUP /var/log/iptables-scanners-*.log
    chmod 640 /var/log/iptables-scanners-*.log
    
    # 3. Перезапуск служб
    systemctl restart rsyslog
    systemctl restart antiscan-aggregate.timer 2>/dev/null || true
    
    # 4. Проверка на пустой ipset (Retry logic)
    sleep 2
    if ! ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep -q "Number of entries"; then
        echo -e "${YELLOW}⚠️ IPSET пуст, повторная попытка загрузки...${NC}"
        traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging >/dev/null
        systemctl restart rsyslog
    fi

    log_ok "Установка завершена успешно!"
}

# --- МЕНЮ МОНИТОРИНГА ---
show_menu() {
    # Обработка Ctrl+C для возврата в меню
    trap 'echo -e "\n${YELLOW}Возврат в меню...${NC}"; sleep 1; return' INT

    while true; do
        clear
        # Сбор статистики
        IPSET_V4=$(ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep "Number of entries" | awk '{print $4}')
        [[ -z "$IPSET_V4" ]] && IPSET_V4="${RED}ОШИБКА${NC}"
        
        PKTS_V4=$(iptables -vnL SCANNERS-BLOCK 2>/dev/null | grep "LOG" | awk '{print $1}')
        [[ -z "$PKTS_V4" ]] && PKTS_V4="0"

        echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║           🛡️  TRAFFICGUARD PRO MONITOR              ║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
        echo -e "║  📊 В базе (IPv4):   ${GREEN}${IPSET_V4}${NC} подсетей              "
        echo -e "║  🔥 Отбито атак:     ${RED}${PKTS_V4}${NC} пакетов               "
        echo -e "║  ⚙️  Статус rsyslog:  $(systemctl is-active rsyslog >/dev/null && echo "${GREEN}OK${NC}" || echo "${RED}FAIL${NC}")                 "
        echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e " ${GREEN}1.${NC} 📈 Топ сканеров (таблица)"
        echo -e " ${GREEN}2.${NC} 🪵 Логи IPv4 (Live) ${YELLOW}[Ctrl+C для возврата]${NC}"
        echo -e " ${GREEN}3.${NC} 🪵 Логи IPv6 (Live) ${YELLOW}[Ctrl+C для возврата]${NC}"
        echo -e " ${GREEN}4.${NC} 🔄 Обновить базы блокировок"
        echo -e " ${GREEN}5.${NC} 🛠️  Переустановить / Починить"
        echo -e " ${RED}0.${NC} ❌ Выход"
        echo ""
        echo -ne "${CYAN}👉 Ваш выбор:${NC} "
        read -r choice

        case $choice in
            1)
                echo -e "\n${GREEN}=== ТОП 20 АТАКУЮЩИХ ===${NC}"
                if [ -s /var/log/iptables-scanners-aggregate.csv ]; then
                    tail -20 /var/log/iptables-scanners-aggregate.csv
                else
                    echo "Данных пока нет (подождите 5-10 мин)..."
                fi
                read -p $'\nНажмите Enter...'
                ;;
            2)
                echo -e "\n${YELLOW}Нажмите Ctrl+C чтобы вернуться в меню${NC}"
                tail -f /var/log/iptables-scanners-ipv4.log
                ;;
            3)
                echo -e "\n${YELLOW}Нажмите Ctrl+C чтобы вернуться в меню${NC}"
                tail -f /var/log/iptables-scanners-ipv6.log
                ;;
            4)
                echo -e "\n🔄 Обновление..."
                traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging
                log_ok "Обновлено!"
                sleep 2
                ;;
            5)
                install_process
                read -p "Нажмите Enter..."
                ;;
            0)
                exit 0
                ;;
            *)
                echo "Неверный выбор"
                sleep 1
                ;;
        esac
    done
}

# --- ТОЧКА ВХОДА ---
check_root

case "${1:-}" in
    install)
        install_process
        ;;
    monitor)
        show_menu
        ;;
    *)
        echo "Использование: $0 {install|monitor}"
        exit 1
        ;;
esac
EOF

chmod +x "$MANAGER_PATH"


# ==============================================================================
# 2. СОЗДАНИЕ ГЛОБАЛЬНОЙ КОМАНДЫ (SYMLINK ВМЕСТО ALIAS)
# ==============================================================================
# Удаляем старые хвосты
rm -f /usr/local/bin/rknpidor
# Создаем жесткую ссылку - работает везде, всегда, сразу
ln -s "$MANAGER_PATH" /usr/local/bin/rknpidor

echo -e "${GREEN}✅ Менеджер установлен в: $MANAGER_PATH${NC}"
echo -e "${GREEN}✅ Команда 'rknpidor' активирована глобально!${NC}"

# ==============================================================================
# 3. ЗАПУСК ПРОЦЕССА
# ==============================================================================
# Запускаем установку через созданный скрипт
rknpidor install

# После установки сразу открываем меню
echo -e "\n${GREEN}🎉 Установка завершена! Запускаем мониторинг...${NC}"
sleep 2
rknpidor monitor
