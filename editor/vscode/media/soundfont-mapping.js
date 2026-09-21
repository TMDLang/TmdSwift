/**
 * Standard General MIDI (0-127) program numbers mapped to Soundfont (FluidR3_GM / MusyngKite) names.
 * When an instrument is not specifically distinct, it maps to the closest timbre in the SoundFont.
 */
var GM_TO_SOUNDFONT = {
  // 0-7: Piano
  0: "acoustic_grand_piano",
  1: "bright_acoustic_piano",
  2: "electric_grand_piano",
  3: "honkytonk_piano",
  4: "electric_piano_1",
  5: "electric_piano_2",
  6: "harpsichord",
  7: "clavinet",

  // 8-15: Chromatic Percussion
  8: "celesta",
  9: "glockenspiel",
  10: "music_box",
  11: "vibraphone",
  12: "marimba",
  13: "xylophone",
  14: "tubular_bells",
  15: "dulcimer",

  // 16-23: Organ
  16: "drawbar_organ",
  17: "percussive_organ",
  18: "rock_organ",
  19: "church_organ",
  20: "reed_organ",
  21: "accordion",
  22: "harmonica",
  23: "tango_accordion",

  // 24-31: Guitar
  24: "acoustic_guitar_nylon",
  25: "acoustic_guitar_steel",
  26: "electric_guitar_jazz",
  27: "electric_guitar_clean",
  28: "electric_guitar_muted",
  29: "overdriven_guitar",
  30: "distortion_guitar",
  31: "guitar_harmonics",

  // 32-39: Bass
  32: "acoustic_bass",
  33: "electric_bass_finger",
  34: "electric_bass_pick",
  35: "fretless_bass",
  36: "slap_bass_1",
  37: "slap_bass_2",
  38: "synth_bass_1",
  39: "synth_bass_2",

  // 40-47: Strings
  40: "violin",
  41: "viola",
  42: "cello",
  43: "contrabass",
  44: "tremolo_strings",
  45: "pizzicato_strings",
  46: "orchestral_harp",
  47: "timpani",

  // 48-55: Ensemble
  48: "string_ensemble_1",
  49: "string_ensemble_2",
  50: "synth_strings_1",
  51: "synth_strings_2",
  52: "choir_aahs",
  53: "voice_oohs",
  54: "lead_6_voice",
  55: "orchestra_hit",

  // 56-63: Brass
  56: "trumpet",
  57: "trombone",
  58: "tuba",
  59: "muted_trumpet",
  60: "french_horn",
  61: "brass_section",
  62: "synth_brass_1",
  63: "synth_brass_2",

  // 64-71: Reed
  64: "soprano_sax",
  65: "alto_sax",
  66: "tenor_sax",
  67: "baritone_sax",
  68: "oboe",
  69: "english_horn",
  70: "bassoon",
  71: "clarinet",

  // 72-79: Pipe
  72: "piccolo",
  73: "flute",
  74: "recorder",
  75: "pan_flute",
  76: "blown_bottle",
  77: "shakuhachi",
  78: "whistle",
  79: "ocarina",

  // 80-87: Synth Lead
  80: "lead_1_square",
  81: "lead_2_sawtooth",
  82: "lead_3_calliope",
  83: "lead_4_chiff",
  84: "lead_5_charang",
  85: "lead_6_voice",
  86: "lead_7_fifths",
  87: "lead_8_bass__lead",

  // 88-95: Synth Pad
  88: "pad_1_new_age",
  89: "pad_2_warm",
  90: "pad_3_polysynth",
  91: "pad_4_choir",
  92: "pad_5_bowed",
  93: "pad_6_metallic",
  94: "pad_7_halo",
  95: "pad_8_sweep",

  // 96-103: Synth Effects
  96: "fx_1_rain",
  97: "fx_2_soundtrack",
  98: "fx_3_crystal",
  99: "fx_4_atmosphere",
  100: "fx_5_brightness",
  101: "fx_6_goblins",
  102: "fx_7_echoes",
  103: "fx_8_scifi",

  // 104-111: Ethnic
  104: "sitar",
  105: "banjo",
  106: "shamisen",
  107: "koto",
  108: "kalimba",
  109: "bagpipe",
  110: "fiddle",
  111: "shanai",

  // 112-119: Percussive
  112: "tinkle_bell",
  113: "agogo",
  114: "steel_drums",
  115: "woodblock",
  116: "taiko_drum",
  117: "melodic_tom",
  118: "synth_drum",
  119: "reverse_cymbal",

  // 120-127: Sound Effects
  120: "guitar_fret_noise",
  121: "breath_noise",
  122: "seashore",
  123: "bird_tweet",
  124: "telephone_ring",
  125: "helicopter",
  126: "applause",
  127: "gunshot",
};

