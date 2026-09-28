const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');

test('extension host recorder exposes start, stop, and cancel controls', () => {
  const recorder = require(path.join(root, 'humming-recorder.js'));
  const instance = recorder.createHummingRecorder({
    spawnProcess: () => ({
      on() { return this; },
      kill() {},
    }),
  });
  assert.equal(typeof instance.start, 'function');
  assert.equal(typeof instance.stop, 'function');
  assert.equal(typeof instance.cancel, 'function');
});

test('panel delegates recording to the extension host instead of getUserMedia', () => {
  const source = fs.readFileSync(path.join(root, 'media', 'humming-panel.ts'), 'utf8');
  assert.match(source, /startHummingRecording/);
  assert.match(source, /stopHummingRecording/);
  assert.doesNotMatch(source, /getUserMedia/);
});
