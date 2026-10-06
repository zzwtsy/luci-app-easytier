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
python3 "$ROOT/scripts/build_targets.py" check >/dev/null
read -r release_arch_count sdk_total stable_sdk_total < <(python3 "$ROOT/scripts/build_targets.py" summary | tr '\t' ' ')
expected_artifacts=$((release_arch_count * sdk_total))
expected_stable_artifacts=$((release_arch_count * stable_sdk_total))
[[ ${#artifacts[@]} -eq $expected_artifacts ]] || {
	echo "Expected $expected_artifacts architecture/SDK artifacts, found ${#artifacts[@]}" >&2
	exit 1
}

shopt -s nullglob
declare -A seen=()
declare -A sdk_count=()
declare -A sdk_format=()
declare -A sdk_separator=()
declare -A sdk_stable=()
declare -A release_arch=()
declare -a sdk_versions=()
declare -a stable_sdk_versions=()
while IFS=$'\t' read -r version format separator stable; do
	sdk_versions+=("$version")
	sdk_format["$version"]="$format"
	sdk_separator["$version"]="$separator"
	sdk_stable["$version"]="$stable"
	[[ "$stable" == true ]] && stable_sdk_versions+=("$version")
done < <(python3 "$ROOT/scripts/build_targets.py" sdk-list)
while IFS= read -r arch; do release_arch["$arch"]=1; done < <(
	python3 -c 'import json, pathlib, sys; print("\n".join(json.loads(pathlib.Path(sys.argv[1]).read_text())["release_architectures"]))' \
		"$ROOT/config/build-targets.json"
)
stable_count=0

for artifact in "${artifacts[@]}"; do
	name="${artifact##*/}"
	sdk=
	for candidate in "${sdk_versions[@]}"; do
		if [[ "$name" == *-"$candidate" ]]; then sdk="$candidate"; break; fi
	done
	[[ -n "$sdk" ]] || { echo "Unknown SDK artifact: $name" >&2; exit 1; }
	arch="${name%-"$sdk"}"
	extension="${sdk_format[$sdk]}"
	separator="${sdk_separator[$sdk]}"

	[[ -n "$arch" && "$arch" != */* ]] || {
		echo "Invalid architecture in artifact name: $name" >&2
			exit 1
	}
	[[ ${release_arch[$arch]+present} ]] || {
		echo "Architecture is not in config/build-targets.json: $arch" >&2
		exit 1
	}
	key="$sdk/$arch"
	[[ -z "${seen[$key]:-}" ]] || {
		echo "Duplicate artifact for $key" >&2
		exit 1
	}
	seen[$key]=1
	if [[ "${sdk_stable[$sdk]}" != true ]]; then continue; fi

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

	if [[ "$extension" == ipk ]]; then
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

[[ "$stable_count" -eq $expected_stable_artifacts ]] || {
	echo "Expected $expected_stable_artifacts stable artifacts, assembled $stable_count" >&2
	exit 1
}
for sdk in "${stable_sdk_versions[@]}"; do
	[[ "${sdk_count[$sdk]:-0}" -eq $release_arch_count ]] || {
		echo "Expected $release_arch_count stable artifacts for SDK $sdk; found ${sdk_count[$sdk]:-0}" >&2
		exit 1
	}
done

python3 - "$SITE_ROOT/feeds" "$ROOT/config/build-targets.json" <<'PY'
import gzip
import hashlib
import json
import pathlib
import re
import sys

feed_root = pathlib.Path(sys.argv[1])
manifest = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
opkg_sdk_roots = [
    feed_root / sdk["version"]
    for sdk in manifest["sdks"]
    if sdk["stable"] and sdk["package_format"] == "ipk"
]
required = {
    "easytier",
    "easytier-noweb",
    "luci-app-easytier",
    "luci-i18n-easytier-zh-cn",
}

for root in opkg_sdk_roots:
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
