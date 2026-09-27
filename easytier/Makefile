# 先固定包目录，后续 include 会改变 MAKEFILE_LIST 的最后一项。
EASYTIER_PACKAGE_DIR:=$(dir $(abspath $(lastword $(MAKEFILE_LIST))))

include $(TOPDIR)/rules.mk
-include $(EASYTIER_PACKAGE_DIR)../version.mk

PKG_NAME:=easytier
PKG_VERSION:=$(or $(EASYTIER_VERSION),2.6.4)
PKG_RELEASE:=1

EASYTIER_HAS_WEB:=1
EASYTIER_CONFLICTS:=easytier-noweb

include $(EASYTIER_PACKAGE_DIR)common.mk
