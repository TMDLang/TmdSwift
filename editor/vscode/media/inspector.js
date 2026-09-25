const vscode = acquireVsCodeApi();
const t = (window.__tmd_t || ((key, ...args) => {
  let s = (window.__TMD_L10N__ && window.__TMD_L10N__[key]) || key;
  args.forEach((a, i) => { s = s.replace('{' + i + '}', a); });
  return s;
}));

let currentProfile = null;
let selectedInstrument = null;

const COLORS = [
  '#2f81f7', '#3fb950', '#d29922', '#db61a2', '#a371f7', 
  '#f0883e', '#56d364', '#79c0ff', '#e3b341', '#f778ba'
];

window.addEventListener('message', event => {
  const message = event.data;
  switch (message.type) {
    case 'update':
      currentProfile = message.profile;
      renderInspector(message.profile, message.fileName);
      break;
    case 'error':
      renderError(message.error, message.fileName);
      break;
  }
});

function renderError(errorMsg, fileName) {
  document.getElementById('status-badge').className = 'badge-error';
  document.getElementById('status-badge').textContent = t('Error');
  document.getElementById('score-title').textContent = fileName || 'TMD Score';
  document.getElementById('file-path').textContent = errorMsg;
}

function renderInspector(profile, fileName) {
  if (!profile) return;

  // Header
  document.getElementById('status-badge').className = 'badge-valid';
  document.getElementById('status-badge').textContent = t('Valid Score');
  document.getElementById('score-title').textContent = profile.title || fileName || 'TMD Score';
  document.getElementById('file-path').textContent = fileName || '';

  // Stats Grid
  const mins = Math.floor(profile.timing.totalDurationSeconds / 60);
  const secs = Math.floor(profile.timing.totalDurationSeconds % 60);
  const durationStr = `${mins}:${secs.toString().padStart(2, '0')}`;
  
  document.getElementById('val-duration').textContent = durationStr;
  document.getElementById('sub-duration').textContent = `${profile.timing.totalDurationSeconds.toFixed(1)}s (${profile.timing.totalMeasures} ${t('bars')})`;

  document.getElementById('val-key').textContent = `${profile.initialKey} ${t('Major')}`;
  document.getElementById('sub-key').textContent = t('Meter <{0}>', profile.initialTimeSignature);

  document.getElementById('val-tempo').textContent = `${profile.initialTempo} BPM`;
  document.getElementById('sub-tempo').textContent = t('Quarter note beat');

  document.getElementById('val-density').textContent = `${profile.density.maxConcurrentTracks} ${t('tracks')}`;
  const secCount = profile.density.sectionDensities.length;
  const avgDensity = secCount > 0 
    ? (profile.density.sectionDensities.reduce((acc, s) => acc + s.trackCount, 0) / secCount).toFixed(1)
    : 0;
  document.getElementById('sub-density').textContent = t('Peak concurrency (avg {0})', avgDensity);

  // Track Selector for Pitch Range
  const ranges = profile.instrumentRanges || [];
  const trackSelect = document.getElementById('track-select');
  trackSelect.innerHTML = '';

  if (ranges.length > 0) {
    if (!selectedInstrument || !ranges.some(r => r.instrument === selectedInstrument)) {
      // Prioritize primary vocal instrument (faithful to TS implementation)
      const primaryVocal = ranges.find(r => /^(main_?vocal|lead_?vocal|vocal|voice|主唱|人聲|歌|vo)$/i.test(r.instrument))
        || ranges.find(r => /vocal|voice|miku|utau|teto|sing|melody|lead|主旋律/i.test(r.instrument) && !/backing|harm|choir|guitar|synth|pad|bass|drum|beat/i.test(r.instrument))
        || (profile.vocalRange ? ranges.find(r => r.instrument === profile.vocalRange.instrument) : null)
        || ranges[0];
      selectedInstrument = primaryVocal ? primaryVocal.instrument : ranges[0].instrument;
    }

    ranges.forEach(r => {
      const opt = document.createElement('option');
      opt.value = r.instrument;
      opt.textContent = `${r.instrument} (${r.totalNotes} ${t('notes')})`;
      if (r.instrument === selectedInstrument) {
        opt.selected = true;
      }
      trackSelect.appendChild(opt);
    });

    renderSelectedInstrumentRange(selectedInstrument, ranges);
  } else {
    document.getElementById('range-container').innerHTML = `<div class="stat-sub">${t('No notes detected.')}</div>`;
  }

  // Harmony & Chords
  const harmonyContainer = document.getElementById('chords-list');
  harmonyContainer.innerHTML = '';
  const chords = profile.harmony.distinctChords || [];
  if (chords.length > 0) {
    chords.forEach(ch => {
      const tag = document.createElement('span');
      tag.className = 'tag-chord';
      tag.textContent = ch;
      tag.title = `Click to search ${ch} in score`;
      tag.addEventListener('click', () => {
        vscode.postMessage({ type: 'findText', text: ch });
      });
      harmonyContainer.appendChild(tag);
    });
  } else {
    harmonyContainer.innerHTML = `<span class="stat-sub">${t('None')}</span>`;
  }

  // Modulations
  const modContainer = document.getElementById('modulations-list');
  modContainer.innerHTML = '';
  const mods = profile.harmony.modulations || [];
  if (mods.length > 0) {
    mods.forEach(m => {
      const tag = document.createElement('span');
      tag.className = 'tag-modulation';
      tag.textContent = m;
      modContainer.appendChild(tag);
    });
  } else {
    modContainer.innerHTML = `<span class="stat-sub">${t('None')}</span>`;
  }

  // Timeline & Sections
  renderTimeline(profile.timing.sections, profile.timing.totalDurationSeconds);
}

