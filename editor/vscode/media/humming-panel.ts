declare const acquireVsCodeApi: () => { postMessage(message: { command: string; tmd?: string }): void };

type Quantizer = {
  detectTonicAndScale(events: Array<unknown>): string;
  quantizeNoteEventsToTmdSection(events: Array<unknown>, options: Record<string, unknown>): string;
};

interface Window {
  TMDHummingQuantizer: Quantizer;
  webkitAudioContext?: typeof AudioContext;
  webkitOfflineAudioContext?: typeof OfflineAudioContext;
}

type BasicPitchModule = {
  BasicPitch: new (modelUrl: string) => {
    evaluateModel(audio: AudioBuffer, onData: (frame: number[], onset: number[], contour: number[]) => void, onProgress: (progress: number) => void): Promise<void>;
  };
  outputToNotesPoly(frames: number[], onsets: number[], onsetThreshold: number, frameThreshold: number, minNoteLength: number): unknown[];
  noteFramesToTime(notes: unknown[]): Array<{ startTimeSeconds: number; durationSeconds: number; pitchMidi: number; amplitude: number }>;
};

(() => {
  const vscode = acquireVsCodeApi();
  const $ = (id: string) => document.getElementById(id) as HTMLInputElement;
  const recordButton = $('hum-record') as HTMLButtonElement;
  const status = $('hum-status');
  const result = $('hum-result') as unknown as HTMLTextAreaElement;
  const applyButton = $('hum-apply') as HTMLButtonElement;
  const previewButton = $('hum-preview') as HTMLButtonElement;
  const keyBadge = $('hum-key-badge');
  let recorder: MediaRecorder | null = null;
  let stream: MediaStream | null = null;
  let chunks: Blob[] = [];
  let recording = false;
  let countInTimer: ReturnType<typeof setTimeout> | null = null;
  let metronomeTimer: ReturnType<typeof setInterval> | null = null;
  let clickContext: AudioContext | null = null;

  function setStatus(message: string, error = false): void {
    if (status) status.textContent = message;
    status?.classList.toggle('hum-error', error);
  }

  function bpm(): number { return Math.max(20, Number($('hum-bpm').value) || 120); }
  function beatsPerMeasure(): number { return 4; }

  function clickSound(first: boolean): void {
    try {
      clickContext ||= new (window.AudioContext || window.webkitAudioContext!)();
      const oscillator = clickContext.createOscillator();
      const gain = clickContext.createGain();
      oscillator.frequency.value = first ? 880 : 440;
      gain.gain.setValueAtTime(0.25, clickContext.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, clickContext.currentTime + 0.05);
      oscillator.connect(gain).connect(clickContext.destination);
      oscillator.start();
      oscillator.stop(clickContext.currentTime + 0.05);
    } catch (_) { /* Audio preview is optional. */ }
  }

  function stopTimers(): void {
    if (countInTimer) clearTimeout(countInTimer);
    if (metronomeTimer) clearInterval(metronomeTimer);
    countInTimer = null;
    metronomeTimer = null;
  }

  function startMetronome(): void {
    if (!$('hum-metronome').checked) return;
    const interval = 60000 / bpm();
    let beat = 0;
    clickSound(true);
    metronomeTimer = setInterval(() => {
      beat = (beat + 1) % beatsPerMeasure();
      clickSound(beat === 0);
    }, interval);
  }

  function stopRecording(): void {
    stopTimers();
    if (recorder && recorder.state !== 'inactive') recorder.stop();
    stream?.getTracks().forEach((track) => track.stop());
    stream = null;
    recording = false;
    recordButton.textContent = '🎙️ Start recording';
  }

  async function resampleAudioBuffer(buffer: AudioBuffer, targetRate = 22050): Promise<AudioBuffer> {
    if (buffer.sampleRate === targetRate) return buffer;
    const OfflineContext = window.OfflineAudioContext || window.webkitOfflineAudioContext!;
    const context = new OfflineContext(1, Math.ceil(buffer.duration * targetRate), targetRate);
    const source = context.createBufferSource();
    source.buffer = buffer;
    source.connect(context.destination);
    source.start(0);
    return context.startRendering();
  }

  function toMonophonic<T extends { startTimeSeconds: number; durationSeconds: number; amplitude: number }>(events: T[]): T[] {
    const ordered = [...events].sort((a, b) => a.startTimeSeconds - b.startTimeSeconds);
    const output: T[] = [];
    for (const event of ordered) {
      if (!output.length) { output.push(event); continue; }
      const previous = output[output.length - 1];
      const previousEnd = previous.startTimeSeconds + previous.durationSeconds;
      if (event.startTimeSeconds < previousEnd - 0.08) {
        if (event.amplitude > previous.amplitude) {
          if (event.startTimeSeconds <= previous.startTimeSeconds + 0.08) output[output.length - 1] = event;
          else {
            previous.durationSeconds = Math.max(0.08, event.startTimeSeconds - previous.startTimeSeconds);
            output.push(event);
          }
        }
      } else output.push(event);
    }
    return output;
  }

  async function transcribe(blob: Blob): Promise<void> {
    setStatus('Transcribing with Spotify Basic Pitch…');
    const audioContext = new (window.AudioContext || window.webkitAudioContext!)();
    const decoded = await audioContext.decodeAudioData(await blob.arrayBuffer());
    const audio = await resampleAudioBuffer(decoded);
    // The webview loads Basic Pitch from the browser's ESM loader at runtime.
    // @ts-ignore: TypeScript does not resolve remote HTTPS modules.
    const basicPitchModule = await import('https://esm.sh/@spotify/basic-pitch@1.0.1?bundle') as unknown as BasicPitchModule;
    const basicPitch = new basicPitchModule.BasicPitch('https://unpkg.com/@spotify/basic-pitch@1.0.1/model/model.json');
    const frames: number[] = [];
    const onsets: number[] = [];
    const contours: number[] = [];
    await basicPitch.evaluateModel(audio, (frame, onset, contour) => {
      frames.push(...frame); onsets.push(...onset); contours.push(...contour);
    }, () => undefined);
    const notes = basicPitchModule.outputToNotesPoly(frames, onsets, 0.5, 0.35, 11);
    const events = toMonophonic(basicPitchModule.noteFramesToTime(notes));
    const selectedKey = $('hum-key').value === 'AUTO' ? window.TMDHummingQuantizer.detectTonicAndScale(events) : $('hum-key').value;
    keyBadge!.textContent = `Detected key: ${selectedKey}`;
    result.value = window.TMDHummingQuantizer.quantizeNoteEventsToTmdSection(events, {
      sectionName: $('hum-section').value.trim() || 'hummed', instrument: $('hum-instrument').value.trim() || 'Vocal',
      bpm: bpm(), grid: Number($('hum-grid').value), key: selectedKey, snapToScale: $('hum-snap').checked, beatsPerMeasure: beatsPerMeasure(),
    });
    applyButton.disabled = false;
    previewButton.disabled = false;
    setStatus('Transcribed successfully. Review the TMD before inserting it.');
  }

  async function startRecording(): Promise<void> {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    chunks = [];
    recorder = new MediaRecorder(stream);
    recorder.ondataavailable = (event) => { if (event.data.size) chunks.push(event.data); };
    recorder.onstop = async () => {
      try { await transcribe(new Blob(chunks, { type: recorder?.mimeType || 'audio/webm' })); }
      catch (error) { setStatus(`Recording or transcription error: ${(error as Error).message || error}`, true); }
      finally { recordButton.disabled = false; }
    };
    const begin = () => {
      recorder!.start(); recording = true; recordButton.textContent = '⏹ Stop and transcribe';
      setStatus('Recording… hum or sing a melody, then stop.'); startMetronome();
    };
    if ($('hum-count-in').checked) {
      let count = 1;
      const tick = () => { clickSound(count === 1); setStatus(`Count-in: beat ${count}`); if (count++ < 4) countInTimer = setTimeout(tick, 60000 / bpm()); else countInTimer = setTimeout(begin, 60000 / bpm()); };
      tick();
    } else begin();
  }

  recordButton.addEventListener('click', async () => {
    if (recording) { stopRecording(); return; }
    recordButton.disabled = true;
    try { await startRecording(); } catch (error) { stopRecording(); recordButton.disabled = false; setStatus(`Microphone unavailable: ${(error as Error).message || error}`, true); }
  });
  $('hum-cancel').addEventListener('click', () => { stopRecording(); vscode.postMessage({ command: 'closeHummingPanel' }); });
  previewButton.addEventListener('click', () => vscode.postMessage({ command: 'previewHummingTmd', tmd: result.value }));
  applyButton.addEventListener('click', () => vscode.postMessage({ command: 'insertHummingTmd', tmd: result.value }));
  window.addEventListener('beforeunload', stopRecording);
  setStatus('Click Start recording and hum a melody (2–8 measures recommended).');
})();
