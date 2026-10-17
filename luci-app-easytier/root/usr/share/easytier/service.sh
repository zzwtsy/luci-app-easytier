#!/bin/sh

# Loaded by the rc.common entry point after OpenWrt and firewall helpers.
CONFIG_FILE=/etc/easytier/config.toml

append_value() {
	local option="$1"
	local value="$2"
	# 把选项和值分别交给 procd，避免拼接命令字符串造成空格拆分或参数歧义。
	if [ -n "$value" ]; then procd_append_param command "$option" "$value"; fi
	return 0
}

append_peer() { procd_append_param command -p "$1"; }
append_proxy_network() { procd_append_param command -n "$1"; }
append_exit_node() { procd_append_param command --exit-nodes "$1"; }
append_manual_route() { procd_append_param command --manual-routes "$1"; }
append_whitelist() { procd_append_param command --relay-network-whitelist "$1"; }
append_mapped_listener() { procd_append_param command --mapped-listeners "$1"; }
append_port_forward() { procd_append_param command --port-forward "$1"; }
append_extra_arg() { procd_append_param command "$1"; }
append_vpn_portal_client() { procd_append_param command --vpn-portal-client "$1"; }
append_stun_server() { procd_append_param command --stun-servers "$1"; }
append_tcp_stun_server() { procd_append_param command --tcp-stun-servers "$1"; }

