# 开发指南

[English](DEVELOPMENT_EN.md) | 简体中文

## 目标平台与结构

目标平台为 OpenWrt 24.10、25.12 及更新版本。LuCI 使用 JavaScript `view`、`form`、`uci`、`fs` 和 `poll` 模块；菜单由 `menu.d` JSON 注册，页面能力由 rpcd ACL 控制。系统服务使用 `/etc/rc.common` 和 procd。

```text
htdocs/luci-static/resources/view/easytier/   LuCI 页面
htdocs/luci-static/resources/easytier/        页面共用模块
root/usr/share/luci/menu.d/                   LuCI 菜单
root/usr/share/rpcd/acl.d/                    最小权限规则
root/usr/libexec/easytier/                    固定操作与状态辅助程序
root/etc/init.d/easytier                      procd 服务定义
root/usr/share/easytier/firewall.sh            UCI 网络和防火墙管理
```

## 跨文件改动地图

新增或修改配置项时，沿着数据流核对相关文件：

| 配置类型 | 需要同步检查 |
| --- | --- |
| LuCI 设置 | `htdocs/luci-static/resources/view/easytier/` 中对应表单、`root/etc/config/easytier` 默认值、`root/etc/init.d/easytier` 加载的服务逻辑、`root/usr/share/easytier/firewall.sh`（若影响网络规则）、`po/templates/easytier.pot`、`po/zh_Hans/easytier.po` 和相关回归检查 |
| RPC 查询或管理操作 | `htdocs/luci-static/resources/easytier/common.js` 与对应页面调用、`root/usr/libexec/easytier/rpc` 或 `manage` 的服务端白名单、`root/usr/share/rpcd/acl.d/luci-app-easytier.json` 的精确权限，以及 RPC 合约检查 |
| 包版本、校验和或构建目标 | `version.mk`、`config/build-targets.json`、共享检查脚本及 `.github/workflows/`；不要在工作流中另行复制目标列表 |

跨文件修改完成后，使用统一入口检查：

```sh
npm ci
npm run check
```

本地还需安装 ShellCheck 和 GNU gettext。联网下载上游 ARM 资产的 ABI 检查由 CI 单独运行：`.github/scripts/check-arm-abi.sh`。

## LuCI 页面与权限

- 页面通过 LuCI 原生模块访问 UCI、文件和固定辅助程序，不增加前端框架或构建步骤。
- 页面文案使用 `_()`，并同步维护 `po/templates/easytier.pot` 与 `po/zh_Hans/easytier.po`。
- ACL 仅开放插件 UCI 配置、必要的配置文件、固定辅助程序操作、指定服务动作和固定上传目标。
- 辅助程序必须自行校验参数。不要把页面输入拼接到 shell 命令中，也不要通过 `eval`、`sh -c` 或通配命令开放任意执行能力。
- 新增文件读写时，同时检查文件路径 ACL 和 `ubus.file` 方法权限；删除文件需要 `remove` 权限。

## 服务管理

- 前台程序作为 procd 命令直接启动；不要用 shell 后台符号、`nohup` 或进程名匹配来托管服务。
- UCI 选项以独立参数传递，列表值按条追加。添加 CLI 选项时同时检查配置表单、启动脚本和防火墙规则是否一致。
- 网络接口开关和防火墙规则开关各自管理自己的 UCI 条目。规则值变为空或无效时要删除旧条目，不能继续放行旧端口。
- 服务不负责在线获取或自我更新二进制。核心程序包由 OpenWrt 包管理器更新；手动上传仅服务于自定义构建和路径。

## 核心程序包

`easytier/Makefile` 与 `easytier-noweb/Makefile` 共用 `easytier/common.mk`。包使用 OpenWrt 的下载和校验流程，资产名采用上游 Release 命名 `easytier-linux-<arch>-v<version>.zip`。

- `EASYTIER_VERSION` 固定上游核心程序版本；`LUCI_APP_VERSION` 固定 LuCI 插件版本和仓库 Release 标签。
- 上游核心程序的默认版本、LuCI 版本和各架构 SHA256 集中保存在 `version.mk`。
- 自定义核心版本必须同时设置 `EASYTIER_VERSION` 和该资产的 `EASYTIER_HASH`；缺少摘要时构建应失败。
- 发布构建应保留源校验，不在设备运行时下载、不跳过摘要验证。
- ARM 包架构通过 OpenWrt `ARCH_PACKAGES` 映射到上游 ARM 或 ARMv7 资产。

## 维护与发布流程

