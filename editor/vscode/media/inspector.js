const vscode = acquireVsCodeApi();

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
  document.getElementById('status-badge').textContent = 'Error';
  document.getElementById('score-title').textContent = fileName || 'TMD Score';
  document.getElementById('file-path').textContent = errorMsg;
}

function renderInspector(profile, fileName) {
  if (!profile) return;

  // Header
  document.getElementById('status-badge').className = 'badge-valid';
  document.getElementById('status-badge').textContent = 'Valid Score';
  document.getElementById('score-title').textContent = profile.title || fileName || 'TMD Score';
  document.getElementById('file-path').textContent = fileName || '';

  // Stats Grid
  const mins = Math.floor(profile.timing.totalDurationSeconds / 60);
  const secs = Math.floor(profile.timing.totalDurationSeconds % 60);
  const durationStr = `${mins}:${secs.toString().padStart(2, '0')}`;
  
  document.getElementById('val-duration').textContent = durationStr;
  document.getElementById('sub-duration').textContent = `${profile.timing.totalDurationSeconds.toFixed(1)}s (${profile.timing.totalMeasures} bars)`;

  document.getElementById('val-key').textContent = `${profile.initialKey} Major`;
  document.getElementById('sub-key').textContent = `Meter <${profile.initialTimeSignature}>`;

  document.getElementById('val-tempo').textContent = `${profile.initialTempo} BPM`;
  document.getElementById('sub-tempo').textContent = 'Quarter note beat';

  document.getElementById('val-density').textContent = `${profile.density.maxConcurrentTracks} tracks`;
  const secCount = profile.density.sectionDensities.length;
  const avgDensity = secCount > 0 
    ? (profile.density.sectionDensities.reduce((acc, s) => acc + s.trackCount, 0) / secCount).toFixed(1)
    : 0;
  document.getElementById('sub-density').textContent = `Peak concurrency (avg ${avgDensity})`;

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
      opt.textContent = `${r.instrument} (${r.totalNotes} notes)`;
      if (r.instrument === selectedInstrument) {
        opt.selected = true;
      }
      trackSelect.appendChild(opt);
    });

    renderSelectedInstrumentRange(selectedInstrument, ranges);
  } else {
    document.getElementById('range-container').innerHTML = '<div class="stat-sub">No notes detected.</div>';
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
    harmonyContainer.innerHTML = '<span class="stat-sub">None</span>';
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
    modContainer.innerHTML = '<span class="stat-sub">None</span>';
  }

  // Timeline & Sections
  renderTimeline(profile.timing.sections, profile.timing.totalDurationSeconds);
}

function renderSelectedInstrumentRange(instName, ranges) {
  const container = document.getElementById('range-container');
  const target = ranges.find(r => r.instrument === instName);
  if (!target) {
    container.innerHTML = '<div class="stat-sub">No data for selected track.</div>';
    return;
  }

  const octaves = (target.spanSemitones / 12.0).toFixed(1);
  const diffStr = (target.difficulty || 'easy').toLowerCase();
  const diffLabels = {
    'easy': 'Easy',
    'moderate': 'Moderate',
    'challenging': 'Challenging',
    'difficult': 'Difficult'
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
    'soprano': 'Soprano (女高音)',
    'mezzo-soprano': 'Mezzo-Soprano (女中音)',
    'contralto': 'Contralto (女低音)',
    'tenor': 'Tenor (男高音)',
    'baritone': 'Baritone (男中音)',
    'bass': 'Bass (男低音)'
  };

  const suitableVoices = (target.suitableVoiceTypes || []).map(v => voiceTypeNames[v] || v);
  const voiceStr = suitableVoices.length > 0 ? suitableVoices.join(', ') : 'None';

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

  container.innerHTML = `
    <div class="vocal-profile-container">
      <div class="pitch-stats-row">
        <div class="pitch-stat-box">
          <span class="stat-label">Vocal Range (音域)</span>
          <span class="stat-value">${target.lowestNote.noteName}${lowDegree} ～ ${target.highestNote.noteName}${highDegree}</span>
          <span class="stat-sub">Key: ${keySig} · [${target.lowestNote.sectionName}] ～ [${target.highestNote.sectionName}]</span>
        </div>
        <div class="pitch-stat-box">
          <span class="stat-label">Pitch Span (跨度)</span>
          <span class="stat-value">${octaves} octaves <span style="font-size: 11px; font-weight: normal; color: var(--muted-color);">(${target.spanSemitones} semitones)</span></span>
          <span class="stat-sub" style="color: ${diffColor}; font-weight: 600;">Difficulty: ${diffLabel}</span>
        </div>
      </div>

      <div class="pitch-details-block">
        <div><strong>Singing Track:</strong> ${target.instrument} (${target.totalNotes} notes total)</div>
        <div style="margin-top: 4px;"><strong>Lowest Note:</strong> ${target.lowestNote.noteName}${lowDegree} in <em>[${target.lowestNote.sectionName}]</em></div>
        <div style="margin-top: 2px;"><strong>Highest Note:</strong> ${target.highestNote.noteName}${highDegree} in <em>[${target.highestNote.sectionName}]</em></div>
        <div class="pitch-details-eval">
          <span>Recommended Voice Classification:</span> <strong>${voiceStr}</strong>
        </div>
      </div>

      <div class="pitch-metric-row">
        <div>
          <div class="stat-label">Center Tessitura (核心音區)</div>
          <div class="span-pill">${avgNoteName}</div>
        </div>
        <div class="pitch-meta">Average vocal pitch</div>
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
