#!/usr/bin/env bash
set -euo pipefail
umask 077

if (( EUID != 0 )); then
    echo "The APT repository importer must run as root." >&2
    exit 1
fi
if (( $# != 0 )); then
    echo "This importer accepts only a tar.gz archive on stdin." >&2
    exit 2
fi

APTLY_CONFIG="${APTLY_CONFIG:-/etc/aptly.conf}"
APTLY_ROOT="${APTLY_ROOT:-/var/lib/aptly}"
DOCROOT="${APT_DOCROOT:-/var/www/vhosts/cursosdedesarrollo.com/repo.cursosdedesarrollo.com}"
SITE_USER="${APT_SITE_USER:-cursosdedesarrollo.co_pz3bsus28c}"
KEY_ID_FILE="${APT_SIGNING_FINGERPRINT_FILE:-/etc/mouse-master-apt/signing-fingerprint}"
PASSPHRASE_FILE="${APT_SIGNING_PASSPHRASE_FILE:-/etc/mouse-master-apt/signing-passphrase}"
LOCK_FILE="${APT_IMPORT_LOCK_FILE:-/run/lock/mouse-master-apt-import.lock}"
GNUPGHOME="${APT_GNUPGHOME:-${GNUPGHOME:-/etc/mouse-master-apt/gnupg}}"
PUBLISH_GATE_FILE="${APT_PUBLISH_GATE_FILE:-/etc/mouse-master-apt/publish-enabled}"
export GNUPGHOME
for command in aptly dpkg-deb dpkg gpg gpgv tar rsync flock runuser stat; do
    command -v "$command" >/dev/null 2>&1 || {
        printf 'Required command is missing: %s\n' "$command" >&2
        exit 1
    }
done
[[ -r "$APTLY_CONFIG" ]] || { echo "aptly config not found." >&2; exit 1; }
[[ -r "$PUBLISH_GATE_FILE" && "$(<"$PUBLISH_GATE_FILE")" == 1password-confirmed ]] || {
    echo "Publishing is disabled until the signing-key backup is confirmed in 1Password." >&2
    exit 1
}
[[ -s "$KEY_ID_FILE" ]] || { echo "Signing key fingerprint is not configured." >&2; exit 1; }
[[ -s "$PASSPHRASE_FILE" ]] || { echo "Signing key passphrase file is not configured." >&2; exit 1; }
getent passwd "$SITE_USER" >/dev/null || { echo "Plesk site user not found." >&2; exit 1; }

key_id="$(<"$KEY_ID_FILE")"
[[ "$key_id" =~ ^[A-Fa-f0-9]{40,64}$ ]] || { echo "Invalid signing key fingerprint." >&2; exit 1; }
gpg --batch --list-secret-keys "$key_id" >/dev/null 2>&1 || {
    echo "Configured signing key is absent from the root GPG keyring." >&2
    exit 1
}

install -d -o root -g root -m 0700 "$APTLY_ROOT/incoming" "$APTLY_ROOT/mouse-master-state"
install -d -o root -g root -m 0755 /run/lock
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "Another APT publication is already running." >&2; exit 1; }

work="$(mktemp -d "$APTLY_ROOT/incoming/import.XXXXXXXX")"
release_stage=
site_stage=
trap 'rm -rf -- "$work" "$release_stage" "$site_stage"' EXIT
archive="$work/artifacts.tar.gz"
extract="$work/extract"
install -d -o root -g root -m 0700 "$extract"
cat > "$archive"
[[ -s "$archive" ]] || { echo "No artifact archive received." >&2; exit 1; }

members_text="$(tar -tzf "$archive")"
mapfile -t members <<< "$members_text"
(( ${#members[@]} == 3 )) || { echo "Expected two package files and one index.html." >&2; exit 1; }

debian_name=
ubuntu_name=
version=
site_name=
for member in "${members[@]}"; do
    if [[ "$member" == index.html ]]; then
        [[ -z "$site_name" ]] || { echo "Duplicate site index." >&2; exit 1; }
        site_name="$member"
        continue
    fi
    [[ "$member" =~ ^mouse-master_([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)_(debian13|ubuntu26\.04)_amd64\.deb$ ]] || {
        printf 'Unexpected archive member: %s\n' "$member" >&2
        exit 1
    }
    member_version="${BASH_REMATCH[1]}"
    distro="${BASH_REMATCH[2]}"
    if [[ -n "$version" && "$version" != "$member_version" ]]; then
        echo "Debian and Ubuntu package versions differ." >&2
        exit 1
    fi
    version="$member_version"
    case "$distro" in
        debian13) [[ -z "$debian_name" ]] || { echo "Duplicate Debian package." >&2; exit 1; }; debian_name="$member" ;;
        ubuntu26.04) [[ -z "$ubuntu_name" ]] || { echo "Duplicate Ubuntu package." >&2; exit 1; }; ubuntu_name="$member" ;;
    esac
done
[[ -n "$debian_name" && -n "$ubuntu_name" && "$site_name" == index.html ]] || {
    echo "Missing a distribution package or site index." >&2
    exit 1
}
tar -xzf "$archive" -C "$extract" --no-same-owner --no-same-permissions
[[ -f "$extract/$debian_name" && ! -L "$extract/$debian_name" ]] || { echo "Invalid Debian archive member." >&2; exit 1; }
[[ -f "$extract/$ubuntu_name" && ! -L "$extract/$ubuntu_name" ]] || { echo "Invalid Ubuntu archive member." >&2; exit 1; }
[[ -f "$extract/$site_name" && ! -L "$extract/$site_name" ]] || { echo "Invalid site index archive member." >&2; exit 1; }
site_bytes="$(stat -c %s "$extract/$site_name")"
if [[ ! "$site_bytes" =~ ^[0-9]+$ ]] || (( site_bytes > 65536 )); then
    echo "Site index exceeds the 64 KiB limit." >&2
    exit 1
fi

for package in "$extract/$debian_name" "$extract/$ubuntu_name"; do
    [[ "$(dpkg-deb -f "$package" Package)" == mouse-master ]] || { echo "Unexpected package name." >&2; exit 1; }
    [[ "$(dpkg-deb -f "$package" Version)" == "$version" ]] || { echo "Filename and package version differ." >&2; exit 1; }
    [[ "$(dpkg-deb -f "$package" Architecture)" == amd64 ]] || { echo "Unexpected package architecture." >&2; exit 1; }
done

manifest_candidate="$work/$version.sha256"
(
    cd "$extract"
    sha256sum -- "$debian_name" "$ubuntu_name"
) > "$manifest_candidate"
manifest="$APTLY_ROOT/mouse-master-state/$version.sha256"
if [[ -e "$manifest" ]] && ! cmp -s "$manifest" "$manifest_candidate"; then
    echo "This package version was already received with different content." >&2
    exit 1
fi

repo_contains() {
    local repo=$1 identity=$2 package
    while IFS= read -r package; do
        [[ "$package" == "$identity" ]] && return 0
    done < <(aptly -config="$APTLY_CONFIG" repo show -with-packages "$repo" | awk '/^Packages:$/ { packages=1; next } packages { print $1 }')
    return 1
}

repo_latest() {
    local repo=$1 package package_version latest=
    while IFS= read -r package; do
        [[ "$package" == mouse-master_*_amd64 ]] || continue
        package_version="${package#mouse-master_}"
        package_version="${package_version%_amd64}"
        if [[ -z "$latest" ]] || dpkg --compare-versions "$package_version" gt "$latest"; then
            latest="$package_version"
        fi
    done < <(aptly -config="$APTLY_CONFIG" repo show -with-packages "$repo" | awk '/^Packages:$/ { packages=1; next } packages { print $1 }')
    printf '%s' "$latest"
}

for entry in "mouse-master-trixie:$debian_name" "mouse-master-resolute:$ubuntu_name"; do
    repo="${entry%%:*}"
    package_name="${entry#*:}"
    latest="$(repo_latest "$repo")"
    identity="mouse-master_${version}_amd64"
    if [[ -n "$latest" ]] && dpkg --compare-versions "$version" lt "$latest"; then
        printf 'Refusing downgrade: incoming %s, %s already has %s.\n' "$version" "$repo" "$latest" >&2
        exit 1
    fi
    aptly -config="$APTLY_CONFIG" repo add -force-replace "$repo" "$extract/$package_name"
done

prefix="apt/mouse-master-releases/$version"
trixie_snapshot="mouse-master-trixie-$version"
resolute_snapshot="mouse-master-resolute-$version"
if ! aptly -config="$APTLY_CONFIG" snapshot show "$trixie_snapshot" >/dev/null 2>&1; then
    aptly -config="$APTLY_CONFIG" snapshot create "$trixie_snapshot" from repo mouse-master-trixie
fi
if ! aptly -config="$APTLY_CONFIG" snapshot show "$resolute_snapshot" >/dev/null 2>&1; then
    aptly -config="$APTLY_CONFIG" snapshot create "$resolute_snapshot" from repo mouse-master-resolute
fi

publish_snapshot() {
    local suite=$1 snapshot=$2
    if aptly -config="$APTLY_CONFIG" publish show "$suite" "$prefix" >/dev/null 2>&1; then
        return
    fi
    aptly -config="$APTLY_CONFIG" publish snapshot \
        -batch \
        -acquire-by-hash \
        -architectures=amd64 \
        -component=main \
        -distribution="$suite" \
        -suite="$suite" \
        -origin=Mouse-Master \
        -label="Mouse Master" \
        -gpg-key="$key_id" \
        -passphrase-file="$PASSPHRASE_FILE" \
        "$snapshot" "$prefix"
}
publish_snapshot trixie "$trixie_snapshot"
publish_snapshot resolute "$resolute_snapshot"

published="$APTLY_ROOT/public/$prefix"
[[ -s "$published/dists/trixie/InRelease" && -s "$published/dists/resolute/InRelease" ]] || {
    echo "Both signed InRelease files must exist before switching the public URL." >&2
    exit 1
}
public_key="$published/cursos-repo.gpg"
gpg --batch --export "$key_id" > "$public_key"
[[ -s "$public_key" ]] || { echo "Could not export the public signing key." >&2; exit 1; }
gpgv --keyring "$public_key" "$published/dists/trixie/InRelease"
gpgv --keyring "$public_key" "$published/dists/resolute/InRelease"
for suite in trixie resolute; do
    release_file="$published/dists/$suite/InRelease"
    grep -Fqx "Codename: $suite" "$release_file" || {
        printf 'Unexpected codename in %s metadata.\n' "$suite" >&2
        exit 1
    }
    grep -Fqx "Architectures: amd64" "$release_file" || {
        printf 'Unexpected architecture in %s metadata.\n' "$suite" >&2
        exit 1
    }
    grep -Fqx "Components: main" "$release_file" || {
        printf 'Unexpected component in %s metadata.\n' "$suite" >&2
        exit 1
    }
done


debian_versioned="$DOCROOT/apt/releases/mouse-master/$version"
install -d -o "$SITE_USER" -g psacln -m 0755 \
    "$DOCROOT/apt" \
    "$DOCROOT/apt/releases" \
    "$DOCROOT/apt/releases/mouse-master"
if [[ -L "$debian_versioned" || ( -e "$debian_versioned" && ! -d "$debian_versioned" ) ]]; then
    echo "Versioned public path exists but is not a directory." >&2
    exit 1
fi

if [[ ! -e "$debian_versioned" ]]; then
    release_stage="$(mktemp -d "$DOCROOT/apt/releases/mouse-master/.${version}.XXXXXXXX")"
    rsync -a --delete "$published/" "$release_stage/"
    chown -R "$SITE_USER":psacln "$release_stage"
    find "$release_stage" -type d -exec chmod 0755 {} +
    find "$release_stage" -type f -exec chmod 0644 {} +
    mv -- "$release_stage" "$debian_versioned"
fi
[[ -s "$debian_versioned/cursos-repo.gpg" ]] || { echo "Published release directory is incomplete." >&2; exit 1; }
[[ -s "$debian_versioned/dists/trixie/InRelease" && -s "$debian_versioned/dists/resolute/InRelease" ]] || {
    echo "Published release directory is missing a suite." >&2
    exit 1
}

link_tmp="$DOCROOT/apt/.mouse-master-link.$$"
runuser -u "$SITE_USER" -- ln -s "releases/mouse-master/$version" "$link_tmp"
current_link="$DOCROOT/apt/mouse-master"
if [[ -e "$current_link" && ! -L "$current_link" ]]; then
    echo "Refusing to replace a non-symlink public path." >&2
    exit 1
fi
mv -Tf -- "$link_tmp" "$current_link"
if [[ -L "$DOCROOT/index.html" || ( -e "$DOCROOT/index.html" && ! -f "$DOCROOT/index.html" ) ]]; then
    echo "Refusing to replace an unexpected Plesk index path." >&2
    exit 1
fi
site_stage="$DOCROOT/.index.html.$version.$$"
install -o "$SITE_USER" -g psacln -m 0644 "$extract/$site_name" "$site_stage"
mv -Tf -- "$site_stage" "$DOCROOT/index.html"
site_stage=
install -o root -g root -m 0600 "$manifest_candidate" "$manifest"
printf '%s\n' "$version" > "$APTLY_ROOT/mouse-master-state/current-version.tmp"
chmod 0600 "$APTLY_ROOT/mouse-master-state/current-version.tmp"
mv -f -- "$APTLY_ROOT/mouse-master-state/current-version.tmp" "$APTLY_ROOT/mouse-master-state/current-version"
printf 'Published Mouse Master %s (trixie, resolute) at %s\n' "$version" "$DOCROOT/apt/mouse-master"
