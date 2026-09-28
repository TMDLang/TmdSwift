"use strict";
(() => {
    const vscode = acquireVsCodeApi();
    const $ = (id) => document.getElementById(id);
    const recordButton = $('hum-record');
    const status = $('hum-status');
    const result = $('hum-result');
    const applyButton = $('hum-apply');
    const previewButton = $('hum-preview');
    const keyBadge = $('hum-key-badge');
    let recording = false;
    let countInTimer = null;
    let metronomeTimer = null;
    let clickContext = null;
    function setStatus(message, error = false) {
        if (status)
            status.textContent = message;
        status?.classList.toggle('hum-error', error);
    }
    function bpm() { return Math.max(20, Number($('hum-bpm').value) || 120); }
    function beatsPerMeasure() { return 4; }
    function clickSound(first) {
        try {
            clickContext || (clickContext = new (window.AudioContext || window.webkitAudioContext)());
            const oscillator = clickContext.createOscillator();
            const gain = clickContext.createGain();
            oscillator.frequency.value = first ? 880 : 440;
            gain.gain.setValueAtTime(0.25, clickContext.currentTime);
            gain.gain.exponentialRampToValueAtTime(0.001, clickContext.currentTime + 0.05);
            oscillator.connect(gain).connect(clickContext.destination);
            oscillator.start();
            oscillator.stop(clickContext.currentTime + 0.05);
        }
        catch (_) { /* Audio preview is optional. */ }
    }
    function stopTimers() {
        if (countInTimer)
            clearTimeout(countInTimer);
        if (metronomeTimer)
            clearInterval(metronomeTimer);
        countInTimer = null;
        metronomeTimer = null;
    }
    function startMetronome() {
        if (!$('hum-metronome').checked)
            return;
        const interval = 60000 / bpm();
        let beat = 0;
        clickSound(true);
        metronomeTimer = setInterval(() => {
            beat = (beat + 1) % beatsPerMeasure();
            clickSound(beat === 0);
        }, interval);
    }
    function stopRecording() {
        stopTimers();
        if (recording)
            vscode.postMessage({ command: 'stopHummingRecording' });
        recording = false;
        recordButton.textContent = '🎙️ Start recording';
    }
    async function resampleAudioBuffer(buffer, targetRate = 22050) {
        if (buffer.sampleRate === targetRate)
            return buffer;
        const OfflineContext = window.OfflineAudioContext || window.webkitOfflineAudioContext;
        const context = new OfflineContext(1, Math.ceil(buffer.duration * targetRate), targetRate);
        const source = context.createBufferSource();
        source.buffer = buffer;
        source.connect(context.destination);
        source.start(0);
        return context.startRendering();
    }
    function toMonophonic(events) {
        const ordered = [...events].sort((a, b) => a.startTimeSeconds - b.startTimeSeconds);
        const output = [];
        for (const event of ordered) {
            if (!output.length) {
                output.push(event);
                continue;
            }
            const previous = output[output.length - 1];
            const previousEnd = previous.startTimeSeconds + previous.durationSeconds;
            if (event.startTimeSeconds < previousEnd - 0.08) {
                if (event.amplitude > previous.amplitude) {
                    if (event.startTimeSeconds <= previous.startTimeSeconds + 0.08)
                        output[output.length - 1] = event;
                    else {
                        previous.durationSeconds = Math.max(0.08, event.startTimeSeconds - previous.startTimeSeconds);
                        output.push(event);
                    }
                }
            }
            else
                output.push(event);
        }
        return output;
    }
    async function transcribe(blob) {
        setStatus('Transcribing with Spotify Basic Pitch…');
        const audioContext = new (window.AudioContext || window.webkitAudioContext)();
        const decoded = await audioContext.decodeAudioData(await blob.arrayBuffer());
        const audio = await resampleAudioBuffer(decoded);
        // The webview loads Basic Pitch from the browser's ESM loader at runtime.
        // @ts-ignore: TypeScript does not resolve remote HTTPS modules.
        const basicPitchModule = await import('https://esm.sh/@spotify/basic-pitch@1.0.1?bundle');
        const basicPitch = new basicPitchModule.BasicPitch('https://unpkg.com/@spotify/basic-pitch@1.0.1/model/model.json');
        const frames = [];
        const onsets = [];
        const contours = [];
        await basicPitch.evaluateModel(audio, (frame, onset, contour) => {
            frames.push(...frame);
            onsets.push(...onset);
            contours.push(...contour);
        }, () => undefined);
        const notes = basicPitchModule.outputToNotesPoly(frames, onsets, 0.5, 0.35, 11);
        const events = toMonophonic(basicPitchModule.noteFramesToTime(notes));
        const selectedKey = $('hum-key').value === 'AUTO' ? window.TMDHummingQuantizer.detectTonicAndScale(events) : $('hum-key').value;
        keyBadge.textContent = `Detected key: ${selectedKey}`;
        result.value = window.TMDHummingQuantizer.quantizeNoteEventsToTmdSection(events, {
            sectionName: $('hum-section').value.trim() || 'hummed', instrument: $('hum-instrument').value.trim() || 'Vocal',
            bpm: bpm(), grid: Number($('hum-grid').value), key: selectedKey, snapToScale: $('hum-snap').checked, beatsPerMeasure: beatsPerMeasure(),
        });
        applyButton.disabled = false;
        previewButton.disabled = false;
        setStatus('Transcribed successfully. Review the TMD before inserting it.');
    }
    function startRecording() {
        const begin = () => {
            vscode.postMessage({ command: 'startHummingRecording' });
            recording = true;
            recordButton.disabled = false;
            recordButton.textContent = '⏹ Stop and transcribe';
            setStatus('Recording… hum or sing a melody, then stop.');
            startMetronome();
        };
        if ($('hum-count-in').checked) {
            let count = 1;
            const tick = () => { clickSound(count === 1); setStatus(`Count-in: beat ${count}`); if (count++ < 4)
                countInTimer = setTimeout(tick, 60000 / bpm());
            else
                countInTimer = setTimeout(begin, 60000 / bpm()); };
            tick();
        }
        else
            begin();
    }
    window.addEventListener('message', (event) => {
        const message = event.data;
        if (message.command === 'hummingRecordingError') {
            stopTimers();
            recording = false;
            recordButton.disabled = false;
            recordButton.textContent = '🎙️ Start recording';
            setStatus(`Microphone unavailable: ${message.error || 'Permission denied.'}`, true);
        }
        if (message.command === 'hummingRecordingReady' && message.audio) {
            recording = false;
            try {
                const bytes = message.audio instanceof Uint8Array ? message.audio : new Uint8Array(message.audio);
                const audioBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
                void transcribe(new Blob([audioBuffer], { type: 'audio/wav' }));
            }
            catch (error) {
                setStatus(`Recording or transcription error: ${error.message || error}`, true);
                recordButton.disabled = false;
            }
        }
    });
    recordButton.addEventListener('click', async () => {
        if (recording) {
            stopRecording();
            return;
        }
        recordButton.disabled = true;
        startRecording();
    });
    $('hum-cancel').addEventListener('click', () => { stopRecording(); vscode.postMessage({ command: 'closeHummingPanel' }); });
    previewButton.addEventListener('click', () => vscode.postMessage({ command: 'previewHummingTmd', tmd: result.value }));
    applyButton.addEventListener('click', () => vscode.postMessage({ command: 'insertHummingTmd', tmd: result.value }));
    window.addEventListener('beforeunload', stopRecording);
    setStatus('Click Start recording and hum a melody (2–8 measures recommended).');
})();
