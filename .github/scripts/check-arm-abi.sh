#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="$(awk -F= '$1 == "EASYTIER_DEFAULT_VERSION:" { print $2; exit }' "$ROOT/version.mk")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

hash_for_asset() {
	local key="EASYTIER_HASH_$1" hash
	hash="$(awk -F':=' -v key="$key" '$1 == key { print $2; exit }' "$ROOT/version.mk")"
	[[ "$hash" =~ ^[[:xdigit:]]{64}$ ]] || {
		echo "Missing or invalid SHA256 for EasyTier asset $1 in version.mk" >&2
		return 1
	}
	printf '%s\n' "$hash"
}

check_asset() {
	local asset="$1" expected_hash="$2" expected_float="$3"
	local archive="$WORK/easytier-linux-$asset-v$VERSION.zip"
	local extract="$WORK/$asset"
	local binary="$extract/easytier-core"
	local flags

	curl -fsSL "https://github.com/EasyTier/EasyTier/releases/download/v$VERSION/easytier-linux-$asset-v$VERSION.zip" -o "$archive"
	printf '%s  %s\n' "$expected_hash" "$archive" | sha256sum -c -
	mkdir -p "$extract"
	local member
	member="$(unzip -Z1 "$archive" | awk -F/ '$NF == "easytier-core" { print; exit }')"
	[[ -n "$member" ]] || { echo "Missing easytier-core in $archive" >&2; return 1; }
	unzip -j -q "$archive" "$member" -d "$extract"
	flags="$(readelf -h "$binary" | awk -F: '/Flags:/ { print $2 }')"

	if [[ "$expected_float" == hard ]]; then
		grep -qi 'hard-float ABI' <<<"$flags" || {
			echo "$asset expected hard-float ABI, got: $flags" >&2
			return 1
		}
	else
		grep -qi 'soft-float ABI' <<<"$flags" || {
			echo "$asset expected soft-float ABI, got: $flags" >&2
			return 1
		}
	fi
	echo "$asset: $flags"
}

check_asset arm "$(hash_for_asset arm)" soft
check_asset armhf "$(hash_for_asset armhf)" hard
check_asset armv7 "$(hash_for_asset armv7)" soft
check_asset armv7hf "$(hash_for_asset armv7hf)" hard
