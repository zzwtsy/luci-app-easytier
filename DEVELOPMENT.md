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

- 默认版本和各架构 SHA256 保存在 `easytier/common.mk` 与 `version.mk`。
- 自定义版本必须同时设置 `EASYTIER_VERSION` 和该资产的 `EASYTIER_HASH`；缺少摘要时构建应失败。
- 发布构建应保留源校验，不在设备运行时下载、不跳过摘要验证。
- ARM 包架构通过 OpenWrt `ARCH_PACKAGES` 映射到上游 ARM 或 ARMv7 资产。

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

- shell 文件通过 `sh -n`。
- 菜单和 ACL JSON 可解析。
- JavaScript 文件可解析，LuCI 模块名和文件路径匹配。
- 翻译通过 `msgfmt --check`。
- `tests/firewall.sh` 覆盖默认拒绝、本机访问开关、四种转发方向、总开关清理、幂等更新和旧配置迁移。
- `tests/check-arch-mapping.sh` 核对 ARM soft-float/hard-float 与其他受支持架构的上游资产映射。
- PR smoke 运行静态检查和 8 个代表目标 × 3 个 SDK；手动完整构建覆盖 22 个目标 × 3 个 SDK。
- 在 OpenWrt SDK 中分别构建 LuCI 包与核心包，确认目标架构和包格式。
- 在设备上核对服务启动/停止、UCI 保存、自动接口/防火墙开关、TOML 启动、上传校验和 Web 数据库重置。
