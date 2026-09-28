const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const packageJson = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
const extension = fs.readFileSync(path.join(root, 'extension.js'), 'utf8');

test('declares the humming panel command and editor entry point', () => {
  const commands = packageJson.contributes.commands.map((command) => command.command);
  assert.ok(commands.includes('tmd.openHummingPanel'));
  const hummingCommand = packageJson.contributes.commands.find((command) => command.command === 'tmd.openHummingPanel');
  assert.equal(hummingCommand.enablement, undefined, 'the independent panel must remain visible in the command palette');
  assert.ok(packageJson.contributes.menus['editor/title'].some((item) => item.command === 'tmd.openHummingPanel'));
  assert.ok(packageJson.activationEvents.includes('onCommand:tmd.openHummingPanel'));
  const panelContainers = packageJson.contributes.viewsContainers.panel || [];
  assert.ok(panelContainers.some((container) => container.id === 'tmdHummingPanel'));
  const panelViews = packageJson.contributes.views.tmdHummingPanel || [];
  assert.deepEqual(panelViews.find((view) => view.id === 'tmdHummingView'), {
    type: 'webview',
    id: 'tmdHummingView',
    name: '%tmd.viewsContainers.tmdHummingPanel%',
  });
});

test('extension wires a dedicated humming webview and editor insertion messages', () => {
  assert.match(extension, /registerWebviewViewProvider\(\s*['"]tmdHummingView['"]/);
  assert.doesNotMatch(extension, /createWebviewPanel\(\s*['"]tmdHummingPanel['"]/);
  assert.match(extension, /message\.command === ['"]insertHummingTmd['"]/);
  assert.match(extension, /humming-panel\.js/);
  assert.match(extension, /TMDHummingQuantizer/);
  assert.match(extension, /__tmdQuantizerExports/);
  assert.match(extension, /! = 120/);
  assert.match(extension, /\? = \$\{key\}/);
});

test('humming webview assets expose recording and result actions', () => {
  const script = fs.readFileSync(path.join(root, 'media', 'humming-panel.js'), 'utf8');
  const css = fs.readFileSync(path.join(root, 'media', 'humming-panel.css'), 'utf8');
  assert.doesNotMatch(script, /getUserMedia/);
  assert.match(script, /startHummingRecording/);
  assert.match(script, /stopHummingRecording/);
  assert.match(script, /BasicPitch/);
  assert.match(script, /insertHummingTmd/);
  assert.match(script, /hum-record/);
  assert.match(css, /\.hum-panel/);
});

test('humming panel wraps content inside a narrow Panel', () => {
  const css = fs.readFileSync(path.join(root, 'media', 'humming-panel.css'), 'utf8');
  assert.match(css, /\.hum-panel[\s\S]*min-width:\s*0/);
  assert.match(css, /\.hum-grid[\s\S]*min-width:\s*0/);
  assert.match(css, /\.hum-field[\s\S]*min-width:\s*0/);
  assert.match(css, /overflow-wrap:\s*anywhere/);
  assert.match(css, /\.hum-actions button[\s\S]*max-width:\s*100%/);
});

test('humming panel places controls left and result right when wide', () => {
  const css = fs.readFileSync(path.join(root, 'media', 'humming-panel.css'), 'utf8');
  assert.doesNotMatch(css, /max-width:\s*760px/);
  assert.match(css, /\.hum-panel[\s\S]*width:\s*100%/);
  assert.match(css, /grid-template-columns:\s*minmax\(220px,\s*\.75fr\)\s+minmax\(300px,\s*1\.25fr\)/);
  assert.match(css, /\.hum-grid[\s\S]*grid-area:\s*settings/);
  assert.match(css, /\.hum-options[\s\S]*grid-area:\s*options/);
  assert.match(css, /\.hum-actions[\s\S]*grid-area:\s*actions/);
  assert.match(css, /\.hum-result[\s\S]*grid-area:\s*result/);
  assert.match(css, /@media \(max-width:\s*700px\)[\s\S]*display:\s*block/);
});

test('humming panel puts recording actions before settings', () => {
  const actionsStart = extension.indexOf('<div class="hum-actions">');
  const settingsStart = extension.indexOf('<section class="hum-grid"');
  assert.ok(actionsStart >= 0);
  assert.ok(settingsStart >= 0);
  assert.ok(actionsStart < settingsStart, 'recording actions should be visible before the settings form');
});

test('humming panel localization keys are complete in every locale', () => {
  const keys = [
    'Hum to TMD', 'Humming settings', 'Reference tempo (BPM)', 'Time grid',
    'Quarter notes', 'Eighth notes', 'Sixteenth notes', 'Expected key', 'Auto-detect',
    'Section name', 'Instrument', 'Snap to natural diatonic scale', 'Metronome',
    'Four-beat count-in', 'Start recording', 'Stop and transcribe', 'Preview TMD audio',
    'Insert into editor', 'Close', 'Processing stays local to the webview.', 'Detected key: {0}',
    'Transcribing with Spotify Basic Pitch…', 'Transcribed successfully. Review the TMD before inserting it.',
    'Recording… hum or sing a melody, then stop.', 'Count-in: beat {0}', 'Microphone unavailable: {0}',
    'Permission denied.', 'Recording or transcription error: {0}', 'Generated TMD',
    'Click Start recording and hum a melody (2–8 measures recommended).',
    'Hummed TMD section inserted.', 'No active microphone recording.',
  ];
  for (const locale of ['bundle.l10n.json', 'bundle.l10n.zh-tw.json', 'bundle.l10n.zh-hant.json']) {
    const messages = JSON.parse(fs.readFileSync(path.join(root, 'l10n', locale), 'utf8'));
    for (const key of keys) assert.equal(typeof messages[key], 'string', `${locale} is missing ${key}`);
  }
});

test('humming Webview receives its localized runtime dictionary', () => {
  const panel = fs.readFileSync(path.join(root, 'media', 'humming-panel.ts'), 'utf8');
  assert.match(extension, /__TMD_HUM_L10N__/);
  assert.match(panel, /__TMD_HUM_L10N__/);
  assert.match(panel, /t\('Transcribing with Spotify Basic Pitch…'\)/);
});
