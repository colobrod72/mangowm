#!/usr/bin/env bash
set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    error "Скрипт должен выполняться с правами root. Используйте: sudo $0"
fi

# Определение версии Debian
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DEBIAN_CODENAME="${VERSION_CODENAME:-}"
else
    error "Не удалось определить версию Debian."
fi

info "Обнаружен Debian: ${DEBIAN_CODENAME:-unknown}"

# --- 1. Установка базовых зависимостей для сборки ---
info "Установка базовых инструментов и библиотек для сборки..."
apt-get update
apt-get install -y \
    build-essential git meson ninja-build pkg-config \
    libwayland-dev wayland-protocols \
    libinput-dev libdrm-dev libxkbcommon-dev \
    libpixman-1-dev libdisplay-info-dev libliftoff-dev \
    libseat-dev libpcre2-dev libcjson-dev \
    libpango1.0-dev libcairo2-dev \
    libxcb1-dev libxcb-icccm4-dev \
    hwdata seatd xwayland

# --- 2. Сборка wlroots 0.19.2 (требуется для MangoWM) ---
# В репозиториях Debian может быть более старая версия, поэтому собираем необходимую.
WLR_VER="0.19.2"
info "Сборка wlroots ${WLR_VER} из исходного кода..."
WLR_DIR="/tmp/wlroots-build"
rm -rf "$WLR_DIR"
git clone --depth 1 -b "$WLR_VER" https://gitlab.freedesktop.org/wlroots/wlroots.git "$WLR_DIR"
cd "$WLR_DIR"
meson setup build --prefix=/usr --buildtype=release
ninja -C build
ninja -C build install
cd /
rm -rf "$WLR_DIR"

# --- 3. Сборка scenefx 0.4.1 (требуется для визуальных эффектов) ---
SFX_VER="0.4.1"
info "Сборка scenefx ${SFX_VER} из исходного кода..."
SFX_DIR="/tmp/scenefx-build"
rm -rf "$SFX_DIR"
git clone --depth 1 -b "$SFX_VER" https://github.com/wlrfx/scenefx.git "$SFX_DIR"
cd "$SFX_DIR"
meson setup build --prefix=/usr --buildtype=release
ninja -C build
ninja -C build install
cd /
rm -rf "$SFX_DIR"

# --- 4. Сборка и установка MangoWM ---
info "Сборка MangoWM из исходного кода..."
MANGO_DIR="/tmp/mangowm-build"
rm -rf "$MANGO_DIR"
git clone --depth 1 https://github.com/mangowm/mango.git "$MANGO_DIR"
cd "$MANGO_DIR"
meson setup build --prefix=/usr --buildtype=release
ninja -C build
ninja -C build install
cd /
rm -rf "$MANGO_DIR"

info "✅ MangoWM успешно собран и установлен."

# --- 5. (Опционально) Установка рекомендуемых инструментов ---
read -rp "Установить рекомендуемый набор инструментов (панель, терминал, лаунчер)? [y/N]: " install_tools
if [[ "$install_tools" =~ ^[Yy]$ ]]; then
    info "Установка рекомендуемых инструментов..."
    apt-get install -y \
        rofi foot waybar swaybg swayidle swaylock \
        wl-clipboard grim slurp brightnessctl playerctl \
        xdg-desktop-portal-wlr xdg-desktop-portal-gtk
    info "✅ Рекомендуемые инструменты установлены."
else
    info "Пропуск установки рекомендуемых инструментов."
fi

info "Готово! Вы можете запустить MangoWM, выполнив команду 'mango' (или 'mangowm')."