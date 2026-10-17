import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../luci-app-easytier/htdocs/luci-static/resources/view/easytier/diagnostics.js', import.meta.url), 'utf8');

function createView() {
	const requests = [];
	const clipboard = [];
	const document = { hidden: false };
	const translations = {
		'Peer RPC Errors': '节点 RPC 错误',
		'Action': '动作',
		'Drop (no response)': '丢弃（不响应）'
	};
	const context = vm.createContext({
		_: text => translations[text] || text,
		E: (tag, attributes, content) => ({ tag, attributes, content, appendChild() {} }),
		view: { extend: value => value },
		document,
		dom: { content: (target, value) => { target.content = value; } },
		ui: { addNotification() {} },
		navigator: { clipboard: { writeText: async text => { clipboard.push(text); } } },
		easytier: {
			read: (action, args) => new Promise((resolve, reject) => {
				requests.push({ action, args: [...args], resolve, reject });
			})
		}
	});
	vm.runInContext('String.prototype.format = function(value) { return this.replace("%s", value); };', context);
	const page = vm.runInContext('(function() {\n' + source + '\n})()', context);
	page.refs = { output: {}, updated: {} };
	page.currentSource = 'stats';
	page.currentText = '';
	return { page, requests, document, clipboard };
}

test('queries are serialized and an old source cannot replace the display or copied text', async () => {
	const { page, requests } = createView();
	const first = page.refresh(false);
	page.refresh(false);
	assert.equal(requests.length, 1);
	page.currentSource = 'node';
	page.refresh(true);
	assert.equal(requests.length, 1);
	requests[0].resolve({ output: 'old stats' });
	await new Promise(setImmediate);
	assert.equal(requests.length, 2);
	assert.deepEqual(requests[1].args, ['node']);
	assert.equal(page.currentText, '');
	requests[1].resolve({ output: 'current node' });
	await first;
	assert.equal(page.currentText, 'current node');
	assert.equal(page.refs.output.content.content, 'current node');
});

test('automatic refresh pauses in hidden pages and manual refresh keeps raw output for copying', async () => {
	const { page, requests, document, clipboard } = createView();
	document.hidden = true;
	await page.refresh(false);
	assert.equal(requests.length, 0);
	const pending = page.refresh(true);
	requests[0].resolve({ output: 'peer_rpc_errors 12' });
	await pending;
	assert.equal(page.refs.output.content.content, '节点 RPC 错误 12');
	await page.copyOutput();
	assert.deepEqual(clipboard, ['peer_rpc_errors 12']);
});

test('ACL field translation preserves values and a failed request can be retried', async () => {
	const { page, requests } = createView();
	page.currentSource = 'acl';
	const failed = page.refresh(true);
	requests[0].reject(new Error('connection lost'));
	await failed;
	assert.equal(page.refs.output.content.content, 'connection lost');
	const retried = page.refresh(true);
	requests[1].resolve({ output: 'action: Drop, name: rule-1' });
	await retried;
	assert.match(page.refs.output.content.content, /^动作: 丢弃（不响应）/);
	assert.match(page.refs.output.content.content, /rule-1/);
	assert.equal(page.currentText, 'action: Drop, name: rule-1');
});

test('unsupported JSON output falls back to the selected source as plain text', async () => {
	const { page, requests } = createView();
	page.currentSource = 'peer';
	const pending = page.refresh(true);
	assert.deepEqual(requests[0].args, ['peer', 'json']);
	requests[0].resolve({ output: 'unsupported format' });
	await new Promise(setImmediate);
	assert.deepEqual(requests[1].args, ['peer']);
	requests[1].resolve({ output: 'peer listing' });
	await pending;
	assert.equal(page.currentText, 'peer listing');
	assert.equal(page.refs.output.content.content, 'peer listing');
});
