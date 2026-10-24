// 装備開発の統計を集計する (GitHub Actions の Development stats ワークフローから毎日呼ぶ)。
//
//   node tool/dev_stats/aggregate.mjs <createitemrecords.gz> <出力フォルダ>
//
// 元データ: poi の公開データ https://api.poi.moe/dump/createitemrecords.gz
// (mongodump --archive --gzip 形式。1回の開発ごとに 資材4種・秘書艦・成功・出た装備。毎月リセットされる)
// 出力:
//   <出力フォルダ>/YYYY-MM.json … 月ごとの集計 (元データがリセットされても残すため、前回の分は消さない)
//   <出力フォルダ>/latest.json  … 直近3か月分を合わせたもの (アプリはこれを取りに行く)
// 形式: rows = [燃料, 弾薬, 鋼材, ボーキ, 秘書艦の艦ID, 試行回数, [装備ID, 出た回数, 装備ID, 出た回数, ...]]

import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const MONTHS_IN_LATEST = 3;
const SOURCE = 'poi (https://api.poi.moe/dump/createitemrecords.gz)';

// ---- mongodump archive (BSON) を読む ----

function readDoc(b, o) {
  const len = b.readInt32LE(o);
  const end = o + len - 1;
  let p = o + 4;
  const d = {};
  while (p < end) {
    const t = b[p++];
    let q = p;
    while (b[q]) q++;
    const k = b.toString('utf8', p, q);
    p = q + 1;
    let v;
    switch (t) {
      case 0x01: v = b.readDoubleLE(p); p += 8; break;
      case 0x02: { const l = b.readInt32LE(p); v = b.toString('utf8', p + 4, p + 4 + l - 1); p += 4 + l; break; }
      case 0x03:
      case 0x04: { const l = b.readInt32LE(p); v = readDoc(b, p); if (t === 0x04) v = Object.values(v); p += l; break; }
      case 0x05: { const l = b.readInt32LE(p); v = null; p += 5 + l; break; }
      case 0x07: v = b.toString('hex', p, p + 12); p += 12; break;
      case 0x08: v = !!b[p]; p += 1; break;
      case 0x09: v = Number(b.readBigInt64LE(p)); p += 8; break;
      case 0x0a: v = null; break;
      case 0x10: v = b.readInt32LE(p); p += 4; break;
      case 0x11:
      case 0x12: v = Number(b.readBigInt64LE(p)); p += 8; break;
      default: throw new Error(`unknown BSON type ${t} at ${p}`);
    }
    d[k] = v;
  }
  return d;
}

/** archive の中の開発記録を1件ずつ返す (先頭の説明や区切りは飛ばす) */
function* records(buffer) {
  const b = zlib.gunzipSync(buffer);
  if (b.readUInt32LE(0) !== 0x8199e26d) throw new Error('not a mongodump archive');
  let o = 4;
  let first = true;
  while (o + 4 <= b.length) {
    const len = b.readInt32LE(o);
    if (len === -1) { o += 4; continue; } // 区切り
    const d = readDoc(b, o);
    o += len;
    if (first) { first = false; continue; } // archive の説明
    if ('db' in d && 'collection' in d) continue; // コレクションの説明・ブロックの見出し
    yield d;
  }
}

// ---- 集計 ----

const isResource = (n) => Number.isInteger(n) && n >= 10 && n <= 300;

/** 正しい形の記録か */
export function validRecord(r) {
  return Array.isArray(r.items) && r.items.length === 4 && r.items.every(isResource) &&
    Number.isInteger(r.secretary) && r.secretary > 0 && typeof r.successful === 'boolean' &&
    (!r.successful || (Number.isInteger(r.itemId) && r.itemId > 0));
}

/** ObjectId の先頭4バイトは作られた時刻 (秒) */
export function monthOf(objectId) {
  const time = new Date(parseInt(objectId.slice(0, 8), 16) * 1000);
  return `${time.getUTCFullYear()}-${String(time.getUTCMonth() + 1).padStart(2, '0')}`;
}

