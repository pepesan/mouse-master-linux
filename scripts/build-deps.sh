#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Install Mouse Master build and Qt runtime dependencies on supported Debian-family systems.

Supported targets: Debian 13 and Ubuntu 26.04.
Usage: ./scripts/build-deps.sh [--dry-run]
EOF
}

dry_run=0
case "${1:-}" in
    "") ;;
    --dry-run|-n) dry_run=1 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'error: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
    printf 'error: too many arguments\n' >&2
    usage >&2
    exit 2
fi

if [[ ! -r /etc/os-release ]]; then
    printf 'error: cannot identify this Linux distribution (/etc/os-release missing)\n' >&2
    exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release

case "${ID:-}" in
    debian)
        if [[ "${VERSION_ID:-}" != 13 ]]; then
            printf 'error: supported Debian release is 13; found %s\n' "${VERSION_ID:-unknown}" >&2
            exit 1
        fi
        ;;
    ubuntu)
        if [[ "${VERSION_ID:-}" != 26.04 ]]; then
            printf 'error: supported Ubuntu release is 26.04; found %s\n' "${VERSION_ID:-unknown}" >&2
            exit 1
        fi
        ;;
    *)
        printf 'error: supported distributions are Debian 13 and Ubuntu 26.04; found %s\n' "${ID:-unknown}" >&2
        exit 1
        ;;
esac

packages=(
    build-essential
    debhelper
    ca-certificates
    cmake
    rustup
    libudev-dev
    pkg-config
    qt6-base-dev
    qt6-declarative-dev
    qt6-svg-dev
    qt6-wayland
    qml6-module-qtquick-controls
    qml6-module-qtquick-layouts
    qml6-module-qtquick-shapes
    qml6-module-qtquick-effects
    qml6-module-qtquick-dialogs
    qml6-module-qtcore
)

if (( dry_run )); then
    printf 'Detected %s %s (%s). Would install:\n' "$PRETTY_NAME" "$VERSION_ID" "${VERSION_CODENAME:-unknown}"
    printf '  %s\n' "${packages[@]}"
    exit 0
fi

sudo_cmd=()
if (( EUID != 0 )); then
    if ! command -v sudo >/dev/null 2>&1; then
        printf 'error: run as root or install sudo\n' >&2
        exit 1
    fi
    sudo_cmd=(sudo)
fi

"${sudo_cmd[@]}" apt-get update
"${sudo_cmd[@]}" apt-get install -y --no-install-recommends "${packages[@]}"

export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
rustup toolchain install stable --profile minimal
rustup default stable
