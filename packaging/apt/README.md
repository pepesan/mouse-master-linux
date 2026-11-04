# Mouse Master APT repository operations

This directory is the version-controlled source for non-secret APT publisher configuration. It targets Debian 13 (`trixie`) and Ubuntu 26.04 (`resolute`), both `amd64`.

**Current state:** signed APT suites `trixie` and `resolute` publish Mouse Master `0.1.0-7`. The bilingual landing page is live at `https://repo.cursosdedesarrollo.com/`. Both `InRelease` URLs return HTTP 200 without authentication; production signatures verify with fingerprint `2C38F5325DF7EE2187803C035C8B354C1929C97A`. The GitHub Actions build, install matrix and local Ubuntu package-upgrade check passed.

## Host layout

- aptly config template: `aptly.conf`; installed on Rivendel as `/etc/aptly.conf`.
- aptly database, repositories, package pool and snapshots: `/var/lib/aptly/`.
- Plesk document root: `/var/www/vhosts/cursosdedesarrollo.com/repo.cursosdedesarrollo.com/`.
- Public APT prefix: `apt/mouse-master/` under that document root.
- Published suites: `dists/trixie/` and `dists/resolute/`; component `main`.
- Local aptly repositories: `mouse-master-trixie` and `mouse-master-resolute`.
- GPG signing keyring and signing files: `/etc/mouse-master-apt/`; the private keyring is `/etc/mouse-master-apt/gnupg/`. Never copy them into this repository, GitHub Actions, or the document root.

Plesk/Nginx serves the public files statically over HTTPS. aptly generates repository metadata and signatures. Do not configure HTTP authentication for the APT path.

## Backup and recovery

Back up these paths from Rivendel with encryption and restricted access:

1. `/var/lib/aptly/` — canonical repository database, package files, snapshots and import manifests.
2. `/etc/aptly.conf` — active aptly configuration; keep it consistent with `aptly.conf` here.
3. `/var/www/vhosts/cursosdedesarrollo.com/repo.cursosdedesarrollo.com/apt/` — active `mouse-master` symlink and versioned published trees under `releases/mouse-master/`.
4. `/etc/mouse-master-apt/` — private GPG keyring, passphrase, fingerprint and the local publication gate. Encrypt this backup and restrict access.
5. `/root/mouse-master-apt-signing-recovery/` — encrypted private-key export and revocation certificate; protect the passphrase separately. Keep an independent copy in 1Password.
6. `/usr/local/sbin/mouse-master-apt-import`, `/usr/local/sbin/mouse-master-apt-enable-publishing`, `/etc/sudoers.d/mouse-master-apt-publisher`, and the dedicated deploy account's restricted `authorized_keys`.
7. Plesk domain/hosting configuration and certificate using Plesk Backup Manager or the host-level backup. Do not edit or back up generated vhost files as a substitute for Plesk's domain configuration backup.
8. GitHub `apt-publish` Environment secret `RIVENDEL_SSH_PRIVATE_KEY`; keep it in a secret manager or rotate the deploy key and `authorized_keys` if unavailable. The pinned public SSH host key is versioned at `known_hosts`.

Test restoration to a staging directory/host before relying on backups. Do not include secrets in Git. GitHub Environment secrets are credentials; rotate them through GitHub and the restricted host account if recovery is needed.

**1Password recovery:** the owner confirmed that the encrypted private-key export, passphrase, fingerprint and revocation certificate are saved in the private 1Password Secure Note `Mouse Master APT — repo.cursosdedesarrollo.com — signing key`. Keep this independent copy current; the publication gate records that confirmation on Rivendel.

## CI publishing and safety gate

The workflow always runs Rust and full application checks. Package builds run for changes to `app/`, `crates/`, `data/`, root build manifests, Debian packaging files other than the generated revision/changelog, or the DEB build scripts. `debian/revision` and `debian/changelog` are handled separately: metadata-only changes run a no-increment matrix validation, and only their merge push to `main` is publish-ready. README/docs-only changes skip the DEB matrix.

