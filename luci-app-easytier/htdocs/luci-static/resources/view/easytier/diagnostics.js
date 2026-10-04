'use strict';
'require view';
'require ui';
'require dom';
'require poll';
'require easytier.common as easytier';

// 与 rpc 辅助程序中的子命令白名单保持一致，页面不能提交任意 CLI 参数。
// 第三列标记支持 JSON 输出的数据源，表格化失败时回退到纯文本。
var sources = [
	['peer', _('Peers'), true],
	['route', _('Routes'), true],
	['node', _('Node'), false],
	['connector', _('Connectors'), false],
	['stun', _('STUN'), false],
	['peer-center', _('Peer Center'), false],
	['vpn-portal', _('VPN Portal'), false],
	['proxy', _('Proxy'), false],
	['acl', _('ACL Statistics'), false],
	['mapped-listener', _('Mapped Listeners'), false],
	['stats', _('Statistics'), false],
	['log', _('Logs'), false]
];

function isPlainObject(value) {
	return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function extractRows(value) {
	// 顶层对象数组优先；否则在对象属性中寻找第一个对象数组，兼容不同子命令的 JSON 结构。
	if (Array.isArray(value) && value.length && value.every(isPlainObject))
		return value;
	if (isPlainObject(value)) {
		for (var key in value) {
			var nested = value[key];
			if (Array.isArray(nested) && nested.length && nested.every(isPlainObject))
				return nested;
		}
	}
	return null;
}

function renderTable(rows) {
	var columns = [];
	rows.forEach(function(row) {
		Object.keys(row).forEach(function(key) {
			if (columns.indexOf(key) === -1)
				columns.push(key);
		});
	});
	var table = E('div', { class: 'table' }, [
		E('div', { class: 'tr table-titles' }, columns.map(function(column) {
			return E('div', { class: 'th' }, column);
		}))
	]);
	rows.forEach(function(row) {
		table.appendChild(E('div', { class: 'tr' }, columns.map(function(column) {
			var value = row[column];
			if (value === null || value === undefined)
				value = '';
			else if (typeof value === 'object')
				value = JSON.stringify(value);
			return E('div', { class: 'td' }, String(value));
		})));
	});
	return table;
}

function textPre(text) {
	return E('pre', { style: 'white-space:pre-wrap;overflow:auto;max-height:70vh;' }, text);
}

return view.extend({
	load: function() {
		return Promise.resolve();
	},
	render: function() {
		var self = this;
		this.currentSource = 'peer';
		this.currentText = '';

		// 更新只使用元素引用：dom.content() 不接受字符串 id。
		var refs = this.refs = {
			output: E('div', {}, textPre(_('Loading…'))),
			updated: E('p', { class: 'cbi-section-descr' }, '')
		};

		var sourceSelect = E('select', { class: 'cbi-input-select' });
		sources.forEach(function(item) {
			sourceSelect.appendChild(E('option', { value: item[0] }, item[1]));
		});
		sourceSelect.value = this.currentSource;

		var intervalSelect = E('select', { class: 'cbi-input-select' }, [
			E('option', { value: '0' }, _('Auto Refresh: Off')),
			E('option', { value: '5' }, _('Auto Refresh: 5s')),
			E('option', { value: '10' }, _('Auto Refresh: 10s')),
			E('option', { value: '30' }, _('Auto Refresh: 30s'))
		]);

		var clearButton = E('button', {
			class: 'btn cbi-button cbi-button-negative',
			style: 'display:none;',
			click: ui.createHandlerFn(this, function() { return this.clearTemporaryLogs(); })
		}, _('Clear Temporary Log Files'));

		// 轮询函数保持稳定引用，便于切换间隔时移除旧的轮询项。
		this.pollFn = L.bind(function() { return this.refresh(false); }, this);

		sourceSelect.addEventListener('change', function() {
			self.currentSource = sourceSelect.value;
			clearButton.style.display = self.currentSource === 'log' ? '' : 'none';
			self.refresh(true);
		});
		intervalSelect.addEventListener('change', function() {
			poll.remove(self.pollFn);
			var seconds = parseInt(intervalSelect.value, 10);
			if (seconds > 0)
				poll.add(self.pollFn, seconds);
		});

		var page = E('div', { class: 'cbi-map' }, [
			E('h2', {}, _('EasyTier Diagnostics')),
			E('div', { class: 'cbi-section' }, [
				E('div', { style: 'display:flex;gap:0.5em;flex-wrap:wrap;align-items:center;margin-bottom:0.5em;' }, [
					sourceSelect,
					intervalSelect,
					E('button', {
						class: 'btn cbi-button cbi-button-action',
						click: ui.createHandlerFn(this, function() { return this.refresh(true); })
					}, _('Refresh')),
					E('button', {
						class: 'btn cbi-button',
						click: ui.createHandlerFn(this, function() { return this.copyOutput(); })
					}, _('Copy')),
					clearButton
				]),
				refs.output,
				refs.updated
			])
		]);

		this.refresh(false);
		return page;
	},
	refresh: function(announce) {
		var self = this;
		var refs = this.refs;
		var source = this.currentSource;
		if (announce)
			dom.content(refs.output, textPre(_('Loading…')));
		return this.fetch(source).then(function(result) {
			if (source !== self.currentSource)
				return;
			dom.content(refs.output, result);
			refs.updated.textContent = _('Last updated: %s').format(new Date().toLocaleTimeString());
		}).catch(function(error) {
			if (source !== self.currentSource)
				return;
			dom.content(refs.output, textPre(error.message));
		});
	},
	fetch: function(source) {
		var self = this;
		if (source === 'log') {
			return easytier.read('logs', ['core']).then(function(result) {
				self.currentText = result.output || _('No EasyTier log entries are available.');
				return textPre(self.currentText);
			});
		}
		var jsonCapable = sources.some(function(item) { return item[0] === source && item[2]; });
		if (!jsonCapable) {
			return easytier.read('conninfo', [source]).then(function(result) {
				self.currentText = result.output || _('No information available');
				return textPre(self.currentText);
			});
		}
		// 优先请求 JSON 输出并渲染为表格；解析失败时回退到纯文本输出，不报错。
		return easytier.read('conninfo', [source, 'json']).then(function(result) {
			var text = result.output || '';
			try {
				var rows = extractRows(JSON.parse(text));
				if (rows) {
					self.currentText = text;
					return renderTable(rows);
				}
			}
			catch (e) { /* 回退到纯文本 */ }
			return easytier.read('conninfo', [source]).then(function(plain) {
				self.currentText = plain.output || _('No information available');
				return textPre(self.currentText);
			});
		});
	},
	copyOutput: function() {
		var text = this.currentText;
		if (!text)
			return Promise.resolve();
		var done = function() {
			ui.addNotification(null, E('p', {}, _('Copied to clipboard.')));
		};
		var failed = function() {
			ui.addNotification(null, E('p', {}, _('Unable to copy to clipboard.')));
		};
		if (navigator.clipboard && navigator.clipboard.writeText)
			return navigator.clipboard.writeText(text).then(done, failed);
		// LuCI 常通过 HTTP 访问，剪贴板 API 可能不可用，退回选区复制。
		var area = document.createElement('textarea');
		area.value = text;
		area.style.position = 'fixed';
		area.style.opacity = '0';
		document.body.appendChild(area);
		area.select();
		try {
			document.execCommand('copy') ? done() : failed();
		}
		catch (e) {
			failed();
		}
		document.body.removeChild(area);
		return Promise.resolve();
	},
	clearTemporaryLogs: function() {
		// 此操作只清理旧版临时日志文件；系统日志由 logread 管理，不在这里删除。
		return easytier.manage('clear-logs').then(function(result) {
			ui.addNotification(null, E('p', {}, result.message));
			return this.refresh(false);
		}.bind(this)).catch(function(error) {
			ui.addNotification(null, E('p', {}, error.message));
		});
	}
});
