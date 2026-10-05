# luci-app-easytier

English | [简体中文](README.md)

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-24.10%2B-orange.svg)](https://openwrt.org)

A LuCI application for configuring and managing [EasyTier](https://github.com/EasyTier/EasyTier) on OpenWrt.

## UI preview

![EasyTier overview and program management](docs/image/Overview.png)

<details>
<summary>View settings, diagnostics, configuration file, and Web Console pages</summary>

![EasyTier settings](docs/image/Settings.png)

![EasyTier diagnostics](docs/image/Diagnostics.png)

![EasyTier configuration file](docs/image/ConfigurationFile.png)

![EasyTier Web Console settings](docs/image/WebConsole.png)

</details>

## Differences from upstream

This project is based on the [official EasyTier LuCI project](https://github.com/EasyTier/luci-app-easytier) and targets OpenWrt 24.10 and later. EasyTier Core comes from [official releases](https://github.com/EasyTier/EasyTier/releases); this repository focuses on the LuCI integration, service management, and OpenWrt package build and distribution.

- **LuCI and platform support:** Uses LuCI JavaScript views and rpcd ACLs, targeting OpenWrt 24.10, 25.12, and later. The upstream project centers on the legacy LuCI Lua architecture and lists support for OpenWrt 18.06 through 26.x.
- **Build and distribution:** Pins the EasyTier version for each target architecture and verifies its SHA256 during the build. It also provides signed IPK/APK package feeds. Devices update the core through the package manager; the service does not download binaries at startup.
- **Runtime maintenance:** Optionally checks configured IPv4 targets and restarts EasyTier Core when all targets are unreachable.

UCI configuration, TOML editing, peer diagnostics, binary upload, and Web Console management overlap with the upstream project. The main differences are the OpenWrt integration and package maintenance workflows.

## Supported platforms

- OpenWrt 24.10, 25.12, and later, including Snapshot.
- OpenWrt architectures for which EasyTier publishes Linux binaries: ARM, AArch64, MIPS, MIPSel, and x86_64. Check the build output for the exact target architecture.
- LuCI JavaScript views, rpcd ACLs, and procd service management. Legacy LuCI Lua pages are not supported.

## Install

Download the package matching your device architecture and OpenWrt release from Releases. OpenWrt 24.10 uses IPK; OpenWrt 25.12 and later use APK. Install one core package with the LuCI application:

OpenWrt 24.10:

```sh
opkg install /tmp/easytier_*.ipk /tmp/luci-app-easytier_*.ipk
```

OpenWrt 25.12 and later:

```sh
apk add --allow-untrusted /tmp/easytier_*.apk /tmp/luci-app-easytier_*.apk
```

`easytier` includes `easytier-core`, `easytier-cli`, and the embedded Web Console binary where supported by the architecture. Use `easytier-noweb` instead on storage-constrained devices or when the embedded Web Console is not needed. The two core packages conflict and cannot be installed together.

You can install only `luci-app-easytier` and upload a custom build from the program management section of **VPN → EasyTier → Overview**. The plugin does not download binaries on the device during boot or service startup.

### Install from the GitHub Pages package feed

Signed feed packages are built for matching OpenWrt 24.10.8 and 25.12.5 SDKs. Each SDK and architecture feed keeps the current EasyTier packages; older versions remain available from Releases. Use the package architecture for your device. On 24.10, check it with `opkg print-architecture`; on 25.12 and later, use `apk --print-arch`. For Snapshot and other point releases, use the matching package archive from Releases.

OpenWrt 24.10.8:

```sh
. /etc/openwrt_release
FEED_BASE=https://zzwtsy.github.io/luci-app-easytier
ARCH="$DISTRIB_ARCH"
wget -O /tmp/easytier-opkg.pub "$FEED_BASE/keys/easytier-opkg.pub"
opkg-key add /tmp/easytier-opkg.pub
echo "src/gz easytier $FEED_BASE/feeds/24.10.8/$ARCH/packages_ci" >> /etc/opkg/customfeeds.conf
opkg update
opkg install easytier luci-app-easytier luci-i18n-easytier-zh-cn
```

OpenWrt 25.12.5:

```sh
. /etc/openwrt_release
FEED_BASE=https://zzwtsy.github.io/luci-app-easytier
ARCH="$DISTRIB_ARCH"
wget -O /etc/apk/keys/easytier-apk.pem "$FEED_BASE/keys/easytier-apk.pem"
echo "$FEED_BASE/feeds/25.12.5/$ARCH/packages_ci/packages.adb" >> /etc/apk/repositories.d/customfeeds.list
apk update
apk add easytier luci-app-easytier luci-i18n-easytier-zh-cn
```

For storage-constrained devices or when the embedded Web Console is not needed, replace `easytier` with `easytier-noweb`. The two core packages conflict. Update feed-installed packages with the corresponding package manager. Manual upload is for custom builds and custom binary paths.

## Features

- Configure EasyTier CLI options through UCI forms or edit the TOML configuration file.
- Start, stop, and supervise EasyTier Core and the Web Console with procd.
- Optionally monitor configured IPv4 targets and restart EasyTier Core when all targets are unreachable.
- View service state, versions, memory use, TUN interface details, connection information, and system logs.
- Manage the EasyTier network interface, firewall rules, and forwarding rules from UCI settings.
- Upload EasyTier ELF binaries or ZIP, TAR, TAR.GZ, and TGZ archives. Uploads are limited to 100 MiB; archive entries, ELF format, and EasyTier version output are checked before installation.
- Configure the Web Console, OpenID Connect, webhooks, and database path.

Plugin settings are stored in `/etc/config/easytier`; the TOML file is stored in `/etc/easytier/config.toml`. The LuCI menu is **VPN → EasyTier**.

## Build from source

Add this repository as an OpenWrt feed:

```sh
echo "src-link easytier /path/to/luci-app-easytier" >> feeds.conf
./scripts/feeds update easytier
./scripts/feeds install -a -p easytier
make menuconfig
make package/feeds/easytier/easytier/compile V=s
make package/feeds/easytier/luci-app-easytier/compile V=s
```

Replace `easytier` with `easytier-noweb` if needed. Core packages fetch a pinned EasyTier GitHub Release asset and verify its SHA256 during the build. For a custom EasyTier version, set `EASYTIER_VERSION` and provide the corresponding asset SHA256 with `EASYTIER_HASH`.

See the [development guide](DEVELOPMENT_EN.md) for implementation and validation details. GitHub Actions builds packages for OpenWrt 24.10, 25.12, and Snapshot.

## License

This project is licensed under the [Apache License 2.0](LICENSE).