check_vpn_portal() {
	local portal="$1" key="$2" listener port key_body
	[ -n "$portal" ] || return 0
	case "$portal" in
		wg://*) listener="${portal#wg://}" ;;
		*) logger -t easytier "VPN portal requires wg://IP:PORT in EasyTier 2.7.0"; return 1 ;;
	esac
	case "$listener" in
		''|*/*|*\?*|*\#*|*@*|*[[:space:]]*)
			logger -t easytier "Migrate the VPN portal to wg://IP:PORT, a private key and named vpn_portal_clients; export new client configurations"
			return 1
			;;
	esac
	port="${listener##*:}"
	case "$listener" in
		\[*\]:*|*.*.*.*:*) ;;
		*) logger -t easytier "VPN portal requires an IP address and port"; return 1 ;;
	esac
	case "$port" in
		''|*[!0-9]*) logger -t easytier "VPN portal requires a numeric port"; return 1 ;;
	esac
	[ "${#port}" -le 5 ] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || {
		logger -t easytier "VPN portal port must be between 1 and 65535"
		return 1
	}
	# 32 字节私钥使用规范的 base64 编码；不将私钥写入命令行或日志。
	key_body="${key%=}"
	if [ "${#key}" -ne 44 ] || [ "$key" = "$key_body" ]; then
		logger -t easytier "VPN portal requires a base64 encoded 32-byte vpn_portal_private_key"
		return 1
	fi
	case "$key_body" in
		*[!A-Za-z0-9+/]*) logger -t easytier "VPN portal private key is not valid base64"; return 1 ;;
	esac
	case "$key_body" in
		*[AEIMQUYcgkosw048]) return 0 ;;
	esac
	logger -t easytier "VPN portal private key is not valid base64"
	return 1
}

load_config() {
	config_load easytier
	SECTION=""
	# config_foreach calls this callback indirectly by its function name.
	# shellcheck disable=SC2317,SC2329
	find_section() { [ -n "$SECTION" ] || SECTION="$1"; }
	config_foreach find_section easytier
	[ -n "$SECTION" ] || SECTION="@easytier[0]"
	config_get enabled "$SECTION" enabled 0
	config_get easytierbin "$SECTION" easytierbin /usr/bin/easytier-core
	config_get web_enabled "$SECTION" web_enabled 0
	config_get webbin "$SECTION" webbin /usr/bin/easytier-web
	config_get etcmd "$SECTION" etcmd etcmd
	config_get log_level "$SECTION" log off
	config_get auto_config_interface "$SECTION" auto_config_interface 1
	migrate_router_input_policy "$SECTION"
	config_get auto_config_firewall "$SECTION" auto_config_firewall 1
	allow_router_input="$(uci -q get "easytier.$SECTION.allow_router_input")"
	[ -n "$allow_router_input" ] || allow_router_input=0
	config_get interface_netmask "$SECTION" interface_netmask 255.0.0.0
	config_get check "$SECTION" check 0
	config_get checktime "$SECTION" checktime 2
	config_get checkip "$SECTION" checkip
	config_get tunname "$SECTION" tunname tun0
	config_get ipaddr "$SECTION" ipaddr
	config_get tcp_port "$SECTION" tcp_port
	config_get udp_port "$SECTION" udp_port
	config_get ws_port "$SECTION" ws_port
	config_get wss_port "$SECTION" wss_port
	config_get wg_port "$SECTION" wg_port
	config_get quic_port "$SECTION" quic_port
	config_get listenermode "$SECTION" listenermode ON
	config_get et_forward "$SECTION" et_forward
}

# 网络接口与防火墙规则分别受 UCI 开关控制；关闭其中一项不会替用户接管另一项。
# load_config assigns these service globals through OpenWrt's config_get callbacks.
# shellcheck disable=SC2154
setup_network() {
	if [ "$auto_config_interface" = 1 ]; then
		setup_network_interface "$tunname" "$ipaddr" "$interface_netmask"
	else
		cleanup_core_interface
	fi
	setup_firewall_policy "$auto_config_firewall" "$allow_router_input" "$et_forward"
	if [ "$auto_config_firewall" = 1 ]; then
		if [ "$etcmd" = etcmd ]; then
			[ "$udp_port" != "$tcp_port" ] || udp_port=""
			set_firewall_rules "$tcp_port" "$udp_port" "$ws_port" "$wss_port" "$wg_port" "$quic_port"
		else
			set_firewall_rules "" "" "" "" "" ""
		fi
	fi
}

get_machine_id() {
	local id_file="$1" uuid_file="$2" machine_id
	machine_id="$(cat "$id_file" 2>/dev/null)"
	[ -n "$machine_id" ] || {
		machine_id="$(cat "$uuid_file" 2>/dev/null)"
		[ -z "$machine_id" ] || printf '%s\n' "$machine_id" >"$id_file"
	}
	printf '%s' "$machine_id"
}

cleanup_core_configuration() {
	cleanup_core_interface
	cleanup_core_firewall_rules
}

# load_config assigns these service globals through OpenWrt's config_get callbacks.
# shellcheck disable=SC2154
start_core() {
	[ "$enabled" = "1" ] || { cleanup_core_configuration; return 0; }
	[ -x "$easytierbin" ] || {
		logger -t easytier "EasyTier Core is enabled but $easytierbin is not installed or executable"
		cleanup_core_configuration
		return 1
	}

	# 配置文件模式启动前先让 EasyTier 自己校验 TOML，错误配置不会进入守护进程。
	if [ "$etcmd" = config ]; then
		[ -r "$CONFIG_FILE" ] || {
			logger -t easytier "Configuration file $CONFIG_FILE is missing"
			cleanup_core_configuration
			return 1
		}
		"$easytierbin" --check-config --config-file "$CONFIG_FILE" >/dev/null 2>&1 || {
			logger -t easytier "Configuration file validation failed"
			cleanup_core_configuration
			return 1
		}
	fi

	local tz="" vpn_portal="" vpn_key=""
	case "$etcmd" in
		config|web) ;;
		*)
			config_get vpn_portal "$SECTION" vpn_portal
			config_get vpn_key "$SECTION" vpn_portal_private_key
			check_vpn_portal "$vpn_portal" "$vpn_key" || {
				cleanup_core_configuration
				return 1
			}
			;;
	esac
	[ -e /etc/localtime ] || tz="$(cat /etc/TZ 2>/dev/null || cat /var/etc/TZ 2>/dev/null || true)"

	procd_open_instance easytier_core
	set --
	[ -z "$tz" ] || set -- "$@" "TZ=$tz"
	[ -z "$vpn_portal" ] || set -- "$@" "ET_VPN_PORTAL_PRIVATE_KEY=$vpn_key"
	[ "$#" -eq 0 ] || procd_set_param env "$@"
	if [ "$etcmd" = "config" ]; then
		procd_set_param command "$easytierbin" -c "$CONFIG_FILE" --console-log-level "$log_level"
	else
		procd_set_param command "$easytierbin"
		if [ "$etcmd" = "web" ]; then
			local web_config machine_id device_name
			config_get web_config "$SECTION" web_config
			config_get device_name "$SECTION" desvice_name
			# 保留旧版官方账号简写的语义，运行时补全 URL，不改写用户的 UCI 值。
			case "$web_config" in
				''|*://*) ;;
				*) web_config="udp://config-server.easytier.cn:22020/$web_config" ;;
			esac
			# Web 模式需要稳定的机器 ID；仅首次缺失时生成并保存，后续启动沿用原值。
			machine_id="$(get_machine_id /etc/easytier/et_machine_id /proc/sys/kernel/random/uuid)"
			append_value --machine-id "$machine_id"
			append_value -w "$web_config"
			append_value --hostname "$device_name"
			config_get value "$SECTION" log off
			procd_append_param command --console-log-level "$value"
		else
			local value flag relay_network
				config_get value "$SECTION" network_name; append_value --network-name "$value"
			config_get value "$SECTION" network_secret; append_value --network-secret "$value"
			config_get value "$SECTION" ipaddr; append_value -i "$value"
			config_get value "$SECTION" ip6addr; append_value --ipv6 "$value"
			config_get value "$SECTION" ip_dhcp 0; [ "$value" = 1 ] && procd_append_param command -d
			config_list_foreach "$SECTION" peeradd append_peer
			config_list_foreach "$SECTION" proxy_network append_proxy_network
			config_list_foreach "$SECTION" exit_nodes append_exit_node
			config_list_foreach "$SECTION" manual_routes append_manual_route
			config_get relay_network "$SECTION" relay_network 0
			if [ "$relay_network" = 1 ]; then
				if [ -n "$(uci -q get easytier.@easytier[0].whitelist)" ]; then
					config_list_foreach "$SECTION" whitelist append_whitelist
				else
					procd_append_param command --relay-network-whitelist
				fi
			fi
			config_list_foreach "$SECTION" mapped_listeners append_mapped_listener
			config_list_foreach "$SECTION" port_forward append_port_forward
			config_get value "$SECTION" rpc_portal; append_value -r "$value"
			config_get value "$SECTION" rpc_portal_whitelist; append_value --rpc-portal-whitelist "$value"
			config_get tcp_port "$SECTION" tcp_port
			[ -z "$tcp_port" ] || procd_append_param command -l "tcp:$tcp_port" -l "udp:$tcp_port"
			config_get udp_port "$SECTION" udp_port
			[ -z "$udp_port" ] || [ "$udp_port" = "$tcp_port" ] || procd_append_param command -l "udp:$udp_port"
			config_get ws_port "$SECTION" ws_port; [ -z "$ws_port" ] || procd_append_param command -l "ws:$ws_port"
			config_get wss_port "$SECTION" wss_port; [ -z "$wss_port" ] || procd_append_param command -l "wss:$wss_port"
			config_get wg_port "$SECTION" wg_port; [ -z "$wg_port" ] || procd_append_param command -l "wg:$wg_port"
			config_get quic_port "$SECTION" quic_port; [ -z "$quic_port" ] || procd_append_param command -l "quic:$quic_port"
			config_get value "$SECTION" external_node; append_value -e "$value"
			config_get listenermode "$SECTION" listenermode ON; [ "$listenermode" = ON ] || procd_append_param command --no-listener
			config_get value "$SECTION" desvice_name; append_value --hostname "$value"
			config_get value "$SECTION" instance_name; append_value -m "$value"
			append_value --vpn-portal "$vpn_portal"
			[ -z "$vpn_portal" ] || config_list_foreach "$SECTION" vpn_portal_clients append_vpn_portal_client
			config_get value "$SECTION" mtu; append_value --mtu "$value"
			config_get value "$SECTION" default_protocol; [ "$value" = - ] || append_value --default-protocol "$value"
			config_get value "$SECTION" tunname; append_value --dev-name "$value"
			# UCI 布尔项通过白名单映射为固定 CLI 开关，不把配置值当作命令执行。
			config_get value "$SECTION" multi_thread 0
			if [ "$value" = 1 ]; then
				procd_append_param command --multi-thread true
			else
				procd_append_param command --multi-thread false
			fi
			for flag in disable_encryption no_tun smoltcp disable_ipv6 latency_first exit_node disable_p2p relay_all kcp_proxy kcp_input proxy_forward accept_dns private_mode quic_proxy quic_input p2p_only disable_tcp disable_udp disable_sym disable_relay_kcp relay_kcp disable_upnp lazy_p2p need_p2p disable_relay_quic relay_quic; do
				config_get value "$SECTION" "$flag" 0
				[ "$value" = 1 ] || continue
				case "$flag" in
					disable_encryption) procd_append_param command -u ;;
					no_tun) procd_append_param command --no-tun ;;
					smoltcp) procd_append_param command --use-smoltcp ;;
					disable_ipv6) procd_append_param command --disable-ipv6 ;;
					latency_first) procd_append_param command --latency-first ;;
					exit_node) procd_append_param command --enable-exit-node ;;
					disable_p2p) procd_append_param command --disable-p2p ;;
					relay_all) procd_append_param command --relay-all-peer-rpc ;;
					kcp_proxy) procd_append_param command --enable-kcp-proxy ;;
					kcp_input) procd_append_param command --disable-kcp-input ;;
					proxy_forward) procd_append_param command --proxy-forward-by-system ;;
					accept_dns) procd_append_param command --accept-dns true ;;
					private_mode) procd_append_param command --private-mode true ;;
					quic_proxy) procd_append_param command --enable-quic-proxy ;;
					quic_input) procd_append_param command --disable-quic-input ;;
					p2p_only) procd_append_param command --p2p-only ;;
					disable_tcp) procd_append_param command --disable-tcp-hole-punching ;;
					disable_udp) procd_append_param command --disable-udp-hole-punching ;;
					disable_sym) procd_append_param command --disable-sym-hole-punching ;;
					disable_relay_kcp) procd_append_param command --disable-relay-kcp true ;;
					relay_kcp) procd_append_param command --enable-relay-foreign-network-kcp true ;;
					disable_upnp) procd_append_param command --disable-upnp ;;
					lazy_p2p) procd_append_param command --lazy-p2p ;;
					need_p2p) procd_append_param command --need-p2p ;;
					disable_relay_quic) procd_append_param command --disable-relay-quic true ;;
					relay_quic) procd_append_param command --enable-relay-foreign-network-quic true ;;
				esac
			done
			config_get value "$SECTION" multi_thread_count; append_value --multi-thread-count "$value"
			config_get value "$SECTION" socks_port; append_value --socks5 "$value"
			config_get value "$SECTION" comp none; [ "$value" = none ] || append_value --compression "$value"
			config_get value "$SECTION" bind_device 0
			procd_append_param command --bind-device "$([ "$value" = 1 ] && echo true || echo false)"
			config_get value "$SECTION" foreign_relay_bps_limit; append_value --foreign-relay-bps-limit "$value"
			config_get value "$SECTION" encryption_algorithm aes-gcm; [ "$value" = aes-gcm ] || append_value --encryption-algorithm "$value"
			config_get value "$SECTION" udp_white_port; append_value --udp-whitelist "$value"
			config_get value "$SECTION" tcp_white_port; append_value --tcp-whitelist "$value"
			config_get value "$SECTION" tld_dns_zone; append_value --tld-dns-zone "$value"
			config_get value "$SECTION" instance_recv_bps_limit; append_value --instance-recv-bps-limit "$value"
			config_get value "$SECTION" socket_mark; append_value --socket-mark "$value"
			config_list_foreach "$SECTION" stun_servers append_stun_server
			config_list_foreach "$SECTION" tcp_stun_servers append_tcp_stun_server
			config_list_foreach "$SECTION" extra_args append_extra_arg
			config_get value "$SECTION" log off
			procd_append_param command --console-log-level "$value"
		fi
	fi
	procd_set_param limits core="unlimited" nofile="1000000 1000000"
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_set_param respawn 3600 5 5
	procd_close_instance

	setup_network
	if [ "$check" = 1 ] && [ -n "$checkip" ]; then
		# 看门狗由独立 procd 实例管理，主进程重启策略与连通性检查互不混用。
		case "$checktime" in ''|*[!0-9]*) checktime=2 ;; esac
		[ "${#checktime}" -le 2 ] && [ "$checktime" -ge 1 ] && [ "$checktime" -le 60 ] || checktime=2
		procd_open_instance easytier_watchdog
		procd_set_param command /usr/libexec/easytier/watchdog "$checktime" "$checkip"
		procd_set_param respawn 3600 5 5
		procd_close_instance
	fi
}

# load_config assigns these service globals through OpenWrt's config_get callbacks.
# shellcheck disable=SC2154
start_web() {
	[ "$web_enabled" = 1 ] || {
		cleanup_web_firewall
		return 0
	}
	[ -x "$webbin" ] || {
		logger -t easytier "EasyTier Web is enabled but $webbin is not installed or executable"
		cleanup_web_firewall
		return 1
	}

	local value tz
	tz="$(cat /etc/TZ 2>/dev/null || cat /var/etc/TZ 2>/dev/null || true)"
	procd_open_instance easytier_web
	[ -z "$tz" ] || procd_set_param env "TZ=$tz"
	procd_set_param command "$webbin"
	config_get value "$SECTION" web_db_path; append_value -d "$value"
	config_get value "$SECTION" web_protocol; append_value -p "$value"
	config_get value "$SECTION" web_port; append_value -c "$value"
	config_get value "$SECTION" web_api_port; append_value -a "$value"
	config_get value "$SECTION" web_api_host; append_value --api-host "$value"
	config_get value "$SECTION" web_geoip_db; append_value --geoip-db "$value"
	config_get value "$SECTION" web_heartbeat_min_response_ms; append_value --heartbeat-min-response-ms "$value"
	config_get value "$SECTION" web_heartbeat_timeout_ms; append_value --heartbeat-timeout-ms "$value"
	config_get value "$SECTION" web_gateway_peer_url; append_value --gateway-peer-url "$value"
	config_get value "$SECTION" web_html_port
	if [ -z "$value" ]; then
		procd_append_param command --no-web
	else
		procd_append_param command -l "$value"
	fi
	config_get value "$SECTION" web_api_addr; [ "$value" = 0.0.0.0 ] || append_value --api-server-addr "$value"
	config_get value "$SECTION" web_html_addr; [ "$value" = 0.0.0.0 ] || append_value --web-server-addr "$value"
	for flag in web_disable_registration web_allow_auto_create_user web_oidc_disable_pkce web_gateway_relay_data; do
		config_get value "$SECTION" "$flag" 0
		[ "$value" = 1 ] || continue
		case "$flag" in
			web_disable_registration) procd_append_param command --disable-registration ;;
			web_allow_auto_create_user) procd_append_param command --allow-auto-create-user ;;
			web_oidc_disable_pkce) procd_append_param command --oidc-disable-pkce ;;
			web_gateway_relay_data) procd_append_param command --gateway-relay-data ;;
		esac
	done
	config_get value "$SECTION" web_oidc_enabled 0
	if [ "$value" = 1 ]; then
		config_get value "$SECTION" web_oidc_issuer_url; append_value --oidc-issuer-url "$value"
		config_get value "$SECTION" web_oidc_client_id; append_value --oidc-client-id "$value"
		config_get value "$SECTION" web_oidc_client_secret; append_value --oidc-client-secret "$value"
		config_get value "$SECTION" web_oidc_redirect_url; append_value --oidc-redirect-url "$value"
		config_get value "$SECTION" web_oidc_username_claim; append_value --oidc-username-claim "$value"
		config_get value "$SECTION" web_oidc_scopes; append_value --oidc-scopes "$value"
		config_get value "$SECTION" web_oidc_frontend_base_url; append_value --oidc-frontend-base-url "$value"
	fi
	config_get value "$SECTION" web_webhook_enabled 0
	if [ "$value" = 1 ]; then
		config_get value "$SECTION" web_webhook_url; append_value --webhook-url "$value"
		config_get value "$SECTION" web_webhook_secret; append_value --webhook-secret "$value"
		config_get value "$SECTION" web_internal_auth_token; append_value --internal-auth-token "$value"
		config_get value "$SECTION" web_web_instance_id; append_value --web-instance-id "$value"
		config_get value "$SECTION" web_web_instance_api_base_url; append_value --web-instance-api-base-url "$value"
	fi
	config_get value "$SECTION" web_weblog off
	[ "$value" = off ] || append_value --console-log-level "$value"
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_set_param respawn 3600 5 5
	procd_close_instance

	# Web 服务单独运行；是否向 WAN 放行端口由 web_fw_* 选项决定。
	local web_port api_port html_port fw_web fw_api
	config_get web_port "$SECTION" web_port
	config_get api_port "$SECTION" web_api_port
	config_get html_port "$SECTION" web_html_port
	config_get fw_web "$SECTION" web_fw_web 0
	config_get fw_api "$SECTION" web_fw_api 0
	set_web_firewall "$web_port" "$api_port" "$html_port" "$fw_web" "$fw_api"
}

start_service() {
	load_config
	start_core
	start_web
	commit_firewall_changes
}

stop_service() {
	load_config
	[ "$enabled" = 1 ] || { cleanup_core_interface; cleanup_core_firewall_rules; }
	[ "$web_enabled" = 1 ] || cleanup_web_firewall
	commit_firewall_changes
}

service_triggers() {
	procd_add_reload_trigger easytier
}