function gmProgramToSoundfontName(program) {
  if (program >= 0 && program <= 127 && GM_TO_SOUNDFONT[program]) {
    return GM_TO_SOUNDFONT[program];
  }
  return "acoustic_grand_piano";
}

function getDrumSoundfontName() {
  return "synth_drum";
}

/**
 * Scans binary SMF data to identify all used General MIDI program changes and whether
 * percussion notes appear on Channel 9 (MIDI Channel 10).
 */
function scanMidiProgramsAndDrums(bytes) {
  var programsSet = new Set();
  var hasDrums = false;

  try {
    var offset = 0;
    var len = bytes.length;

    if (
      len >= 14 &&
      bytes[0] === 0x4d &&
      bytes[1] === 0x54 &&
      bytes[2] === 0x68 &&
      bytes[3] === 0x64
    ) {
      var headerLen =
        (bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | bytes[7];
      var numTracks = (bytes[10] << 8) | bytes[11];
      offset = 8 + headerLen;

      for (var t = 0; t < numTracks && offset < len; t++) {
        if (
          offset + 8 <= len &&
          bytes[offset] === 0x4d &&
          bytes[offset + 1] === 0x54 &&
          bytes[offset + 2] === 0x72 &&
          bytes[offset + 3] === 0x6b
        ) {
          var trackLen =
            ((bytes[offset + 4] << 24) >>> 0) |
            (bytes[offset + 5] << 16) |
            (bytes[offset + 6] << 8) |
            bytes[offset + 7];
          var trackEnd = Math.min(len, offset + 8 + trackLen);
          var p = offset + 8;
          var runningStatus = 0;

          while (p < trackEnd) {
            while (p < trackEnd && (bytes[p] & 0x80) !== 0) {
              p++;
            }
            p++;
            if (p >= trackEnd) break;

            var status = bytes[p];
            if ((status & 0x80) !== 0) {
              runningStatus = status;
              p++;
            } else {
              status = runningStatus;
            }

            if (status === 0xff) {
              p++;
              var metaLen = 0;
              while (p < trackEnd) {
                var b = bytes[p++];
                metaLen = (metaLen << 7) | (b & 0x7f);
                if ((b & 0x80) === 0) break;
              }
              p += metaLen;
            } else if (status === 0xf0 || status === 0xf7) {
              var sysexLen = 0;
              while (p < trackEnd) {
                var b = bytes[p++];
                sysexLen = (sysexLen << 7) | (b & 0x7f);
                if ((b & 0x80) === 0) break;
              }
              p += sysexLen;
            } else {
              var type = status & 0xf0;
              var channel = status & 0x0f;

              if (type === 0xc0) {
                if (p < trackEnd) {
                  var prog = bytes[p++];
                  if (channel !== 9) {
                    programsSet.add(prog);
                  }
                }
              } else if (type === 0xd0) {
                p++;
              } else if (
                type === 0x80 ||
                type === 0x90 ||
                type === 0xa0 ||
                type === 0xb0 ||
                type === 0xe0
              ) {
                var d1 = p < trackEnd ? bytes[p++] : 0;
                var d2 = p < trackEnd ? bytes[p++] : 0;
                if (channel === 9 && type === 0x90 && d2 > 0) {
                  hasDrums = true;
                }
              } else {
                p++;
              }
            }
          }

          offset = trackEnd;
        } else {
          offset++;
        }
      }
    }
  } catch (err) {
    console.warn("[scanMidiProgramsAndDrums] Failed to parse SMF:", err);
  }

  if (programsSet.size === 0 && !hasDrums) {
    programsSet.add(0);
  }

  var programs = Array.from(programsSet).sort(function(a, b) { return a - b; });
  var instrumentNamesSet = new Set();

  for (var i = 0; i < programs.length; i++) {
    instrumentNamesSet.add(gmProgramToSoundfontName(programs[i]));
  }
  if (hasDrums) {
    instrumentNamesSet.add(getDrumSoundfontName());
  }

  return {
    programs: programs,
    hasDrums: hasDrums,
    instrumentNames: Array.from(instrumentNamesSet),
  };
}

// Attach to window / global scope
if (typeof window !== 'undefined') {
  window.GM_TO_SOUNDFONT = GM_TO_SOUNDFONT;
  window.gmProgramToSoundfontName = gmProgramToSoundfontName;
  window.getDrumSoundfontName = getDrumSoundfontName;
  window.scanMidiProgramsAndDrums = scanMidiProgramsAndDrums;
}
