#!/usr/bin/env python3
"""只读取证实机升级链：status / help / 版本文件 / 脚本哈希 / 空间。

约束：
- 只执行只读命令（--status / --help / cat / ls / sha256sum / df），不写盘、不下载、不升级。
- auth_none（dropbear 允许 root 空口令），不读取、不保存任何密码。
- 每条命令单独记录 rc、耗时、原始输出，落 evidence/status-<ts>/。
"""
from __future__ import annotations

import json
import os
import sys
import time
from datetime import datetime

import paramiko

HOST = os.environ.get("OC_HOST")
if not HOST:
    raise SystemExit("请通过 OC_HOST=<设备地址> 指定目标设备")
PORT = int(os.environ.get("OC_PORT", "22"))
USER = os.environ.get("OC_USER", "root")

# 只读命令白名单：任何新增命令必须只能读，不能改设备
COMMANDS = [
    ("status", "upgrade --status"),
    ("help", "upgrade --help"),
    ("version_file", "cat /etc/oc-version 2>/dev/null"),
    ("repo_file", "cat /etc/oc-repo 2>/dev/null"),
    ("release", "cat /etc/openwrt_release 2>/dev/null"),
    ("script_hash", "sha256sum /usr/lib/oc-upgrade.sh /usr/bin/upgrade 2>/dev/null; ls -l /usr/lib/oc-upgrade.sh /usr/bin/upgrade"),
    ("space", "df -k / /opt /tmp 2>/dev/null"),
    ("backups", "ls -dt /opt/upgrade-backup-* 2>/dev/null | head -5"),
    ("cache", "ls -l /opt/rfs-upgrade 2>/dev/null"),
]


def run(channel_holder, cmd: str, timeout: int = 30) -> dict:
    t0 = time.time()
    ch = channel_holder.open_session()
    ch.settimeout(timeout)
    ch.exec_command(cmd)
    buf = b""
    deadline = time.time() + timeout
    while True:
        if ch.recv_ready():
            buf += ch.recv(65536)
        if ch.exit_status_ready() and not ch.recv_ready():
            break
        if time.time() > deadline:
            break
        time.sleep(0.05)
    while ch.recv_ready():
        buf += ch.recv(65536)
    rc = ch.recv_exit_status()
    ch.close()
    return {
        "cmd": cmd,
        "rc": rc,
        "duration_ms": int((time.time() - t0) * 1000),
        "stdout": buf.decode("utf-8", "replace"),
    }


def main() -> int:
    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ts = datetime.now().strftime("%Y%m%dT%H%M%S")
    outdir = os.path.join(base, "evidence", f"status-{ts}")
    os.makedirs(outdir, exist_ok=True)

    transport = paramiko.Transport((HOST, PORT))
    transport.start_client(timeout=15)
    transport.auth_none(USER)

    results = []
    for name, cmd in COMMANDS:
        r = run(transport, cmd)
        r["name"] = name
        results.append(r)
        print(f"[{name}] rc={r['rc']} {r['duration_ms']}ms")
        print(r["stdout"])
        print("-" * 60)

    transport.close()

    payload = {
        "host": HOST,
        "port": PORT,
        "collected_at": ts,
        "readonly": True,
        "results": results,
    }
    with open(os.path.join(outdir, "status.json"), "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    print(f"saved: {outdir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
