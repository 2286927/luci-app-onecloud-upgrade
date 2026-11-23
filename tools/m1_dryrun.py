#!/usr/bin/env python3
"""M1 第 1 步：在设备上用 dry-run 后端跑通 check -> download -> apply 状态迁移。

只写 /tmp（测试根）与 /etc/config/onecloud-upgrade（本应用自己的配置），
不下载升级包、不调用 upgrade --reboot、不碰任何块设备。
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
CORE = os.path.join(ROOT, "package/fwupgrade-core/files")
PROV = os.path.join(ROOT, "package/fwupgrade-provider-github/files")
FLASH = os.path.join(ROOT, "package/fwupgrade-flasher-dryrun/files")
FIX = os.path.join(ROOT, "tests/fixtures/manifest.dryrun.json")


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


def main() -> int:
    t = paramiko.Transport((HOST, 22))
    t.start_client(timeout=15)
    t.auth_none("root")
    s = paramiko.SFTPClient.from_transport(t)

    def put(local, remote, mode=None):
        sftp_mkdirs(s, os.path.dirname(remote))
        s.put(local, remote)
        if mode:
            s.chmod(remote, mode)

    print("== 部署到 /tmp/fwu（不改系统路径）==")
    run(t, "rm -rf /tmp/fwu /tmp/fwuroot /tmp/fwu-src /tmp/fwu.lock; mkdir -p /tmp/fwu/providers /tmp/fwu/flashers /tmp/fwuroot /tmp/fwu-src")
    for name in ("lib.sh", "manifest.uc"):
        put(os.path.join(CORE, "usr/libexec/fwupgrade", name), f"/tmp/fwu/{name}")
    for name in ("fwupgradectl", "worker.sh"):
        put(os.path.join(CORE, "usr/libexec/fwupgrade", name), f"/tmp/fwu/{name}", 0o755)
    put(os.path.join(PROV, "usr/libexec/fwupgrade/providers/local-file.sh"), "/tmp/fwu/providers/local-file.sh", 0o755)
    put(os.path.join(PROV, "usr/libexec/fwupgrade/providers/github.sh"), "/tmp/fwu/providers/github.sh", 0o755)
    put(os.path.join(PROV, "usr/libexec/fwupgrade/ghrelease.uc"), "/tmp/fwu/ghrelease.uc")
    put(os.path.join(FLASH, "usr/libexec/fwupgrade/flashers/dryrun.sh"), "/tmp/fwu/flashers/dryrun.sh", 0o755)
    put(FIX, "/tmp/fwu-src/manifest.json")

    print("== 写本应用自己的配置（新增文件，不动其它配置）==")
    cfg_local = os.path.join(CORE, "etc/config/onecloud-upgrade")
    put(cfg_local, "/etc/config/onecloud-upgrade", 0o600)
    rc, out = run(t, "uci set onecloud-upgrade.main.provider='local-file'; "
                     "uci set onecloud-upgrade.main.base_url='/tmp/fwu-src'; "
                     "uci set onecloud-upgrade.main.channel='stable'; uci commit onecloud-upgrade; "
                     "uci show onecloud-upgrade")
    print(out)
    if rc != 0:
        return rc

    env = "export FWU_LIBDIR=/tmp/fwu FWU_ROOT=/tmp/fwuroot FWU_LOCK=/tmp/fwu.lock"

    print("== check ==")
    rc, out = run(t, f"{env}; sh /tmp/fwu/fwupgradectl check 2>&1", 90)
    print(out, f"\nrc={rc}")
    if rc != 0:
        return rc

    print("== download（dryrun：只记录，不下载）==")
    rc, out = run(t, f"{env}; sh /tmp/fwu/fwupgradectl download 2>&1", 60)
    print(out, f"\nrc={rc}")

    print("== apply（dryrun：会走预检与阶段模拟，不写盘）==")
    ver = ""
    for line in run(t, f"{env}; sh /tmp/fwu/fwupgradectl status --json")[1].splitlines():
        if '"version"' in line:
            ver = line.split('"version":"')[1].split('"')[0]
    print("目标版本:", ver)
    rc, out = run(t, f"{env}; sh /tmp/fwu/fwupgradectl apply --confirm '{ver}' 2>&1", 60)
    print(out, f"\nrc={rc}")

    print("== 等待 worker 完成，读状态 ==")
    time.sleep(8)
    rc, out = run(t, f"{env}; sh /tmp/fwu/fwupgradectl status --json; echo; tail -n 20 /tmp/fwuroot/journal.log")
    print(out, f"\nrc={rc}")

    print("== 清理 /tmp（配置保留，供第 2 步复用）==")
    run(t, "rm -rf /tmp/fwu /tmp/fwuroot /tmp/fwu-src /tmp/fwu.lock")
    t.close()
    return 0


def sftp_mkdirs(s, path):
    if not path or path == "/":
        return
    parts = path.strip("/").split("/")
    cur = ""
    for p in parts:
        cur += "/" + p
        try:
            s.stat(cur)
        except IOError:
            s.mkdir(cur)


if __name__ == "__main__":
    sys.exit(main())