For a package-input change on `main`, CI builds and smoke-tests both distributions with the next revision, then opens or updates `automation/deb-revision` as a PR. CI dispatches a validation run on that branch so its required checks exist despite using `GITHUB_TOKEN`. The PR must pass Rust, full-build and Debian/Ubuntu DEB checks and be merged before publication. The merge build reuses the recorded revision without incrementing it again; only that owner-triggered push to `main` can create the versioned GitHub Release and publish APT. No CI job pushes revision metadata directly to `main`.

Manual dispatch skips DEB work by default. Setting `force_package` prepares the revision PR; it does not publish early. Secondary branches and PRs can build/test packages but never publish. `publish-apt` downloads the tested artifacts, validates package/version/architecture, and sends both `.deb` files plus `index.html` over SSH. The host key is pinned in `known_hosts`; the `apt-publish` GitHub Environment must contain secret `RIVENDEL_SSH_PRIVATE_KEY`.

Rivendel accepts that key only as user `apt-publisher`, with SSH forwarding/PTY disabled and a forced command to `/usr/local/sbin/mouse-master-apt-import`. The importer validates artifacts, signs both suites with the host-local key, verifies both signatures, stages a versioned static tree, atomically switches `apt/mouse-master`, and installs the bilingual root page from `packaging/apt/site/index.html`. CI never receives the APT signing private key. The dependent `verify-apt` matrix job checks public HTTP 200 responses, runs `apt-get update`, and installs the exact published version inside Debian 13 and Ubuntu 26.04 containers.

Server setup scripts:

1. `scripts/apt-repo-setup.sh` installs the aptly configuration and creates the two local repositories.
2. `scripts/apt-repo-signing-key-setup.sh` creates the signing key, protected passphrase file and recovery material. It does **not** enable publication.
3. `scripts/apt-repo-deploy-user-setup.sh <public-key-file>` installs the restricted SSH account, importer and publication-gate helper.
4. After the owner confirms the recovery material is saved in 1Password, run `/usr/local/sbin/mouse-master-apt-enable-publishing` interactively. This creates `/etc/mouse-master-apt/publish-enabled`; without that file, the importer refuses publication.

Live checks passed: both signed `InRelease` files return HTTP 200 without authentication:

- `https://repo.cursosdedesarrollo.com/apt/mouse-master/dists/trixie/InRelease`
- `https://repo.cursosdedesarrollo.com/apt/mouse-master/dists/resolute/InRelease`

The public key is `https://repo.cursosdedesarrollo.com/apt/mouse-master/cursos-repo.gpg`.

After the first live checks succeeded, install the repository key once:

```sh
sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSLo /etc/apt/keyrings/cursos-repo.gpg https://repo.cursosdedesarrollo.com/apt/mouse-master/cursos-repo.gpg
sudo chmod 0644 /etc/apt/keyrings/cursos-repo.gpg
```

## Client sources (target configuration)

Debian 13:

```text
Types: deb
URIs: https://repo.cursosdedesarrollo.com/apt/mouse-master
Suites: trixie
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/cursos-repo.gpg
```

Save the stanza as `/etc/apt/sources.list.d/mouse-master.sources`, then run:

```sh
sudo apt update
sudo apt install mouse-master
```

Ubuntu 26.04:

```text
Types: deb
URIs: https://repo.cursosdedesarrollo.com/apt/mouse-master
Suites: resolute
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/cursos-repo.gpg
```

Save the stanza as `/etc/apt/sources.list.d/mouse-master.sources`, then run:

```sh
sudo apt update
sudo apt install mouse-master
```

## First run: service and device permissions

The DEB package reloads the udev rule and reapplies it to existing devices when installed or upgraded. Launch **Mouse Master**; if the service is stopped, click **Start service**. If button actions remain paused because `/dev/uinput` is inaccessible, click **Grant access** and authenticate. That action retries the same udev rule installation and restarts the service. Device settings can work before virtual input access is granted; button actions need `/dev/uinput`.

Verify the setup from a terminal:

```sh
mouse-masterctl doctor
mouse-masterctl list
```

The repository is live. CI successfully ran `apt-get update` and installed the exact published version from each corresponding suite in Debian 13 and Ubuntu 26.04 containers. Configure only your distribution's stanza above.
