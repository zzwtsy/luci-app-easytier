#
# Copyright (C) 2008-2014 The LuCI Team <luci@lists.subsignal.org>
#
# This is free software, licensed under the Apache License, Version 2.0.
#

# 先固定包目录，保证公共版本文件不受后续 include 改变 MAKEFILE_LIST 的影响。
EASYTIER_PACKAGE_DIR:=$(dir $(abspath $(lastword $(MAKEFILE_LIST))))

include $(TOPDIR)/rules.mk
-include $(EASYTIER_PACKAGE_DIR)../version.mk

PKG_NAME:=luci-app-easytier
PKG_VERSION:=$(or $(LUCI_APP_VERSION),3.0.0)
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
# Keep the translation package version aligned with this LuCI package release.
PKG_PO_VERSION:=$(PKG_VERSION)

LUCI_TITLE:=LuCI support for EasyTier
LUCI_DEPENDS:=+luci-base +kmod-tun +unzip
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/conffiles
/etc/config/easytier
/etc/easytier/
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
