const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const cssPath = path.join(__dirname, '..', 'media', 'inspector.css');

test('tonality analysis cells can shrink and wrap long content', () => {
  const css = fs.readFileSync(cssPath, 'utf8');

  assert.match(css, /\.tonality-stat-box\s*\{[^}]*min-width:\s*0;/s);
  assert.match(css, /\.pitch-metric-row\s*\{[^}]*min-width:\s*0;/s);
  assert.match(css, /\.tonality-stat-box[^}]*overflow-wrap:\s*anywhere/s);
  assert.match(css, /\.pitch-metric-row[^}]*overflow-wrap:\s*anywhere/s);
});
