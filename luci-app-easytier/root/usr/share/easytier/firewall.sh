#!/bin/sh

set_option() {
	local package="$1" section="$2" option="$3" value="$4"
	# 只在值变化时写入 UCI，避免服务重复启动时产生无意义的配置变更。
	[ "$(uci -q get "$package.$section.$option")" = "$value" ] || uci set "$package.$section.$option=$value"
}

set_type() {
	local package="$1" section="$2" type="$3"
	[ "$(uci -q get "$package.$section")" = "$type" ] || uci set "$package.$section=$type"
}

set_rule() {
	local section="$1" protocol="$2" port="$3"
	# 端口为空或不合法时清除旧规则，防止配置被移除后仍意外暴露服务。
	case "$port" in ''|*[!0-9]*) uci -q delete "firewall.$section"; return 0 ;; esac
	[ "${#port}" -le 5 ] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || {
		uci -q delete "firewall.$section"
		return 0
	}
	set_type firewall "$section" rule
	set_option firewall "$section" name "$section"
	set_option firewall "$section" target ACCEPT
	set_option firewall "$section" src wan
	set_option firewall "$section" proto "$protocol"
	set_option firewall "$section" dest_port "$port"
	set_option firewall "$section" enabled 1
}

setup_network_interface() {
	local device="$1" address="$2" netmask="$3"
	[ -n "$device" ] || device=tun0
	set_type network EasyTier interface
	set_option network EasyTier device "$device"
	if [ -n "$address" ]; then
		set_option network EasyTier proto static
		set_option network EasyTier ipaddr "$address"
		set_option network EasyTier netmask "${netmask:-255.0.0.0}"
	else
		set_option network EasyTier proto none
		uci -q delete network.EasyTier.ipaddr
		uci -q delete network.EasyTier.netmask
	fi
	uci -q delete network.EasyTier.ifname
}

# 规则名称固定带有 EasyTier 前缀，清理时只删除本插件创建和维护的 UCI 节。
setup_firewall_zone() {
	set_type firewall easytierzone zone
	set_option firewall easytierzone name EasyTier
	set_option firewall easytierzone network EasyTier
	set_option firewall easytierzone input ACCEPT
	set_option firewall easytierzone output ACCEPT
	set_option firewall easytierzone forward ACCEPT
	set_option firewall easytierzone masq 1
	set_option firewall easytierzone mtu_fix 1
}

setup_forwarding_rules() {
	local forwards="$1"
	# 每个选项描述一个明确的源到目标方向，未选中的方向会移除对应转发节。
	case "$forwards" in *etfwlan*)
		set_type firewall easytierfwlan forwarding
		set_option firewall easytierfwlan src EasyTier
		set_option firewall easytierfwlan dest lan
		;;
	*) uci -q delete firewall.easytierfwlan ;;
	esac
	case "$forwards" in *etfwwan*)
		set_type firewall easytierfwwan forwarding
		set_option firewall easytierfwwan src EasyTier
		set_option firewall easytierfwwan dest wan
		;;
	*) uci -q delete firewall.easytierfwwan ;;
	esac
	case "$forwards" in *lanfwet*)
		set_type firewall lanfweasytier forwarding
		set_option firewall lanfweasytier src lan
		set_option firewall lanfweasytier dest EasyTier
		;;
	*) uci -q delete firewall.lanfweasytier ;;
	esac
	case "$forwards" in *wanfwet*)
		set_type firewall wanfweasytier forwarding
		set_option firewall wanfweasytier src wan
		set_option firewall wanfweasytier dest EasyTier
		;;
	*) uci -q delete firewall.wanfweasytier ;;
	esac
}

set_firewall_rules() {
	set_rule easytier_tcp_udp 'tcp udp' "$1"
	set_rule easytier_udp udp "$2"
	set_rule easytier_ws tcp "$3"
	set_rule easytier_wss tcp "$4"
	set_rule easytier_wg udp "$5"
	set_rule easytier_quic 'tcp udp' "$6"
}

set_web_firewall() {
	local web_port="$1" api_port="$2" html_port="$3" allow_web="$4" allow_api="$5"
	[ "$allow_web" = 1 ] && set_rule easytier_webserver 'tcp udp' "$web_port" || uci -q delete firewall.easytier_webserver
	[ "$allow_api" = 1 ] && set_rule easytier_webapi tcp "$api_port" || uci -q delete firewall.easytier_webapi
	if [ "$allow_api" = 1 ] && [ "$html_port" != "$api_port" ]; then
		set_rule easytier_webhtml tcp "$html_port"
	else
		uci -q delete firewall.easytier_webhtml
	fi
}

cleanup_web_firewall() {
	uci -q delete firewall.easytier_webserver
	uci -q delete firewall.easytier_webapi
	uci -q delete firewall.easytier_webhtml
}

cleanup_core_interface() {
	uci -q delete network.EasyTier
}

cleanup_core_firewall_rules() {
	uci -q delete firewall.easytierzone
	uci -q delete firewall.easytierfwlan
	uci -q delete firewall.easytierfwwan
	uci -q delete firewall.lanfweasytier
	uci -q delete firewall.wanfweasytier
	uci -q delete firewall.easytier_tcp_udp
	uci -q delete firewall.easytier_udp
	uci -q delete firewall.easytier_ws
	uci -q delete firewall.easytier_wss
	uci -q delete firewall.easytier_wg
	uci -q delete firewall.easytier_quic
	uci -q delete firewall.easytier_tcp
	uci -q delete firewall.easytier_wireguard
	uci -q delete firewall.easytier_socks5
}

commit_firewall_changes() {
	local network_changed=0 firewall_changed=0
	[ -z "$(uci changes network)" ] || { uci commit network && network_changed=1; }
	[ -z "$(uci changes firewall)" ] || { uci commit firewall && firewall_changed=1; }
	if [ "$network_changed" = 1 ] || [ "$firewall_changed" = 1 ]; then
		# 等待 procd 完成本次启动后再重载网络和防火墙，避免同步重载打断启动流程。
		(
			sleep 5
			[ "$network_changed" = 0 ] || /etc/init.d/network reload >/dev/null 2>&1
			[ "$firewall_changed" = 0 ] || /etc/init.d/firewall reload >/dev/null 2>&1
		) >/dev/null 2>&1 &
	fi
}
