#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAKEFILE="$ROOT/easytier/tests/arch-mapping.mk"

check_mapping() {
	local arch="$1" packages="$2" float="$3" expected="$4"
	local args=("ARCH=$arch" "ARCH_PACKAGES=$packages" "EXPECTED_ARCH=$expected")
	[[ "$float" == soft ]] && args+=("CONFIG_SOFT_FLOAT=y")
	make -s -f "$MAKEFILE" "${args[@]}" check
}

check_mapping aarch64 aarch64_generic hard aarch64
check_mapping arm arm_arm926ej-s soft arm
check_mapping arm arm_arm1176jzf-s_vfp hard armhf
check_mapping arm arm_cortex-a7 soft armv7
check_mapping arm arm_cortex-a7_neon-vfpv4 hard armv7hf
check_mapping mips mips_24kc hard mips
check_mapping mipsel mipsel_24kc hard mipsel
check_mapping x86_64 x86_64 hard x86_64

echo "All EasyTier architecture mappings passed."
