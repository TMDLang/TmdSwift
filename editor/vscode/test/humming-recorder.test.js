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

function spawnRecorderProcess() {
  const listeners = new Map();
  return {
    args: null,
    once(event, listener) {
      listeners.set(event, listener);
      if (event === 'spawn') queueMicrotask(listener);
      return this;
    },
    kill() {
      listeners.get('close')?.(0);
      return true;
    },
  };
}

test('recorder selects AVFoundation input on macOS', async () => {
  let spawned;
  const recorder = require(path.join(root, 'humming-recorder.js')).createHummingRecorder({
    platform: 'darwin',
    outputPath: path.join('/tmp', 'tmd-humming-test.wav'),
    spawnProcess: (_command, args) => {
      spawned = spawnRecorderProcess();
      spawned.args = args;
      return spawned;
    },
  });
  await recorder.start();
  assert.deepEqual(spawned.args.slice(0, 6), ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'avfoundation']);
  assert.deepEqual(spawned.args.slice(6, 8), ['-i', ':default']);
  recorder.cancel();
});

test('recorder selects DirectShow input on Windows', async () => {
  let spawned;
  const recorder = require(path.join(root, 'humming-recorder.js')).createHummingRecorder({
    platform: 'win32',
    inputDevice: 'audio=USB Microphone',
    outputPath: path.join('/tmp', 'tmd-humming-test.wav'),
    spawnProcess: (_command, args) => {
      spawned = spawnRecorderProcess();
      spawned.args = args;
      return spawned;
    },
  });
  await recorder.start();
  assert.deepEqual(spawned.args.slice(4, 8), ['-f', 'dshow', '-i', 'audio=USB Microphone']);
  recorder.cancel();
});

test('recorder selects PulseAudio input on Linux', async () => {
  let spawned;
  const recorder = require(path.join(root, 'humming-recorder.js')).createHummingRecorder({
    platform: 'linux',
    outputPath: path.join('/tmp', 'tmd-humming-test.wav'),
    spawnProcess: (_command, args) => {
      spawned = spawnRecorderProcess();
      spawned.args = args;
      return spawned;
    },
  });
  await recorder.start();
  assert.deepEqual(spawned.args.slice(4, 8), ['-f', 'pulse', '-i', 'default']);
  recorder.cancel();
});

test('recorder rejects unsupported host platforms clearly', async () => {
  const recorder = require(path.join(root, 'humming-recorder.js')).createHummingRecorder({ platform: 'freebsd' });
  await assert.rejects(recorder.start(), /Unsupported microphone recording platform/);
});

test('humming recording exposes cross-platform ffmpeg settings', () => {
  const packageJson = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
  const properties = packageJson.contributes.configuration.properties;
  assert.equal(properties['tmd.humming.ffmpegPath'].type, 'string');
  assert.equal(properties['tmd.humming.inputDevice'].type, 'string');
  assert.deepEqual(properties['tmd.humming.linuxInputFormat'].enum, ['pulse', 'alsa']);
  const extension = fs.readFileSync(path.join(root, 'extension.js'), 'utf8');
  assert.match(extension, /getConfiguration\(['"]tmd\.humming['"]\)/);
  assert.match(extension, /inputDevice/);
  assert.match(extension, /linuxInputFormat/);
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
