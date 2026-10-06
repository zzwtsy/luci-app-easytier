# 先固定包目录，后续 include 会改变 MAKEFILE_LIST 的最后一项。
EASYTIER_PACKAGE_DIR:=$(dir $(abspath $(lastword $(MAKEFILE_LIST))))

include $(TOPDIR)/rules.mk
-include $(EASYTIER_PACKAGE_DIR)../version.mk

PKG_NAME:=easytier-noweb
PKG_VERSION:=$(or $(EASYTIER_VERSION),$(EASYTIER_DEFAULT_VERSION))
PKG_RELEASE:=1

EASYTIER_HAS_WEB:=0
EASYTIER_CONFLICTS:=easytier

include $(EASYTIER_PACKAGE_DIR)../easytier/common.mk

$(eval $(call BuildPackage,$(PKG_NAME)))
