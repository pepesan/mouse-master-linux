#!/usr/bin/env bash
set -euo pipefail
umask 077

if (( EUID != 0 )); then
    echo "Run this key setup script as root on Rivendel." >&2
    exit 1
fi
if (( $# != 0 )); then
    echo "This script takes no arguments." >&2
    exit 2
fi

CONFIG_DIR="${APT_SIGNING_CONFIG_DIR:-/etc/mouse-master-apt}"
GNUPGHOME="${APT_GNUPGHOME:-$CONFIG_DIR/gnupg}"
PASSPHRASE_FILE="${APT_SIGNING_PASSPHRASE_FILE:-$CONFIG_DIR/signing-passphrase}"
FINGERPRINT_FILE="${APT_SIGNING_FINGERPRINT_FILE:-$CONFIG_DIR/signing-fingerprint}"
RECOVERY_DIR="${APT_SIGNING_RECOVERY_DIR:-/root/mouse-master-apt-signing-recovery}"
PRIVATE_EXPORT="$RECOVERY_DIR/private-key.asc"
REVOCATION_EXPORT="$RECOVERY_DIR/revocation.asc"

for command in gpg openssl awk install; do
    command -v "$command" >/dev/null 2>&1 || {
        printf 'Required command is missing: %s\n' "$command" >&2
        exit 1
    }
done
if [[ -e "$PASSPHRASE_FILE" || -e "$FINGERPRINT_FILE" || -e "$PRIVATE_EXPORT" ]]; then
    echo "Signing-key setup already has output; refusing to overwrite it." >&2
    exit 1
fi

install -d -o root -g root -m 0700 "$CONFIG_DIR" "$GNUPGHOME" "$RECOVERY_DIR"
if gpg --homedir "$GNUPGHOME" --batch --with-colons --list-secret-keys 2>/dev/null | awk -F: '$1 == "sec" { found=1 } END { exit !found }'; then
    echo "The dedicated GPG keyring already contains a secret key." >&2
    exit 1
fi

openssl rand -base64 48 > "$PASSPHRASE_FILE"
chmod 0600 "$PASSPHRASE_FILE"
gpg --homedir "$GNUPGHOME" \
    --batch \
    --pinentry-mode loopback \
    --passphrase-file "$PASSPHRASE_FILE" \
    --quick-generate-key \
    'Mouse Master APT Repository <apt@repo.cursosdedesarrollo.com>' \
    ed25519 sign 5y

fingerprint="$(gpg --homedir "$GNUPGHOME" --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')"
[[ "$fingerprint" =~ ^[A-Fa-f0-9]{40,64}$ ]] || { echo "Could not read generated key fingerprint." >&2; exit 1; }
printf '%s\n' "$fingerprint" > "$FINGERPRINT_FILE"
chmod 0600 "$FINGERPRINT_FILE"
gpg --homedir "$GNUPGHOME" \
    --batch \
    --pinentry-mode loopback \
    --passphrase-file "$PASSPHRASE_FILE" \
    --armor \
    --output "$PRIVATE_EXPORT" \
    --export-secret-keys "$fingerprint"
chmod 0600 "$PRIVATE_EXPORT"
revocation_source="$GNUPGHOME/openpgp-revocs.d/$fingerprint.rev"
[[ -s "$revocation_source" ]] || { echo "GnuPG did not create a revocation certificate." >&2; exit 1; }
install -o root -g root -m 0600 "$revocation_source" "$REVOCATION_EXPORT"

printf 'Created signing key fingerprint: %s\n' "$fingerprint"
printf 'Encrypted private-key export: %s\n' "$PRIVATE_EXPORT"
printf 'Passphrase file (copy the contents privately): %s\n' "$PASSPHRASE_FILE"
printf 'Fingerprint file: %s\n' "$FINGERPRINT_FILE"
printf 'Revocation certificate: %s\n' "$REVOCATION_EXPORT"
printf '\nURGENT: Save the encrypted export, passphrase, fingerprint and revocation certificate in the private 1Password Secure Note titled exactly:\nMouse Master APT — repo.cursosdedesarrollo.com — signing key\n'
printf 'Production publishing remains disabled until the owner confirms that 1Password backup.\n'