### 更新 EasyTier Core

1. 从 EasyTier 官方 Release 选择新版本，按 `easytier/arch.mk` 的映射核对每种上游资产架构，并计算对应资产的 SHA256。
2. 在 `version.mk` 更新 `EASYTIER_DEFAULT_VERSION` 和该版本所有资产的 `EASYTIER_HASH_*`；不要只更新当前手头设备对应的架构。
3. `EASYTIER_VERSION` 与 `LUCI_APP_VERSION` 用途不同。只做构建验证时可只更新 Core 版本；要发布包含新 Core 的完整软件包时，也要提升 `LUCI_APP_VERSION`，因为它决定 LuCI 包版本和仓库 Release tag。
4. 运行 `npm run check`、架构映射检查和 `.github/scripts/check-arm-abi.sh`。发布时从仓库默认分支手动运行 `build.yml`，填写与 `LUCI_APP_VERSION` 一致的 tag（可带 `v`）并选择 `all`。PR smoke 覆盖 8 个代表架构 × 3 个 SDK；完整发布构建覆盖 22 个架构 × 3 个 SDK。

### 扩展 SDK 或架构

同步检查 `config/build-targets.json`、`easytier/arch.mk`、`build.yml` 的手动架构选项，以及 README 和发布包指南中的 SDK 版本说明。`npm run check` 会验证构建目标和手动架构选项一致；新架构还应核对上游资产映射及 ABI。

### 软件源签名密钥

GitHub Secrets `OPKG_FEED_SIGNING_KEY` 与 `.github/pages/keys/easytier-opkg.pub` 配对；`APK_FEED_SIGNING_KEY` 与 `.github/pages/keys/easytier-apk.pem` 配对。发布和签名索引验证都要求两种私钥 Secret 可用。设备安装的公钥是本地信任配置，仓库替换公钥不会自动更新设备上的信任密钥；密钥轮换需要另行安排设备迁移，本指南不改变当前签名流程。

### 首次启动的防火墙配置迁移

服务加载防火墙配置时，如果迁移标记 `firewall_input_migration_version` 不是 `1`，且 `allow_router_input` 尚未设置，插件会将旧选项 `auto_config_firewall` 的值 `1` 映射为 `1`，其他值映射为 `0`；旧选项缺失时按 `1` 处理。已有 `allow_router_input` 值会保留。迁移完成后写入标记并提交 `easytier` UCI，此后启动不会再次覆盖用户选择。相关行为由 `tests/firewall.sh` 覆盖。

手动上传辅助程序只接受固定的 EasyTier 文件名。归档成员路径先校验，再提取至临时区；目标 ELF 需有正确文件头，且在超时限制内返回 EasyTier 版本信息。安装前先暂存并校验所有目标，替换失败时恢复原文件。

## 本地构建

在 OpenWrt 24.10 或更新版本 SDK 中将本仓库配置为 feed：

```sh
echo "src-link easytier /path/to/luci-app-easytier" >> feeds.conf
./scripts/feeds update easytier
./scripts/feeds install -a -p easytier
make menuconfig
make package/feeds/easytier/easytier/compile V=s
make package/feeds/easytier/easytier-noweb/compile V=s
make package/feeds/easytier/luci-app-easytier/compile V=s
```

`easytier` 包可选安装内嵌 Web 控制台；`easytier-noweb` 不包含它。仓库的 GitHub Actions 构建 OpenWrt 24.10、25.12 和 Snapshot 包。

## 提交前检查

- `npm run check` 统一运行 ESLint、ShellCheck、Shell 语法检查、JSON 校验、gettext 格式与翻译键检查，以及主机侧回归检查。
- `tests/firewall.sh` 覆盖默认拒绝、本机访问开关、四种转发方向、总开关清理、幂等更新和旧配置迁移。
- `tests/check-arch-mapping.sh` 核对 ARM soft-float/hard-float 与其他受支持架构的上游资产映射。
- `.github/scripts/check-arm-abi.sh` 会联网下载 EasyTier 上游 ARM 资产，验证固定 SHA256 和 ELF ABI；CI 单独运行。
- PR smoke 运行静态检查和 8 个代表目标 × 3 个 SDK；手动完整构建覆盖 22 个目标 × 3 个 SDK。
- 在 OpenWrt SDK 中分别构建 LuCI 包与核心包，确认目标架构和包格式。
- 在设备上核对服务启动/停止、UCI 保存、自动接口/防火墙开关、TOML 启动、上传校验和 Web 数据库重置。
