'use strict';
'require view';
'require rpc';
'require poll';
'require ui';

var callStatus = rpc.declare({
	object: 'luci.onecloud-upgrade',
	method: 'status',
});

var callCheck = rpc.declare({
	object: 'luci.onecloud-upgrade',
	method: 'check',
	expect: { ok: true }
});

var callApply = rpc.declare({
	object: 'luci.onecloud-upgrade',
	method: 'apply',
	params: [ 'confirm' ],
	expect: { ok: true }
});

var callConfigGet = rpc.declare({
	object: 'luci.onecloud-upgrade',
	method: 'config_get',
});

var callConfigSet = rpc.declare({
	object: 'luci.onecloud-upgrade',
	method: 'config_set',
	params: [ 'provider', 'repo', 'asset_rootfs', 'asset_boot', 'channel' ],
	expect: { ok: true }
});

var callDiag = rpc.declare({
	object: 'luci.onecloud-upgrade',
	method: 'diag',
	expect: { ok: true }
});

var callBackups = rpc.declare({
	object: 'luci.onecloud-upgrade',
	method: 'backups'
});

var callRollback = rpc.declare({
	object: 'luci.onecloud-upgrade',
	method: 'rollback',
	params: [ 'id', 'mode' ],
	expect: { ok: true }
});

var callLogTail = rpc.declare({
	object: 'luci.onecloud-upgrade',
	method: 'log_tail',
	params: [ 'lines' ],
	expect: { lines: '' }
});

function badge(phase) {
	var map = {
		idle: '已就绪', checking: '检测中', ready: '可升级',
		applying: '写入中', writing_boot: '写入 boot', boot_written: '已写入待重启',
		unknown: '状态未知'
	};
	return map[phase] || phase || '未知';
}

