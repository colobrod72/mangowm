#!/bin/bash
# =====================================================
# Установка MangoWM на Devuan Linux
# С автоматической настройкой seatd/elogind и выбором DM
# =====================================================

set -e

# ---------- Цвета ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }
ask()  { echo -e "${CYAN}[?]${NC} $1"; }

# ---------- Проверки ----------
[ "$EUID" -ne 0 ] && err "Запускайте через sudo"
grep -qiE 'devuan|debian' /etc/os-release || warn "Система не Devuan/Debian — продолжаем на свой риск"

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
REAL_UID=$(id -u "$REAL_USER")

# ---------- Определение init-системы ----------
INIT_SYS="unknown"
if [ -d /run/systemd/system ]; then
    INIT_SYS="systemd"
elif command -v rc-service >/dev/null 2>&1; then
    INIT_SYS="openrc"
elif [ -f /sbin/init ] && readlink -f /sbin/init | grep -q sysvinit; then
    INIT_SYS="sysvinit"
elif pidof systemd >/dev/null 2>&1; then
    INIT_SYS="systemd"
fi

# Проверка наличия elogind/sytemd-logind
HAS_LOGIND="no"
if [ -d /run/elogind ] || [ -S /run/elogind/seat0 ] 2>/dev/null; then
    HAS_LOGIND="elogind"
elif [ -d /run/systemd/seats ] 2>/dev/null; then
    HAS_LOGIND="systemd-logind"
fi

log "Init-система: ${BLUE}$INIT_SYS${NC}"
log "Logind-провайдер: ${BLUE}$HAS_LOGIND${NC}"
log "Пользователь: ${BLUE}$REAL_USER${NC} (UID $REAL_UID)"

# ---------- Универсальная функция управления сервисом ----------
svc_enable_start() {
    local svc="$1"
    case "$INIT_SYS" in
        systemd)
            systemctl enable --now "$svc" 2>/dev/null || systemctl enable "$svc" && systemctl start "$svc"
            ;;
        openrc)
            rc-update add "$svc" default 2>/dev/null || true
            rc-service "$svc" start 2>/dev/null || true
            ;;
        sysvinit)
            if command -v update-rc.d >/dev/null 2>&1; then
                update-rc.d "$svc" defaults 2>/dev/null || true
            fi
            service "$svc" start 2>/dev/null || /etc/init.d/"$svc" start 2>/dev/null || true
            ;;
        *)
            warn "Неизвестная init-система, запустите '$svc' вручную"
            ;;
    esac
}

# -----------------------------------------------------
# 1. Обновление и базовые зависимости
# -----------------------------------------------------
log "Обновление пакетов..."
apt update

log "Установка базовых зависимостей..."
apt install -y \
    build-essential git meson ninja-build pkg-config \
    wget curl ca-certificates \
    libwayland-dev wayland-protocols libwlroots-dev \
    libxkbcommon-dev libpixman-1-dev libinput-dev \
    libdrm-dev libgbm-dev libegl-dev libgles2-mesa-dev \
    libxcb1-dev libxcb-render0-dev libxcb-shape0-dev libxcb-xfixes0-dev \
    libseat-dev libdisplay-info-dev libliftoff-dev libtoml-dev \
    xwayland dbus polkitd \
    xdg-desktop-portal-wlr wl-clipboard xdg-utils \
    foot fuzzel waybar swaybg swayidle swaylock \
    grim slurp wf-recorder mako-notifier \
    || warn "Некоторые пакеты могли быть недоступны"

# -----------------------------------------------------
# 2. wlroots (сборка при необходимости)
# -----------------------------------------------------
WLR_VER="0.18.2"
if pkg-config --atleast-version=0.18 wlroots 2>/dev/null; then
    log "wlroots уже >= 0.18"
else
    log "Сборка wlroots ${WLR_VER}..."
    cd /tmp
    wget -q "https://gitlab.freedesktop.org/wlroots/wlroots/-/archive/${WLR_VER}/wlroots-${WLR_VER}.tar.gz"
    tar -xf "wlroots-${WLR_VER}.tar.gz"
    cd "wlroots-${WLR_VER}"
    meson setup build --prefix=/usr/local --buildtype=release
    ninja -C build && ninja -C build install
    ldconfig
fi

# -----------------------------------------------------
# 3. MangoWM
# -----------------------------------------------------
log "Клонирование и сборка MangoWM..."
cd /opt
if [ -d mangowm ]; then
    cd mangowm && git pull
else
    git clone https://github.com/mangowm/mango.git mangowm
    cd mangowm
fi
meson setup build --prefix=/usr/local --buildtype=release
ninja -C build && ninja -C build install

