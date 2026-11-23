#!/usr/bin/env python3
"""按固件 Release 生成 manifest.json（供 usign 签名后随 Release 发布）。

用法：
  python3 tools/gen_manifest.py --repo 2286927/onecloud-25.12-onlineFirmware -o manifest.json

依赖：仅标准库；GitHub API 匿名可读 public 仓，私有仓需 GITHUB_TOKEN。
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import urllib.request

DEFAULT_ROOTFS_SUFFIX = "rootfs.tar.gz"
DEFAULT_BOOT = "onecloud-boot.tar.gz"


def api(url: str) -> dict:
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "gen-manifest"})
    tok = os.environ.get("GITHUB_TOKEN")
    if tok:
        req.add_header("Authorization", "Bearer " + tok)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def norm_version(tag: str) -> str:
    m = re.search(r"(\d{2}\.\d{2}\.\d{2}_\d{2}\.\d{2}\.\d{2})", tag)
    return m.group(1) if m else tag


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True, help="owner/name")
    ap.add_argument("--release", default="latest", help="latest 或 tag 名")
    ap.add_argument("--target", default="amlogic/meson8b")
    ap.add_argument("--board", default="onecloud")
    ap.add_argument("--compatible", default="thunder,onecloud")
    ap.add_argument("--rootfs-name", default=None, help="默认选第一个 *rootfs.tar.gz（排除 targz-rootfs）")
    ap.add_argument("--boot-name", default=DEFAULT_BOOT)
    ap.add_argument("--flasher", default="onecloud-emmc")
    ap.add_argument("--abi", type=int, default=1)
    ap.add_argument("-o", "--output", default="manifest.json")
    args = ap.parse_args()

    rel = api(f"https://api.github.com/repos/{args.repo}/releases/{args.release}")
    assets = {a["name"]: a for a in rel.get("assets", [])}

    rootfs_name = args.rootfs_name
    if not rootfs_name:
        cands = [n for n in assets if n.endswith(DEFAULT_ROOTFS_SUFFIX) and "targz" not in n]
        if not cands:
            print("找不到 rootfs 资产（*.rootfs.tar.gz，排除 targz）", file=sys.stderr)
            return 2
        rootfs_name = cands[0]
    if args.boot_name not in assets:
        print(f"找不到 boot 资产：{args.boot_name}", file=sys.stderr)
        return 2

    def ent(name: str, kind: str) -> dict:
        a = assets[name]
        digest = (a.get("digest") or "").split(":")[-1]
        if len(digest) != 64:
            print(f"资产 {name} 缺少 sha256 digest，GitHub API 未返回", file=sys.stderr)
            sys.exit(2)
        return {"kind": kind, "url": "./" + name, "size": a["size"], "sha256": digest}

    ts = int(dt.datetime.fromisoformat(rel["published_at"].replace("Z", "+00:00")).timestamp())
    manifest = {
        "schema": 1,
        "channel": "stable",
        "generated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "release": {"version": norm_version(rel["tag_name"]), "build_ts": ts},
        "targets": [{
            "target": args.target,
            "boards": [args.board],
            "compatible": args.compatible.split(","),
        }],
        "assets": [ent(rootfs_name, "rootfs"), ent(args.boot_name, "boot")],
        "flasher": {
            "type": args.flasher,
            "abi": args.abi,
            "keep_paths": ["/etc/config", "/etc/shadow", "/etc/dropbear", "/etc/uhttpd.crt", "/etc/uhttpd.key", "/opt", "/root"],
            "rollback": "config-only",
        },
    }
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"written {args.output}: version={manifest['release']['version']} assets={[a['kind'] for a in manifest['assets']]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
