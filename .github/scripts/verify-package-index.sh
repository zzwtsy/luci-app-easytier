#!/usr/bin/env bash
set -euo pipefail

: "${PACKAGE_DIR:?PACKAGE_DIR must point to the SDK output directory}"
: "${SDK:?SDK is required}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KEY_DIR="$ROOT/.github/pages/keys"

case "$SDK" in
	24.10.*)
		[[ -s "$PACKAGE_DIR/Packages" && -s "$PACKAGE_DIR/Packages.gz" && -s "$PACKAGE_DIR/Packages.sig" ]] || {
			echo "Missing signed opkg feed index for SDK $SDK" >&2
			exit 1
		}
		public_key="$KEY_DIR/easytier-opkg.pub"
		key_mount="$public_key:/keys/easytier-opkg.pub:ro"
		docker_command='gzip -dc /feed/Packages.gz > /tmp/Packages && /builder/staging_dir/host/bin/usign -V -q -m /tmp/Packages -p /keys/easytier-opkg.pub -x /feed/Packages.sig'
		;;
	25.12.*)
		[[ -s "$PACKAGE_DIR/packages.adb" ]] || {
			echo "Missing apk packages.adb for SDK $SDK" >&2
			exit 1
		}
		public_key="$KEY_DIR/easytier-apk.pem"
		key_mount="$public_key:/keys/easytier-apk.pem:ro"
		docker_command='/builder/staging_dir/host/bin/apk --keys-dir /keys verify /feed/packages.adb'
		;;
	*)
		echo "No signed feed verification is configured for SDK $SDK" >&2
		exit 1
		;;
esac

[[ -s "$public_key" ]] || {
	echo "Missing public key for SDK $SDK: $public_key" >&2
	exit 1
}

if [[ "$SDK" == 24.10.* ]]; then
	docker run --rm \
		--entrypoint /bin/sh \
		-v "$PACKAGE_DIR:/feed:ro" \
		-v "$key_mount" \
		sdk -ec "$docker_command"
	python3 "$ROOT/.github/scripts/validate-package-index.py" opkg "$PACKAGE_DIR"
else
	docker run --rm \
		--entrypoint /bin/sh \
		-v "$PACKAGE_DIR:/feed:ro" \
		-v "$key_mount" \
		sdk -ec "$docker_command"
	docker run --rm \
		--entrypoint /bin/sh \
		-v "$PACKAGE_DIR:/feed:ro" \
		sdk -ec '/builder/staging_dir/host/bin/apk adbdump --format json /feed/packages.adb' \
		| python3 "$ROOT/.github/scripts/validate-package-index.py" apk "$PACKAGE_DIR"
fi