# -----------------------------------------------------
# 4. ВЫБОР И НАСТРОЙКА SEAT-ПРОВАЙДЕРА
# -----------------------------------------------------
# Если elogind или systemd-logind уже есть — спрашиваем, нужно ли что-то менять
if [ "$HAS_LOGIND" != "no" ]; then
    log "Обнаружен logind-провайдер: $HAS_LOGIND — seatd не требуется"
    SEAT_CHOICE="existing"
else
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  MangoWM (wlroots) требует доступ к DRM/seat.${NC}"
    echo -e "${CYAN}  В Devuan без systemd выберите один из вариантов:${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo "  1) seatd     — лёгкий seat-менеджер (рекомендуется для минимальных систем)"
    echo "  2) elogind   — порт systemd-logind (совместимость с приложениями,"
    echo "                 требует PAM-интеграции и перезагрузки)"
    echo "  0) пропустить (настрою вручную)"
    echo ""
    while true; do
        read -rp "Выбор [1/2/0]: " SEAT_CHOICE
        case "$SEAT_CHOICE" in
            1|2|0) break ;;
            *) echo "Введите 1, 2 или 0" ;;
        esac
    done
fi

case "$SEAT_CHOICE" in
    1)
        log "Установка seatd..."
        apt install -y seatd

        # Группа _seatd (Debian/Devuan) или seat (upstream)
        SEATD_GROUP="_seatd"
        getent group "$SEATD_GROUP" >/dev/null || SEATD_GROUP="seat"

        if getent group "$SEATD_GROUP" >/dev/null; then
            log "Добавление $REAL_USER в группу $SEATD_GROUP..."
            usermod -aG "$SEATD_GROUP" "$REAL_USER"
        else
            warn "Группа _seatd/seat не найдена — проверьте /etc/group"
        fi

        svc_enable_start seatd
        log "seatd запущен (init: $INIT_SYS)"
        SEAT_PROVIDER="seatd"
        ;;

    2)
        log "Установка elogind..."
        apt install -y elogind libpam-elogind

        # Отключаем seatd, если был
        if [ -f /etc/init.d/seatd ]; then
            case "$INIT_SYS" in
                systemd) systemctl disable --now seatd 2>/dev/null || true ;;
                openrc)  rc-update del seatd default 2>/dev/null || true
                         rc-service seatd stop 2>/dev/null || true ;;
                sysvinit) update-rc.d -f seatd remove 2>/dev/null || true
                          service seatd stop 2>/dev/null || true ;;
            esac
        fi

        svc_enable_start elogind

        # PAM: убедимся, что pam_elogind подключён
        if [ -f /etc/pam.d/common-session ]; then
            if ! grep -q pam_elogind /etc/pam.d/common-session; then
                log "Добавление pam_elogind в common-session..."
                echo "session optional pam_elogind.so" >> /etc/pam.d/common-session
            fi
        fi
        if [ -f /etc/pam.d/common-session-noninteractive ]; then
            if ! grep -q pam_elogind /etc/pam.d/common-session-noninteractive; then
                echo "session optional pam_elogind.so" >> /etc/pam.d/common-session-noninteractive
            fi
        fi

        SEAT_PROVIDER="elogind"
        warn "elogind требует перезагрузки для полного применения"
        ;;

    0|existing)
        SEAT_PROVIDER="${HAS_LOGIND:-none}"
        warn "Настройка seat-провайдера пропущена"
        ;;
esac

# -----------------------------------------------------
# 5. ВЫБОР DISPLAY MANAGER
# -----------------------------------------------------
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Выбор Display Manager для входа в MangoWM${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
echo "  1) greetd + tuigreet  — минималистичный TUI DM, отлично для Wayland"
echo "  2) ly                 — лёгкий TUI DM (Wayland-friendly)"
echo "  3) lightdm            — GTK DM (стабильный, работает с Wayland)"
echo "  4) sddm               — Qt DM (лучшая поддержка Wayland-сессий)"
echo "  0) не устанавливать (запуск вручную из TTY)"
echo ""

DM_ALREADY=$(dpkg -l 2>/dev/null | awk '/^ii/ {print $2}' \
    | grep -E '^(sddm|lightdm|ly|greetd)$' | head -1 || true)
[ -n "$DM_ALREADY" ] && log "Обнаружен установленный DM: $DM_ALREADY"

DM_CHOICE=""
while true; do
    read -rp "Выбор [1/2/3/4/0]: " DM_CHOICE
    case "$DM_CHOICE" in
        1|2|3|4|0) break ;;
        *) echo "Введите 1, 2, 3, 4 или 0" ;;
    esac
done

