PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

EASYTIER_COMMON_DIR:=$(dir $(abspath $(lastword $(MAKEFILE_LIST))))
include $(EASYTIER_COMMON_DIR)arch.mk

PKG_BUILD_DEPENDS:=unzip/host
PKG_LICENSE:=Apache-2.0

# Resolve the binary asset and checksum only when a target SDK provides its architecture.
ifneq ($(strip $(APP_ARCH)),)
PKG_SOURCE:=easytier-linux-$(APP_ARCH)-v$(PKG_VERSION).zip
PKG_SOURCE_URL:=https://github.com/EasyTier/EasyTier/releases/download/v$(PKG_VERSION)

# 固定上游版本使用逐架构校验和；覆盖版本时必须由调用方提供对应摘要。
ifeq ($(PKG_VERSION),2.6.4)
	ifeq ($(APP_ARCH),aarch64)
		PKG_HASH:=f533ec25a7ea714e09f645615012200278058525795cc3bb690ff011aec1a70f
	else ifeq ($(APP_ARCH),arm)
		PKG_HASH:=6d2bd44507d7183a4fa9857ced8f89cb4eddc99cdfc8f8ddef5cc78f52caf2fd
	else ifeq ($(APP_ARCH),armhf)
		PKG_HASH:=526cff8b0495ff0025d4fdbf3bd22d46d88c10a3aad94c30af991ff9a1869f3e
	else ifeq ($(APP_ARCH),armv7)
		PKG_HASH:=93b1d2831e45db1fd3ca1d8d68c191b300bd69d331ca1858394a0cf884363cc3
	else ifeq ($(APP_ARCH),armv7hf)
		PKG_HASH:=af0186ce95ffbe90b0e9dc8df0e9a01563f59e94ea52212651950c34dc35ac37
	else ifeq ($(APP_ARCH),mips)
		PKG_HASH:=3b4d084aa922a4b23f5d0167b9bb4966c1593f5184061f7ff075132a2207a260
	else ifeq ($(APP_ARCH),mipsel)
		PKG_HASH:=7c93bcc9e9276f102b5299b0773941db7fd1d99ad04bac42b479a0d979ef5220
	else ifeq ($(APP_ARCH),x86_64)
		PKG_HASH:=61b659eaedba658fa66fe47d17e1426cdd77e5d02fa15fed447bb4357c09dfd6
	else
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
