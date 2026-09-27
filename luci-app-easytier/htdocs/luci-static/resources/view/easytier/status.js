'use strict';
'require view';
'require ui';
'require dom';
'require poll';
'require uci';
'require easytier.common as easytier';

function configSection() {
	// 所有页面共用首个匿名 UCI 节，与 init 脚本读取的配置节保持一致。
	var sections = uci.sections('easytier', 'easytier');
	return sections.length ? sections[0]['.name'] : null;
}

return view.extend({
	load: function() {
		return Promise.all([
			easytier.read('status'),
			easytier.read('netinfo'),
			uci.load('easytier')
		]);
	},
	render: function(data) {
		// 更新函数只使用元素引用：dom.content() 不接受字符串 id，且初始渲染时节点尚未挂载。
		var refs = this.refs = {
			coreState: E('span', { class: 'label' }, '—'),
			coreVersion: E('span', {}, '—'),
			coreMemory: E('span', {}, ''),
			webState: E('span', { class: 'label' }, '—'),
			webVersion: E('span', {}, '—'),
			webMemory: E('span', {}, ''),
			alerts: E('div', {}),
			actions: E('div', {}),
			ifaceName: E('span', {}, '—'),
			ifaceAddresses: E('span', {}, '—'),
			ifaceMtu: E('span', {}, '—'),
			ifaceRx: E('span', {}, '—'),
			ifaceTx: E('span', {}, '—')
		};

		var sid = configSection();
		var corePath = E('input', { class: 'cbi-input-text', type: 'text' });
		var webPath = E('input', { class: 'cbi-input-text', type: 'text' });
		corePath.value = uci.get('easytier', sid, 'easytierbin') || '/usr/bin/easytier-core';
		webPath.value = uci.get('easytier', sid, 'webbin') || '/usr/bin/easytier-web';
		var file = E('input', { type: 'file', accept: '.zip,.tar,.tar.gz,.tgz,easytier-core,easytier-cli,easytier-web-embed' });
		var progress = E('progress', { max: 100, value: 0, style: 'width:100%;display:none;' });
		var message = E('p', {}, _('Select an official EasyTier binary or release archive.'));
		var installRestart = E('button', {
			class: 'btn cbi-button cbi-button-positive',
			click: ui.createHandlerFn(this, function() { return this.restart(); })
		}, _('Restart EasyTier'));
		installRestart.disabled = true;

		refs.program = E('div', { class: 'cbi-section' }, [
			E('h3', {}, _('Program Management')),
			E('p', {}, _('Binaries installed by the OpenWrt package manager should be updated through the package manager. Manual upload is provided for custom builds and custom installation paths.')),
			E('div', { class: 'table' }, [
				E('div', { class: 'tr' }, [E('div', { class: 'td left', style: 'width:30%' }, _('Core Binary Path')), E('div', { class: 'td left' }, corePath)]),
				E('div', { class: 'tr' }, [E('div', { class: 'td left', style: 'width:30%' }, _('Web Binary Path')), E('div', { class: 'td left' }, webPath)])
			]),
			E('button', {
				class: 'btn cbi-button cbi-button-save',
				click: ui.createHandlerFn(this, function() { return this.savePaths(sid, corePath.value, webPath.value); })
			}, _('Save Binary Paths')),
			E('hr'),
			E('p', {}, _('Supported archive formats: ZIP, TAR, TAR.GZ, and TGZ. Supported binaries: easytier-core, easytier-cli, and easytier-web-embed.')),
			file,
			progress,
			message,
			E('button', {
				class: 'btn cbi-button cbi-button-action',
				click: ui.createHandlerFn(this, function() {
					if (!file.files || !file.files.length) {
						message.textContent = _('Choose a file first.');
						return Promise.resolve();
					}
					return this.upload(file.files[0], progress, message, installRestart);
				})
			}, _('Upload and Install')),
			' ',
			installRestart
		]);

		function row(title, valueEl) {
			return E('div', { class: 'tr' }, [
				E('div', { class: 'td left', style: 'width:30%' }, title),
				E('div', { class: 'td left' }, valueEl)
			]);
		}

		var page = E('div', { class: 'cbi-map' }, [
			E('h2', {}, _('EasyTier Overview')),
			refs.alerts,
			E('div', { class: 'cbi-section' }, [
				E('h3', {}, _('Service Status')),
				E('div', { class: 'table' }, [
					row(_('EasyTier Core'), [refs.coreState, ' ', refs.coreVersion, ' ', refs.coreMemory]),
					row(_('EasyTier Web'), [refs.webState, ' ', refs.webVersion, ' ', refs.webMemory])
				]),
				refs.actions
			]),
			E('div', { class: 'cbi-section' }, [
				E('h3', {}, _('TUN Interface')),
				E('div', { class: 'table' }, [
					row(_('Interface'), refs.ifaceName),
					row(_('Addresses'), refs.ifaceAddresses),
					row(_('MTU'), refs.ifaceMtu),
					row(_('Received Bytes'), refs.ifaceRx),
					row(_('Transmitted Bytes'), refs.ifaceTx)
				])
			]),
			refs.program
		]);

		this.updateStatus(data[0]);
		this.updateNetinfo(data[1]);
		poll.add(L.bind(function() {
			// 概览页每 10 秒更新进程与接口信息。
			return Promise.all([
				easytier.read('status'),
				easytier.read('netinfo')
			]).then(L.bind(function(data) {
				this.updateStatus(data[0]);
				this.updateNetinfo(data[1]);
			}, this));
		}, this), 10);
		return page;
	},
	stateBadge: function(el, running, enabled, installed) {
		el.classList.remove('success', 'warning');
		if (!installed) {
			el.textContent = _('Not installed');
			return;
		}
		if (running) {
			el.classList.add('success');
			el.textContent = _('Running');
			return;
		}
		if (enabled)
			el.classList.add('warning');
		el.textContent = _('Stopped');
	},
	updateStatus: function(status) {
		var refs = this.refs;
		var coreInstalled = status.core_version && status.core_version !== 'unknown';
		var webInstalled = status.web_version && status.web_version !== 'unknown';
		this.stateBadge(refs.coreState, status.core_running, status.core_enabled, coreInstalled);
		this.stateBadge(refs.webState, status.web_running, status.web_enabled, webInstalled);
		refs.coreVersion.textContent = coreInstalled ? status.core_version : '—';
		refs.coreMemory.textContent = status.core_running && status.core_memory !== '-' ? status.core_memory : '';
		refs.webVersion.textContent = webInstalled ? status.web_version : '—';
		refs.webMemory.textContent = status.web_running && status.web_memory !== '-' ? status.web_memory : '';

		var messages = [];
		if (!coreInstalled)
			messages.push(E('div', { class: 'alert-message' }, [
				_('The EasyTier Core program is not installed. Install it in the program management section below first.'),
				' ',
				E('a', { href: '#', click: L.bind(function(ev) {
					ev.preventDefault();
					this.refs.program.scrollIntoView({ behavior: 'smooth' });
				}, this) }, _('Go to Program Management'))
			]));
		else if (status.core_enabled && !status.core_running)
			messages.push(E('div', { class: 'alert-message warning' }, [
				_('EasyTier Core is enabled but not running.'),
				' ',
				E('a', { href: L.url('admin/vpn/easytier/diagnostics') }, _('Open Diagnostics'))
			]));
		dom.content(refs.alerts, E([], messages));

		// 按运行态给出可执行操作：运行中显示停止与重启，停止时显示启动。
		var actions = [];
		if (coreInstalled) {
			if (status.core_running) {
				actions.push(E('button', {
					class: 'btn cbi-button cbi-button-negative',
					click: ui.createHandlerFn(this, function() { return this.runAction('stop'); })
				}, _('Stop')));
				actions.push(' ');
				actions.push(E('button', {
					class: 'btn cbi-button cbi-button-action',
					click: ui.createHandlerFn(this, function() { return this.runAction('restart'); })
				}, _('Restart')));
			}
			else {
				actions.push(E('button', {
					class: 'btn cbi-button cbi-button-positive',
					click: ui.createHandlerFn(this, function() { return this.runAction('start'); })
				}, _('Start')));
			}
		}
		dom.content(refs.actions, E([], actions));
	},
	updateNetinfo: function(network) {
		var refs = this.refs;
		refs.ifaceName.textContent = network.interface || '—';
		refs.ifaceAddresses.textContent = network.addresses || '—';
		refs.ifaceMtu.textContent = network.mtu || '—';
		refs.ifaceRx.textContent = network.rx_bytes || '—';
		refs.ifaceTx.textContent = network.tx_bytes || '—';
	},
	runAction: function(action) {
		return easytier.service(action).then(function() {
			ui.addNotification(null, E('p', {}, _('Service action requested: %s').format(action)));
		}).catch(function(error) {
			ui.addNotification(null, E('p', {}, error.message));
		});
	},
	savePaths: function(sid, corePath, webPath) {
		// 仅保存绝对路径和简单路径字符，并拒绝 .. 路径段；服务端仍会再次校验安装目标。
		if (!sid || !/^\/[A-Za-z0-9_./-]+$/.test(corePath) || !/^\/[A-Za-z0-9_./-]+$/.test(webPath) || /(^|\/)\.\.(\/|$)/.test(corePath) || /(^|\/)\.\.(\/|$)/.test(webPath)) {
			ui.addNotification(null, E('p', {}, _('Paths must be absolute and must not contain parent-directory components.')));
			return Promise.resolve();
		}
		uci.set('easytier', sid, 'easytierbin', corePath);
		uci.set('easytier', sid, 'webbin', webPath);
		return uci.save().then(function() { return uci.apply(); }).then(function() {
			ui.addNotification(null, E('p', {}, _('Binary paths saved.')));
		}).catch(function(error) {
			ui.addNotification(null, E('p', {}, _('Unable to save binary paths: %s').format(error.message || error)));
		});
	},
	upload: function(selectedFile, progress, message, restart) {
		var name = selectedFile.name.split('/').pop();
		// 浏览器先筛选名称和体积以尽早反馈；manage 辅助程序会在设备端重新验证文件内容。
		if (!/^(easytier-core|easytier-cli|easytier-web-embed|.+\.zip|.+\.tar|.+\.tar\.gz|.+\.tgz)$/.test(name)) {
			message.textContent = _('Unsupported file name.');
			return Promise.resolve();
		}
		if (selectedFile.size > 100 * 1024 * 1024) {
			message.textContent = _('File exceeds the 100 MiB upload limit.');
			return Promise.resolve();
		}
		message.textContent = _('Uploading…');
		progress.style.display = '';
		progress.value = 0;
		return new Promise(function(resolve, reject) {
			var body = new FormData();
			var request = new XMLHttpRequest();
			// 上传到固定临时路径并设置私有权限；后续安装命令只接受已知产物名。
			body.append('sessionid', L.env.sessionid);
			body.append('filename', '/tmp/easytier-upload');
			body.append('filemode', '600');
			body.append('filedata', selectedFile, name);
			request.open('POST', L.env.cgi_base + '/cgi-upload', true);
			request.upload.onprogress = function(event) {
				if (event.lengthComputable)
					progress.value = Math.round(event.loaded * 100 / event.total);
			};
			request.onerror = function() { reject(new Error(_('Upload request failed.'))); };
			request.onload = function() {
				if (request.status < 200 || request.status >= 300) {
					reject(new Error(request.responseText || _('Upload was rejected.')));
					return;
				}
				// 上传接口仅负责落盘；归档检查、二进制校验和原子替换由设备端处理。
				message.textContent = _('Validating and installing…');
				easytier.manage('install-upload', [name]).then(function(result) {
					message.textContent = result.message;
					// 安装成功后才开放重启按钮，让用户明确决定何时切换正在运行的程序。
					restart.disabled = false;
					resolve();
				}).catch(reject);
			};
			request.send(body);
		}).catch(function(error) {
			message.textContent = error.message;
			ui.addNotification(null, E('p', {}, error.message));
		});
	},
	restart: function() {
		return easytier.service('restart').then(function() {
			ui.addNotification(null, E('p', {}, _('EasyTier service restarted.')));
		}).catch(function(error) {
			ui.addNotification(null, E('p', {}, error.message));
		});
	}
});