install_greetd() {
    log "Установка greetd + tuigreet..."
    apt install -y greetd tuigreet || warn "tuigreet не найден в репозитории — установите вручную (cargo install tuigreet)"

    cat > /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --remember-session --sessions /usr/share/wayland-sessions"
user = "_greetd"
EOF

    # PAM для greetd — создать, если отсутствует
    if [ ! -f /etc/pam.d/greetd ]; then
        cat > /etc/pam.d/greetd <<'EOF'
auth       required     pam_securetty.so
auth       requisite    pam_nologin.so
auth       include      common-auth
account    include      common-account
password   include      common-password
session    required     pam_loginuid.so
session    include      common-session
EOF
    fi

    svc_enable_start greetd
}

install_ly() {
    log "Установка ly..."
    apt install -y ly || warn "ly не найден в репозитории — соберите из github.com/nullgemm/ly"
    svc_enable_start ly
}

install_lightdm() {
    log "Установка lightdm + greeter..."
    apt install -y lightdm lightdm-gtk-greeter
    cat > /etc/lightdm/lightdm.conf <<'EOF'
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=mango
type=wayland
EOF
    svc_enable_start lightdm
}

install_sddm() {
    log "Установка sddm..."
    apt install -y sddm
    # Отключаем автозапуск X11 — sddm сам определит Wayland
    svc_enable_start sddm
}

case "$DM_CHOICE" in
    1) install_greetd ;;
    2) install_ly ;;
    3) install_lightdm ;;
    4) install_sddm ;;
    0) warn "DM не установлен — запуск вручную из TTY" ;;
esac

# -----------------------------------------------------
# 6. Сессия MangoWM
# -----------------------------------------------------
log "Создание скрипта сессии..."

cat > /usr/local/bin/mango-session <<'EOF'
#!/bin/sh
export XDG_CURRENT_DESKTOP=mango
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=mango
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
export GDK_BACKEND=wayland
export CLUTTER_BACKEND=wayland
export SDL_VIDEODRIVER=wayland
export _JAVA_AWT_WM_NONREPARENTING=1
export WLR_NO_HARDWARE_CURSORS=${WLR_NO_HARDWARE_CURSORS:-0}
exec dbus-run-session -- /usr/local/bin/mango
EOF
chmod +x /usr/local/bin/mango-session

mkdir -p /usr/share/wayland-sessions
cat > /usr/share/wayland-sessions/mango.desktop <<'EOF'
[Desktop Entry]
Name=MangoWM
Comment=Dynamic Wayland tiling window manager
Exec=/usr/local/bin/mango-session
Type=Application
DesktopNames=mango
EOF

# -----------------------------------------------------
# 7. Пользовательская конфигурация
# -----------------------------------------------------
if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
    log "Создание конфигурации MangoWM для $REAL_USER..."
    mkdir -p "$REAL_HOME/.config/mango"
    if [ ! -f "$REAL_HOME/.config/mango/config.conf" ]; then
        cat > "$REAL_HOME/.config/mango/config.conf" <<'EOF'
kb_layout=us,ru
kb_options=grp:alt_shift_toggle
gappih=5
gappiv=5
gappoh=10
gappov=10
borderpx=2
termcmd=foot
menucmd=fuzzel
exec-once=waybar
exec-once=swaybg -i /usr/share/backgrounds/default.png -m fill
exec-once=mako
EOF
    fi
    chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/mango"
fi

# -----------------------------------------------------
# 8. Финальная проверка
# -----------------------------------------------------
ldconfig

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Установка завершена!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo "  Init-система     : $INIT_SYS"
echo "  Seat-провайдер   : $SEAT_PROVIDER"
echo "  Display Manager  : ${DM_ALREADY:-$([ "$DM_CHOICE" = "0" ] && echo "не установлен" || echo "установлен")}"
echo "  Конфиг           : $REAL_HOME/.config/mango/config.conf"
echo ""
echo "  Запуск вручную   : dbus-run-session mango-session"
echo "  Запуск из DM     : выберите 'MangoWM' в меню сессий"
echo ""

if [ "$SEAT_PROVIDER" = "elogind" ]; then
    warn "elogind установлен — ПЕРЕЗАГРУЗИТЕ систему перед первым входом:"
    warn "  sudo reboot"
fi

if [ "$SEAT_PROVIDER" = "seatd" ]; then
    log "seatd запущен. Выйдите и войдите заново, чтобы применилась группа _seatd"
fi

echo ""
echo -e "${CYAN}Проверка после перезагрузки:${NC}"
echo "  loginctl show-session \$XDG_SESSION_ID 2>/dev/null || echo 'нет logind'"
echo "  ls -l /dev/dri/"
echo ""