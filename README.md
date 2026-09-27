# luci-app-easytier

[English](README_EN.md) | 简体中文

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-24.10%2B-orange.svg)](https://openwrt.org)

OpenWrt LuCI 插件，用于配置和管理 [EasyTier](https://github.com/EasyTier/EasyTier)。

## 支持范围

- OpenWrt 24.10、25.12 及更新版本，包括 Snapshot。
- EasyTier 提供 Linux 发布包的 OpenWrt 架构：ARM、AArch64、MIPS、MIPSel 和 x86_64。实际可用包以对应设备架构构建结果为准。
- 使用 LuCI JavaScript 前端、rpcd ACL 和 procd 服务管理，不支持旧版 LuCI Lua 页面。

## 安装

从项目 Releases 下载与设备架构匹配的 APK。核心程序包和 LuCI 插件需要分别安装：

```sh
apk add --allow-untrusted /tmp/easytier_*.apk /tmp/luci-app-easytier_*.apk
```

`easytier` 包含 `easytier-core`、`easytier-cli` 和架构支持时的内嵌 Web 控制台。存储空间有限或不需要内嵌 Web 控制台时，使用 `easytier-noweb` 替代；两个核心包不能同时安装。

也可以只安装 `luci-app-easytier`，然后在 **VPN → EasyTier → 概览** 页面的程序管理区安装自定义构建。插件不会在设备启动或服务启动时联网下载程序。

如果通过 APK 软件源安装，请使用软件源中的包名：

```sh
apk update
apk add easytier luci-app-easytier
```

更新软件源安装的程序时使用 APK 包管理器。手动上传适用于自定义构建或自定义程序路径。

## 功能

- 使用 UCI 表单配置 EasyTier 命令行参数，或编辑 TOML 配置文件。
- 使用 procd 启动、停止和监控 EasyTier Core 与 Web 控制台。
- 可选地按配置的 IPv4 目标检查连通性；全部目标不可达时重启 EasyTier Core。
- 查看服务状态、版本、内存占用、TUN 接口信息、连接信息和系统日志。
- 根据 UCI 配置管理 EasyTier 网络接口、防火墙规则和转发规则。
- 手动上传 EasyTier ELF 程序或 ZIP、TAR、TAR.GZ、TGZ 压缩包。上传大小上限为 100 MiB；安装前会校验归档成员、ELF 文件和 EasyTier 版本信息。
- 配置 Web 控制台、OpenID Connect、Webhook 和数据库路径。

插件配置保存在 `/etc/config/easytier`，TOML 配置保存在 `/etc/easytier/config.toml`。LuCI 菜单位于 **VPN → EasyTier**。

## 从源码构建

将本仓库作为 OpenWrt feed：

```sh
echo "src-link easytier /path/to/luci-app-easytier" >> feeds.conf
./scripts/feeds update easytier
./scripts/feeds install -a -p easytier
make menuconfig
make package/feeds/easytier/easytier/compile V=s
make package/feeds/easytier/luci-app-easytier/compile V=s
```

按需将 `easytier` 替换为 `easytier-noweb`。程序包从 EasyTier GitHub Release 获取固定版本资产，并在构建时校验 SHA256。构建自定义 EasyTier 版本时，需通过 `EASYTIER_VERSION` 指定版本，并通过 `EASYTIER_HASH` 提供该资产的 SHA256。

更多开发约定和验证方式见 [开发指南](DEVELOPMENT.md)。GitHub Actions 构建 OpenWrt 24.10、25.12 和 Snapshot 包。

## 许可证

本项目使用 [Apache License 2.0](LICENSE)。
