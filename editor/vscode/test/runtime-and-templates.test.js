const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');

const root = path.join(__dirname, '..');
const extensionPath = path.join(root, 'extension.js');

function loadExtensionWithVscodeStub() {
  const originalLoad = Module._load;
  Module._load = function (request, parent, isMain) {
    if (request === 'vscode') {
      return {};
    }
    return originalLoad.call(this, request, parent, isMain);
  };
  try {
    delete require.cache[require.resolve(extensionPath)];
    return require(extensionPath);
  } finally {
    Module._load = originalLoad;
  }
}

test('CLI playback commands use --play instead of -p (--parse-only)', () => {
  const extensionJs = fs.readFileSync(extensionPath, 'utf8');

  assert.match(
    extensionJs,
    /runCliFile\(getTmdExecutable\(\),\s*\[tempPath,\s*'--play'\]/,
    'previewHummingTmd should pass --play to CLI'
  );
  assert.doesNotMatch(
    extensionJs,
    /runCliFile\(getTmdExecutable\(\),\s*\[tempPath,\s*'-p'\]/,
    'previewHummingTmd must not pass -p (--parse-only)'
  );

  assert.match(
    extensionJs,
    /term\.sendText\(`"\$\{tmdBin\}" "\$\{filePath\}" --play`\)/,
    'tmd.playAudio should run CLI with --play'
  );
  assert.doesNotMatch(
    extensionJs,
    /term\.sendText\(`"\$\{tmdBin\}" "\$\{filePath\}" -p`\)/,
    'tmd.playAudio must not run CLI with -p'
  );
});

test('extractScoreTitle and extractScoreKeySignature parse canonical TMD headers', () => {
  const ext = loadExtensionWithVscodeStub();
  assert.equal(typeof ext.extractScoreTitle, 'function', 'extractScoreTitle should be exported');
  assert.equal(typeof ext.extractScoreKeySignature, 'function', 'extractScoreKeySignature should be exported');

  const sampleScore = `::SCORE::
** 孤勇者 (Lonely Warrior) **
!= 75
?= Eb
key = Cm
<4/4>
`;
  assert.equal(ext.extractScoreTitle(sampleScore, 'fallback.tmd'), '孤勇者 (Lonely Warrior)');
  assert.equal(ext.extractScoreTitle('::SCORE::\n!= 120\n', 'fallback.tmd'), 'fallback.tmd');

  assert.equal(ext.extractScoreKeySignature(sampleScore), 'Eb');
  assert.equal(ext.extractScoreKeySignature('::SCORE::\n?= F#\n'), 'F#');
  assert.equal(ext.extractScoreKeySignature('::SCORE::\nkey = Bm\n'), 'Bm');
  assert.equal(ext.extractScoreKeySignature('::SCORE::\n!= 120\n'), 'C');

  const extensionJs = fs.readFileSync(extensionPath, 'utf8');
  assert.doesNotMatch(extensionJs, /\\s\*name\\s\*:/, 'stale name: header regex should be removed');
  assert.doesNotMatch(extensionJs, /\(\?:\\\?=|key\)\\s\*:/, 'stale ?=/key: colon regex should be removed');
});

test('Outline tree provider matches canonical Playback node name', () => {
  const extensionJs = fs.readFileSync(extensionPath, 'utf8');
  assert.match(
    extensionJs,
    /node\.name === 'Playback'/,
    'TMDOutlineTreeDataProvider.buildTreeItem should match node.name === "Playback"'
  );
});

test('TMD_TEMPLATES use canonical 0 rest token instead of deprecated dot rest', () => {
  const ext = loadExtensionWithVscodeStub();
  assert.ok(Array.isArray(ext.TMD_TEMPLATES), 'TMD_TEMPLATES should be exported');

  const starter = ext.TMD_TEMPLATES.find((t) => t.id === 'starter');
  assert.ok(starter, 'starter template should exist');
  assert.match(starter.content, /- 休止符：0\b/);
  assert.doesNotMatch(starter.content, /- 休止符：\. 或 0/);

  const leadsheet = ext.TMD_TEMPLATES.find((t) => t.id === 'leadsheet');
  assert.ok(leadsheet, 'leadsheet template should exist');
  assert.match(leadsheet.content, /intro:Lead@\|0\|\{\s*<4\*>\s*\| 0 0 0 0 \| 0 0 0 0 \|/);
  assert.doesNotMatch(leadsheet.content, /\| \. \. \. \. \|/);
});
