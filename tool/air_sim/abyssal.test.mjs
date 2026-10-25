// node --test tool/air_sim/abyssal.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';

import { abyssalTable, buildAbyssalJson, readShipData } from './abyssal.mjs';

const sample = `var SHIPDATA = {
	1: { name: 'Mutsuki', AA: 9, SLOTS: [0, 0] },
	1528: { name: 'CV Wo-Class Flagship', nameJP: '空母ヲ級flagship', AA: 50, SLOTS: [32, 32, 32], EQUIPS: [1520, 1517, 1524] },
	1530: { name: 'SS Ka-Class', AA: 0, SLOTS: [0, 0] },
	1999: { name: 'broken', SLOTS: [-1, 'x'] },
};`;

test('reads SHIPDATA from the script', () => {
  const data = readShipData(sample);
  assert.equal(data[1528].AA, 50);
});

test('keeps only abyssal ships with AA and plane counts', () => {
  const table = abyssalTable(readShipData(sample));
  assert.deepEqual(Object.keys(table).sort(), ['1528', '1530', '1999']);
  assert.deepEqual(table[1528], [50, [32, 32, 32]]);
  assert.deepEqual(table[1999], [0, [0, 0]]);
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
