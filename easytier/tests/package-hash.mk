ROOT:=$(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
include $(ROOT)/version.mk

PKG_VERSION?=$(EASYTIER_VERSION)
PKG_SOURCE:=easytier-linux-$(APP_ARCH)-v$(PKG_VERSION).zip
APP_ARCH?=aarch64
ARCH:=
EASYTIER_COMMON_DIR:=$(ROOT)/easytier/

include $(ROOT)/easytier/common.mk

.PHONY: check
check:
	@test -n "$(PKG_HASH)"
