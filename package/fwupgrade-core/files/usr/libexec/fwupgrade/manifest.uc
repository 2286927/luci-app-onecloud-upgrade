#!/usr/bin/ucode
// manifest.json -> KEY=VALUE（供 ash 读取）
// 只做解析与扁平化，不做任何判断；判断在 shell 侧，便于单测。
import { readfile } from 'fs';

let raw = readfile('/dev/stdin');
if (raw == null) {
    printf('ERROR=empty\n');
    exit(1);
}

let m;
try {
    m = json(raw);
} catch (e) {
    printf('ERROR=invalid_json\n');
    exit(1);
}

if (type(m) != 'object') {
    printf('ERROR=not_object\n');
    exit(1);
}

function put(k, v) {
    printf('%s=', k);
    if (v != null)
        printf('%s', v);
    printf('\n');
}

put('SCHEMA', m.schema);
put('CHANNEL', m.channel);
put('GENERATED_AT', m.generated_at);

let r = m.release;
if (type(r) == 'object') {
    put('VERSION', r.version);
    put('BUILD_TS', r.build_ts);
    put('NOTES_URL', r.notes_url);
}

put('MIN_FROM', m.min_from);

let tcount = 0;
if (type(m.targets) == 'array')
    tcount = length(m.targets);
put('TARGET_COUNT', tcount);
for (let i = 0; i < tcount; i++) {
    let t = m.targets[i];
    if (type(t) != 'object')
        continue;
    put(`TARGET_${i}_TARGET`, t.target);
    if (type(t.boards) == 'array') {
        let b = '';
        for (let j = 0; j < length(t.boards); j++) {
            if (j > 0) b += ',';
            b += t.boards[j];
        }
        put(`TARGET_${i}_BOARDS`, b);
    }
    if (type(t.compatible) == 'array') {
        let c = '';
        for (let j = 0; j < length(t.compatible); j++) {
            if (j > 0) c += ',';
            c += t.compatible[j];
        }
        put(`TARGET_${i}_COMPAT`, c);
    }
}

let acount = 0;
if (type(m.assets) == 'array')
    acount = length(m.assets);
put('ASSET_COUNT', acount);
for (let i = 0; i < acount; i++) {
    let a = m.assets[i];
    if (type(a) != 'object')
        continue;
    put(`ASSET_${i}_KIND`, a.kind);
    put(`ASSET_${i}_URL`, a.url);
    put(`ASSET_${i}_SIZE`, a.size);
    put(`ASSET_${i}_SHA256`, a.sha256);
}

let f = m.flasher;
if (type(f) == 'object') {
    put('FLASHER_TYPE', f.type);
    put('FLASHER_ABI', f.abi);
    put('FLASHER_ROLLBACK', f.rollback);
    if (type(f.keep_paths) == 'array') {
        let k = '';
        for (let i = 0; i < length(f.keep_paths); i++) {
            if (i > 0) k += ',';
            k += f.keep_paths[i];
        }
        put('FLASHER_KEEP', k);
    }
}

if (type(m.rollback_bundle) == 'object') {
    put('RB_URL', m.rollback_bundle.url);
    put('RB_SHA256', m.rollback_bundle.sha256);
}

if (type(m.signature) == 'object') {
    put('SIGNATURE_ALG', m.signature.alg);
    put('SIGNATURE_KEY_ID', m.signature.key_id);
}
