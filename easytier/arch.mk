# Map OpenWrt target/ABI properties to an upstream EasyTier release asset.
ifeq ($(ARCH),arm)
  ifneq ($(filter arm_cortex-a%,$(ARCH_PACKAGES)),)
    EASYTIER_ARM_ARCH:=armv7
  else
    EASYTIER_ARM_ARCH:=arm
  endif
  ifeq ($(CONFIG_SOFT_FLOAT),y)
    APP_ARCH:=$(EASYTIER_ARM_ARCH)
  else
    APP_ARCH:=$(EASYTIER_ARM_ARCH)hf
  endif
else ifneq ($(filter aarch64 arm64 armv8,$(ARCH)),)
  APP_ARCH:=aarch64
else ifneq ($(filter mips mipsel x86_64,$(ARCH)),)
  APP_ARCH:=$(ARCH)
else
  $(error Unsupported EasyTier OpenWrt architecture: ARCH=$(ARCH), ARCH_PACKAGES=$(ARCH_PACKAGES))
endif
