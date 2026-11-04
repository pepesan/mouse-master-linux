#!/usr/bin/env bash
set -euo pipefail
umask 077

if (( EUID != 0 )); then
    echo "Run this publishing gate as root on Rivendel." >&2
    exit 1
fi

CONFIG_DIR="${APT_SIGNING_CONFIG_DIR:-/etc/mouse-master-apt}"
RECOVERY_DIR="${APT_SIGNING_RECOVERY_DIR:-/root/mouse-master-apt-signing-recovery}"
PASSPHRASE_FILE="${APT_SIGNING_PASSPHRASE_FILE:-$CONFIG_DIR/signing-passphrase}"
FINGERPRINT_FILE="${APT_SIGNING_FINGERPRINT_FILE:-$CONFIG_DIR/signing-fingerprint}"
GATE_FILE="${APT_PUBLISH_GATE_FILE:-$CONFIG_DIR/publish-enabled}"

for file in "$PASSPHRASE_FILE" "$FINGERPRINT_FILE" "$RECOVERY_DIR/private-key.asc" "$RECOVERY_DIR/revocation.asc"; do
    [[ -s "$file" ]] || { printf 'Required recovery item is missing: %s\n' "$file" >&2; exit 1; }
done
[[ -t 0 ]] || { echo "A terminal is required for the explicit backup confirmation." >&2; exit 1; }
printf 'Confirm all four recovery items are saved in the private 1Password note "Mouse Master APT — repo.cursosdedesarrollo.com — signing key". Type SAVE-TO-1PASSWORD to enable production publishing: '
read -r confirmation </dev/tty
[[ "$confirmation" == SAVE-TO-1PASSWORD ]] || { echo "Publishing remains disabled." >&2; exit 1; }

gate_tmp="$(mktemp "$CONFIG_DIR/.publish-enabled.XXXXXXXX")"
trap 'rm -f -- "$gate_tmp"' EXIT
printf '1password-confirmed\n' > "$gate_tmp"
chmod 0600 "$gate_tmp"
chown root:root "$gate_tmp"
mv -f -- "$gate_tmp" "$GATE_FILE"
printf 'Production publishing enabled. The key backup confirmation was recorded locally.\n'
