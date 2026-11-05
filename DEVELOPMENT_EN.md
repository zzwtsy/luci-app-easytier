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

## Maintenance and release workflows

### Updating EasyTier Core

1. Choose a new EasyTier upstream release, check each asset architecture against `easytier/arch.mk`, and calculate the SHA256 for every mapped asset.
2. Update `EASYTIER_DEFAULT_VERSION` and all `EASYTIER_HASH_*` values for that release in `version.mk`. Do not update only the architecture available on your own device.
3. `EASYTIER_VERSION` and `LUCI_APP_VERSION` serve different purposes. A build-only check can change only the Core version. To publish packages containing the new Core, also increment `LUCI_APP_VERSION`, which versions the LuCI package and repository Release tag.
4. Run `npm run check`, the architecture mapping checks, and `.github/scripts/check-arm-abi.sh`. For a release, manually run `build.yml` from the repository default branch, enter a tag matching `LUCI_APP_VERSION` (optional `v` prefix), and select `all`. PR smoke covers 8 representative architectures × 3 SDKs; a full release builds 22 architectures × 3 SDKs.

### Synchronizing EasyTier 2.7.0

The synchronized upstream LuCI commit is `9c51d3f8d2bfcefd039f2ff2354c6a7674293a06`. New UCI fields keep the upstream names, while their behavior is ported to JavaScript forms and `service.sh`. Legacy Lua pages and runtime download scripts remain deleted.

- Keep legacy WireGuard values and refuse startup with instructions to supply a portal key, named clients, and freshly exported client configurations. Pass the key only through `ET_VPN_PORTAL_PRIVATE_KEY`, setting it together with `TZ` to preserve both environment values.
- Expand official Web username shortcuts into full URLs at runtime. Pass the multithreading choice explicitly as `true` or `false` to preserve the previous UI semantics.
- Pass `--gateway-relay-data` without a value. The trailing `true` in the upstream script is rejected by the official 2.7.0 binary.
- Keep synchronous TOML validation and `respawn 3600 5 5`. Diagnostics remain on demand, with serialized queries, hidden-page refresh suspension, and statistics/ACL translations. Copying preserves raw output.
- Set `EASYTIER_TEST_CORE` and `EASYTIER_TEST_WEB` to official host binaries to check generated arguments in `tests/service.sh`. The regular checks do not require these binaries. VPN Portal operation, Web database migration, and rollback still need device validation.

### Adding an SDK or architecture

Review `config/build-targets.json`, `easytier/arch.mk`, the manual architecture choices in `build.yml`, and SDK version references in the READMEs and generated package guide. `npm run check` verifies that the target manifest and manual architecture choices agree. For a new architecture, also verify its upstream asset mapping and ABI.

For stable SDKs, `version` pins the build baseline, `feed_path` independently selects the feed directory, and `feed_aliases` lists old directories to retain. The 25.12.5 SDK currently uses `feed_path: "25.12"` and `feed_aliases: ["25.12.5"]`; 24.10.8 keeps `feed_path: "24.10.8"` with no aliases. Build selection and Release archive names continue to use the exact SDK version. Snapshot publishes only Release archives, without a stable feed.

When upgrading an SDK, retain the series directory and every published compatibility alias. Aliases mirror the series' current signed indexes and packages; they do not pin an old SDK permanently. Publish real files for compatibility directories on GitHub Pages rather than relying on symlinks. A series feed still requires compatibility validation across point releases: check userspace package architecture, ABI, and dependencies, then validate installation and operation on devices. Obtain `kmod-tun` from the official feed matching the device firmware.

### Package feed signing keys

The `OPKG_FEED_SIGNING_KEY` GitHub secret pairs with `.github/pages/keys/easytier-opkg.pub`; `APK_FEED_SIGNING_KEY` pairs with `.github/pages/keys/easytier-apk.pem`. Both private-key secrets are required for releases and signed-index verification. Devices store their trusted public keys locally, so changing a repository public key does not update device trust automatically. Key rotation requires a separate device migration plan; this guide does not change the current signing workflow.

### First-start firewall configuration migration

When the service loads firewall configuration, if `firewall_input_migration_version` is not `1` and `allow_router_input` is unset, the plugin maps a legacy `auto_config_firewall` value of `1` to `1` and any other value to `0`; a missing legacy option defaults to `1`. An existing `allow_router_input` value is preserved. The migration then writes the marker and commits the `easytier` UCI package, so later starts do not overwrite the user's choice. `tests/firewall.sh` covers this behavior.

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
