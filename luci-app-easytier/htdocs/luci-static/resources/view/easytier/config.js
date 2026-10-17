'use strict';
'require view';
'require form';
'require uci';
'require validation';

function add(section, tab, type, name, title, description, datatype) {
	var option = section.taboption(tab, type, name, _(title), description ? _(description) : null);
	if (datatype)
		option.datatype = datatype;
	return option;
}

function addValues(section, tab, name, title, description, values, defaultValue) {
	var option = add(section, tab, form.ListValue, name, title, description);
	values.forEach(function(value) { option.value(value[0], _(value[1])); });
	if (defaultValue != null)
		option.default = defaultValue;
	return option;
}

return view.extend({
	load: function() {
		return uci.load('easytier');
	},
	render: function() {
		var m = new form.Map('easytier', _('EasyTier Settings'),
			_('Configure EasyTier Core startup, network settings, and firewall integration.'));

		// 所有选项映射到同一个匿名 UCI 节，由 init 脚本按启动方式转换成 Core 参数。
		var s = m.section(form.TypedSection, 'easytier');
		s.anonymous = true;
		s.addremove = false;
		s.tab('general', _('General Settings'));
		s.tab('listeners', _('Listeners'));
		s.tab('relay', _('Forwarding and Proxy'));
		s.tab('security', _('Security'));
		s.tab('advanced', _('Advanced Settings'));
		s.tab('network', _('Network and Firewall'));

		var enabled = add(s, 'general', form.Flag, 'enabled', 'Enable EasyTier Core');
		enabled.default = '0';
		enabled.rmempty = false;
		addValues(s, 'general', 'etcmd', 'Startup Method', 'Choose CLI arguments, TOML file, or Web Console configuration.', [
			['etcmd', 'CLI Arguments'], ['config', 'Configuration File'], ['web', 'Web Console']
		], 'etcmd');
		addValues(s, 'general', 'log', 'Program Log Level', 'Log level passed to EasyTier Core.', [
			['off', 'off'], ['error', 'error'], ['warn', 'warn'], ['info', 'info'], ['debug', 'debug'], ['trace', 'trace']
		], 'off');
		var networkName = add(s, 'general', form.Value, 'network_name', 'Network Name', 'Identifies the virtual network.');
		networkName.password = true;
		networkName.maxlength = 64;
		networkName.depends('etcmd', 'etcmd');
		var secret = add(s, 'general', form.Value, 'network_secret', 'Network Secret', 'Shared secret used to authenticate this node.');
		secret.password = true;
		secret.maxlength = 128;
		secret.depends('etcmd', 'etcmd');
		add(s, 'general', form.Value, 'external_node', 'External Node', 'Optional public address advertised by this node.').depends('etcmd', 'etcmd');
		add(s, 'general', form.Flag, 'ip_dhcp', 'Enable DHCP', 'Obtain the virtual address from EasyTier.').depends('etcmd', 'etcmd');
		add(s, 'general', form.Value, 'ipaddr', 'Interface IPv4 Address', 'Leave empty for forwarding only.', 'ip4addr').depends('etcmd', 'etcmd');
		add(s, 'general', form.Value, 'ip6addr', 'Interface IPv6 Address', 'Optional address for dual-stack operation.', 'ip6addr').depends('etcmd', 'etcmd');
		add(s, 'general', form.DynamicList, 'peeradd', 'Peer Nodes', 'Initial peer addresses.').depends('etcmd', 'etcmd');
		var webConfig = add(s, 'general', form.Value, 'web_config', 'Web Configuration Address', 'Use a full URL such as udp://config-server.easytier.cn:22020/username. Legacy official usernames are expanded automatically.');
		webConfig.placeholder = 'udp://config-server.easytier.cn:22020/username';
		webConfig.depends('etcmd', 'web');
		add(s, 'general', form.Value, 'desvice_name', 'Hostname', 'Name shown to other nodes.').depends('etcmd', 'web');
		add(s, 'general', form.Value, 'tunname', 'Virtual Interface Name', 'TUN device name.').depends('etcmd', 'etcmd');

		addValues(s, 'listeners', 'listenermode', 'Listener Ports', 'Disable listeners when this node only connects to peers.', [
			['ON', 'Listen'], ['OFF', 'Do Not Listen']
		], 'ON').depends('etcmd', 'etcmd');
		[
			['tcp_port', 'TCP/UDP Port'], ['udp_port', 'UDP Port'], ['ws_port', 'WS Port'], ['wss_port', 'WSS Port'],
			['wg_port', 'WireGuard Port'], ['quic_port', 'QUIC Port']
		].forEach(function(item) {
			var o = add(s, 'listeners', form.Value, item[0], item[1], 'Listening port used by the selected protocol.', 'port');
			o.depends({ listenermode: 'ON', etcmd: 'etcmd' });
		});
		var mapped = add(s, 'listeners', form.DynamicList, 'mapped_listeners', 'Mapped Listener Addresses', 'Public addresses for listening ports.');
		mapped.depends({ listenermode: 'ON', etcmd: 'etcmd' });
		addValues(s, 'listeners', 'default_protocol', 'Default Protocol', null, [
			['-', 'Default'], ['tcp', 'TCP'], ['udp', 'UDP'], ['ws', 'WS'], ['wss', 'WSS']
		], '-').depends('etcmd', 'etcmd');

		add(s, 'relay', form.DynamicList, 'proxy_network', 'Subnet Proxy', 'Local networks exported to EasyTier peers.').depends('etcmd', 'etcmd');
		add(s, 'relay', form.Flag, 'proxy_forward', 'Disable Built-in NAT').depends('etcmd', 'etcmd');
		add(s, 'relay', form.Flag, 'relay_all', 'Allow Forwarding from All Peers').depends('etcmd', 'etcmd');
		var relay = add(s, 'relay', form.Flag, 'relay_network', 'Limit Forwarded Networks');
		relay.depends('etcmd', 'etcmd');
		var whitelist = add(s, 'relay', form.DynamicList, 'whitelist', 'Whitelisted Networks', 'Empty list disables forwarding.');
		whitelist.depends({ relay_network: '1', etcmd: 'etcmd' });
		add(s, 'relay', form.Flag, 'exit_node', 'Enable Exit Node').depends('etcmd', 'etcmd');
		add(s, 'relay', form.DynamicList, 'exit_nodes', 'Exit Node Addresses', 'Virtual IPv4 addresses of exit nodes.').depends('etcmd', 'etcmd');
		add(s, 'relay', form.DynamicList, 'manual_routes', 'Manual Routes', 'Route CIDR entries.').depends('etcmd', 'etcmd');
		add(s, 'relay', form.Value, 'socks_port', 'SOCKS5 Port', 'Leave empty to disable SOCKS5.', 'port').depends('etcmd', 'etcmd');
		add(s, 'relay', form.DynamicList, 'port_forward', 'Port Forwarding', 'Port forwarding rules for EasyTier peers.').depends('etcmd', 'etcmd');
		add(s, 'relay', form.Value, 'foreign_relay_bps_limit', 'Foreign Relay Bandwidth Limit', null, 'uinteger').depends('etcmd', 'etcmd');
		add(s, 'relay', form.Value, 'instance_recv_bps_limit', 'Instance Receive Rate Limit', 'Maximum inbound bytes per second for this instance. Leave empty for no limit.', 'uinteger').depends('etcmd', 'etcmd');
		[
			['kcp_proxy', 'Enable KCP Proxy'], ['kcp_input', 'Disable KCP Input'],
			['quic_proxy', 'Enable QUIC Proxy'], ['quic_input', 'Disable QUIC Input'],
			['relay_kcp', 'Enable Foreign Network KCP Relay'], ['disable_relay_kcp', 'Disable Relay KCP'],
			['relay_quic', 'Enable Foreign Network QUIC Relay'], ['disable_relay_quic', 'Disable Relay QUIC']
		].forEach(function(item) { add(s, 'relay', form.Flag, item[0], item[1]).depends('etcmd', 'etcmd'); });

		add(s, 'security', form.Flag, 'disable_encryption', 'Disable Encryption').depends('etcmd', 'etcmd');
		addValues(s, 'security', 'encryption_algorithm', 'Encryption Algorithm', null, [
			['xor', 'xor'], ['chacha20', 'chacha20'], ['aes-gcm', 'aes-gcm'], ['aes-256-gcm', 'aes-256-gcm'],
			['openssl-aes-gcm', 'openssl-aes-gcm'], ['openssl-chacha20', 'openssl-chacha20'], ['openssl-aes-256-gcm', 'openssl-aes-256-gcm']
		], 'aes-gcm').depends('etcmd', 'etcmd');
		add(s, 'security', form.Flag, 'private_mode', 'Private Mode').depends('etcmd', 'etcmd');
		add(s, 'security', form.Value, 'rpc_portal', 'RPC Portal Port', 'Local management port used by easytier-cli.', 'port').depends('etcmd', 'etcmd');
		add(s, 'security', form.Value, 'rpc_portal_whitelist', 'RPC Access Whitelist', 'Comma-separated client address ranges.').depends('etcmd', 'etcmd');
		add(s, 'security', form.Value, 'instance_name', 'Instance Name', 'Distinguishes multiple EasyTier instances on this device.').depends('etcmd', 'etcmd');
		add(s, 'security', form.Value, 'udp_white_port', 'UDP Port Whitelist').depends('etcmd', 'etcmd');
		add(s, 'security', form.Value, 'tcp_white_port', 'TCP Port Whitelist').depends('etcmd', 'etcmd');

		add(s, 'advanced', form.Flag, 'multi_thread', 'Enable Multithreading').depends('etcmd', 'etcmd');
		add(s, 'advanced', form.Value, 'multi_thread_count', 'Number of Threads', null, 'uinteger').depends('etcmd', 'etcmd');
		add(s, 'advanced', form.Value, 'mtu', 'MTU', null, 'range(1,1500)').depends('etcmd', 'etcmd');
		var portal = add(s, 'advanced', form.Value, 'vpn_portal', 'VPN Portal Listen Address', 'EasyTier 2.7.0 requires wg://IP:PORT, a non-empty network secret, a portal private key and named clients. Migrate old CIDR URLs and export new client configurations.');
		portal.placeholder = 'wg://0.0.0.0:51820';
		portal.depends('etcmd', 'etcmd');
		portal.validate = function(sectionId, value) {
			if (!value)
				return true;
			var match = /^wg:\/\/(\[[^\]]+\]|[^:\/\s?#@]+):([0-9]+)$/.exec(value);
			if (!match || !(match[1][0] === '[' ? validation.parseIPv6(match[1].slice(1, -1)) : validation.parseIPv4(match[1])) || +match[2] < 1 || +match[2] > 65535)
				return _('Use wg://IP:PORT without a client CIDR path.');
			return privateKey.formvalue(sectionId) ? true : _('A VPN portal private key is required.');
		};
		var privateKey = add(s, 'advanced', form.Value, 'vpn_portal_private_key', 'VPN Portal Private Key', 'Base64 encoded 32-byte WireGuard private key. Passed through the process environment.');
		privateKey.password = true;
		privateKey.retain = true;
		privateKey.depends('etcmd', 'etcmd');
		privateKey.validate = function(sectionId, value) {
			if (!value)
				return portal.formvalue(sectionId) ? _('A VPN portal private key is required.') : true;
			return /^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$/.test(value) ? true : _('Enter a base64 encoded 32-byte WireGuard private key.');
		};
		var clients = add(s, 'advanced', form.DynamicList, 'vpn_portal_clients', 'VPN Portal Clients', 'One named WireGuard client per entry: NAME=IPv4/PREFIX, for example client1=10.14.14.1/24. Requires EasyTier 2.7.0.');
		clients.placeholder = 'client1=10.14.14.1/24';
		clients.retain = true;
		clients.depends('etcmd', 'etcmd');
		clients.validate = function(sectionId, value) {
			var entries = Array.isArray(value) ? value : [value];
			return entries.every(function(entry) {
				if (!entry)
					return true;
				var match = /^[A-Za-z0-9][A-Za-z0-9-]*=([0-9.]+)\/([0-9]{1,2})$/.exec(entry);
				return match && validation.parseIPv4(match[1]) && +match[2] <= 32;
			}) ? true : _('Use NAME=IPv4/PREFIX; names may contain letters, digits and dashes.');
		};
		addValues(s, 'advanced', 'comp', 'Compression Algorithm', null, [['none', 'Default'], ['zstd', 'Zstandard']], 'none').depends('etcmd', 'etcmd');
		[
			['smoltcp', 'Use Userspace TCP/IP Stack'], ['no_tun', 'No TUN Mode'],
			['disable_ipv6', 'Disable IPv6'], ['latency_first', 'Latency First'],
			['disable_p2p', 'Disable P2P'], ['p2p_only', 'P2P Only'],
			['lazy_p2p', 'Lazy P2P'], ['need_p2p', 'Need P2P'],
			['disable_udp', 'Disable UDP Hole Punching'], ['disable_tcp', 'Disable TCP Hole Punching'],
			['disable_sym', 'Disable Symmetric NAT Hole Punching'], ['bind_device', 'Bind to Physical NIC'],
			['accept_dns', 'Accept DNS']
		].forEach(function(item) { add(s, 'advanced', form.Flag, item[0], item[1]).depends('etcmd', 'etcmd'); });
		add(s, 'advanced', form.Flag, 'disable_upnp', 'Disable UPnP', 'Disable automatic UPnP and NAT-PMP listener port mapping. Requires EasyTier 2.7.0.').depends('etcmd', 'etcmd');
		add(s, 'advanced', form.Value, 'socket_mark', 'Socket Mark', 'Linux SO_MARK for underlay sockets, used with policy routing.', 'range(0,4294967295)').depends('etcmd', 'etcmd');
		var dnsZone = add(s, 'advanced', form.Value, 'tld_dns_zone', 'Magic DNS Zone', 'DNS zone used by Magic DNS. The default is et.net.');
		dnsZone.placeholder = 'et.net.';
		dnsZone.depends({ etcmd: 'etcmd', accept_dns: '1' });
		dnsZone.retain = true;
		add(s, 'advanced', form.DynamicList, 'stun_servers', 'STUN Servers', 'Custom UDP STUN servers in HOST:PORT format. Leave empty for built-in defaults.').depends('etcmd', 'etcmd');
		add(s, 'advanced', form.DynamicList, 'tcp_stun_servers', 'STUN Servers (TCP)', 'Custom TCP STUN servers in HOST:PORT format. Leave empty for built-in defaults.').depends('etcmd', 'etcmd');
		add(s, 'advanced', form.DynamicList, 'extra_args', 'Additional Arguments', 'Each list entry is passed as one argument.').depends('etcmd', 'etcmd');

		// 接口、防火墙和连通性检查独立于启动方式，适用于由外部自行管理网络的部署。
		add(s, 'network', form.Flag, 'auto_config_interface', 'Manage EasyTier Network Interface');
		add(s, 'network', form.Flag, 'auto_config_firewall', 'Manage EasyTier Firewall Rules');
		var allowRouterInput = add(s, 'network', form.Flag, 'allow_router_input', 'Allow EasyTier Nodes to Access Router Services', 'Allow nodes in the EasyTier network to reach services on the router itself.');
		allowRouterInput.default = '0';
		allowRouterInput.depends('auto_config_firewall', '1');
		add(s, 'network', form.Value, 'interface_netmask', 'Interface IPv4 Netmask', null, 'ip4addr');
		var connectivityCheck = add(s, 'network', form.Flag, 'check', 'Connectivity Check', 'Restart EasyTier Core when every configured IPv4 target is unreachable.');
		connectivityCheck.default = '0';
		var checkTargets = add(s, 'network', form.DynamicList, 'checkip', 'Check IPs', 'IPv4 addresses checked while EasyTier Core is running.');
		checkTargets.datatype = 'ip4addr';
		checkTargets.depends('check', '1');
		var checkInterval = add(s, 'network', form.Value, 'checktime', 'Interval Time (minutes)', null, 'range(1,60)');
		checkInterval.default = '2';
		checkInterval.depends('check', '1');
		var forward = s.taboption('network', form.MultiValue, 'et_forward', _('Access Control'));
		forward.value('etfwlan', _('Allow traffic from EasyTier to LAN'));
		forward.value('etfwwan', _('Allow traffic from EasyTier to WAN'));
		forward.value('lanfwet', _('Allow traffic from LAN to EasyTier'));
		forward.value('wanfwet', _('Allow traffic from WAN to EasyTier'));

		return m.render();
	}
});
