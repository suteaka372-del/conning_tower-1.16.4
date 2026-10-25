// node --test tool/air_sim/abyssal.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';

import { abyssalTable, buildAbyssalJson, readShipData } from './abyssal.mjs';

const sample = `var SHIPDATA = {
	1: { name: 'Mutsuki', AA: 9, SLOTS: [0, 0] },
	1528: { name: 'CV Wo-Class Flagship', nameJP: '空母ヲ級flagship', AA: 50, SLOTS: [32, 32, 32], EQUIPS: [1520, 1517, 1524],
		HP: 96, FP: 25, TP: 0, AR: 80, ASW: 0, nightattack: 1 },
	1530: { name: 'SS Ka-Class', AA: 0, SLOTS: [0, 0], HP: 13, FP: 0, TP: 12, AR: 4, ASW: 0, canOpTorp: function() { return true; } },
	1653: { nameJP: '集積地棲姫', installtype: 3, HP: 600, FP: 70, TP: 88, AR: 100, AA: 50, SLOTS: [16, 16, 16, 0] },
	1753: { nameJP: '集積地夏姫', installtype: 3, HP: 690, AR: 129, SLOTS: [16, 16, 0, 0] },
	1999: { name: 'broken', SLOTS: [-1, 'x'] },
};`;

test('reads SHIPDATA from the script', () => {
  const data = readShipData(sample);
  assert.equal(data[1528].AA, 50);
});

test('keeps only abyssal ships: AA, plane counts, then stats for the damage simulator', () => {
  const table = abyssalTable(readShipData(sample));
  assert.deepEqual(Object.keys(table).sort(), ['1528', '1530', '1653', '1753', '1999']);
  // [対空, 搭載数, 耐久, 火力, 雷装, 装甲, 対潜, 陸上型, 印]
  assert.deepEqual(table[1528], [50, [32, 32, 32], 96, 25, 0, 80, 0, 0, 4]);
  assert.deepEqual(table[1530].slice(2), [13, 0, 12, 4, 0, 0, 0]);
  assert.deepEqual(table[1653].slice(7), [3, 2]); // 集積地補正あり
  assert.deepEqual(table[1753].slice(7), [3, 0]); // 集積地夏姫は集積地補正なし
  assert.deepEqual(table[1999], [0, [0, 0], 0, 0, 0, 0, 0, 0, 0]);
});

test('refuses data that looks broken', () => {
  assert.throws(() => buildAbyssalJson(sample), /too few/);
  let many = 'var SHIPDATA = {';
  for (let i = 1501; i < 1700; i++) many += `${i}: { AA: ${i % 7}, SLOTS: [${i % 3}] },`;
  many += '};';
  const json = buildAbyssalJson(many, new Date('2026-10-25T00:00:00Z'));
  assert.equal(json.updated, '2026-10-25');
  assert.equal(Object.keys(json.ships).length, 199);
});
