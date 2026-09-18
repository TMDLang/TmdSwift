(function () {
    const vscode = acquireVsCodeApi();

    // Initialize JZZ and Tiny synth
    if (typeof JZZ !== 'undefined') {
        try {
            if (typeof synthTiny === 'function') synthTiny(JZZ);
            if (typeof smf === 'function') smf(JZZ);
            JZZ();
        } catch (e) {
            console.warn('[TMD Player] JZZ init warning:', e);
        }
    }

    let tinySynth = null;
    try {
        if (JZZ && JZZ.synth && JZZ.synth.Tiny) {
            tinySynth = JZZ.synth.Tiny();
        }
    } catch (e) {
        console.warn('[TMD Player] TinySynth init warning:', e);
    }

    let audioContext = null;
    let pianoInstrument = null;
    let isPianoLoading = false;
    let soundfontWidget = null;
    let activeNotes = new Map();
    let webMidiPort = null;

    let currentPlayer = null;
    let isPausedState = false;
    let progressTimer = null;
    let currentMidiBytes = null;
    let currentTitle = 'score.mid';
    let isSeeking = false;
    let durationSec = 0;

    // DOM Elements
    const playerIcon = document.getElementById('player-icon');
    const scoreTitle = document.getElementById('score-title');
    const scoreSubtitle = document.getElementById('score-subtitle');
    const timelineSlider = document.getElementById('timeline-slider');
    const currentTimeEl = document.getElementById('current-time');
    const totalTimeEl = document.getElementById('total-time');
    const btnPlayPause = document.getElementById('btn-play-pause');
    const btnStop = document.getElementById('btn-stop');
    const synthSelect = document.getElementById('synth-select');
    const statusText = document.getElementById('status-text');
    const tracksContainer = document.getElementById('tracks-container');

    function formatTime(seconds) {
        if (isNaN(seconds) || seconds < 0) seconds = 0;
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
    }

    function getAudioContext() {
        if (!audioContext) {
            try {
                if (JZZ && JZZ.lib && typeof JZZ.lib.getAudioContext === 'function') {
                    audioContext = JZZ.lib.getAudioContext();
                }
            } catch (_) {}
            if (!audioContext && typeof AudioContext !== 'undefined') {
                audioContext = new AudioContext();
            }
        }
        return audioContext;
    }

    async function loadPianoInstrument() {
        if (pianoInstrument) return pianoInstrument;
        if (isPianoLoading) return null;

        const ctx = getAudioContext();
        if (!ctx) return null;

        isPianoLoading = true;
        setStatus('Loading SoundFont Piano...');
        try {
            if (typeof Soundfont !== 'undefined') {
                pianoInstrument = await Soundfont.instrument(ctx, 'acoustic_grand_piano', {
                    soundfont: 'FluidR3_GM',
                    format: 'mp3'
                });
                setStatus('SoundFont Piano loaded.');
            }
        } catch (err) {
            console.warn('[TMD Player] Failed to load SoundFont piano:', err);
            setStatus('Piano SoundFont unavailable, using TinySynth.');
        } finally {
            isPianoLoading = false;
        }
        return pianoInstrument;
    }

    function stopActiveNotes() {
        for (const [_, node] of activeNotes) {
            try {
                if (node && typeof node.stop === 'function') {
                    node.stop();
                }
            } catch (_) {}
        }
        activeNotes.clear();
    }

    function getSoundfontWidget() {
        if (soundfontWidget) return soundfontWidget;
        soundfontWidget = JZZ.Widget({
            _receive: function (msg) {
                if (!msg || msg.length < 1 || !pianoInstrument) return;
                const status = msg[0] & 0xf0;
                const channel = msg[0] & 0x0f;
                const note = msg[1];
                const velocity = msg[2] || 0;

                if (status === 0x90 && velocity > 0) {
                    const key = (channel << 8) | note;
                    const oldNode = activeNotes.get(key);
                    if (oldNode) {
                        try { oldNode.stop(); } catch (_) {}
                    }
                    const gain = Math.max(0.1, Math.min(1.0, velocity / 127));
                    try {
                        const node = pianoInstrument.play(note, undefined, { gain });
                        if (node) activeNotes.set(key, node);
                    } catch (_) {}
                } else if (status === 0x80 || (status === 0x90 && velocity === 0)) {
                    const key = (channel << 8) | note;
                    const node = activeNotes.get(key);
                    if (node) {
                        try { node.stop(); } catch (_) {}
                        activeNotes.delete(key);
                    }
                } else if (status === 0xb0 && (msg[1] === 120 || msg[1] === 123)) {
                    stopActiveNotes();
                }
            }
        });
        return soundfontWidget;
    }

    function setStatus(msg) {
        if (statusText) statusText.textContent = msg;
    }

    function updatePlayPauseUI(isPlaying) {
        if (btnPlayPause) {
            btnPlayPause.textContent = isPlaying ? '⏸' : '▶';
            btnPlayPause.title = isPlaying ? 'Pause' : 'Play';
        }
        if (playerIcon) {
            if (isPlaying) {
                playerIcon.classList.add('playing');
            } else {
                playerIcon.classList.remove('playing');
            }
        }
    }

    function startProgressTimer() {
        stopProgressTimer();
        progressTimer = setInterval(() => {
            if (currentPlayer && !isPausedState && !isSeeking) {
                try {
                    const posMs = currentPlayer.positionMS() || 0;
                    const posSec = posMs / 1000;
                    timelineSlider.value = posSec.toString();
                    currentTimeEl.textContent = formatTime(posSec);
                } catch (_) {}
            }
        }, 150);
    }

    function stopProgressTimer() {
        if (progressTimer !== null) {
            clearInterval(progressTimer);
            progressTimer = null;
        }
    }

    async function playCurrentMidi() {
        if (!currentMidiBytes) {
            setStatus('No MIDI data loaded.');
            return;
        }

        const ctx = getAudioContext();
        if (ctx && typeof ctx.resume === 'function' && ctx.state === 'suspended') {
            try { await ctx.resume(); } catch (_) {}
        }

        if (currentPlayer) {
            try { currentPlayer.stop(); } catch (_) {}
            currentPlayer = null;
        }
        stopActiveNotes();

        try {
            const smfData = new JZZ.MIDI.SMF(currentMidiBytes);
            const player = smfData.player();
            const synthType = synthSelect.value;

            if (synthType === 'piano') {
                const piano = await loadPianoInstrument();
                if (piano) {
                    player.connect(getSoundfontWidget());
                } else if (tinySynth) {
                    player.connect(tinySynth);
                }
            } else if (synthType === 'webmidi') {
                let connected = false;
                try {
                    if (!webMidiPort) {
                        webMidiPort = await JZZ().openMidiOut();
                    }
                    if (webMidiPort) {
                        player.connect(webMidiPort);
                        connected = true;
                    }
                } catch (e) {
                    console.warn('WebMIDI open failed:', e);
                }
                if (!connected && tinySynth) {
                    player.connect(tinySynth);
                }
            } else {
                // TinySynth
                if (tinySynth) {
                    if (typeof tinySynth.resume === 'function') tinySynth.resume();
                    player.connect(tinySynth);
                }
            }

            durationSec = (player.durationMS() || 0) / 1000;
            timelineSlider.max = Math.max(1, durationSec).toString();
            totalTimeEl.textContent = formatTime(durationSec);

            player.onEnd = () => {
                stopProgressTimer();
                stopActiveNotes();
                isPausedState = false;
                currentPlayer = null;
                updatePlayPauseUI(false);
                timelineSlider.value = '0';
                currentTimeEl.textContent = formatTime(0);
                setStatus('Playback finished.');
            };

            currentPlayer = player;
            isPausedState = false;
            player.play();
            updatePlayPauseUI(true);
            startProgressTimer();
            setStatus('Playing...');
        } catch (err) {
            console.error('[TMD Player] Playback error:', err);
            setStatus(`Playback error: ${err.message}`);
            stopPlayback();
        }
    }

    function pausePlayback() {
        if (currentPlayer && !isPausedState) {
            try {
                currentPlayer.pause();
                isPausedState = true;
                stopProgressTimer();
                stopActiveNotes();
                updatePlayPauseUI(false);
                setStatus('Paused');
            } catch (e) {
                console.warn(e);
            }
        }
    }

    function resumePlayback() {
        if (currentPlayer && isPausedState) {
            try {
                currentPlayer.resume();
                isPausedState = false;
                startProgressTimer();
                updatePlayPauseUI(true);
                setStatus('Playing...');
            } catch (e) {
                console.warn(e);
            }
        }
    }

    function stopPlayback() {
        stopProgressTimer();
        stopActiveNotes();
        if (currentPlayer) {
            try { currentPlayer.stop(); } catch (_) {}
            currentPlayer = null;
        }
        isPausedState = false;
        updatePlayPauseUI(false);
        timelineSlider.value = '0';
        currentTimeEl.textContent = formatTime(0);
        setStatus('Stopped');
    }

    function seek(sec) {
        if (!currentPlayer) return;
        try {
            stopActiveNotes();
            currentPlayer.jumpMS(Math.max(0, sec * 1000));
            currentTimeEl.textContent = formatTime(sec);
        } catch (e) {
            console.warn('Seek error:', e);
        }
    }

    // UI Event Listeners
    btnPlayPause.addEventListener('click', () => {
        if (!currentPlayer) {
            playCurrentMidi();
        } else if (isPausedState) {
            resumePlayback();
        } else {
            pausePlayback();
        }
    });

    btnStop.addEventListener('click', () => {
        stopPlayback();
    });

    timelineSlider.addEventListener('mousedown', () => { isSeeking = true; });
    timelineSlider.addEventListener('touchstart', () => { isSeeking = true; }, { passive: true });

    timelineSlider.addEventListener('input', () => {
        const sec = parseFloat(timelineSlider.value);
        currentTimeEl.textContent = formatTime(sec);
    });

    const commitSeek = () => {
        if (isSeeking) {
            const sec = parseFloat(timelineSlider.value);
            seek(sec);
            isSeeking = false;
        }
    };

    timelineSlider.addEventListener('change', commitSeek);
    timelineSlider.addEventListener('mouseup', commitSeek);
    timelineSlider.addEventListener('touchend', commitSeek);

    synthSelect.addEventListener('change', () => {
        if (currentPlayer && !isPausedState) {
            const currentPos = (currentPlayer.positionMS() || 0) / 1000;
            playCurrentMidi().then(() => {
                if (currentPos > 0) seek(currentPos);
            });
        }
    });

    // Handle messages from VS Code extension host
    window.addEventListener('message', async (event) => {
        const message = event.data;
        switch (message.command) {
            case 'loadMidi': {
                currentTitle = message.title || 'score.mid';
                scoreTitle.textContent = currentTitle;
                scoreSubtitle.textContent = message.sourceFile || 'TMD Score Preview';

                // Decode base64 MIDI data
                const binaryStr = atob(message.base64);
                const bytes = new Uint8Array(binaryStr.length);
                for (let i = 0; i < binaryStr.length; i++) {
                    bytes[i] = binaryStr.charCodeAt(i);
                }
                currentMidiBytes = bytes;

                // Inspect track names if possible
                if (tracksContainer) {
                    tracksContainer.innerHTML = '';
                    if (message.tracks && message.tracks.length > 0) {
                        message.tracks.forEach((track, index) => {
                            const badge = document.createElement('div');
                            badge.className = 'track-badge';
                            badge.innerHTML = `<span>🎵 ${track.name || `Track ${index + 1}`}</span><span style="color: var(--text-muted); font-size: 11px;">${track.instrument || ''}</span>`;
                            tracksContainer.appendChild(badge);
                        });
                    }
                }

                setStatus('MIDI loaded. Ready to play.');
                if (message.autoPlay) {
                    await playCurrentMidi();
                }
                break;
            }
            case 'stop': {
                stopPlayback();
                break;
            }
        }
    });

    // Notify extension host that webview is ready
    vscode.postMessage({ command: 'ready' });
})();
