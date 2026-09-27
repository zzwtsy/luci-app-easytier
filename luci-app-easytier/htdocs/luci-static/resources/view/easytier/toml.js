'use strict';
'require view';
'require fs';
'require ui';
'require uci';
'require easytier.common as easytier';

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(fs.read('/etc/easytier/config.toml'), ''),
			L.resolveDefault(fs.read('/etc/easytier/et_machine_id'), ''),
			uci.load('easytier')
		]);
	},
	render: function(data) {
		var config = E('textarea', {
			id: 'easytier-toml-config',
			class: 'cbi-input-textarea',
			rows: 24,
			spellcheck: 'false',
			style: 'font-family:monospace;width:100%;'
		});
		config.value = data[0];
		var machineId = E('input', {
			id: 'easytier-machine-id',
			class: 'cbi-input-text',
			type: 'text',
			style: 'width:100%;'
		});
		machineId.value = data[1].trim();

		// 启动方式不是配置文件时，此文件的修改不会生效，提前提示避免误操作。
		var sections = uci.sections('easytier', 'easytier');
		var etcmd = sections.length ? (uci.get('easytier', sections[0]['.name'], 'etcmd') || 'etcmd') : 'etcmd';
		var banner = [];
		if (etcmd !== 'config')
			banner.push(E('div', { class: 'alert-message' }, [
				_('The current startup method does not use this file. Set Startup Method to Configuration File in the settings for it to take effect.'),
				' ',
				E('a', { href: L.url('admin/vpn/easytier/config') }, _('Open Settings'))
			]));

		var restartRow = E('div', { style: 'display:none;margin-top:0.5em;', id: 'easytier-toml-restart' }, [
			E('button', {
				class: 'btn cbi-button cbi-button-positive',
				click: ui.createHandlerFn(this, function() { return this.restartCore(); })
			}, _('Restart EasyTier Core'))
		]);

		return E('div', { class: 'cbi-map' }, [
			E('h2', {}, _('EasyTier Configuration File')),
			E('div', { class: 'cbi-section' }, [
				banner,
				E('p', {}, _('Edit /etc/easytier/config.toml. The Core startup method must be set to Configuration File for this file to be used.')),
				config,
				E('div', { class: 'right' }, E('button', {
					class: 'btn cbi-button cbi-button-save',
					click: ui.createHandlerFn(this, function() { return this.saveConfig(config.value); })
				}, _('Save Configuration File'))),
				restartRow
			]),
			E('div', { class: 'cbi-section' }, [
				E('h3', {}, _('Machine ID')),
				E('p', {}, _('Used by the EasyTier Web configuration mode. Leave empty to generate an ID on service start.')),
				machineId,
				E('div', { class: 'right' }, E('button', {
					class: 'btn cbi-button cbi-button-save',
					click: ui.createHandlerFn(this, function() { return this.saveMachineId(machineId.value); })
				}, _('Save Machine ID')))
			])
		]);
	},
	saveConfig: function(content) {
		// 384 是 fs.write 接受的十进制权限值，对应仅 root 可读写的 0600。
		return fs.write('/etc/easytier/config.toml', content.replace(/\r\n/g, '\n'), 384).then(function() {
			ui.addNotification(null, E('p', {}, _('Configuration file saved. Restart EasyTier Core to apply it.')));
			var restartRow = document.getElementById('easytier-toml-restart');
			if (restartRow)
				restartRow.style.display = '';
		}).catch(function(error) {
			ui.addNotification(null, E('p', {}, error.message));
		});
	},
	restartCore: function() {
		return easytier.service('restart').then(function() {
			ui.addNotification(null, E('p', {}, _('EasyTier service restarted.')));
		}).catch(function(error) {
			ui.addNotification(null, E('p', {}, error.message));
		});
	},
	saveMachineId: function(value) {
		value = value.trim();
		// 限制机器 ID 字符集和长度，避免把不受控内容写入服务身份文件。
		if (value && !/^[A-Za-z0-9-]{1,128}$/.test(value)) {
			ui.addNotification(null, E('p', {}, _('Machine ID may contain only letters, numbers, and hyphens.')));
			return Promise.resolve();
		}
		// 删除自定义 ID 后，init 脚本会在 Web 模式启动时生成并持久化新 ID。
		if (!value)
			return fs.remove('/etc/easytier/et_machine_id').then(function() {
				ui.addNotification(null, E('p', {}, _('Machine ID removed. A new ID will be generated when required.')));
			});
		return fs.write('/etc/easytier/et_machine_id', value + '\n', 384).then(function() {
			ui.addNotification(null, E('p', {}, _('Machine ID saved.')));
		}).catch(function(error) {
			ui.addNotification(null, E('p', {}, error.message));
		});
	}
});
