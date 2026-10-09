const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');

test('VS Code extension exposes LilyPond export and omits WAV export', () => {
  const packageJson = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
  const extensionJs = fs.readFileSync(path.join(root, 'extension.js'), 'utf8');

  const commands = packageJson.contributes.commands.map((entry) => entry.command);
  assert.ok(commands.includes('tmd.exportLilyPond'), 'contributes.commands should include tmd.exportLilyPond');
  assert.ok(!commands.includes('tmd.renderWAV'), 'contributes.commands should not include tmd.renderWAV');

  const contextMenu = packageJson.contributes.menus['editor/context'];
  const contextCommands = contextMenu.map((entry) => entry.command);
  assert.ok(contextCommands.includes('tmd.exportLilyPond'), 'editor/context menu should include tmd.exportLilyPond');
  assert.ok(!contextCommands.includes('tmd.renderWAV'), 'editor/context menu should not include tmd.renderWAV');

  const lilypondMenuEntry = contextMenu.find((entry) => entry.command === 'tmd.exportLilyPond');
  assert.equal(lilypondMenuEntry.when, 'editorLangId == tmd');
  assert.match(lilypondMenuEntry.group, /^tmd_export@/);

  assert.match(extensionJs, /registerCommand\('tmd\.exportLilyPond'/);
  assert.match(extensionJs, /runTmdExport\(\[filePath,\s*'-l',\s*outputPath\]/);
  assert.doesNotMatch(extensionJs, /tmd\.renderWAV/);

  for (const nlsFile of ['package.nls.json', 'package.nls.zh-tw.json', 'package.nls.zh-hant.json']) {
    const nls = JSON.parse(fs.readFileSync(path.join(root, nlsFile), 'utf8'));
    assert.ok('tmd.commands.exportLilyPond' in nls, `${nlsFile} should include tmd.commands.exportLilyPond`);
    assert.ok(!('tmd.commands.renderWAV' in nls), `${nlsFile} should not include tmd.commands.renderWAV`);
  }

  for (const bundleFile of ['l10n/bundle.l10n.json', 'l10n/bundle.l10n.zh-tw.json', 'l10n/bundle.l10n.zh-hant.json']) {
    const bundle = JSON.parse(fs.readFileSync(path.join(root, bundleFile), 'utf8'));
    assert.ok('LilyPond file exported successfully to {0}' in bundle, `${bundleFile} should include LilyPond export message`);
    assert.ok(!('WAV rendered successfully to {0}' in bundle), `${bundleFile} should not include WAV render message`);
  }
});
