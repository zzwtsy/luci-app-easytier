# Development Guide

English | [简体中文](DEVELOPMENT.md)

## Target and structure

The target is OpenWrt 24.10, 25.12, and later. LuCI uses the native JavaScript `view`, `form`, `uci`, `fs`, and `poll` modules. The menu is registered through `menu.d` JSON and page capabilities are controlled by rpcd ACLs. The system service uses `/etc/rc.common` and procd.

```text
htdocs/luci-static/resources/view/easytier/   LuCI pages
htdocs/luci-static/resources/easytier/        Shared page modules
root/usr/share/luci/menu.d/                   LuCI menu
root/usr/share/rpcd/acl.d/                    Least-privilege rules
root/usr/libexec/easytier/                    Fixed operations and status helpers
root/etc/init.d/easytier                      procd service definition
root/usr/share/easytier/firewall.sh            UCI network and firewall management
```

## Cross-file change map

When adding or changing a setting, follow its data flow through the repository:

| Change | Files to review together |
| --- | --- |
| LuCI setting | The matching form under `htdocs/luci-static/resources/view/easytier/`, defaults in `root/etc/config/easytier`, service logic loaded by `root/etc/init.d/easytier`, `root/usr/share/easytier/firewall.sh` when networking is affected, both gettext catalogs, and the related regression checks |
| RPC query or management operation | The call in `htdocs/luci-static/resources/easytier/common.js` or its page, the server-side allowlist in `root/usr/libexec/easytier/rpc` or `manage`, the exact permission in `root/usr/share/rpcd/acl.d/luci-app-easytier.json`, and the RPC contract check |
| Package version, checksum, or build target | `version.mk`, `config/build-targets.json`, shared check scripts, and `.github/workflows/`; do not duplicate target lists in workflow code |

Run the common checks after a cross-file change:

```sh
npm ci
npm run check
```

Install ShellCheck and GNU gettext on the host first. The ARM ABI check downloads upstream assets and runs separately in CI: `.github/scripts/check-arm-abi.sh`.

## LuCI pages and permissions

- Use LuCI's native modules for UCI, file access, and fixed helper operations. Do not add a frontend framework or build step.
- Wrap page strings with `_()` and keep `po/templates/easytier.pot` and `po/zh_Hans/easytier.po` current.
- ACLs should expose only the plugin's UCI settings, required files, fixed helper operations, specific service actions, and the fixed upload destination.
- Helpers must validate their own arguments. Do not interpolate page input into shell commands or add arbitrary execution through `eval`, `sh -c`, or wildcard command access.
- When adding file access, check both the path ACL and the required `ubus.file` methods. File deletion needs the `remove` permission.

## Service management

- Start foreground processes directly through procd. Do not manage them with shell backgrounding, `nohup`, or process-name matching.
- Pass UCI options as separate arguments and append list values one at a time. When adding a CLI option, keep the form, init script, and firewall behavior aligned.
- The interface toggle and firewall toggle manage separate UCI entries. If a port becomes empty or invalid, remove its old rule instead of leaving the previous port open.
- The service does not fetch or self-update binaries online. OpenWrt package management updates packaged binaries; manual upload is for custom builds and paths.

## Core packages

`easytier/Makefile` and `easytier-noweb/Makefile` share `easytier/common.mk`. Packages use OpenWrt's download and checksum flow with the upstream asset name `easytier-linux-<arch>-v<version>.zip`.

- `EASYTIER_VERSION` pins the upstream core binary; `LUCI_APP_VERSION` versions the LuCI package and repository release tag.
- The default upstream core version, LuCI version, and per-architecture SHA256 hashes are centralized in `version.mk`.
- A custom core version must set both `EASYTIER_VERSION` and `EASYTIER_HASH`; the build should fail when the checksum is missing.
- Keep source verification enabled in release builds. Do not download binaries on the device or skip checksum verification.
- Map ARM packages to the upstream ARM or ARMv7 asset using OpenWrt's `ARCH_PACKAGES` value.

The manual upload helper accepts only the supported EasyTier filenames. It validates archive paths before extracting to a temporary directory. Each target ELF must have a valid file header and return EasyTier version information within a timeout. All files are staged and checked before replacement; a failed replacement restores the previous files.

## Local build

Add this repository as a feed in an OpenWrt 24.10 or newer SDK:

```sh
echo "src-link easytier /path/to/luci-app-easytier" >> feeds.conf
./scripts/feeds update easytier
./scripts/feeds install -a -p easytier
make menuconfig
make package/feeds/easytier/easytier/compile V=s
make package/feeds/easytier/easytier-noweb/compile V=s
make package/feeds/easytier/luci-app-easytier/compile V=s
```

The `easytier` package can include the embedded Web Console; `easytier-noweb` omits it. GitHub Actions builds packages for OpenWrt 24.10, 25.12, and Snapshot.

## Before submitting

- `npm run check` runs ESLint, ShellCheck, shell syntax checks, JSON validation, gettext format and translation-key checks, and host-side regression checks.
- `tests/firewall.sh` covers the default deny policy, router input, all forwarding directions, cleanup, idempotence, and legacy migration.
- `tests/check-arch-mapping.sh` checks ARM soft-float/hard-float and other supported asset mappings.
- `.github/scripts/check-arm-abi.sh` downloads EasyTier ARM assets and checks their pinned SHA256 hashes and ELF ABI; CI runs it separately.
- PR smoke runs static checks and 8 representative targets × 3 SDKs; the manual full build covers 22 targets × 3 SDKs.
- Build the LuCI and core packages in an OpenWrt SDK; confirm target architecture and package format.
- On a device, check service start/stop, UCI saves, independent interface/firewall toggles, TOML startup, upload validation, and Web database reset.
