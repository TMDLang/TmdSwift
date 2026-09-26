const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const inspectorPath = path.join(__dirname, '..', 'media', 'inspector.js');

test('VSCode inspector consumes the current inferred-tonality contract', () => {
  const source = fs.readFileSync(inspectorPath, 'utf8');

  assert.match(source, /tonality\.globalInference/);
  assert.match(source, /tonality\.playbackContext/);
  assert.match(source, /tonality\.inferredModulationPath/);
  assert.doesNotMatch(source, /tonality\.globalCorrelation/);
  assert.doesNotMatch(source, /Declared Key/);
});

test('VSCode top metric labels the movable-do playback base explicitly', () => {
  const extensionSource = fs.readFileSync(path.join(__dirname, '..', 'extension.js'), 'utf8');
  const inspectorSource = fs.readFileSync(inspectorPath, 'utf8');

  assert.match(extensionSource, /Movable-do base/);
  assert.doesNotMatch(extensionSource, /vscode\.l10n\.t\('Initial Key'\)/);
  assert.match(inspectorSource, /profile\.initialKey/);
});

test('VSCode inspector keeps structure rendering independent of tonality rendering', () => {
  const source = fs.readFileSync(inspectorPath, 'utf8');
  const tonalityCall = source.indexOf('renderTonalityProfile(profile.tonality)');
  const timelineCall = source.indexOf('renderTimeline(profile.timing.sections, profile.timing.totalDurationSeconds)');

  assert.notEqual(tonalityCall, -1);
  assert.notEqual(timelineCall, -1);
  assert.ok(timelineCall < tonalityCall, 'structure timeline must render before optional tonality data');
});
