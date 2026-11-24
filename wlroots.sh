#!/usr/bin/env bash
#
# build-wlroots.sh - Сборка wlroots 0.18 из исходников для Devuan (OpenRC)
#
# Использование:
#   ./build-wlroots.sh [команда]
#
# Команды:
#   deps       - установить зависимости для сборки
#   build      - клонировать и собрать (по умолчанию)
#   install    - установить собранный пакет (нужен sudo)
#   uninstall  - удалить установленный wlroots из /usr/local
#   clean      - удалить каталог сборки
#   all        - deps + build + install
#   help       - показать эту справку
#
# Переменные окружения (можно переопределить):
#   WLROOTS_VERSION  - версия (ветка/тег), по умолчанию 0.18
#   PREFIX           - префикс установки, по умолчанию /usr/local
#   SRC_DIR          - каталог для исходников, по умолчанию ./wlroots
#   BUILD_DIR        - каталог сборки, по умолчанию ./build
#   JOBS             - число параллельных задач (по умолчанию nproc)
#   ENABLE_XWAYLAND  - 1 чтобы включить XWayland, 0 чтобы отключить (по умолчанию 0)
#   ENABLE_EXAMPLES  - 1 чтобы собрать примеры (по умолчанию 0)

set -euo pipefail

# ---------- Параметры по умолчанию ----------
WLROOTS_VERSION="${WLROOTS_VERSION:-0.18}"
PREFIX="${PREFIX:-/usr/local}"
SRC_DIR="${SRC_DIR:-$(pwd)/wlroots}"
BUILD_DIR="${BUILD_DIR:-$(pwd)/build}"
JOBS="${JOBS:-$(nproc)}"
ENABLE_XWAYLAND="${ENABLE_XWAYLAND:-0}"
ENABLE_EXAMPLES="${ENABLE_EXAMPLES:-0}"

REPO_URL="https://gitlab.freedesktop.org/wlroots/wlroots.git"

# ---------- Цветной вывод ----------
if [[ -t 1 ]]; then
    C_RESET=$'\e[0m'; C_INFO=$'\e[1;34m'; C_OK=$'\e[1;32m'
    C_WARN=$'\e[1;33m'; C_ERR=$'\e[1;31m'
else
    C_RESET=""; C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""
fi
info()  { echo "${C_INFO}[INFO]${C_RESET}  $*"; }
ok()    { echo "${C_OK}[ OK ]${C_RESET}  $*"; }
warn()  { echo "${C_WARN}[WARN]${C_RESET}  $*" >&2; }
err()   { echo "${C_ERR}[FAIL]${C_RESET}  $*" >&2; }
die()   { err "$*"; exit 1; }

# ---------- Проверки ----------
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "команда '$1' не найдена. Установите её пакет."
}

check_devuan() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        if [[ "${ID:-}" != "devuan" && "${ID_LIKE:-}" != *"devuan"* && "${ID:-}" != "debian" ]]; then
            warn "Система не распознана как Devuan (ID=${ID:-?}). Продолжаем, но будьте осторожны."
        fi
        if [[ "${ID:-}" == "devuan" ]]; then
            info "Обнаружен Devuan ${VERSION_CODENAME:-?} (${PRETTY_NAME:-})"
        fi
    fi
    # Проверка, что мы действительно на OpenRC / elogind, а не на systemd
    if command -v systemctl >/dev/null 2>&1 && pidof systemd >/dev/null 2>&1; then
        warn "Похоже, используется systemd. Скрипт ориентирован на Devuan/OpenRC."
    fi
}

# ---------- Установка зависимостей ----------
cmd_deps() {
    info "Установка зависимостей для сборки wlroots (Devuan)..."
    sudo apt update
    sudo apt install -y --no-install-recommends \
        build-essential meson ninja-build pkg-config git ca-certificates \
        libwayland-dev wayland-protocols libxkbcommon-dev \
        libdrm-dev libgbm-dev libinput-dev libudev-dev \
        libpixman-1-dev libseat-dev libvulkan-dev \
        libxcb1-dev libxcb-composite0-dev libxcb-render0-dev \
        libxcb-xfixes0-dev libxcb-icccm4-dev libxcb-ewmh-dev \
        libxcb-xinput-dev libxcb-xkb-dev libx11-xcb-dev \
        libelogind-dev libcap-dev hwdata
    ok "Зависимости установлены."
    info "Проверка наличия elogind:"
    pkg-config --exists libelogind && ok "libelogind найдена ($(pkg-config --modversion libelogind))" \
        || warn "libelogind не найдена через pkg-config. Сборка с elogind может не удасться."
}

