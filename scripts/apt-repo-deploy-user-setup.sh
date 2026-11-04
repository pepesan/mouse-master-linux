#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
    echo "Run this setup script as root on Rivendel." >&2
    exit 1
fi
if (( $# != 1 )); then
    echo "Usage: $0 <GitHub Actions SSH public-key file>" >&2
    exit 2
fi

ROOT="${APT_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PUBLIC_KEY_FILE="$1"
USER_NAME=apt-publisher
IMPORTER=/usr/local/sbin/mouse-master-apt-import
SUDOERS_FILE=/etc/sudoers.d/mouse-master-apt-publisher
ENABLE_PUBLISHING=/usr/local/sbin/mouse-master-apt-enable-publishing

for command in ssh-keygen useradd usermod passwd sudo visudo install; do
    command -v "$command" >/dev/null 2>&1 || {
        printf 'Required command is missing: %s\n' "$command" >&2
        exit 1
    }
done
[[ -r "$PUBLIC_KEY_FILE" ]] || { echo "Public key file is not readable." >&2; exit 1; }
[[ "$(wc -l < "$PUBLIC_KEY_FILE")" -eq 1 ]] || { echo "Expected exactly one SSH public key." >&2; exit 1; }
read -r key_type _ <<< "$(<"$PUBLIC_KEY_FILE")"
[[ "$key_type" == ssh-ed25519 ]] || { echo "Only an Ed25519 deploy key is accepted." >&2; exit 1; }
ssh-keygen -lf "$PUBLIC_KEY_FILE" >/dev/null

if ! id -u "$USER_NAME" >/dev/null 2>&1; then
    useradd --system --user-group --create-home --home-dir "/var/lib/$USER_NAME" --shell /bin/bash "$USER_NAME"
fi
usermod --shell /bin/bash "$USER_NAME"
passwd --lock "$USER_NAME" >/dev/null

install -o root -g root -m 0755 "$ROOT/scripts/apt-repo-import.sh" "$IMPORTER"
install -o root -g root -m 0755 "$ROOT/scripts/apt-repo-enable-publishing.sh" "$ENABLE_PUBLISHING"
home_dir="$(getent passwd "$USER_NAME" | cut -d: -f6)"
[[ -n "$home_dir" ]] || { echo "Could not determine deploy account home." >&2; exit 1; }
install -d -o "$USER_NAME" -g "$USER_NAME" -m 0700 "$home_dir/.ssh"
key_line="$(<"$PUBLIC_KEY_FILE")"
printf 'restrict,command="/usr/bin/sudo -n %s" %s\n' "$IMPORTER" "$key_line" > "$home_dir/.ssh/authorized_keys"
chown "$USER_NAME":"$USER_NAME" "$home_dir/.ssh/authorized_keys"
chmod 0600 "$home_dir/.ssh/authorized_keys"

sudoers_tmp="$(mktemp /etc/sudoers.d/.mouse-master-apt-publisher.XXXXXXXX)"
trap 'rm -f -- "$sudoers_tmp"' EXIT
printf '%s ALL=(root) NOPASSWD: %s\n' "$USER_NAME" "$IMPORTER" > "$sudoers_tmp"
chmod 0440 "$sudoers_tmp"
visudo -cf "$sudoers_tmp"
install -o root -g root -m 0440 "$sudoers_tmp" "$SUDOERS_FILE"
visudo -cf /etc/sudoers
printf 'Configured forced-command account %s; the SSH key can only invoke %s.\n' "$USER_NAME" "$IMPORTER"
