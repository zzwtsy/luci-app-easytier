#!/usr/bin/env bash
set -euo pipefail

: "${PACKAGE_DIR:?PACKAGE_DIR must point to the SDK output directory}"
: "${BUILD_TARGET:?BUILD_TARGET is required}"
: "${SDK:?SDK is required}"
: "${RELEASE_TAG:=}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

case "$SDK" in
	24.10.*)
		extension=ipk
		package_separator=_
		manager=opkg
		standard_install="opkg install /tmp/easytier_*.ipk /tmp/luci-app-easytier_*.ipk /tmp/luci-i18n-easytier-zh-cn_*.ipk"
		noweb_install="opkg install /tmp/easytier-noweb_*.ipk /tmp/luci-app-easytier_*.ipk /tmp/luci-i18n-easytier-zh-cn_*.ipk"
		luci_install="opkg install /tmp/luci-app-easytier_*.ipk /tmp/luci-i18n-easytier-zh-cn_*.ipk"
		;;
	25.12.*|SNAPSHOT)
		extension=apk
		package_separator=-
		manager=apk
		standard_install="apk add --allow-untrusted /tmp/easytier-*.apk /tmp/luci-app-easytier-*.apk /tmp/luci-i18n-easytier-zh-cn-*.apk"
		noweb_install="apk add --allow-untrusted /tmp/easytier-noweb-*.apk /tmp/luci-app-easytier-*.apk /tmp/luci-i18n-easytier-zh-cn-*.apk"
		luci_install="apk add --allow-untrusted /tmp/luci-app-easytier-*.apk /tmp/luci-i18n-easytier-zh-cn-*.apk"
		;;
	*)
		echo "Unsupported SDK version: $SDK" >&2
		exit 1
		;;
esac

shopt -s nullglob
for prefix in easytier easytier-noweb luci-app-easytier luci-i18n-easytier-zh-cn; do
	matches=("$PACKAGE_DIR/$prefix$package_separator"*."$extension")
	if [[ ${#matches[@]} -eq 0 ]]; then
		echo "Missing $prefix *.$extension package for $BUILD_TARGET in $PACKAGE_DIR" >&2
		exit 1
	fi
done

case "$SDK" in
	24.10.*)
		for index in Packages Packages.gz; do
			if [[ ! -s "$PACKAGE_DIR/$index" ]]; then
				echo "Missing $index for $BUILD_TARGET in $PACKAGE_DIR" >&2
				exit 1
			fi
		done
		if [[ -n "$RELEASE_TAG" && ! -s "$PACKAGE_DIR/Packages.sig" ]]; then
			echo "Missing signed Packages.sig for tagged release $BUILD_TARGET" >&2
			exit 1
		fi
		;;
	25.12.*|SNAPSHOT)
		if [[ ! -s "$PACKAGE_DIR/packages.adb" ]]; then
			echo "Missing packages.adb for $BUILD_TARGET in $PACKAGE_DIR" >&2
			exit 1
		fi
		;;
esac

export BUILD_TARGET EASYTIER_VERSION="$(awk -F= '$1 == "EASYTIER_VERSION" { print $2; exit }' "$ROOT/version.mk")"
export PACKAGE_EXTENSION="$extension" PACKAGE_MANAGER="$manager"
export INSTALL_STANDARD="$standard_install" INSTALL_NOWEB="$noweb_install" INSTALL_LUCI_ONLY="$luci_install"
python3 - "$ROOT/.github/README_PACKAGE.md.in" "$PACKAGE_DIR/README_PACKAGE.md" <<'PY'
import os
import pathlib
import sys

template = pathlib.Path(sys.argv[1]).read_text()
values = {
    "BUILD_TARGET": os.environ["BUILD_TARGET"],
    "EASYTIER_VERSION": os.environ["EASYTIER_VERSION"],
    "PACKAGE_EXTENSION": os.environ["PACKAGE_EXTENSION"],
    "PACKAGE_MANAGER": os.environ["PACKAGE_MANAGER"],
    "INSTALL_STANDARD": os.environ["INSTALL_STANDARD"],
    "INSTALL_NOWEB": os.environ["INSTALL_NOWEB"],
    "INSTALL_LUCI_ONLY": os.environ["INSTALL_LUCI_ONLY"],
}
for key, value in values.items():
    template = template.replace("@" + key + "@", value)
if "@" in template:
    raise SystemExit("Unresolved placeholder in package guide")
pathlib.Path(sys.argv[2]).write_text(template)
PY
