// node --test tool/dev_stats
import assert from 'node:assert/strict';
import test from 'node:test';

import { aggregate, mergeRows, monthOf, validRecord } from './aggregate.mjs';

// ObjectId の先頭は作られた時刻 (秒)
const id = (iso) => Math.floor(Date.parse(iso) / 1000).toString(16).padStart(8, '0') + '0'.repeat(16);

test('month comes from the record id', () => {
  assert.equal(monthOf(id('2026-10-01T00:00:24Z')), '2026-10');
  assert.equal(monthOf(id('2026-09-30T23:59:59Z')), '2026-09');
});

test('broken records are skipped', () => {
  const ok = { _id: id('2026-10-02T00:00:00Z'), items: [10, 30, 90, 10], secretary: 400, successful: true, itemId: 46 };
  assert.ok(validRecord(ok));
  assert.ok(validRecord({ ...ok, successful: false, itemId: -1 }));
  assert.ok(!validRecord({ ...ok, items: [10, 30, 90] }));
  assert.ok(!validRecord({ ...ok, items: [10, 30, 90, 301] }));
  assert.ok(!validRecord({ ...ok, items: [5, 30, 90, 10] }));
  assert.ok(!validRecord({ ...ok, secretary: 0 }));
  assert.ok(!validRecord({ ...ok, itemId: -1 })); // 成功なのに装備が無い
});

test('counts tries and items per recipe and secretary, per month', () => {
  const r = (iso, items, secretary, itemId) =>
    ({ _id: id(iso), items, secretary, successful: itemId > 0, itemId: itemId > 0 ? itemId : -1 });
  const { months, skipped } = aggregate([
    r('2026-10-02T00:00:00Z', [10, 30, 90, 10], 400, 46),
    r('2026-10-03T00:00:00Z', [10, 30, 90, 10], 400, 46),
    r('2026-10-04T00:00:00Z', [10, 30, 90, 10], 400, 0),
    r('2026-10-05T00:00:00Z', [10, 30, 90, 10], 401, 47),
    r('2026-09-30T00:00:00Z', [10, 30, 90, 10], 400, 46),
    { _id: id('2026-10-05T00:00:00Z'), items: [1, 2, 3, 4], secretary: 1, successful: false },
  ]);
  assert.equal(skipped, 1);
  assert.deepEqual([...months.keys()].sort(), ['2026-09', '2026-10']);
  const oct = months.get('2026-10');
  assert.equal(oct.get('10,30,90,10,400').tries, 3);
  assert.deepEqual([...oct.get('10,30,90,10,400').hits], [[46, 2]]);
  assert.equal(oct.get('10,30,90,10,401').tries, 1);
});

test('months are added together', () => {
  const merged = mergeRows([
    [[10, 30, 90, 10, 400, 3, [46, 2]], [10, 10, 10, 10, 1, 5, []]],
    [[10, 30, 90, 10, 400, 7, [46, 1, 47, 2]]],
  ]);
  assert.deepEqual(merged, [
    [10, 10, 10, 10, 1, 5, []],
    [10, 30, 90, 10, 400, 10, [46, 3, 47, 2]],
  ]);
});
