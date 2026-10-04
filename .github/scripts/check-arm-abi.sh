#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="$(awk -F= '$1 == "EASYTIER_VERSION" { print $2; exit }' "$ROOT/version.mk")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

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

check_asset arm 6d2bd44507d7183a4fa9857ced8f89cb4eddc99cdfc8f8ddef5cc78f52caf2fd soft
check_asset armhf 526cff8b0495ff0025d4fdbf3bd22d46d88c10a3aad94c30af991ff9a1869f3e hard
check_asset armv7 93b1d2831e45db1fd3ca1d8d68c191b300bd69d331ca1858394a0cf884363cc3 soft
check_asset armv7hf af0186ce95ffbe90b0e9dc8df0e9a01563f59e94ea52212651950c34dc35ac37 hard
