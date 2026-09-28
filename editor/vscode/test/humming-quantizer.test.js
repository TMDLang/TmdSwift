const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const {
  detectTonicAndScale,
  midiPitchToJianpu,
  quantizeNoteEventsToTmdSection,
} = require('../media/humming-quantizer');

test('quantizer runtime exposes CommonJS functions for the Webview bridge', () => {
  const runtime = fs.readFileSync(path.join(__dirname, '..', 'media', 'humming-quantizer.js'), 'utf8');
  assert.match(runtime, /exports\.detectTonicAndScale/);
  assert.match(runtime, /exports\.quantizeNoteEventsToTmdSection/);
});

test('converts MIDI pitch to Jianpu relative to the key', () => {
  assert.equal(midiPitchToJianpu(60, 'C'), '1');
  assert.equal(midiPitchToJianpu(72, 'C'), '1^');
  assert.equal(midiPitchToJianpu(48, 'C'), '1_');
  assert.equal(midiPitchToJianpu(61, 'C'), "1'");
  assert.equal(midiPitchToJianpu(67, 'G'), '1');
  assert.equal(midiPitchToJianpu(72, 'G'), '4');
  assert.equal(midiPitchToJianpu(61, 'C', true), '1');
});

test('quantizes rests and sustained notes into a parseable TMD section', () => {
  const tmd = quantizeNoteEventsToTmdSection([
    { startTimeSeconds: 0, durationSeconds: 0.5, pitchMidi: 60, amplitude: 0.9 },
    { startTimeSeconds: 0.75, durationSeconds: 0.25, pitchMidi: 67, amplitude: 0.9 },
  ], { sectionName: 'verse', instrument: 'Vocal', bpm: 120, grid: 8, key: 'C' });

  assert.equal(tmd, [
    'verse:Vocal@|0|{',
    '    <8*>',
    '    | 1 - 0 5 0 0 0 0 |',
    '}',
  ].join('\n'));
});

test('detects G major from duration-weighted note events', () => {
  const events = [
    { startTimeSeconds: 0, durationSeconds: 1, pitchMidi: 67, amplitude: 0.9 },
    { startTimeSeconds: 1, durationSeconds: 0.5, pitchMidi: 69, amplitude: 0.8 },
    { startTimeSeconds: 1.5, durationSeconds: 0.5, pitchMidi: 71, amplitude: 0.8 },
    { startTimeSeconds: 2, durationSeconds: 0.5, pitchMidi: 72, amplitude: 0.8 },
    { startTimeSeconds: 2.5, durationSeconds: 1, pitchMidi: 74, amplitude: 0.9 },
    { startTimeSeconds: 3.5, durationSeconds: 1.5, pitchMidi: 67, amplitude: 0.9 },
  ];

  assert.equal(detectTonicAndScale(events), 'G');
});

test('returns a rest section for empty or unusable input', () => {
  const tmd = quantizeNoteEventsToTmdSection([], { sectionName: 'empty', bpm: 100, grid: 4 });
  assert.match(tmd, /empty:Vocal@\|0\|\{/);
  assert.match(tmd, /<4\*>/);
  assert.match(tmd, /\n    0\n/);
});

test('returns a rest section instead of allocating on invalid note input', () => {
  const tmd = quantizeNoteEventsToTmdSection([
    { startTimeSeconds: 0, durationSeconds: Infinity, pitchMidi: 60, amplitude: 0.9 },
    { startTimeSeconds: NaN, durationSeconds: 0.5, pitchMidi: 60, amplitude: 0.9 },
  ], { sectionName: 'invalid', bpm: 120, grid: 8 });

  assert.match(tmd, /^invalid:Vocal@\|0\|\{/);
  assert.match(tmd, /\n    0\n/);
});

test('generated TMD passes the existing measure checker', () => {
  const tmd = quantizeNoteEventsToTmdSection([
    { startTimeSeconds: 0, durationSeconds: 0.5, pitchMidi: 60, amplitude: 0.9 },
  ], { sectionName: 'checked', bpm: 120, grid: 8, key: 'C' });
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'tmd-humming-test-'));
  const file = path.join(directory, 'checked.tmd');
  fs.writeFileSync(file, `::SCORE::\n\n-> checked -> #\n\n${tmd}\n`);
  assert.doesNotThrow(() => execFileSync('tmd', ['-p', file], { stdio: 'pipe' }));
});
