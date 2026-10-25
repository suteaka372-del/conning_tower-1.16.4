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

/** 印 (ダメージシミュレーター用) */
export const FLAG_PT = 1; // PT小鬼群
export const FLAG_SUPPLY_DEPOT = 2; // 集積地補正 (キャップ後) を受ける
export const FLAG_NIGHT_ATTACK = 4; // 夜戦で攻撃できる空母

const num = (v) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};

/**
 * 深海棲艦 (ID 1501 以上) だけを
 * { id: [素の対空, [搭載数...], 耐久, 火力, 雷装, 装甲, 対潜, 陸上型の種類, 印] } にする。
 * 陸上型の種類: 0 = 水上艦、1 = ソフトスキン型、2 = 砲台小鬼 (トーチカ型)、3 = 集積地型、4 = 離島棲姫 (ハードスキン型)、5 = 北端上陸姫、6 = 港湾夏姫
 */
export function abyssalTable(shipData) {
  const ships = {};
  for (const [key, ship] of Object.entries(shipData)) {
    const id = Number(key);
    if (!Number.isInteger(id) || id <= 1500 || !ship) continue;
    // vm の中で作られた配列なので、Array.from でこちらの配列にする
    const slots = Array.isArray(ship.SLOTS) ? Array.from(ship.SLOTS, (n) => Math.max(0, Number(n) || 0)) : [];
    const install = num(ship.installtype);
    let flags = 0;
    if (ship.isPT) flags |= FLAG_PT;
    // 集積地夏姫は集積地補正を受けない。集積地棲姫III バカンスmode は水上艦だが集積地補正を受ける
    if ((install === 3 && !String(ship.nameJP ?? '').includes('夏姫')) || ship.isSupplyDepot) flags |= FLAG_SUPPLY_DEPOT;
    if (num(ship.nightattack) > 0) flags |= FLAG_NIGHT_ATTACK;
    ships[id] = [num(ship.AA), slots, num(ship.HP), num(ship.FP), num(ship.TP), num(ship.AR), num(ship.ASW), install, flags];
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
