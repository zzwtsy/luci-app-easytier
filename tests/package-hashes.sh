#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "$ROOT/.package-hash-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/include"
: >"$TMP/include/package.mk"

for app_arch in aarch64 arm armhf armv7 armv7hf mips mipsel x86_64; do
	make -s -f "$ROOT/easytier/tests/package-hash.mk" \
		BUILD_DIR="$TMP" INCLUDE_DIR="$TMP/include" APP_ARCH="$app_arch" check
done

if output="$(make -s -f "$ROOT/easytier/tests/package-hash.mk" \
	BUILD_DIR="$TMP" INCLUDE_DIR="$TMP/include" APP_ARCH=aarch64 PKG_VERSION=9.9.9 2>&1)"; then
	echo "Custom EasyTier version unexpectedly built without a checksum" >&2
	exit 1
fi
[[ "$output" == *"Set EASYTIER_HASH"* ]] || {
	echo "Custom version failed for an unexpected reason: $output" >&2
	exit 1
}

make -s -f "$ROOT/easytier/tests/package-hash.mk" \
	BUILD_DIR="$TMP" INCLUDE_DIR="$TMP/include" APP_ARCH=aarch64 \
	PKG_VERSION=9.9.9 EASYTIER_HASH=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa check

echo "Package checksum configuration checks passed."