return view.extend({
	load: function() {
		// 顺序加载：rpcd 的 exec 插件对同一对象的并发调用会互相卡住（实测 Promise.all 会一直停在加载中）
		return callStatus().then(function(st) {
			return callConfigGet().then(function(cfg) {
				return callBackups().then(function(bk) { return [ st, cfg, bk ]; });
			});
		});
	},

	render: function(data) {
		var st = data[0] || {}, cfg = data[1] || {};
		var bks = (data[2] && data[2].backups) || [];
		var self = this;

		this.statusEl = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, '当前状态'),
			E('p', { 'id': 'oc-phase' }, '阶段：' + badge(st.phase)),
			E('p', { 'id': 'oc-current' }, '本机版本：' + (st.current || '—')),
			E('p', { 'id': 'oc-version' }, '目标版本：' + (st.version || '—')),
			E('p', { 'id': 'oc-detail' }, '说明：' + (st.detail || '—'))
		]);

		var form = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, '固件源'),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, '仓库（owner/name）'),
				E('div', { 'class': 'cbi-value-field' },
					E('input', { 'id': 'oc-repo', 'type': 'text', 'value': cfg.repo || '', 'style': 'width:100%' }))
			]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, 'rootfs 资产名'),
				E('div', { 'class': 'cbi-value-field' },
					E('input', { 'id': 'oc-rootfs', 'type': 'text', 'value': cfg.asset_rootfs || '', 'style': 'width:100%' }))
			]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, 'boot 资产名'),
				E('div', { 'class': 'cbi-value-field' },
					E('input', { 'id': 'oc-boot', 'type': 'text', 'value': cfg.asset_boot || '', 'style': 'width:100%' }))
			]),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, '通道'),
				E('div', { 'class': 'cbi-value-field' },
					E('select', { 'id': 'oc-channel' }, [
						E('option', { 'value': 'stable', 'selected': cfg.channel === 'stable' ? '' : null }, 'stable'),
						E('option', { 'value': 'beta', 'selected': cfg.channel === 'beta' ? '' : null }, 'beta')
					]))
			]),
			E('div', { 'class': 'cbi-page-actions' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-save',
					'click': ui.createHandlerFn(this, function() {
						return callConfigSet(
							'github-release',
							document.getElementById('oc-repo').value,
							document.getElementById('oc-rootfs').value,
							document.getElementById('oc-boot').value,
							document.getElementById('oc-channel').value
						).then(function() { ui.addNotification(null, E('p', {}, '已保存'), 'info'); });
					})
				}, '保存')
			])
		]);

		var actions = E('div', { 'class': 'cbi-page-actions' }, [
			E('button', {
				'class': 'btn cbi-button cbi-button-action',
				'click': ui.createHandlerFn(this, function() {
					return callCheck().then(function() {
						ui.addNotification(null, E('p', {}, '已开始检测'), 'info');
					});
				})
			}, '检测新版本'),
			E('button', {
				'class': 'btn cbi-button cbi-button-action',
				'click': ui.createHandlerFn(this, function() {
					return callStatus().then(function(s) {
						if (!s || !s.version) { ui.addNotification(null, E('p', {}, '没有可升级版本，请先检测'), 'warning'); return; }
						if (!confirm('确认升级到 ' + s.version + '？\n\n写入期间不要断电。')) return;
						return callApply(s.version).then(function() {
							ui.addNotification(null, E('p', {}, '已受理，正在后台执行'), 'info');
						});
					});
				})
			}, '升级'),
			E('button', {
				'class': 'btn cbi-button',
				'click': ui.createHandlerFn(this, function() {
					return callDiag().then(function(r) {
						ui.addNotification(null, E('p', {},
							r && r.ok ? '诊断包已生成：' + r.path : '生成失败，请查看日志'), 'info');
					});
				})
			}, '导出诊断包')
		]);

		var backupRows = bks.map(function(b) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, b.id),
				E('td', { 'class': 'td' }, b.created_at || '—'),
				E('td', { 'class': 'td' }, String(b.size_kb || 0) + ' KB'),
				E('td', { 'class': 'td' }, b.kind === 'ours' ? '本应用' : '现网脚本'),
				E('td', { 'class': 'td' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-action',
						'click': ui.createHandlerFn(self, function() {
							if (!confirm('从备份 ' + b.id + ' 恢复 /etc/config？\n\n只覆盖备份里存在的文件，当前配置会先另存一份。'))
								return;
							return callRollback(b.id, 'merge').then(function(r) {
								ui.addNotification(null, E('p', {},
									r && r.ok ? '已恢复，重启或 reload 后生效' : '恢复失败，请查看日志'), 'info');
							});
						})
					}, '恢复')
				])
			]);
		});

		var backupSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, '配置备份与回滚'),
			E('p', { 'class': 'cbi-section-descr' },
				'恢复只作用于 /etc/config：默认合并（只覆盖备份里存在的文件），不会删除当前新增的配置。' +
				'若备份里含 network / firewall / uhttpd，恢复后可能影响当前连接，请先确认本地可访问设备。回滚本身也是一次写入。'),
			bks.length
				? E('table', { 'class': 'table' }, [
					E('tr', { 'class': 'tr table-titles' }, [
						E('th', { 'class': 'th' }, '备份 ID'),
						E('th', { 'class': 'th' }, '时间'),
						E('th', { 'class': 'th' }, '大小'),
						E('th', { 'class': 'th' }, '来源'),
						E('th', { 'class': 'th' }, '操作')
					])
				].concat(backupRows))
				: E('p', {}, '没有可用备份')
		]);

		var logEl = E('pre', { 'id': 'oc-log', 'style': 'max-height:260px;overflow:auto;font-size:12px' }, '');

		this.refresh = function() {
			callStatus().then(function(s) {
				if (!s) return;
				document.getElementById('oc-phase').textContent = '阶段：' + badge(s.phase);
				document.getElementById('oc-current').textContent = '本机版本：' + (s.current || '—');
				document.getElementById('oc-version').textContent = '目标版本：' + (s.version || '—');
				document.getElementById('oc-detail').textContent = '说明：' + (s.detail || '—');
			});
			callLogTail(40).then(function(r) {
				if (r && r.lines) document.getElementById('oc-log').textContent = r.lines;
			});
		};

		poll.add(this.refresh.bind(this), 3);

		return E('div', {}, [
			E('h2', {}, 'OneCloud 在线升级'),
			E('p', { 'class': 'cbi-section-descr' },
				'本应用只针对 OneCloud；固件源由你填写，不写死仓库。写入由设备自带的 upgrade 脚本执行。'),
			E('p', { 'class': 'alert-message ' + (cfg.dry_run === '1' ? 'warning' : 'danger') },
				cfg.dry_run === '1'
					? '当前为演练模式：升级只做预检与阶段模拟，不会写盘、不会重启。'
					: '当前为实盘模式：点“升级”会真正写入并重启设备，请确认已做好备份。'),
			this.statusEl,
			actions,
			form,
			backupSection,
			E('h3', {}, '日志'),
			logEl
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
