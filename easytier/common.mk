PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

EASYTIER_COMMON_DIR:=$(dir $(abspath $(lastword $(MAKEFILE_LIST))))
include $(EASYTIER_COMMON_DIR)arch.mk

PKG_BUILD_DEPENDS:=unzip/host
PKG_LICENSE:=Apache-2.0

# Resolve the binary asset and checksum only when a target SDK provides its architecture.
ifneq ($(strip $(APP_ARCH)),)
PKG_SOURCE:=easytier-linux-$(APP_ARCH)-v$(PKG_VERSION).zip
PKG_SOURCE_URL:=https://github.com/EasyTier/EasyTier/releases/download/v$(PKG_VERSION)

# Fixed release hashes are stored in version.mk. Any other version requires a caller-supplied hash.
ifeq ($(PKG_VERSION),$(EASYTIER_DEFAULT_VERSION))
PKG_HASH:=$(EASYTIER_HASH_$(APP_ARCH))
ifeq ($(strip $(PKG_HASH)),)
$(error No SHA256 is configured for APP_ARCH=$(APP_ARCH))
endif
else
ifeq ($(strip $(EASYTIER_HASH)),)
$(error Set EASYTIER_HASH to the SHA256 of $(PKG_SOURCE) when overriding EasyTier version)
endif
PKG_HASH:=$(EASYTIER_HASH)
endif
endif

include $(INCLUDE_DIR)/package.mk

RSTRIP:=:

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=Network
	TITLE:=A simple, decentralized mesh VPN with WireGuard support.
	DEPENDS:=@(TARGET_x86_64||arm||aarch64||mipsel||mips) +kmod-tun
	CONFLICTS:=$(EASYTIER_CONFLICTS)
	URL:=https://github.com/EasyTier/EasyTier
	MENU:=1
endef

define Package/$(PKG_NAME)/description
  A simple, decentralized mesh VPN with WireGuard support.
endef

ifeq ($(EASYTIER_HAS_WEB),1)
# MIPS 发布包不提供 Web 二进制，因此只在支持的目标上暴露该构建选项。
define Package/$(PKG_NAME)/config
	config EASYTIER_INCLUDE_WEBCONSOLE
		bool "Include Web Console (easytier-web)"
		depends on PACKAGE_$(PKG_NAME)
		depends on !(mips || mipsel)
		default y
		help
		  Install the easytier-web embedded web console.
endef
endif

define Build/Prepare
	# 上游发布的是预编译二进制压缩包；这里只解包，不在 OpenWrt 构建机上重编译。
	mkdir -p $(PKG_BUILD_DIR)
	unzip -o -j $(DL_DIR)/$(PKG_SOURCE) -d $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/easytier-core $(1)/usr/bin/easytier-core
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/easytier-cli $(1)/usr/bin/easytier-cli
ifeq ($(EASYTIER_HAS_WEB),1)
ifdef CONFIG_EASYTIER_INCLUDE_WEBCONSOLE
	# Web 控制台由构建选项控制，避免在未选择时安装不存在的文件。
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/easytier-web-embed $(1)/usr/bin/easytier-web
endif
endif
endef
