#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

require_command() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "Required development tool is missing: $1" >&2
		exit 1
	}
}

for tool in node eslint shellcheck python3 msgfmt xgettext; do require_command "$tool"; done

node_major="$(node -p 'process.versions.node.split(".")[0]')"
[[ "$node_major" == 24 ]] || {
	echo "Node.js 24 is required; found $(node --version)" >&2
	exit 1
}

npm run --silent lint

# Check scripts according to their declared shell. OpenWrt /bin/sh scripts use POSIX sh;
# host tests and CI helpers explicitly use Bash.
mapfile -t shell_files < <(
	rg --files luci-app-easytier/root tests scripts .github/scripts \
		-g '*.sh' -g 'easytier' -g 'manage' -g 'rpc' -g 'watchdog' \
		-g 'luci-easytier' -g 'luci-i18n-easytier-zh-cn' | sort
)
for script in "${shell_files[@]}"; do
	IFS= read -r first_line <"$script" || true
	case "$script" in
		luci-app-easytier/root/*)
			shellcheck --external-sources --shell=busybox "$script"
			sh -n "$script"
			;;
		*)
		case "$first_line" in
				*'bash'*) shellcheck --external-sources --shell=bash "$script"; bash -n "$script" ;;
				*'sh'*) shellcheck --external-sources --shell=sh "$script"; sh -n "$script" ;;
			esac
			;;
	esac
done

mapfile -t js_files < <(rg --files luci-app-easytier/htdocs -g '*.js' | sort)
for script in "${js_files[@]}"; do node --check "$script"; done

while IFS= read -r json_file; do
	python3 -m json.tool "$json_file" >/dev/null
done < <(rg --files --hidden -g '*.json' -g '!node_modules/**' | sort)

msgfmt --check --check-header -o /dev/null luci-app-easytier/po/zh_Hans/easytier.po
msgfmt --check-format -o /dev/null luci-app-easytier/po/templates/easytier.pot
python3 scripts/check_translations.py

python3 scripts/build_targets.py check
python3 tests/check-rpc-contract.py
python3 -m unittest tests/test_build_targets.py
python3 -m unittest tests/test_translations.py
bash tests/check-arch-mapping.sh
bash tests/package-hashes.sh
bash tests/firewall.sh
bash tests/service.sh
bash tests/manage-upload.sh

echo "All local development checks passed."