function renderSelectedInstrumentRange(instName, ranges) {
  const container = document.getElementById('range-container');
  const target = ranges.find(r => r.instrument === instName);
  if (!target) {
    container.innerHTML = `<div class="stat-sub">${t('No data for selected track.')}</div>`;
    return;
  }

  const octaves = (target.spanSemitones / 12.0).toFixed(1);
  const diffStr = (target.difficulty || 'easy').toLowerCase();
  const diffLabels = {
    'easy': t('Easy'),
    'moderate': t('Moderate'),
    'challenging': t('Challenging'),
    'difficult': t('Difficult')
  };
  const diffColors = {
    'easy': '#3fb950',
    'moderate': '#58a6ff',
    'challenging': '#d29922',
    'difficult': '#f85149'
  };
  const diffLabel = diffLabels[diffStr] || target.difficulty;
  const diffColor = diffColors[diffStr] || '#58a6ff';

  const voiceTypeNames = {
    'soprano': t('Soprano'),
    'mezzo-soprano': t('Mezzo-Soprano'),
    'contralto': t('Contralto'),
    'tenor': t('Tenor'),
    'baritone': t('Baritone'),
    'bass': t('Bass')
  };

  const suitableVoices = (target.suitableVoiceTypes || []).map(v => voiceTypeNames[v] || v);
  const voiceStr = suitableVoices.length > 0 ? suitableVoices.join(', ') : t('None');

  // Compute Jianpu degree if virtualKeyboardHelper is available
  const keySig = (currentProfile && currentProfile.initialKey) ? currentProfile.initialKey : 'C';
  let lowDegree = '';
  let highDegree = '';
  let avgNoteName = '';
  if (typeof midiToTmdNote === 'function') {
    lowDegree = ` (${midiToTmdNote(target.lowestNote.midiPitch, keySig)})`;
    highDegree = ` (${midiToTmdNote(target.highestNote.midiPitch, keySig)})`;
  }
  if (typeof midiToNoteLabel === 'function') {
    const avgRound = Math.round(target.averageMidiPitch);
    const avgLabel = midiToNoteLabel(avgRound, keySig);
    avgNoteName = `${avgLabel.noteName} (${avgLabel.degreeLabel})`;
  } else {
    avgNoteName = `${Math.round(target.averageMidiPitch)}`;
  }

  const lowSec = target.lowestNote.sectionName ? `[${target.lowestNote.sectionName}]` : '';
  const highSec = target.highestNote.sectionName ? `[${target.highestNote.sectionName}]` : '';
  const sectionSpan = (lowSec && highSec)
    ? (lowSec === highSec ? t('Section {0}', lowSec) : `${lowSec} ～ ${highSec}`)
    : (lowSec || highSec || '');

  container.innerHTML = `
    <div class="vocal-profile-container">
      <div class="pitch-stats-row">
        <div class="pitch-stat-box">
          <span class="stat-label">${t('Pitch Range')}</span>
          <span class="stat-value">${target.lowestNote.noteName}${lowDegree} ～ ${target.highestNote.noteName}${highDegree}</span>
          <span class="stat-sub">${sectionSpan}</span>
        </div>
        <div class="pitch-stat-box">
          <span class="stat-label">${t('Pitch Span')}</span>
          <span class="stat-value">${octaves} ${t('octaves')} <span style="font-size: 11px; font-weight: normal; color: var(--muted-color);">(${target.spanSemitones} ${t('semitones')})</span></span>
          <span class="stat-sub" style="color: ${diffColor}; font-weight: 600;">${t('Difficulty: {0}', diffLabel)}</span>
        </div>
      </div>

      <div class="pitch-metric-row">
        <div>
          <div class="stat-label">${t('Center Tessitura')}</div>
          <div class="span-pill">${avgNoteName}</div>
        </div>
        <div class="pitch-meta">${t('Average pitch')}</div>
      </div>

      <div class="pitch-metric-row">
        <div>
          <div class="stat-label">${t('Recommended Voice Classification')}</div>
          <div style="font-weight: 600; color: #58a6ff; margin-top: 3px;">${voiceStr}</div>
        </div>
        <div class="pitch-meta">${t('Based on pitch range')}</div>
      </div>
    </div>
  `;
}

