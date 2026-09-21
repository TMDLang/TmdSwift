var NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
var IS_BLACK_KEY = [false, true, false, true, false, false, true, false, true, false, true, false];

var INTERVAL_TO_DEGREE = {
  0: { degree: 1, accidental: "" },
  1: { degree: 1, accidental: "'" },
  2: { degree: 2, accidental: "" },
  3: { degree: 2, accidental: "'" },
  4: { degree: 3, accidental: "" },
  5: { degree: 4, accidental: "" },
  6: { degree: 4, accidental: "'" },
  7: { degree: 5, accidental: "" },
  8: { degree: 5, accidental: "'" },
  9: { degree: 6, accidental: "" },
  10: { degree: 7, accidental: "," },
  11: { degree: 7, accidental: "" },
};

var KEY_SIG_OFFSETS = {
  "C": 0, "B#": 0,
  "C'": 1, "C#": 1, "D,": 1, "Db": 1,
  "D": 2,
  "D'": 3, "D#": 3, "E,": 3, "Eb": 3,
  "E": 4, "F,": 4, "Fb": 4,
  "F": 5, "E'": 5, "E#": 5,
  "F'": 6, "F#": 6, "G,": 6, "Gb": 6,
  "G": 7,
  "G'": 8, "G#": 8, "A,": 8, "Ab": 8,
  "A": 9,
  "A'": 10, "A#": 10, "B,": 10, "Bb": 10,
  "B": 11, "C,": 11, "Cb": 11
};

function parseKeyOffset(keySignatureStr) {
  if (!keySignatureStr) return 0;
  var normalized = keySignatureStr.trim();
  if (KEY_SIG_OFFSETS.hasOwnProperty(normalized)) {
    return KEY_SIG_OFFSETS[normalized];
  }
  return 0;
}

function midiToTmdNote(midi, keySignatureStr) {
  var keyOffset = parseKeyOffset(keySignatureStr || "C");
  var baseTonicMidi = 60 + keyOffset;
  var relativePitch = midi - baseTonicMidi;

  var semitoneInOctave = ((relativePitch % 12) + 12) % 12;
  var octaveDiff = Math.floor(relativePitch / 12);

  var mapping = INTERVAL_TO_DEGREE[semitoneInOctave] || { degree: 1, accidental: "" };
  var octaveStr = "";
  if (octaveDiff > 0) {
    octaveStr = "^".repeat(octaveDiff);
  } else if (octaveDiff < 0) {
    octaveStr = "_".repeat(-octaveDiff);
  }

  return "" + mapping.degree + mapping.accidental + octaveStr;
}

function midiToNoteLabel(midi, keySignatureStr) {
  var semitone = ((midi % 12) + 12) % 12;
  var octave = Math.floor(midi / 12) - 1;
  var noteName = "" + NOTE_NAMES[semitone] + octave;
  var isBlack = IS_BLACK_KEY[semitone];
  var tmdNote = midiToTmdNote(midi, keySignatureStr);

  return {
    noteName: noteName,
    degreeLabel: tmdNote,
    isBlack: isBlack,
  };
}

function calculateWhiteKeyCountForWidth(containerWidth) {
  var availableWidth = Math.max(0, containerWidth - 28);
  var keyWidth = 44;
  var count = Math.floor(availableWidth / keyWidth);
  return Math.max(8, Math.min(52, count));
}

function generateDynamicKeyboardKeys(baseOctave, targetWhiteKeyCount, keySignatureStr) {
  if (baseOctave === undefined) baseOctave = 4;
  if (targetWhiteKeyCount === undefined) targetWhiteKeyCount = 15;
  if (keySignatureStr === undefined) keySignatureStr = "C";

  var startMidi = (baseOctave + 1) * 12;
  var keys = [];
  var currentMidi = startMidi;
  var whiteCount = 0;

  while (whiteCount < targetWhiteKeyCount && currentMidi <= 108) {
    var label = midiToNoteLabel(currentMidi, keySignatureStr);
    var tmdNote = midiToTmdNote(currentMidi, keySignatureStr);

    keys.push({
      midi: currentMidi,
      noteName: label.noteName,
      degreeLabel: label.degreeLabel,
      tmdNote: tmdNote,
      isBlack: label.isBlack,
    });

    if (!label.isBlack) {
      whiteCount++;
    }
    currentMidi++;
  }

  return keys;
}

if (typeof window !== 'undefined') {
  window.midiToTmdNote = midiToTmdNote;
  window.midiToNoteLabel = midiToNoteLabel;
  window.calculateWhiteKeyCountForWidth = calculateWhiteKeyCountForWidth;
  window.generateDynamicKeyboardKeys = generateDynamicKeyboardKeys;
}
