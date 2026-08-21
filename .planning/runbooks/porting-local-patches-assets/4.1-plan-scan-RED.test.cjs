'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const planScan = require('/Users/rerganian/Documents/git/personal/gsd-core/gsd-core/bin/lib/plan-scan.cjs');

function writeFile(dir, relName, content) {
  const full = path.join(dir, relName);
  fs.mkdirSync(path.dirname(full), { recursive: true });
  fs.writeFileSync(full, content);
}
function planBody() { return '---\nstatus: done\n---\nbody\n'; }

test('row11b: -PLAN-CHECK.md present -> NOT counted (mirrors row11 -PLAN-REVIEW.md)', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'plan-check-red-'));
  try {
    writeFile(dir, '01-PLAN.md', planBody());
    writeFile(dir, '01-PLAN-CHECK.md', planBody());
    const scan = planScan(dir);
    assert.strictEqual(scan.planCount, 1);
    assert.ok(!scan.planFiles.includes('01-PLAN-CHECK.md'));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