function renderTimeline(sections, totalSeconds) {
  const barWrapper = document.getElementById('timeline-bar-wrapper');
  const listWrapper = document.getElementById('timeline-list');
  barWrapper.innerHTML = '';
  listWrapper.innerHTML = '';

  const activeSections = (sections || []).filter(s => s.name !== '#');
  if (activeSections.length === 0 || totalSeconds <= 0) return;

  activeSections.forEach((sec, idx) => {
    const pct = ((sec.durationSeconds / totalSeconds) * 100).toFixed(2);
    const color = COLORS[idx % COLORS.length];

    // Horizontal Segment
    const seg = document.createElement('div');
    seg.className = 'timeline-segment';
    seg.style.width = `${pct}%`;
    seg.style.backgroundColor = color;
    seg.title = `${sec.name}: ${sec.durationSeconds.toFixed(1)}s (${sec.measures} bars, ${pct}%)`;
    if (parseFloat(pct) > 5) {
      seg.textContent = sec.name;
    }
    seg.addEventListener('click', () => {
      vscode.postMessage({ type: 'jumpToSection', sectionName: sec.name });
    });
    barWrapper.appendChild(seg);

    // List item
    const item = document.createElement('div');
    item.className = 'timeline-item';
    item.innerHTML = `
      <span class="timeline-item-index" style="color: ${color};">#${idx + 1}</span>
      <span class="timeline-item-name">${sec.name}</span>
      <span class="timeline-item-time">${sec.durationSeconds.toFixed(1)}s (${sec.measures}m)</span>
    `;
    item.addEventListener('click', () => {
      vscode.postMessage({ type: 'jumpToSection', sectionName: sec.name });
    });
    listWrapper.appendChild(item);
  });
}

// Event Listeners
document.getElementById('track-select').addEventListener('change', (e) => {
  selectedInstrument = e.target.value;
  if (currentProfile && currentProfile.instrumentRanges) {
    renderSelectedInstrumentRange(selectedInstrument, currentProfile.instrumentRanges);
  }
});

document.getElementById('btn-refresh').addEventListener('click', () => {
  vscode.postMessage({ type: 'refresh' });
});
