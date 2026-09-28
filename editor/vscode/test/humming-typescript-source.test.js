const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const mediaDir = require('node:path').join(__dirname, '..', 'media');

test('humming quantization has a TypeScript source of truth', () => {
  const source = fs.readFileSync(require('node:path').join(mediaDir, 'humming-quantizer.ts'), 'utf8');
  assert.match(source, /export type HummingNoteEvent/);
  assert.match(source, /export function detectTonicAndScale/);
  assert.match(source, /export function quantizeNoteEventsToTmdSection/);
});

test('humming panel has a TypeScript source of truth', () => {
  const source = fs.readFileSync(require('node:path').join(mediaDir, 'humming-panel.ts'), 'utf8');
  assert.match(source, /declare const acquireVsCodeApi/);
  assert.match(source, /startHummingRecording/);
  assert.match(source, /stopHummingRecording/);
  assert.doesNotMatch(source, /getUserMedia/);
  assert.match(source, /BasicPitch/);
});

test('humming recorder has an extension-host TypeScript source of truth', () => {
  const source = fs.readFileSync(require('node:path').join(__dirname, '..', 'humming-recorder.ts'), 'utf8');
  assert.match(source, /export function createHummingRecorder/);
  assert.match(source, /avfoundation/);
  assert.match(source, /Microphone recording requires ffmpeg/);
});
