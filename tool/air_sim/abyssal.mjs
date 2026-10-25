// 深海棲艦の素の対空値と搭載数を、KC3Kai/kancolle-replay の kcSHIPDATA.js から取り出して JSON にする。
// (kancolle-replay: MIT License, Copyright (c) 2016 fourinone41。https://github.com/KC3Kai/kancolle-replay)
// アプリの「シミュ」タブ (制空権) が data ブランチの airsim/abyssal.json を取りに行く。
// 使い方: node tool/air_sim/abyssal.mjs kcSHIPDATA.js out/airsim/abyssal.json
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

/** kcSHIPDATA.js の中身から SHIPDATA を取り出す (ファイルはデータの代入だけ) */
export function readShipData(source) {
  const context = {};
  vm.createContext(context);
  vm.runInContext(source.replace(/^\s*var\s+SHIPDATA\s*=/m, 'SHIPDATA ='), context, { timeout: 10000 });
  if (!context.SHIPDATA || typeof context.SHIPDATA !== 'object') throw new Error('SHIPDATA not found');
  return context.SHIPDATA;
}

/** 深海棲艦 (ID 1501 以上) だけを { id: [素の対空, [搭載数...]] } にする */
export function abyssalTable(shipData) {
  const ships = {};
  for (const [key, ship] of Object.entries(shipData)) {
    const id = Number(key);
    if (!Number.isInteger(id) || id <= 1500 || !ship) continue;
    const aa = Number(ship.AA);
    // vm の中で作られた配列なので、Array.from でこちらの配列にする
    const slots = Array.isArray(ship.SLOTS) ? Array.from(ship.SLOTS, (n) => Math.max(0, Number(n) || 0)) : [];
    ships[id] = [Number.isFinite(aa) ? aa : 0, slots];
  }
  return ships;
}

export function buildAbyssalJson(source, now = new Date()) {
  const ships = abyssalTable(readShipData(source));
  const count = Object.keys(ships).length;
  if (count < 100) throw new Error(`too few abyssal ships (${count})`);
  return {
    v: 1,
    updated: now.toISOString().slice(0, 10),
    source: 'KC3Kai/kancolle-replay kcSHIPDATA.js (MIT License)',
    ships,
  };
}

if (path.basename(process.argv[1] ?? '') === 'abyssal.mjs') {
  const [input, output] = process.argv.slice(2);
  if (!input || !output) {
    console.error('usage: node abyssal.mjs kcSHIPDATA.js out/airsim/abyssal.json');
    process.exit(2);
  }
  const json = buildAbyssalJson(fs.readFileSync(input, 'utf8'));
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, JSON.stringify(json));
  console.log(`abyssal ships: ${Object.keys(json.ships).length}`);
}
