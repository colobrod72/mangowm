#!/usr/bin/env bash
set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# Проверка, что скрипт запущен с правами root (или через sudo)
if [[ $EUID -ne 0 ]]; then
   error "Этот скрипт должен выполняться с правами root. Используйте: sudo $0"
fi

# Определение версии Debian
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DEBIAN_CODENAME="${VERSION_CODENAME:-}"
else
    error "Не удалось определить версию Debian (/etc/os-release отсутствует)."
fi

info "Обнаружен Debian: ${DEBIAN_CODENAME:-unknown}"

# --- Функция установки из APT-репозитория (рекомендуется) ---
install_from_repo() {
    info "Установка Noctalia из официального APT-репозитория..."

    # 1. Установка ключа репозитория
    info "Загрузка и установка ключа подписи репозитория..."
    wget -q https://pkg.noctalia.dev/deb/nickh-archive-keyring.deb -O /tmp/nickh-archive-keyring.deb
    dpkg -i /tmp/nickh-archive-keyring.deb
    rm -f /tmp/nickh-archive-keyring.deb

    # 2. Добавление репозитория в зависимости от версии Debian
    local repo_url=""
    case "$DEBIAN_CODENAME" in
        trixie)
            repo_url="https://pkg.noctalia.dev/deb/noctalia-trixie.sources"
            ;;
        sid|unstable)
            repo_url="https://pkg.noctalia.dev/deb/noctalia-unstable.sources"
            ;;
        *)
            warn "Ваша версия Debian (${DEBIAN_CODENAME}) не указана в официальной документации."
            warn "Скрипт попытается использовать репозиторий для Trixie. Если установка не удастся,"
            warn "возможно, потребуется сборка из исходного кода (вариант 2)."
            repo_url="https://pkg.noctalia.dev/deb/noctalia-trixie.sources"
            ;;
    esac

    info "Добавление репозитория: $repo_url"
    wget -qO /etc/apt/sources.list.d/noctalia.list "$repo_url"

    # 3. Обновление и установка
    info "Обновление списка пакетов..."
    apt-get update

    info "Установка пакета noctalia..."
    apt-get install -y noctalia

    info "✅ Noctalia успешно установлена из репозитория."
}

# --- Функция сборки из исходного кода ---
build_from_source() {
    info "Подготовка к сборке Noctalia из исходного кода..."

    # Проверка версии Debian и предупреждение о возможных проблемах
    if [[ "$DEBIAN_CODENAME" == "bookworm" ]]; then
        warn "Debian 12 (Bookworm) имеет старый g++ по умолчанию. Возможно, потребуется g++-13."
        warn "Рекомендуется установить g++-13 и использовать его при сборке."
    fi

    if [[ "$DEBIAN_CODENAME" == "trixie" ]]; then
        warn "Debian 13 (Trixie) поставляет wlroots 0.18, но Noctalia может требовать wlroots 0.20."
        warn "Если сборка не удастся из-за wlroots, рассмотрите вариант 1 (установка из репозитория)."
    fi

    # Установка зависимостей для сборки (согласно официальной документации)
    info "Установка зависимостей для сборки..."
    apt-get update
    apt-get install -y \
        meson g++ just git \
        libwayland-dev wayland-protocols \
        libwlroots-0.20-dev libinput-dev \
        libegl-dev libgles-dev \
        libfreetype-dev libfontconfig-dev \
        libcairo2-dev libpango1.0-dev libharfbuzz-dev \
        libxkbcommon-dev libglib2.0-dev \
        libsdbus-c++-dev libpipewire-0.3-dev \
        libpam0g-dev libpolkit-agent-1-dev libpolkit-gobject-1-dev \
        libcurl4-openssl-dev libwebp-dev librsvg2-dev \
        libqalculate-dev libxml2-dev \
        libjemalloc-dev

    # Клонирование и сборка
    local BUILD_DIR="/tmp/noctalia-build"
    info "Клонирование репозитория Noctalia в $BUILD_DIR..."
    rm -rf "$BUILD_DIR"
    git clone https://github.com/noctalia-dev/noctalia.git "$BUILD_DIR"
    cd "$BUILD_DIR"

    info "Настройка сборки через meson..."
    meson setup build-release --prefix=/usr --buildtype=release

    info "Сборка..."
    just build-release

    info "Установка..."
    meson install -C build-release

    info "✅ Noctalia успешно собрана и установлена из исходного кода."
    cd /
    rm -rf "$BUILD_DIR"
}

# --- Основное меню ---
echo "========================================"
echo "  Установка Noctalia на Debian"
echo "========================================"
echo "Выберите способ установки:"
echo "  1) Из официального APT-репозитория (рекомендуется, быстро и просто)"
echo "  2) Сборка из исходного кода (потребует установки всех зависимостей для разработки)"
echo "  3) Выход"
read -rp "Ваш выбор [1-3]: " choice

case "$choice" in
    1)
        install_from_repo
        ;;
    2)
        build_from_source
        ;;
    3)
        info "Выход."
        exit 0
        ;;
    *)
        error "Неверный выбор. Завершение."
        ;;
esac

info "Готово! Вы можете запустить Noctalia, выполнив команду 'noctalia' (или в соответствии с вашей конфигурацией рабочего стола)."