# ---------- Сборка ----------
cmd_build() {
    require_cmd git
    require_cmd meson
    require_cmd ninja
    require_cmd pkg-config

    # Обязательные зависимости на этапе конфигурации
    for pkg in wayland-server libdrm gbm libinput libudev pixman-1 libseat libelogind; do
        if ! pkg-config --exists "$pkg"; then
            die "Не найдена библиотека разработки '$pkg'. Запустите: $0 deps"
        fi
    done

    if [[ ! -d "$SRC_DIR/.git" ]]; then
        info "Клонирование wlroots в $SRC_DIR ..."
        git clone "$REPO_URL" "$SRC_DIR"
    else
        info "Каталог исходников уже существует: $SRC_DIR"
    fi

    pushd "$SRC_DIR" >/dev/null
    info "Получение обновлений и переключение на ветку/тег '$WLROOTS_VERSION'..."
    git fetch --tags --prune origin
    git checkout "$WLROOTS_VERSION"
    git pull --ff-only origin "$WLROOTS_VERSION" || warn "git pull не удался, продолжаем с локальной версией."
    popd >/dev/null

    # Чистим каталог сборки, чтобы избежать stale-кэша
    rm -rf "$BUILD_DIR"

    # Формируем опции Meson
    local -a meson_opts=(
        "--prefix=$PREFIX"
        "--buildtype=release"
        "-Dlogind-provider=elogind"
    )
    if [[ "$ENABLE_XWAYLAND" == "1" ]]; then
        meson_opts+=("-Dxwayland=enabled")
    else
        meson_opts+=("-Dxwayland=disabled")
    fi
    if [[ "$ENABLE_EXAMPLES" == "1" ]]; then
        meson_opts+=("-Dexamples=true")
    else
        meson_opts+=("-Dexamples=false")
    fi

    info "Настройка сборки (meson setup) с опциями:"
    printf '        %s\n' "${meson_opts[@]}"
    meson setup "$BUILD_DIR" "$SRC_DIR" "${meson_opts[@]}"

    info "Компиляция (ninja -j$JOBS)..."
    ninja -C "$BUILD_DIR" -j "$JOBS"

    ok "Сборка завершена. Каталог: $BUILD_DIR"
    info "Для установки запустите: sudo $0 install"
}

# ---------- Установка ----------
cmd_install() {
    [[ -d "$BUILD_DIR" ]] || die "Каталог сборки '$BUILD_DIR' не найден. Сначала выполните: $0 build"
    if [[ "$EUID" -ne 0 ]]; then
        info "Требуются права root, перезапуск через sudo..."
        exec sudo -E "$0" install
    fi
    info "Установка в $PREFIX ..."
    ninja -C "$BUILD_DIR" install
    ldconfig
    ok "Установлено. Версия: $(pkg-config --modversion wlroots-${WLROOTS_VERSION%.*} 2>/dev/null || echo '?')"
    info "Проверьте путь pkg-config: pkg-config --cflags --libs wlroots-0.18"
}

# ---------- Удаление ----------
cmd_uninstall() {
    if [[ "$EUID" -ne 0 ]]; then
        info "Требуются права root, перезапуск через sudo..."
        exec sudo -E "$0" uninstall
    fi
    [[ -d "$BUILD_DIR" ]] || { warn "Каталог сборки отсутствует. Пробуем найти установленные файлы по префиксу $PREFIX."; }
    if [[ -f "$BUILD_DIR/install_manifest.txt" ]]; then
        info "Удаление файлов по install_manifest.txt ..."
        xargs -r rm -v < "$BUILD_DIR/install_manifest.txt"
    else
        warn "install_manifest.txt не найден. Удаляем по шаблону..."
        rm -f "$PREFIX"/lib*/libwlroots* \
              "$PREFIX"/include/wlroots*/* \
              2>/dev/null || true
    fi
    ldconfig
    ok "Удаление завершено."
}

# ---------- Очистка ----------
cmd_clean() {
    info "Удаление каталога сборки: $BUILD_DIR"
    rm -rf "$BUILD_DIR"
    ok "Готово."
}

cmd_all() {
    cmd_deps
    cmd_build
    cmd_install
}

cmd_help() {
    sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------- Точка входа ----------
main() {
    local action="${1:-build}"
    case "$action" in
        deps)       check_devuan; cmd_deps ;;
        build)      check_devuan; cmd_build ;;
        install)    check_devuan; cmd_install ;;
        uninstall)  cmd_uninstall ;;
        clean)      cmd_clean ;;
        all)        check_devuan; cmd_all ;;
        help|-h|--help) cmd_help ;;
        *)          die "Неизвестная команда: $action (см. $0 help)" ;;
    esac
}

main "$@"