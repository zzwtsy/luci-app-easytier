#!/usr/bin/env bash
set -euo pipefail

: "${1:?Usage: assemble-feed-site.sh <artifact-root> <site-root>}"
: "${2:?Usage: assemble-feed-site.sh <artifact-root> <site-root>}"
ARTIFACT_ROOT="$1"
SITE_ROOT="$2"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

[[ -d "$ARTIFACT_ROOT" ]] || {
	echo "Artifact directory does not exist: $ARTIFACT_ROOT" >&2
	exit 1
}
case "$SITE_ROOT" in
	""|/|.)
		echo "Refusing unsafe site output directory: $SITE_ROOT" >&2
		exit 1
		;;
esac

for key in easytier-opkg.pub easytier-apk.pem; do
	[[ -s "$ROOT/.github/pages/keys/$key" ]] || {
		echo "Missing public key: $key" >&2
		exit 1
	}
done

[[ ! -e "$SITE_ROOT" ]] || {
	echo "Site output directory already exists: $SITE_ROOT" >&2
	exit 1
}
mkdir -p "$SITE_ROOT/keys"
install -m 0644 "$ROOT/.github/pages/index.html" "$SITE_ROOT/index.html"
install -m 0644 "$ROOT/.github/pages/keys/easytier-opkg.pub" "$SITE_ROOT/keys/easytier-opkg.pub"
install -m 0644 "$ROOT/.github/pages/keys/easytier-apk.pem" "$SITE_ROOT/keys/easytier-apk.pem"
: > "$SITE_ROOT/.nojekyll"

mapfile -t artifacts < <(find "$ARTIFACT_ROOT" -mindepth 1 -maxdepth 1 -type d -print | sort)
[[ ${#artifacts[@]} -eq 66 ]] || {
	echo "Expected 66 architecture/SDK artifacts, found ${#artifacts[@]}" >&2
	exit 1
}

shopt -s nullglob
declare -A seen=()
declare -A sdk_count=()
stable_count=0

for artifact in "${artifacts[@]}"; do
	name="${artifact##*/}"
	case "$name" in
		*-24.10.8)
			sdk=24.10.8
			arch="${name%-24.10.8}"
			extension=ipk
			separator=_
			;;
		*-25.12.5)
			sdk=25.12.5
			arch="${name%-25.12.5}"
			extension=apk
			separator=-
			;;
		*-SNAPSHOT)
			continue
			;;
		*)
			echo "Unknown SDK artifact: $name" >&2
			exit 1
			;;
	esac

	[[ -n "$arch" && "$arch" != */* ]] || {
		echo "Invalid architecture in artifact name: $name" >&2
		exit 1
	}
	key="$sdk/$arch"
	[[ -z "${seen[$key]:-}" ]] || {
		echo "Duplicate artifact for $key" >&2
		exit 1
	}
	seen[$key]=1

	packages=("$artifact"/*."$extension")
	for package in easytier easytier-noweb luci-app-easytier luci-i18n-easytier-zh-cn; do
		matches=("$artifact/$package$separator"*."$extension")
		[[ ${#matches[@]} -gt 0 ]] || {
			echo "Missing $package package in $name" >&2
			exit 1
		}
	done

	destination="$SITE_ROOT/feeds/$sdk/$arch/packages_ci"
	mkdir -p "$destination"
	cp -- "${packages[@]}" "$destination/"

	if [[ "$sdk" == 24.10.8 ]]; then
		for index in Packages Packages.gz Packages.sig; do
			[[ -s "$artifact/$index" ]] || {
				echo "Missing $index in signed artifact $name" >&2
				exit 1
			}
		done
		cp -- "$artifact/Packages" "$artifact/Packages.gz" "$artifact/Packages.sig" "$destination/"
	else
		[[ -s "$artifact/packages.adb" ]] || {
			echo "Missing packages.adb in signed artifact $name" >&2
			exit 1
		}
		cp -- "$artifact/packages.adb" "$destination/"
	fi

	stable_count=$((stable_count + 1))
	sdk_count[$sdk]=$(( ${sdk_count[$sdk]:-0} + 1 ))
done

[[ "$stable_count" -eq 44 && "${sdk_count[24.10.8]:-0}" -eq 22 && "${sdk_count[25.12.5]:-0}" -eq 22 ]] || {
	echo "Expected 22 architectures for each stable SDK; assembled $stable_count stable artifacts" >&2
	exit 1
}

python3 - "$SITE_ROOT/feeds/24.10.8" <<'PY'
import gzip
import hashlib
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
required = {
    "easytier",
    "easytier-noweb",
    "luci-app-easytier",
    "luci-i18n-easytier-zh-cn",
}

for index in sorted(root.glob("*/packages_ci/Packages.gz")):
    feed = index.parent
    records = gzip.decompress(index.read_bytes()).decode("utf-8").strip().split("\n\n")
    found = set()
    for record in records:
        fields = dict(re.findall(r"^([^:]+):\s*(.*)$", record, re.MULTILINE))
        if "Package" not in fields:
            continue
        found.add(fields["Package"])
        filename = fields.get("Filename", "").removeprefix("./")
        package = (feed / filename).resolve()
        if not filename or not package.is_relative_to(feed.resolve()) or not package.is_file():
            raise SystemExit(f"Invalid or missing package referenced by {index}: {filename}")
        if package.stat().st_size != int(fields.get("Size", "-1")):
            raise SystemExit(f"Package size mismatch in {index}: {filename}")
        digest = hashlib.sha256(package.read_bytes()).hexdigest()
        if digest != fields.get("SHA256sum"):
            raise SystemExit(f"Package SHA256 mismatch in {index}: {filename}")
    missing = required - found
    if missing:
        raise SystemExit(f"{index} is missing package records: {', '.join(sorted(missing))}")
PY

echo "Assembled stable package feeds in $SITE_ROOT"
