#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
export RUSTUP_TOOLCHAIN=stable

app_version="$(awk '/^project\(mouse-master VERSION / { print $3; exit }' CMakeLists.txt)"
cargo_version="$(awk '
    /^\[workspace\.package\]$/ { in_workspace = 1; next }
    /^\[/ { in_workspace = 0 }
    in_workspace && /^version[[:space:]]*=/ { gsub(/["[:space:]]/, "", $3); print $3; exit }
' Cargo.toml)"
metainfo_version="$(awk -F '\"' '/<release version=/ { print $2; exit }' data/metainfo/io.github.burakgon.MouseMaster.metainfo.xml)"

if [[ ! "$app_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'error: unsupported application version: %s\n' "$app_version" >&2
    exit 1
fi
if [[ "$cargo_version" != "$app_version" ]]; then
    printf 'error: CMake version %s differs from Cargo workspace version %s\n' \
        "$app_version" "$cargo_version" >&2
    exit 1
fi
if [[ "$metainfo_version" != "$app_version" ]]; then
    printf 'error: CMake version %s differs from latest AppStream release %s\n' \
        "$app_version" "$metainfo_version" >&2
    exit 1
fi

package_version="$(dpkg-parsechangelog -S Version)"
revision_file="debian/revision"
current_revision="$(<"$revision_file")"
if [[ ! "$current_revision" =~ ^[0-9]+$ ]]; then
    printf 'error: invalid package revision in %s: %s\n' "$revision_file" "$current_revision" >&2
    exit 1
fi

debian_revision=$((10#$current_revision + 1))
desired_package_version="${app_version}-${debian_revision}"
if dpkg --compare-versions "$desired_package_version" le "$package_version"; then
    printf 'error: next package version %s is not newer than changelog version %s\n' \
        "$desired_package_version" "$package_version" >&2
    exit 1
fi

revision_tmp="$(mktemp "${revision_file}.XXXXXX")"
trap 'rm -f "$revision_tmp"' EXIT
printf '%s\n' "$debian_revision" > "$revision_tmp"
chmod 644 "$revision_tmp"
mv "$revision_tmp" "$revision_file"
trap - EXIT

maintainer="$(awk -F ': ' '$1 == "Maintainer" { print $2; exit }' debian/control)"
date="$(LC_ALL=C date -R)"
changelog_tmp="$(mktemp debian/changelog.XXXXXX)"
trap 'rm -f "$changelog_tmp"' EXIT
{
    printf 'mouse-master (%s) unstable; urgency=medium\n\n' "$desired_package_version"
    printf '  * Debian package revision %s for upstream version %s.\n\n' \
        "$debian_revision" "$app_version"
    printf ' -- %s  %s\n\n' "$maintainer" "$date"
    cat debian/changelog
} > "$changelog_tmp"
chmod 644 "$changelog_tmp"
mv "$changelog_tmp" debian/changelog
trap - EXIT
printf 'Incremented DEB revision to %s (app version %s)\n' "$debian_revision" "$app_version"

command dpkg-buildpackage -us -uc -b
printf 'Built ../mouse-master_%s_amd64.deb\n' "$desired_package_version"

