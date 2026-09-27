'use strict';
'require fs';

function callRead(action, params) {
	// 只读 RPC 返回结构化 JSON；非零退出码和格式错误都转换为页面可显示的异常。
	return fs.exec('/usr/libexec/easytier/rpc', [action].concat(params || []))
		.then(function(result) {
			if (result.code !== 0)
				return Promise.reject(new Error(result.stderr || _('EasyTier status request failed')));
			try {
				return JSON.parse(result.stdout || '{}');
			}
			catch (e) {
				return Promise.reject(new Error(_('Invalid reply from EasyTier helper')));
			}
		});
}

function callManage(action, params) {
	// 管理操作以 JSON 的 success 字段为准，兼容辅助程序通过标准输出返回错误说明。
	return fs.exec('/usr/libexec/easytier/manage', [action].concat(params || []))
		.then(function(result) {
			var reply;
			try {
				reply = JSON.parse(result.stdout || '{}');
			}
			catch (e) {
				return Promise.reject(new Error(_('Invalid reply from EasyTier helper')));
			}
			if (!reply.success)
				return Promise.reject(new Error(reply.message || result.stderr || _('EasyTier operation failed')));
			return reply;
		});
}

function initAction(action) {
	// 服务动作单独走 init 脚本，不让页面直接执行任意 shell 命令。
	return fs.exec('/etc/init.d/easytier', [action]).then(function(result) {
		if (result.code !== 0)
			return Promise.reject(new Error(result.stderr || _('Service action failed')));
		return result;
	});
}

return {
	read: callRead,
	manage: callManage,
	service: initAction
};
