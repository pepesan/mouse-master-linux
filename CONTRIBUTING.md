# Contributing to Mouse Master

Thank you for helping! Mouse Master aims to be the best way to use a Logitech mouse on Linux,
and that takes many devices, desktops and hands.

## Ways to help

- **Report your device.** Run `mouse-masterctl info --json` and open a
  [device report](https://github.com/burakgon/mouse-master-linux/issues/new?template=device-report.yml).
  Tell us what works and what does not. This is the single most useful contribution.
- **Draw your mouse.** Artwork lives in `app/assets/devices` (SVG, 400×560, top view, no
  filters) and control positions in `app/qml/Layouts.js`. Look at `mx-master.svg` for the style.
- **Add a desktop.** Desktop actions are in `crates/daemon/src/actions/exec.rs` and focus
  tracking in `crates/daemon/src/window.rs`.
- **Translate** (coming soon), improve the docs, or pick an issue labelled *good first issue*.

## Building

```sh
cargo test --workspace                       # all Rust tests, no hardware needed
cargo run -p mouse-masterd -- --demo -v      # the service on simulated devices
cmake -B build -DBUILD_SERVICE=OFF -DCMAKE_BUILD_TYPE=Debug
cmake --build build && ./build/app/mouse-master
```

Stop the installed service first (`systemctl --user stop mouse-master`) when running a
development build; only one instance can own the D-Bus name.

Useful while working on the app:

- `QT_FORCE_STDERR_LOGGING=1` shows QML warnings in the terminal.
- `MM_SCREENSHOT=/tmp/out.png MM_PAGE=buttons MM_CONTROL=gesture ./build/app/mouse-master`
  renders a page to a file and quits.

## Guidelines

- **Never break a mouse.** The service must leave every control it does not need untouched
  and restore what it changed. New features that write to a device need a test in
  `crates/daemon/src/tests.rs` against the simulator (`crates/hidpp/src/sim.rs`).
- **Match the surrounding code.** `cargo fmt` (see `rustfmt.toml`), `cargo clippy`, and for
  QML the existing component style: colours and sizes come from `Theme.qml`.
- **Keep commits focused** and write messages that explain *why*.
- **Respect trademarks**: describe compatibility ("works with MX Master 3S") but do not use
  Logitech logos or product photos.

## Contribution workflow

Both `main` and `develop` are protected. Use GitFlow; do not push directly or force-push either
branch:

- Start `feature/<name>` and `bugfix/<name>` branches from `develop`; open PRs back to
  `develop`.
- Start `release/<version>` from `develop`; stabilize it there, then open a PR to `main`.
- For urgent production fixes, start `hotfix/<name>` from `main` and open a PR to `main`.
- After a release or hotfix reaches `main`, bring `main` back into `develop` with a PR so the
  branches do not drift.

Do not merge feature or ordinary bug-fix PRs directly into `main`. Release and hotfix PRs are
the only normal routes to `main`.

Before opening a PR:

1. Update your branch from its correct base (`develop` for features and bug fixes; `main` for
   hotfixes).
2. Keep the change focused and explain its purpose in the PR description.
3. Describe the tests you ran and complete the applicable checklist in the PR template.
4. For device-affecting changes, include simulator coverage; report real-device results when
   available, including model, connection type and desktop.

PRs must pass the required checks before they can be merged:

- `Service, CLI and protocol`
- `Full build (Arch Linux, Qt 6)`
- `DEB package validation`

The DEB validation check is successful for documentation-only changes when the package matrix
is correctly skipped. Package builds run when application, build or Debian packaging inputs
change; README and documentation changes alone do not build or publish packages.

### DEB package revision and release flow

Do not increment `debian/revision` or edit the generated package version manually for an
ordinary application change. Feature and bug-fix PRs to `develop` run CI but never publish.
When package-input changes enter `main` through a release or hotfix, CI builds and tests Debian
13 and Ubuntu 26.04 packages with the next revision, then opens or updates a pull request from
`automation/deb-revision` to `main`. Review and merge that PR through the same protected-`main`
process. The resulting `main` run uses the recorded revision without incrementing it again,
then publishes the GitHub Release and signed APT repository. The release keeps the upstream
application version and increments only the Debian revision. Merge `main` back into `develop`
after the release PRs are complete.

To request a package build without package-input changes, the repository owner can manually
dispatch the CI workflow on `main` with `force_package` enabled. This prepares the revision PR;
it does not bypass review or publish packages from a secondary branch. Only the qualifying
owner-triggered `main` workflow publishes.

When editing GitHub Actions steps that run inside Debian or Ubuntu containers, use POSIX
`sh` syntax unless the step explicitly selects Bash. Container `run` steps default to `sh`;
Bash-only conditionals such as `[[ ... ]]` can silently take the wrong branch.

## Protocol notes

If you add a HID++ feature, document the byte layout in the module, cite where it came from
(Logitech's published documents, Solaar, logiops, or your own captures), and add parsing
tests with real replies from a device where possible.

By contributing you agree that your contributions are licensed under GPL-3.0-or-later.
