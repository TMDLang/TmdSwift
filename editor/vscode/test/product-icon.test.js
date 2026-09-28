const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');

test('VS Code product icon is the monochrome brace-and-note mark', () => {
  const icon = fs.readFileSync(path.join(root, 'media', 'tmd.svg'), 'utf8');
  const packageJson = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
  const extension = fs.readFileSync(path.join(root, 'extension.js'), 'utf8');

  assert.match(icon, /<svg[^>]+viewBox="0 0 64 64"/);
  assert.match(icon, /#000000/);
  assert.match(icon, /#ffffff/);
  assert.doesNotMatch(icon, /gradient|#58a6ff|#bc8cff|#2ea043/);
  assert.equal(packageJson.contributes.viewsContainers.activitybar[0].icon, './media/tmd.svg');
  assert.equal(packageJson.contributes.viewsContainers.panel[0].icon, './media/tmd.svg');
  assert.doesNotMatch(extension, /media', 'player\.svg/);
  assert.match(extension, /media', 'tmd\.svg/);
  assert.match(extension, /class="hum-brand-icon"/);
});
