#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=luci-app-easytier/root/usr/share/easytier/firewall.sh
. "$ROOT/luci-app-easytier/root/usr/share/easytier/firewall.sh"

declare -A UCI_STATE=()
UCI_WRITES=()

uci() {
	if [[ "$1" == -q ]]; then shift; fi
	local command="$1"
	shift
	case "$command" in
		get)
			local key="$1"
			[[ ${UCI_STATE[$key]+present} ]] || return 1
			printf '%s\n' "${UCI_STATE[$key]}"
			;;
		set)
			local assignment="$1" key="${1%%=*}" value="${1#*=}"
			UCI_STATE["$key"]="$value"
			UCI_WRITES+=("$assignment")
			;;
		delete)
			local prefix="$1" key
			for key in "${!UCI_STATE[@]}"; do
				if [[ "$key" == "$prefix" || "$key" == "$prefix".* ]]; then
					unset "UCI_STATE[$key]"
					UCI_WRITES+=("delete:$key")
				fi
			done
			;;
		commit)
			return 0
			;;
		changes)
			return 0
			;;
		*)
			echo "unsupported mock uci command: $command" >&2
			return 2
			;;
	esac
}

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_value() {
	local key="$1" expected="$2"
	[[ ${UCI_STATE[$key]+present} && "${UCI_STATE[$key]}" == "$expected" ]] ||
		fail "$key expected '$expected', got '${UCI_STATE[$key]-<missing>}'"
}

assert_missing() {
	local key="$1"
	[[ ! ${UCI_STATE[$key]+present} ]] || fail "$key should be absent"
}

# A new installation defaults to rejecting traffic addressed to the router.
grep -Eq "option allow_router_input '0'" "$ROOT/luci-app-easytier/root/etc/config/easytier" ||
	fail "UCI default does not deny router input"
setup_firewall_zone
assert_value firewall.easytierzone.input REJECT
setup_firewall_zone 1
assert_value firewall.easytierzone.input ACCEPT

# Each forwarding choice creates only its own source-to-destination rule.
setup_forwarding_rules 'etfwlan etfwwan lanfwet wanfwet'
assert_value firewall.easytierfwlan.src EasyTier
assert_value firewall.easytierfwlan.dest lan
assert_value firewall.easytierfwwan.src EasyTier
assert_value firewall.easytierfwwan.dest wan
assert_value firewall.lanfweasytier.src lan
assert_value firewall.lanfweasytier.dest EasyTier
assert_value firewall.wanfweasytier.src wan
assert_value firewall.wanfweasytier.dest EasyTier
setup_forwarding_rules 'etfwlan'
assert_value firewall.easytierfwlan.dest lan
assert_missing firewall.easytierfwwan
assert_missing firewall.lanfweasytier
assert_missing firewall.wanfweasytier
setup_forwarding_rules ''
assert_missing firewall.easytierfwlan

# Disabling automatic firewall management removes all core rules but leaves Web rules alone.
for section in easytierzone easytierfwlan easytierfwwan lanfweasytier wanfweasytier \
	easytier_tcp_udp easytier_udp easytier_ws easytier_wss easytier_wg easytier_quic \
	easytier_tcp easytier_wireguard easytier_socks5; do
	UCI_STATE["firewall.$section"]="rule"
done
UCI_STATE[firewall.easytier_webserver]="rule"
setup_firewall_policy 0 0 ""
for section in easytierzone easytierfwlan easytierfwwan lanfweasytier wanfweasytier \
	easytier_tcp_udp easytier_udp easytier_ws easytier_wss easytier_wg easytier_quic \
	easytier_tcp easytier_wireguard easytier_socks5; do
	assert_missing "firewall.$section"
done
assert_value firewall.easytier_webserver rule

# Reapplying the same zone and forwarding configuration does not write UCI again.
UCI_WRITES=()
setup_firewall_zone 0
first_writes=${#UCI_WRITES[@]}
setup_firewall_zone 0
[[ ${#UCI_WRITES[@]} -eq $first_writes ]] || fail "zone update is not idempotent"
setup_forwarding_rules etfwlan
first_writes=${#UCI_WRITES[@]}
setup_forwarding_rules etfwlan
[[ ${#UCI_WRITES[@]} -eq $first_writes ]] || fail "forwarding update is not idempotent"

# First upgrade migrates legacy behavior once; later starts preserve the user's new choice.
UCI_STATE=()
UCI_WRITES=()
UCI_STATE[easytier.main.auto_config_firewall]=1
migrate_router_input_policy main
assert_value easytier.main.allow_router_input 1
assert_value easytier.main.firewall_input_migration_version 1
UCI_STATE[easytier.main.allow_router_input]=0
migrate_router_input_policy main
assert_value easytier.main.allow_router_input 0

UCI_STATE=()
UCI_WRITES=()
UCI_STATE[easytier.main.auto_config_firewall]=0
migrate_router_input_policy main
assert_value easytier.main.allow_router_input 0

UCI_STATE=()
UCI_WRITES=()
UCI_STATE[easytier.main.auto_config_firewall]=1
UCI_STATE[easytier.main.allow_router_input]=0
migrate_router_input_policy main
assert_value easytier.main.allow_router_input 0

echo "All firewall regression checks passed."
