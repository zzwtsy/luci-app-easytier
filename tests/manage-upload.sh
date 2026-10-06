#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "$ROOT/.upload-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=luci-app-easytier/root/usr/share/easytier/manage-upload.sh
. "$ROOT/luci-app-easytier/root/usr/share/easytier/manage-upload.sh"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

error() {
	echo "$1" >&2
	exit 1
}

success() { :; }

timeout() {
	printf '%s\n' 'EasyTier test binary'
}

CONFIG_CORE=
CONFIG_WEB=
config_value() {
	case "$1" in
		easytierbin) printf '%s\n' "$CONFIG_CORE" ;;
		webbin) printf '%s\n' "$CONFIG_WEB" ;;
		*) return 1 ;;
	esac
}

make_archive() {
	local archive="$1" mode="$2" binary="$3"
	python3 - "$archive" "$mode" "$binary" <<'PY'
import sys
import zipfile

archive, mode, binary = sys.argv[1:]
with open(binary, "rb") as source:
    payload = source.read()
with zipfile.ZipFile(archive, "w") as output:
    if mode == "valid":
        output.writestr("release/easytier-core", payload)
    elif mode == "absolute":
        output.writestr("/absolute/easytier-core", payload)
    elif mode == "parent":
        output.writestr("../easytier-core", payload)
    elif mode == "unknown":
        output.writestr("easytier-core", payload)
        output.writestr("unexpected.txt", b"unexpected")
    elif mode == "duplicate":
        output.writestr("one/easytier-core", payload)
        output.writestr("two/easytier-core", payload)
    elif mode == "invalid-elf":
        output.writestr("easytier-core", b"not an ELF executable")
    elif mode == "two-binaries":
        output.writestr("easytier-core", payload)
        output.writestr("easytier-cli", payload)
    else:
        raise SystemExit(f"unknown archive fixture: {mode}")
PY
}

assert_archive_rejected() {
	local mode="$1" archive="$TMP/$1.zip"
	make_archive "$archive" "$mode" "$TMP/valid-elf"
	UPLOAD="$archive"
	WORKDIR=
	INSTALL_COMMITTED=0
	TRANSACTION_FINISHED=0
	if install_archive "${archive##*/}"; then
		cleanup_install
		fail "archive mode $mode should have been rejected"
	fi
	cleanup_install
}

# A small ELF header is enough to test file-header handling; timeout is stubbed to avoid executing it.
printf '\177ELFtest-binary\n' >"$TMP/valid-elf"
chmod 0644 "$TMP/valid-elf"
valid_binary "$TMP/valid-elf" || fail "valid ELF was rejected"
printf 'not-elf\n' >"$TMP/invalid-elf"
if valid_binary "$TMP/invalid-elf"; then fail "invalid ELF was accepted"; fi

# Upload checks accept regular files and reject symbolic links.
UPLOAD="$TMP/valid-elf"
check_upload
ln -s "$TMP/valid-elf" "$TMP/upload-link"
UPLOAD="$TMP/upload-link"
if (check_upload) 2>/dev/null; then fail "symbolic-link upload was accepted"; fi

mkdir -p "$TMP/bin"
CONFIG_CORE="$TMP/bin/easytier-core"
CONFIG_WEB="$TMP/bin/easytier-web"
printf 'previous core\n' >"$CONFIG_CORE"
printf 'previous cli\n' >"$TMP/bin/easytier-cli"

# A known member in a prefixed path installs successfully.
make_archive "$TMP/valid.zip" valid "$TMP/valid-elf"
UPLOAD="$TMP/valid.zip"
WORKDIR=
INSTALL_COMMITTED=0
TRANSACTION_FINISHED=0
install_archive "${UPLOAD##*/}" || fail "valid archive was rejected"
cleanup_install
cmp -s "$CONFIG_CORE" "$TMP/valid-elf" || fail "valid archive did not install the core binary"

# Unsafe paths, unknown members, duplicate targets, and invalid ELF payloads are rejected.
for mode in absolute parent unknown duplicate invalid-elf; do
	assert_archive_rejected "$mode"
done

# A failed second replacement removes the first new file and restores both old files.
make_archive "$TMP/two-binaries.zip" two-binaries "$TMP/valid-elf"
printf 'previous core\n' >"$CONFIG_CORE"
printf 'previous cli\n' >"$TMP/bin/easytier-cli"
UPLOAD="$TMP/two-binaries.zip"
WORKDIR=
INSTALL_COMMITTED=0
TRANSACTION_FINISHED=0
FAIL_DESTINATION="$TMP/bin/easytier-cli"
# The sourced install helper invokes mv dynamically; this wrapper injects a failure for the test.
# shellcheck disable=SC2317
mv() {
	local -a arguments=("$@")
	local source destination
	source="${arguments[${#arguments[@]}-2]}"
	destination="${arguments[${#arguments[@]}-1]}"
	if [[ "$destination" == "$FAIL_DESTINATION" && "$source" == */.easytier-install.* ]]; then
		return 1
	fi
	command mv "$@"
}
if install_archive "${UPLOAD##*/}"; then
	cleanup_install
	fail "injected replacement failure did not fail the archive install"
fi
cleanup_install
unset -f mv
[[ "$(cat "$CONFIG_CORE")" == 'previous core' ]] || fail "core binary was not restored after rollback"
[[ "$(cat "$TMP/bin/easytier-cli")" == 'previous cli' ]] || fail "CLI binary was not restored after rollback"

echo "Upload validation and transaction regression checks passed."
