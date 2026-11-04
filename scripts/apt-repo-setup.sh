#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
    echo "Run this setup script as root on Rivendel." >&2
    exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APTLY_CONFIG=/etc/aptly.conf

if ! command -v aptly >/dev/null 2>&1; then
    echo "aptly is required; install it from the distribution repository first." >&2
    exit 1
fi

install -o root -g root -m 0644 "$ROOT/packaging/apt/aptly.conf" "$APTLY_CONFIG"
install -d -o root -g root -m 0750 /var/lib/aptly

ensure_repo() {
    local name=$1 distribution=$2
    if aptly -config="$APTLY_CONFIG" repo show "$name" >/dev/null 2>&1; then
        return
    fi
    aptly -config="$APTLY_CONFIG" repo create \
        -distribution="$distribution" \
        -component=main \
        "$name"
}

ensure_repo mouse-master-trixie trixie
ensure_repo mouse-master-resolute resolute

aptly -config="$APTLY_CONFIG" repo list
