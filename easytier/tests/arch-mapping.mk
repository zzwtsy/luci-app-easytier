EASYTIER_COMMON_DIR:=$(dir $(abspath $(lastword $(MAKEFILE_LIST))))../
include $(EASYTIER_COMMON_DIR)arch.mk

.PHONY: check
check:
	@test "$(APP_ARCH)" = "$(EXPECTED_ARCH)" || { echo "expected $(EXPECTED_ARCH), got $(APP_ARCH)" >&2; exit 1; }
