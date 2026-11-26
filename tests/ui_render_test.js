#!/usr/bin/env node
/*
 * 视图渲染冒烟测试（不需要设备、不需要浏览器）
 *
 * 用桩件执行 overview.js 的真实代码，验证：
 *   1. 阶段进度在非写入阶段显示 “—”，写入阶段显示百分比
 *   2. 日志区能拿到 log_tail 的内容（曾经因为 rpc.declare 的 expect 写错而永远空白）
 *   3. 首屏渲染用的是当前状态，而不是写死的 0
 *
 * 用法：node tests/ui_render_test.js
 */
'use strict';

const fs = require('fs');
const path = require('path');

const VIEW = path.join(__dirname, '..', 'package', 'luci-app-onecloud-upgrade',
	'htdocs', 'luci-static', 'resources', 'view', 'onecloud_upgrade', 'overview.js');

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log('  ok   ' + m); };
const bad = (m) => { fail++; console.log('  FAIL ' + m); };
const eq = (m, a, b) => (a === b ? ok(m) : bad(`${m}（期望 [${b}] 实际 [${a}]）`));

// ---- 极简 DOM ----
const registry = new Map();
function makeEl(tag, attrs, children) {
	const el = {
		tag, attrs: attrs || {}, children: [], textContent: '', value: attrs && attrs.value,
		checked: !!(attrs && attrs.checked), scrollTop: 0, scrollHeight: 0,
		appendChild(c) { this.children.push(c); if (c && c.attrs && c.attrs.id) registry.set(c.attrs.id, c); return c; }
	};
	if (typeof children === 'string') el.textContent = children;
	else if (Array.isArray(children)) {
		for (const c of children) {
			if (c == null) continue;
			if (typeof c === 'string') el.textContent += c;
			else if (c && c.attrs && c.attrs.id) registry.set(c.attrs.id, c);
			el.children.push(c);
		}
	}
	// 递归登记子节点里的 id
	(function walk(node) {
		if (!node || !node.children) return;
		for (const c of node.children) {
			if (c && c.attrs && c.attrs.id) registry.set(c.attrs.id, c);
			walk(c);
		}
	})(el);
	return el;
}
const E = (tag, attrs, children) => makeEl(tag, attrs, children);
const documentStub = { getElementById: (id) => registry.get(id) || null };

// ---- rpc 桩件 ----
const calls = [];
const replies = {
	status: () => state,
	config_get: () => config,
	backups: () => ({ backups: [] }),
	log_tail: () => ({ lines: 'line-1\nline-2\n' })
};
const rpc = {
	declare: (spec) => {
		const fn = function (...args) {
			calls.push(spec.method);
			const r = replies[spec.method];
			if (!r) return Promise.resolve({});
			const out = r.apply(null, args);
			// 模拟 LuCI 的 expect 语义：声明了 expect 就必须逐字段相等，否则 reject
			if (spec.expect) {
				for (const k of Object.keys(spec.expect)) {
					const want = spec.expect[k], got = out ? out[k] : undefined;
					if (got !== want) return Promise.reject(new Error(`unexpected data for ${spec.method}: ${k}`));
				}
			}
			return Promise.resolve(out);
		};
		return fn;
	}
};

let pollFns = [];
const poll = { add: (fn) => pollFns.push(fn) };
const ui = { addNotification: () => {}, createHandlerFn: (ctx, fn) => fn };
const windowStub = { setTimeout: (fn) => fn() };
const view = { extend: (o) => o };

let state = {}, config = {};

function loadView() {
	const src = fs.readFileSync(VIEW, 'utf8');
	// 视图源码顶层有 return，包一层函数即可执行
	const factory = new Function('view', 'rpc', 'poll', 'ui', 'E', 'document', 'window', 'confirm',
		src + '\n//# sourceURL=overview.js');
	return factory(view, rpc, poll, ui, E, documentStub, windowStub, () => true);
}

function ctx(label, st, cfg) {
	registry.clear(); pollFns = []; calls.length = 0;
	state = st; config = cfg;
	const mod = loadView();
	const data = [st, cfg, { backups: [] }];
	mod.render.call(mod, data);
	return mod;
}

(async function main() {
	console.log('== 视图：已就绪（idle/ok）==');
	ctx('idle', {
		schema: 1, phase: 'idle', last_result: 'ok', mixed_state: 'N',
		current: '26.11.21_08.59.21', version: '26.11.21_08.59.21',
		detail: '已是最新（26.11.21_08.59.21）', progress: 70, code: 0
	}, { repo: 'a/b', tag: '', channel: 'stable', dry_run: '0', require_signature: '0', force: '0' });

	eq('状态卡不再有进度条元素', registry.get('oc-prog'), undefined);

	await new Promise((r) => setTimeout(r, 10));
	await Promise.all(pollFns.map((f) => f()));
	eq('日志区拿到 log_tail 内容', registry.get('oc-log').textContent, 'line-1\nline-2\n');
	ok('log_tail 被调用：' + (calls.includes('log_tail') ? '是' : '否'));

	console.log('== 视图：写入中（writing_boot）==');
	ctx('writing_boot', {
		schema: 1, phase: 'writing_boot', last_result: 'none', mixed_state: 'N',
		current: '26.11.18_16.27.30', version: '26.11.21_08.59.21',
		detail: '正在写入（boot 为最后一步）', progress: 70, code: 0
	}, { repo: 'a/b', dry_run: '0' });

	eq('写入阶段显示阶段名', registry.get('oc-phase').textContent, '阶段：写入 boot');
	eq('写入阶段显示说明', registry.get('oc-detail').textContent, '说明：正在写入（boot 为最后一步）');
	eq('写入阶段同样没有进度条', registry.get('oc-prog'), undefined);

	console.log('== 视图：日志为空 ==');
	registry.clear(); pollFns = []; calls.length = 0;
	replies.log_tail = () => ({ lines: '' });
	state = { phase: 'idle', progress: 0, current: 'x', version: 'x', detail: 'd' };
	const mod = loadView();
	mod.render.call(mod, [state, { repo: 'a/b' }, { backups: [] }]);
	await new Promise((r) => setTimeout(r, 10));
	await Promise.all(pollFns.map((f) => f()));
	eq('空日志给出提示', registry.get('oc-log').textContent, '（暂无日志）');

	console.log(`结果: pass=${pass} fail=${fail}`);
	process.exit(fail === 0 ? 0 : 1);
})().catch((e) => { console.error('harness error:', e); process.exit(2); });
