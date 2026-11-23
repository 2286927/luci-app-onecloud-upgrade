#!/usr/bin/ucode
// GitHub Release API JSON -> KEY=VALUE
import { readfile } from 'fs';

let raw = readfile('/dev/stdin');
if (raw == null) { printf('ERROR=empty\n'); exit(1); }

let r;
try { r = json(raw); } catch (e) { printf('ERROR=invalid_json\n'); exit(1); }
if (type(r) != 'object') { printf('ERROR=not_release\n'); exit(1); }

function put(k, v) {
    printf('%s=', k);
    if (v != null) printf('%s', v);
    printf('\n');
}

put('TAG', r.tag_name);
put('NAME', r.name);
put('PUBLISHED_AT', r.published_at);
put('PRERELEASE', r.prerelease);
put('DRAFT', r.draft);
put('BODY', r.body ? 1 : 0);

let n = 0;
if (type(r.assets) == 'array') n = length(r.assets);
put('ASSET_COUNT', n);
for (let i = 0; i < n; i++) {
    let a = r.assets[i];
    if (type(a) != 'object') continue;
    put(`ASSET_${i}_NAME`, a.name);
    put(`ASSET_${i}_SIZE`, a.size);
    put(`ASSET_${i}_DIGEST`, a.digest);
    put(`ASSET_${i}_URL`, a.browser_download_url);
}