/** レシピ×秘書艦ごとに数える。返り値: Map<月, Map<key, {tries, hits: Map<装備ID, 回数>}>> */
export function aggregate(recordIterable) {
  const months = new Map();
  let skipped = 0;
  for (const r of recordIterable) {
    if (!validRecord(r) || typeof r._id !== 'string') { skipped++; continue; }
    const month = monthOf(r._id);
    let table = months.get(month);
    if (!table) months.set(month, (table = new Map()));
    const key = `${r.items.join(',')},${r.secretary}`;
    let e = table.get(key);
    if (!e) table.set(key, (e = { tries: 0, hits: new Map() }));
    e.tries++;
    if (r.successful) e.hits.set(r.itemId, (e.hits.get(r.itemId) ?? 0) + 1);
  }
  return { months, skipped };
}

function toRows(table) {
  const rows = [];
  for (const [key, e] of table) {
    const hits = [];
    for (const [item, count] of [...e.hits].sort((a, b) => a[0] - b[0])) hits.push(item, count);
    rows.push([...key.split(',').map(Number), e.tries, hits]);
  }
  rows.sort((a, b) => { for (let i = 0; i < 5; i++) if (a[i] !== b[i]) return a[i] - b[i]; return 0; });
  return rows;
}

const totalTries = (rows) => rows.reduce((sum, r) => sum + r[5], 0);

/** 月ごとの表を合わせる */
export function mergeRows(rowLists) {
  const table = new Map();
  for (const rows of rowLists) {
    for (const [f, a, s, b, secretary, tries, hits] of rows) {
      const key = `${f},${a},${s},${b},${secretary}`;
      let e = table.get(key);
      if (!e) table.set(key, (e = { tries: 0, hits: new Map() }));
      e.tries += tries;
      for (let i = 0; i < hits.length; i += 2) e.hits.set(hits[i], (e.hits.get(hits[i]) ?? 0) + hits[i + 1]);
    }
  }
  return toRows(table);
}

function main() {
  const [dumpPath, outDir] = process.argv.slice(2);
  if (!dumpPath || !outDir) {
    console.error('usage: node aggregate.mjs <createitemrecords.gz> <outDir>');
    process.exit(2);
  }
  fs.mkdirSync(outDir, { recursive: true });
  const { months, skipped } = aggregate(records(fs.readFileSync(dumpPath)));
  const now = new Date().toISOString();

  for (const [month, table] of [...months].sort()) {
    const rows = toRows(table);
    const file = path.join(outDir, `${month}.json`);
    // 元データは月の途中で増えるだけ。リセット後に前の月の残りが少しだけ来ても、前に保存した多い方を残す
    if (fs.existsSync(file)) {
      const old = JSON.parse(fs.readFileSync(file, 'utf8'));
      if (totalTries(old.rows) > totalTries(rows)) {
        console.log(`${month}: keep saved (${totalTries(old.rows)} > ${totalTries(rows)})`);
        continue;
      }
    }
    fs.writeFileSync(file, JSON.stringify({ v: 1, source: SOURCE, month, generated: now, rows }));
    console.log(`${month}: ${rows.length} rows, ${totalTries(rows)} tries`);
  }

  const monthFiles = fs.readdirSync(outDir).filter((f) => /^\d{4}-\d{2}\.json$/.test(f)).sort().slice(-MONTHS_IN_LATEST);
  if (monthFiles.length === 0) throw new Error('no data');
  const rowLists = monthFiles.map((f) => JSON.parse(fs.readFileSync(path.join(outDir, f), 'utf8')).rows);
  const rows = mergeRows(rowLists);
  const latest = { v: 1, source: SOURCE, months: monthFiles.map((f) => f.slice(0, 7)), generated: now, rows };
  fs.writeFileSync(path.join(outDir, 'latest.json'), JSON.stringify(latest));
  console.log(`latest: ${latest.months.join(', ')} ${rows.length} rows, ${totalTries(rows)} tries (skipped ${skipped})`);
}

// コマンドとして実行したときだけ動かす (テストから読み込んだときは動かさない)
if (path.basename(process.argv[1] ?? '') === 'aggregate.mjs') main();
