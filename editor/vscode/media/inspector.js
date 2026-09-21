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
      // Prioritize vocal or default to first
      const vocalTrack = ranges.find(r => /vocal|voice|vo|歌/i.test(r.instrument));
      selectedInstrument = vocalTrack ? vocalTrack.instrument : ranges[0].instrument;
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
    container.innerHTML = '<div class="stat-sub">No data for selected instrument.</div>';
    return;
  }

  const octaves = (target.spanSemitones / 12.0).toFixed(1);
  const avgPitch = target.averageMidiPitch.toFixed(1);

  let difficultyHtml = '';
  if (target.difficulty) {
    const diffColorMap = {
      'Easy': '#3fb950',
      'Moderate': '#58a6ff',
      'Challenging': '#d29922',
      'Extreme': '#f85149'
    };
    const diffColor = diffColorMap[target.difficulty] || 'var(--accent-color)';
    difficultyHtml = `
      <div class="pitch-metric-row">
        <div>
          <div class="stat-label">Vocal Difficulty</div>
          <div style="font-weight: 600; font-size: 13px; color: ${diffColor};">${target.difficulty}</div>
        </div>
        <div class="pitch-meta">${target.spanSemitones} semitones span</div>
      </div>
    `;
  }

  let voiceTypesHtml = '';
  if (target.suitableVoiceTypes && target.suitableVoiceTypes.length > 0) {
    const badges = target.suitableVoiceTypes.map(v => `<span class="span-pill" style="font-size: 11px; margin-right: 4px;">${v}</span>`).join('');
    voiceTypesHtml = `
      <div class="pitch-metric-row">
        <div>
          <div class="stat-label">Suitable Voice Types</div>
          <div style="margin-top: 3px;">${badges}</div>
        </div>
        <div class="pitch-meta">Based on pitch range</div>
      </div>
    `;
  }

  container.innerHTML = `
    <div class="pitch-metric-row">
      <div>
        <div class="stat-label">Lowest Pitch</div>
        <div class="pitch-note-badge">${target.lowestNote.noteName} (MIDI ${target.lowestNote.midiPitch})</div>
      </div>
      <div class="pitch-meta">in [${target.lowestNote.sectionName}]</div>
    </div>
    <div class="pitch-metric-row">
      <div>
        <div class="stat-label">Highest Pitch</div>
        <div class="pitch-note-badge">${target.highestNote.noteName} (MIDI ${target.highestNote.midiPitch})</div>
      </div>
      <div class="pitch-meta">in [${target.highestNote.sectionName}]</div>
    </div>
    <div class="pitch-metric-row">
      <div>
        <div class="stat-label">Pitch Span & Tessitura</div>
        <div class="span-pill">${target.spanSemitones} semitones / ${octaves} octaves</div>
      </div>
      <div class="pitch-meta">Avg MIDI: ${avgPitch} · ${target.totalNotes} notes</div>
    </div>
    ${difficultyHtml}
    ${voiceTypesHtml}
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
