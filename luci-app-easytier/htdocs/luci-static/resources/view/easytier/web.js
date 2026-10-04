'use strict';
'require view';
'require form';
'require uci';
'require ui';
'require easytier.common as easytier';

function value(section, id, title, description, datatype) {
	var option = section.option(form.Value, id, _(title), description ? _(description) : null);
	if (datatype)
		option.datatype = datatype;
	return option;
}

function flag(section, id, title, description) {
	var option = section.option(form.Flag, id, _(title), description ? _(description) : null);
	option.default = '0';
	return option;
}

function fold(option, master) {
	// 高级字段随启用开关折叠；retain 避免关闭开关时清除已保存的配置。
	option.depends(master, '1');
	option.retain = true;
	return option;
}

return view.extend({
	load: function() {
		return uci.load('easytier');
	},
	render: function() {
		var m = new form.Map('easytier', _('EasyTier Web Console'),
			_('Configure the self-hosted EasyTier Web Console service.'));

		var s = m.section(form.TypedSection, 'easytier', _('Web Service'),
			_('Service listening addresses, ports, and firewall access.'));
		s.anonymous = true;
		s.addremove = false;
		flag(s, 'web_enabled', 'Enable EasyTier Web');
		value(s, 'webbin', 'Web Binary Path');
		value(s, 'web_db_path', 'Database Path', 'Database files are restricted to /etc/easytier or /var/lib/easytier by the reset operation.');
		var protocol = s.option(form.ListValue, 'web_protocol', _('Protocol'));
		protocol.value('udp', 'UDP');
		protocol.value('tcp', 'TCP');
		protocol.default = 'udp';
		value(s, 'web_port', 'Web Service Port', null, 'port');
		value(s, 'web_api_port', 'API Port', null, 'port');
		value(s, 'web_html_port', 'HTML Port', 'Leave empty to disable the HTML service.', 'port');
		value(s, 'web_api_addr', 'API Listen Address', 'Defaults to 0.0.0.0.');
		value(s, 'web_html_addr', 'HTML Listen Address', 'Defaults to 0.0.0.0.');
		value(s, 'web_api_host', 'API Host');
		value(s, 'web_geoip_db', 'GeoIP Database Path');
		var resetDatabase = s.option(form.Button, '_reset_database', _('Reset Database'));
		resetDatabase.inputtitle = _('Delete Web Database');
		resetDatabase.inputstyle = 'remove';
		resetDatabase.onclick = function() {
			// 页面确认用于防止误触；路径、符号链接和 Web 进程状态仍由设备端再次检查。
			if (!window.confirm(_('This permanently deletes the Web Console database and its WAL files. Continue?')))
				return Promise.resolve();
			return easytier.manage('reset-database').then(function(result) {
				ui.addNotification(null, E('p', {}, result.message));
			}).catch(function(error) {
				ui.addNotification(null, E('p', {}, error.message));
			});
		};
		flag(s, 'web_fw_web', 'Allow Web Service Through WAN Firewall');
		flag(s, 'web_fw_api', 'Allow API and HTML Through WAN Firewall');
		flag(s, 'web_disable_registration', 'Disable Registration');
		flag(s, 'web_allow_auto_create_user', 'Allow Automatic User Creation');
		var log = s.option(form.ListValue, 'web_weblog', _('Web Log Level'));
		['off', 'error', 'warn', 'info', 'debug', 'trace'].forEach(function(level) { log.value(level); });

		var oidc = m.section(form.TypedSection, 'easytier', _('OpenID Connect'),
			_('External identity provider sign-in for the Web Console.'));
		oidc.anonymous = true;
		oidc.addremove = false;
		flag(oidc, 'web_oidc_enabled', 'Enable OpenID Connect');
		[
			['web_oidc_issuer_url', 'Issuer URL'], ['web_oidc_client_id', 'Client ID'],
			['web_oidc_redirect_url', 'Redirect URL'], ['web_oidc_username_claim', 'Username Claim'],
			['web_oidc_scopes', 'Scopes'], ['web_oidc_frontend_base_url', 'Frontend Base URL']
		].forEach(function(item) { fold(value(oidc, item[0], item[1]), 'web_oidc_enabled'); });
		fold(value(oidc, 'web_oidc_client_secret', 'Client Secret'), 'web_oidc_enabled').password = true;
		fold(flag(oidc, 'web_oidc_disable_pkce', 'Disable PKCE'), 'web_oidc_enabled');

		var webhook = m.section(form.TypedSection, 'easytier', _('Webhook and Internal Authentication'),
			_('Event notifications and trusted access between services.'));
		webhook.anonymous = true;
		webhook.addremove = false;
		flag(webhook, 'web_webhook_enabled', 'Enable Webhook');
		fold(value(webhook, 'web_webhook_url', 'Webhook URL'), 'web_webhook_enabled');
		fold(value(webhook, 'web_webhook_secret', 'Webhook Secret'), 'web_webhook_enabled').password = true;
		var internalToken = value(webhook, 'web_internal_auth_token', 'Internal Authentication Token');
		internalToken.password = true;
		value(webhook, 'web_web_instance_id', 'Instance ID');
		value(webhook, 'web_web_instance_api_base_url', 'Instance API Base URL');
		return m.render();
	}
});
