#!/usr/bin/env python3
"""M1 第 3 步：把应用文件装到系统路径（全部为新增文件），并验证 ubus 与静态资源。

安全边界：
- 部署前逐路径检查，任一目标已存在就中止（不覆盖任何既有文件）。
- 不 enable init.d、不重启设备、不调用 upgrade。
- 只重启 rpcd（让新对象注册），这一步会短暂影响 LuCI 的 RPC。
"""
from __future__ import annotations

import os
import sys
import time

import paramiko

HOST = os.environ.get("OC_HOST")
if not HOST:
    raise SystemExit("请通过 OC_HOST=<设备地址> 指定目标设备")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKG = os.path.join(ROOT, "package")

FILES = [
    (f"{PKG}/fwupgrade-core/files/usr/libexec/fwupgrade/lib.sh", "/usr/libexec/fwupgrade/lib.sh", 0o644),
    (f"{PKG}/fwupgrade-core/files/usr/libexec/fwupgrade/manifest.uc", "/usr/libexec/fwupgrade/manifest.uc", 0o644),
    (f"{PKG}/fwupgrade-core/files/usr/libexec/fwupgrade/worker.sh", "/usr/libexec/fwupgrade/worker.sh", 0o755),
    (f"{PKG}/fwupgrade-core/files/usr/libexec/fwupgrade/fwupgradectl", "/usr/libexec/fwupgrade/fwupgradectl", 0o755),
    (f"{PKG}/fwupgrade-core/files/etc/config/onecloud-upgrade", "/etc/config/onecloud-upgrade", 0o600),
    (f"{PKG}/fwupgrade-core/files/etc/init.d/fwupgrade", "/etc/init.d/fwupgrade", 0o755),
    (f"{PKG}/fwupgrade-provider-github/files/usr/libexec/fwupgrade/ghrelease.uc", "/usr/libexec/fwupgrade/ghrelease.uc", 0o644),
    (f"{PKG}/fwupgrade-provider-github/files/usr/libexec/fwupgrade/providers/github.sh", "/usr/libexec/fwupgrade/providers/github.sh", 0o755),
    (f"{PKG}/fwupgrade-provider-github/files/usr/libexec/fwupgrade/providers/static-https.sh", "/usr/libexec/fwupgrade/providers/static-https.sh", 0o755),
    (f"{PKG}/fwupgrade-provider-github/files/usr/libexec/fwupgrade/providers/local-file.sh", "/usr/libexec/fwupgrade/providers/local-file.sh", 0o755),
    (f"{PKG}/fwupgrade-flasher-onecloud/files/usr/libexec/fwupgrade/flashers/onecloud.sh", "/usr/libexec/fwupgrade/flashers/onecloud.sh", 0o755),
    (f"{PKG}/fwupgrade-flasher-dryrun/files/usr/libexec/fwupgrade/flashers/dryrun.sh", "/usr/libexec/fwupgrade/flashers/dryrun.sh", 0o755),
    (f"{PKG}/luci-app-onecloud-upgrade/root/usr/libexec/rpcd/luci.onecloud-upgrade", "/usr/libexec/rpcd/luci.onecloud-upgrade", 0o755),
    (f"{PKG}/luci-app-onecloud-upgrade/root/usr/share/rpcd/acl.d/luci-app-onecloud-upgrade.json", "/usr/share/rpcd/acl.d/luci-app-onecloud-upgrade.json", 0o644),
    (f"{PKG}/luci-app-onecloud-upgrade/root/usr/share/luci/menu.d/luci-app-onecloud-upgrade.json", "/usr/share/luci/menu.d/luci-app-onecloud-upgrade.json", 0o644),
    (f"{PKG}/luci-app-onecloud-upgrade/htdocs/luci-static/resources/view/onecloud_upgrade/overview.js", "/www/luci-static/resources/view/onecloud_upgrade/overview.js", 0o644),
]


def run(t, cmd, timeout=60):
    ch = t.open_session()
    ch.settimeout(timeout)
    ch.exec_command(cmd)
    out = b""
    end = time.time() + timeout
    while True:
        if ch.recv_ready():
            out += ch.recv(65536)
        if ch.exit_status_ready() and not ch.recv_ready():
            break
        if time.time() > end:
            break
        time.sleep(0.05)
    while ch.recv_ready():
        out += ch.recv(65536)
    rc = ch.recv_exit_status()
    ch.close()
    return rc, out.decode("utf-8", "replace")


def mkdirs(s, path):
    cur = ""
    for p in path.strip("/").split("/"):
        cur += "/" + p
        try:
            s.stat(cur)
        except IOError:
            s.mkdir(cur)


def main() -> int:
    t = paramiko.Transport((HOST, 22))
    t.start_client(timeout=15)
    t.auth_none("root")
    s = paramiko.SFTPClient.from_transport(t)

    print("== 部署前检查：目标路径不得已存在 ==")
    for _, remote, _ in FILES:
        rc2, out = run(t, f"[ -e {remote} ] && echo yes || echo no", 15)
        if out.strip() == "yes":
            if remote == "/etc/config/onecloud-upgrade":
                print(f"  {remote} 已存在（本应用自己的配置，保留不覆盖）")
                continue
            print(f"中止：{remote} 已存在，拒绝覆盖")
            return 2
    print("检查通过，继续")

    print("== 上传 ==")
    for local, remote, mode in FILES:
        rc2, out = run(t, f"[ -e {remote} ] && echo yes || echo no", 15)
        if out.strip() == "yes" and remote == "/etc/config/onecloud-upgrade":
            continue
        mkdirs(s, os.path.dirname(remote))
        s.put(local, remote)
        s.chmod(remote, mode)
        print(f"  {remote}")

    print("== 重启 rpcd 注册新对象 ==")
    rc, out = run(t, "/etc/init.d/rpcd restart; sleep 2; ubus list | grep -i onecloud", 40)
    print(out, f"rc={rc}")
    if "onecloud" not in out:
        print("rpcd 未注册对象，继续收集日志")
        print(run(t, "logread | tail -n 20")[1])
        return 3

    print("== ubus 调用 status ==")
    rc, out = run(t, "ubus call luci.onecloud-upgrade status", 30)
    print(out, f"rc={rc}")

    print("== 生成一次真实检测（写入 /opt/fwupgrade）==")
    rc, out = run(t, "/usr/libexec/fwupgrade/fwupgradectl check 2>&1", 120)
    print(out, f"rc={rc}")

    print("== ubus status 复查 ==")
    print(run(t, "ubus call luci.onecloud-upgrade status")[1])

    print("== 静态资源与菜单 ==")
    rc, out = run(t, "uclient-fetch -q -O /dev/null http://127.0.0.1:8080/luci-static/resources/view/onecloud_upgrade/overview.js && echo JS_OK || echo JS_FAIL", 30)
    print(out)
    print(run(t, "ls -l /usr/share/luci/menu.d/luci-app-onecloud-upgrade.json /www/luci-static/resources/view/onecloud_upgrade/overview.js")[1])

    print("== 清 LuCI 菜单缓存（下次访问重建）==")
    run(t, "rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null; echo done", 20)

    print("== 卸载清单（回滚用）==")
    for _, remote, _ in FILES:
        print(remote)
    t.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
