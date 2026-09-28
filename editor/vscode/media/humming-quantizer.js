'use strict';

const SEMITONE_TO_JIANPU = ['1', "1'", '2', "2'", '3', '4', "4'", '5', "5'", '6', "6'", '7'];
const DIATONIC_SEMITONES = [0, 0, 2, 2, 4, 5, 5, 7, 7, 9, 9, 11];
const MAJOR_PROFILE = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88];
const PITCH_CLASSES = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
const NATURAL_PITCHES = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };

function keyOffset(key) {
  const match = String(key || 'C').trim().match(/^([A-Ga-g])([#'b,]?)$/);
  if (!match) return 0;
  const accidental = match[2];
  return ((NATURAL_PITCHES[match[1].toUpperCase()] + (accidental === '#' || accidental === "'" ? 1 : accidental === 'b' || accidental === ',' ? -1 : 0)) % 12 + 12) % 12;
}

function detectTonicAndScale(events) {
  if (!events.length) return 'C';
  const chroma = new Array(12).fill(0);
  for (const event of events) {
    if (event.amplitude <= 0.05 || event.durationSeconds <= 0.05) continue;
    const semitone = ((Math.round(event.pitchMidi) % 12) + 12) % 12;
    chroma[semitone] += Math.max(0.1, event.durationSeconds) * (event.amplitude || 1);
  }

  const chromaMean = chroma.reduce((sum, value) => sum + value, 0) / 12;
  const profileMean = MAJOR_PROFILE.reduce((sum, value) => sum + value, 0) / 12;
  let bestKey = 'C';
  let bestScore = -Infinity;
  for (let root = 0; root < 12; root++) {
    let numerator = 0;
    let chromaDenominator = 0;
    let profileDenominator = 0;
    for (let index = 0; index < 12; index++) {
      const chromaValue = chroma[(root + index) % 12] - chromaMean;
      const profileValue = MAJOR_PROFILE[index] - profileMean;
      numerator += chromaValue * profileValue;
      chromaDenominator += chromaValue * chromaValue;
      profileDenominator += profileValue * profileValue;
    }
    const denominator = Math.sqrt(chromaDenominator * profileDenominator);
    const score = denominator === 0 ? 0 : numerator / denominator;
    if (score > bestScore) {
      bestScore = score;
      bestKey = PITCH_CLASSES[root];
    }
  }
  return bestKey;
}

function midiPitchToJianpu(pitchMidi, key = 'C', snapToScale = false) {
  const relativePitch = Math.round(pitchMidi) - 60 - keyOffset(key);
  const octave = Math.floor(relativePitch / 12);
  let semitone = ((relativePitch % 12) + 12) % 12;
  if (snapToScale) semitone = DIATONIC_SEMITONES[semitone];
  const octaveMark = octave > 0 ? '^'.repeat(octave) : octave < 0 ? '_'.repeat(-octave) : '';
  return `${SEMITONE_TO_JIANPU[semitone]}${octaveMark}`;
}

function emptySection(sectionName, instrument, grid) {
  return `${sectionName}:${instrument}@|0|{\n    <${grid}*>\n    0\n}`;
}

function quantizeNoteEventsToTmdSection(events, options = {}) {
  const sectionName = options.sectionName || 'hummed';
  const instrument = options.instrument || 'Vocal';
  const bpm = Math.max(20, options.bpm || 120);
  const grid = options.grid || 8;
  const beatsPerMeasure = Math.max(1, options.beatsPerMeasure || 4);
  const key = !options.key || options.key === 'AUTO' ? detectTonicAndScale(events) : options.key;
  const slotDuration = (4 / grid) * (60 / bpm);
  if (!events.length) return emptySection(sectionName, instrument, grid);

  const minimumDuration = Math.max(0.1, slotDuration * 0.4);
  const validEvents = events
    .filter((event) => event.amplitude > 0.15 && event.durationSeconds >= minimumDuration)
    .sort((a, b) => a.startTimeSeconds - b.startTimeSeconds);
  if (!validEvents.length) return emptySection(sectionName, instrument, grid);

  const lastEvent = validEvents[validEvents.length - 1];
  const rawTotalSlots = Math.ceil((lastEvent.startTimeSeconds + lastEvent.durationSeconds) / slotDuration);
  const slotsPerMeasure = Math.max(1, Math.round((grid / 4) * beatsPerMeasure));
  const totalSlots = Math.max(slotsPerMeasure, Math.ceil(rawTotalSlots / slotsPerMeasure) * slotsPerMeasure);
  const slots = new Array(totalSlots).fill(null);

  for (const event of validEvents) {
    const startSlot = Math.max(0, Math.round(event.startTimeSeconds / slotDuration));
    const durationSlots = Math.max(1, Math.round(event.durationSeconds / slotDuration));
    if (startSlot >= totalSlots) continue;
    slots[startSlot] = midiPitchToJianpu(event.pitchMidi, key, options.snapToScale || false);
    for (let offset = 1; offset < durationSlots && startSlot + offset < totalSlots; offset++) {
      if (!slots[startSlot + offset]) slots[startSlot + offset] = '-';
    }
  }

  const measures = [];
  for (let start = 0; start < totalSlots; start += slotsPerMeasure) {
    const tokens = slots.slice(start, start + slotsPerMeasure).map((token) => token || '0');
    measures.push(`    | ${tokens.join(' ')} |`);
  }
  return `${sectionName}:${instrument}@|0|{\n    <${grid}*>\n${measures.join('\n')}\n}`;
}

const api = {
  detectTonicAndScale,
  midiPitchToJianpu,
  quantizeNoteEventsToTmdSection,
};

if (typeof window !== 'undefined') window.TMDHummingQuantizer = api;
if (typeof module !== 'undefined') module.exports = api;
