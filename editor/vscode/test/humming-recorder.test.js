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

test('panel re-enables Stop after the host recording starts', () => {
  const source = fs.readFileSync(path.join(root, 'media', 'humming-panel.ts'), 'utf8');
  assert.match(source, /postMessage\(\{ command: 'startHummingRecording' \}\);\s*recording = true;\s*recordButton\.disabled = false;/);
});

test('panel reports recognition failures and restores the record control', () => {
  const source = fs.readFileSync(path.join(root, 'media', 'humming-panel.ts'), 'utf8');
  assert.match(source, /void transcribe\(new Blob\(\[audioBuffer\]/);
  assert.match(source, /\.catch\(\(error\) => setStatus\(t\('Recording or transcription error: \{0\}'/);
  assert.match(source, /setStatus\(t\('Recording or transcription error: \{0\}'/);
  assert.match(source, /\.finally\(\(\) => \{ recordButton\.disabled = false; \}/);
});

test('recorded audio crosses the Webview boundary as JSON-safe Base64', () => {
  const extension = fs.readFileSync(path.join(root, 'extension.js'), 'utf8');
  const panel = fs.readFileSync(path.join(root, 'media', 'humming-panel.ts'), 'utf8');
  assert.match(extension, /audioBase64:\s*Buffer\.from\(audio\)\.toString\(['"]base64['"]\)/);
  assert.match(panel, /audioBase64\?: string/);
  assert.match(panel, /atob\(message\.audioBase64\)/);
});
