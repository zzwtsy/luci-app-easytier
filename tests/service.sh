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
ENV_ARGS=()
INSTANCE=
LOG_MESSAGES=()
CLEANUPS=0

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
	ENV_ARGS=()
}

procd_set_param() {
	local parameter="$1"
	shift
	if [[ "$parameter" == command ]]; then COMMAND_ARGS+=("$@"); fi
	if [[ "$parameter" == env ]]; then ENV_ARGS=("$@"); fi
}

procd_append_param() {
	local parameter="$1"
	shift
	if [[ "$parameter" == command ]]; then COMMAND_ARGS+=("$@"); fi
}

procd_close_instance() { :; }
setup_network() { :; }
set_web_firewall() { :; }
cleanup_core_configuration() { CLEANUPS=$((CLEANUPS + 1)); }
logger() { LOG_MESSAGES+=("$*"); }

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

assert_option_values() {
	local option="$1" index
	shift
	local -a actual=() expected=("$@")
	for index in "${!COMMAND_ARGS[@]}"; do
		if [[ "${COMMAND_ARGS[$index]}" == "$option" ]]; then
			actual+=("${COMMAND_ARGS[$((index + 1))]-}")
		fi
	done
	[[ ${#actual[@]} -eq ${#expected[@]} ]] || fail "$option has the wrong number of values"
	for index in "${!expected[@]}"; do
		[[ "${actual[$index]}" == "${expected[$index]}" ]] || fail "$option lost an argument boundary"
	done
}

check_real_core_arguments() {
	[[ -n "${EASYTIER_TEST_CORE:-}" ]] || return 0
	env "${ENV_ARGS[@]}" "$EASYTIER_TEST_CORE" --check-config --config-file "$ROOT/luci-app-easytier/root/etc/easytier/config.toml" "${COMMAND_ARGS[@]:1}" >"$TMP/core-check.log" 2>&1 || {
		cat "$TMP/core-check.log" >&2
		fail "Generated arguments were rejected by EasyTier Core"
	}
}

# The generated machine ID is persisted and then reused on later starts.
printf '%s\n' 'generated-id' >"$TMP/uuid"
[[ "$(get_machine_id "$TMP/machine-id" "$TMP/uuid")" == generated-id ]] || fail "machine ID was not generated"
[[ "$(cat "$TMP/machine-id")" == generated-id ]] || fail "generated machine ID was not persisted"
printf '%s\n' 'changed-uuid' >"$TMP/uuid"
# Test the imported helper before replacing it with the startup fixture below.
# shellcheck disable=SC2218
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
MOCK_MACHINE_ID='machine id with space'
get_machine_id() { printf '%s' "$MOCK_MACHINE_ID"; }
etcmd=web
CONFIG_VALUES[main.web_config]='https://web console'
CONFIG_VALUES[main.desvice_name]='router name'
CONFIG_VALUES[main.log]=debug
start_core
assert_args "Web startup" "$easytierbin" --machine-id 'machine id with space' -w 'https://web console' --hostname 'router name' --console-log-level debug

# Official usernames are expanded at runtime; the saved value remains unchanged.
MOCK_MACHINE_ID='f9f05421-7c6b-47d6-a67d-4d58d49f51d8'
CONFIG_VALUES[main.web_config]='my-token'
start_core
assert_option_values -w 'udp://config-server.easytier.cn:22020/my-token'
[[ "${CONFIG_VALUES[main.web_config]}" == my-token ]] || fail "Web username was rewritten"
check_real_core_arguments

# Ordinary startup preserves UCI strings and each list item as separate procd arguments.
etcmd=etcmd
CONFIG_VALUES[main.network_name]='mesh network'
CONFIG_VALUES[main.network_secret]='secret with spaces'
CONFIG_VALUES[main.bind_device]=0
CONFIG_VALUES[main.log]=off
LIST_VALUES[main.peeradd]=$'peer with spaces\nsecond-peer'
start_core
assert_args "ordinary startup" "$easytierbin" --network-name 'mesh network' --network-secret 'secret with spaces' -p 'peer with spaces' -p second-peer --hostname 'router name' --multi-thread false --bind-device false --console-log-level off

# New list entries stay separate, and the portal key is present only in the environment.
LIST_VALUES=()
CONFIG_VALUES[main.vpn_portal]='wg://127.0.0.1:51820'
CONFIG_VALUES[main.vpn_portal_private_key]='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
LIST_VALUES[main.vpn_portal_clients]=$'alice=10.14.14.1/24\nbob=10.14.14.2/24'
LIST_VALUES[main.stun_servers]=$'stun.example.com:3478\nstun2.example.com:3478'
LIST_VALUES[main.tcp_stun_servers]=$'stun.example.com:3478\nstun2.example.com:3478'
CONFIG_VALUES[main.multi_thread]=1
CONFIG_VALUES[main.disable_upnp]=1
CONFIG_VALUES[main.lazy_p2p]=1
CONFIG_VALUES[main.need_p2p]=1
CONFIG_VALUES[main.disable_relay_quic]=1
CONFIG_VALUES[main.relay_quic]=1
CONFIG_VALUES[main.tld_dns_zone]='mesh.example.'
CONFIG_VALUES[main.instance_recv_bps_limit]=1024
CONFIG_VALUES[main.socket_mark]=42
start_core
assert_option_values --vpn-portal 'wg://127.0.0.1:51820'
assert_option_values --vpn-portal-client 'alice=10.14.14.1/24' 'bob=10.14.14.2/24'
assert_option_values --stun-servers 'stun.example.com:3478' 'stun2.example.com:3478'
assert_option_values --tcp-stun-servers 'stun.example.com:3478' 'stun2.example.com:3478'
assert_option_values --multi-thread true
assert_option_values --instance-recv-bps-limit 1024
assert_option_values --socket-mark 42
assert_option_values --tld-dns-zone 'mesh.example.'
[[ " ${ENV_ARGS[*]} " == *' ET_VPN_PORTAL_PRIVATE_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= '* ]] || fail "Portal key was not passed through the environment"
[[ " ${COMMAND_ARGS[*]} " != *'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='* ]] || fail "Portal key leaked into command arguments"
check_real_core_arguments

# Legacy or incomplete portals stop before opening a procd instance or changing networking.
for invalid_portal in 'wg://127.0.0.1:51820/10.14.14.0/24' 'wg://127.0.0.1:70000'; do
	CONFIG_VALUES[main.vpn_portal]="$invalid_portal"
	INSTANCE=
	if start_core; then fail "Invalid portal was accepted: $invalid_portal"; fi
	[[ -z "$INSTANCE" ]] || fail "Invalid portal opened a procd instance"
	[[ "${CONFIG_VALUES[main.vpn_portal]}" == "$invalid_portal" ]] || fail "Legacy portal was rewritten"
done
CONFIG_VALUES[main.vpn_portal]='wg://127.0.0.1:51820'
CONFIG_VALUES[main.vpn_portal_private_key]=''
if start_core; then fail "Portal without a private key was accepted"; fi
[[ " ${LOG_MESSAGES[*]} " != *'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='* ]] || fail "Portal key leaked into logs"
[[ "$CLEANUPS" -eq 3 ]] || fail "Rejected portals did not clean up network configuration"

# Failed TOML validation must not start a managed process.
printf '#!/bin/sh\nexit 1\n' >"$TMP/easytier-core"
etcmd=config
INSTANCE=
if start_core; then fail "Invalid TOML was accepted"; fi
[[ -z "$INSTANCE" ]] || fail "Invalid TOML opened a procd instance"

# --gateway-relay-data is a flag; passing a trailing true breaks the real 2.7.0 CLI.
printf '#!/bin/sh\nexit 0\n' >"$TMP/easytier-core"
CONFIG_VALUES=()
web_enabled=1
webbin="$TMP/easytier-core"
CONFIG_VALUES[main.web_protocol]=tcp
CONFIG_VALUES[main.web_heartbeat_min_response_ms]=3500
CONFIG_VALUES[main.web_heartbeat_timeout_ms]=15000
CONFIG_VALUES[main.web_gateway_peer_url]='tcp://127.0.0.1:11010'
CONFIG_VALUES[main.web_gateway_relay_data]=1
start_web
[[ "$INSTANCE" == easytier_web ]] || fail "Web instance was not opened"
assert_option_values --heartbeat-min-response-ms 3500
assert_option_values --heartbeat-timeout-ms 15000
assert_option_values --gateway-peer-url 'tcp://127.0.0.1:11010'
gateway_flags=0
for argument in "${COMMAND_ARGS[@]}"; do
	[[ "$argument" != true ]] || fail "Gateway flag incorrectly received a true value"
	if [[ "$argument" == --gateway-relay-data ]]; then gateway_flags=$((gateway_flags + 1)); fi
done
[[ "$gateway_flags" -eq 1 ]] || fail "Gateway relay flag was not passed"

if [[ -n "${EASYTIER_TEST_WEB:-}" ]]; then
	"$EASYTIER_TEST_WEB" "${COMMAND_ARGS[@]:1}" --help >"$TMP/web-check.log" 2>&1 || {
		cat "$TMP/web-check.log" >&2
		fail "Generated arguments were rejected by EasyTier Web"
	}
fi

echo "Service parameter regression checks passed."
