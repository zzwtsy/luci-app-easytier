#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "$ROOT/.service-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=luci-app-easytier/root/usr/share/easytier/service.sh
. "$ROOT/luci-app-easytier/root/usr/share/easytier/service.sh"

declare -A CONFIG_VALUES=()
declare -A LIST_VALUES=()
COMMAND_ARGS=()
INSTANCE=

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

config_get() {
	local destination="$1" section="$2" option="$3" default="${4-}" key="$2.$3" resolved_value
	resolved_value="${CONFIG_VALUES[$key]-$default}"
	printf -v "$destination" '%s' "$resolved_value"
}

config_list_foreach() {
	local section="$1" option="$2" callback="$3" key entries entry
	key="$section.$option"
	entries="${LIST_VALUES[$key]-}"
	[ -n "$entries" ] || return 0
	while IFS= read -r entry; do
		[ -n "$entry" ] && "$callback" "$entry"
	done <<<"$entries"
}

procd_open_instance() {
	INSTANCE="$1"
	COMMAND_ARGS=()
}

procd_set_param() {
	local parameter="$1"
	shift
	if [[ "$parameter" == command ]]; then COMMAND_ARGS+=("$@"); fi
}

procd_append_param() {
	local parameter="$1"
	shift
	if [[ "$parameter" == command ]]; then COMMAND_ARGS+=("$@"); fi
}

procd_close_instance() { :; }
setup_network() { :; }

assert_args() {
	local description="$1" index
	shift
	[[ "$INSTANCE" == easytier_core ]] || fail "$description did not open the core instance"
	local -a expected=("$@")
	[[ ${#COMMAND_ARGS[@]} -eq ${#expected[@]} ]] ||
		fail "$description expected ${#expected[@]} arguments, got ${#COMMAND_ARGS[@]}: ${COMMAND_ARGS[*]}"
	for index in "${!expected[@]}"; do
		[[ "${COMMAND_ARGS[$index]}" == "${expected[$index]}" ]] ||
			fail "$description argument $index expected '${expected[$index]}', got '${COMMAND_ARGS[$index]}'"
	done
}

# The generated machine ID is persisted and then reused on later starts.
printf '%s\n' 'generated-id' >"$TMP/uuid"
[[ "$(get_machine_id "$TMP/machine-id" "$TMP/uuid")" == generated-id ]] || fail "machine ID was not generated"
[[ "$(cat "$TMP/machine-id")" == generated-id ]] || fail "generated machine ID was not persisted"
printf '%s\n' 'changed-uuid' >"$TMP/uuid"
[[ "$(get_machine_id "$TMP/machine-id" "$TMP/uuid")" == generated-id ]] || fail "persisted machine ID was not reused"

mkdir -p "$TMP/etc"
printf '[network]\n' >"$TMP/etc/config.toml"
cat >"$TMP/easytier-core" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$TMP/easytier-core"
easytierbin="$TMP/easytier-core"
enabled=1
SECTION=main
CONFIG_FILE="$TMP/etc/config.toml"
check=0
checkip=

# Configuration-file mode validates the TOML then passes one config-file argument to procd.
etcmd=config
log_level=info
start_core
assert_args "configuration-file startup" "$easytierbin" -c "$CONFIG_FILE" --console-log-level info

# Web mode keeps each value, including values with spaces, as an independent process argument.
get_machine_id() { printf '%s' 'machine id with space'; }
etcmd=web
CONFIG_VALUES[main.web_config]='https://web console'
CONFIG_VALUES[main.desvice_name]='router name'
CONFIG_VALUES[main.log]=debug
start_core
assert_args "Web startup" "$easytierbin" --machine-id 'machine id with space' -w 'https://web console' --hostname 'router name' --console-log-level debug

# Ordinary startup preserves UCI strings and each list item as separate procd arguments.
etcmd=etcmd
CONFIG_VALUES[main.network_name]='mesh network'
CONFIG_VALUES[main.network_secret]='secret with spaces'
CONFIG_VALUES[main.bind_device]=0
CONFIG_VALUES[main.log]=off
LIST_VALUES[main.peeradd]=$'peer with spaces\nsecond-peer'
start_core
assert_args "ordinary startup" "$easytierbin" --network-name 'mesh network' --network-secret 'secret with spaces' -p 'peer with spaces' -p second-peer --hostname 'router name' --bind-device false --console-log-level off

echo "Service parameter regression checks passed."
