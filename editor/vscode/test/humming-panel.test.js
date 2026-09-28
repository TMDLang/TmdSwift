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
    name: 'Hum to TMD',
  });
});

test('extension wires a dedicated humming webview and editor insertion messages', () => {
  assert.match(extension, /registerWebviewViewProvider\(\s*['"]tmdHummingView['"]/);
  assert.doesNotMatch(extension, /createWebviewPanel\(\s*['"]tmdHummingPanel['"]/);
  assert.match(extension, /message\.command === ['"]insertHummingTmd['"]/);
  assert.match(extension, /humming-panel\.js/);
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
