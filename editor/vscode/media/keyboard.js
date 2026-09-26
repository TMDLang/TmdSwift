(function () {
    const vscode = acquireVsCodeApi();

    if (typeof installSoundfontFetchCache === 'function' && typeof loadAudio !== 'undefined') {
        installSoundfontFetchCache(loadAudio, { version: '1' });
    }

    let audioContext = null;
    let pianoInstrument = null;
    let isPianoLoading = false;
    const activeNotes = new Map();
    const auditionOscMap = new Map();

    let baseOctave = 4;
    let currentKeySig = 'C';
    let keyboardMode = 'audition'; // 'audition' | 'insert'

    // DOM Elements
    const keyboardContainer = document.getElementById('keyboard-container');
    const keyboardKeysContainer = document.getElementById('keyboard-keys-container');
    const keyboardKeyBadge = document.getElementById('keyboard-key-badge');
    const btnModeAudition = document.getElementById('btn-mode-audition');
    const btnModeInsert = document.getElementById('btn-mode-insert');
    const btnOctaveDown = document.getElementById('btn-octave-down');
    const btnOctaveUp = document.getElementById('btn-octave-up');
    const octaveDisplay = document.getElementById('octave-display');

    function getAudioContext() {
        if (!audioContext) {
            try {
                if (typeof AudioContext !== 'undefined') {
                    audioContext = new AudioContext();
                }
            } catch (_) {}
        }
        return audioContext;
    }

    async function loadPianoInstrument() {
        if (pianoInstrument) return pianoInstrument;
        if (isPianoLoading) return null;

        const ctx = getAudioContext();
        if (!ctx || typeof Soundfont === 'undefined') return null;

        isPianoLoading = true;
        try {
            pianoInstrument = await Soundfont.instrument(ctx, 'acoustic_grand_piano', {
                soundfont: 'FluidR3_GM',
                format: 'mp3'
            });
        } catch (err) {
            console.warn('[TMD Keyboard] Failed to load Soundfont piano:', err);
        } finally {
            isPianoLoading = false;
        }
        return pianoInstrument;
    }

    async function playAuditionNote(midiPitch, velocity = 80) {
        const ctx = getAudioContext();
        if (ctx && typeof ctx.resume === 'function' && ctx.state === 'suspended') {
            try { await ctx.resume(); } catch (_) {}
        }

        let playedWithSoundfont = false;
        try {
            if (!pianoInstrument && !isPianoLoading) {
                loadPianoInstrument().catch(() => {});
            }
            if (pianoInstrument) {
                const gain = Math.max(0.1, Math.min(1.0, velocity / 127));
                const auditionKey = 0x9900 | midiPitch;
                const prev = activeNotes.get(auditionKey);
                if (prev && typeof prev.stop === 'function') {
                    try { prev.stop(); } catch (_) {}
                }
                const node = pianoInstrument.play(midiPitch, undefined, { gain });
                if (node) {
                    activeNotes.set(auditionKey, node);
                    playedWithSoundfont = true;
                }
            }
        } catch (err) {
            console.warn('[TMD Keyboard] Soundfont play error:', err);
        }

        if (!playedWithSoundfont && ctx) {
            try {
                const freq = 440 * Math.pow(2, (midiPitch - 69) / 12);
                const now = ctx.currentTime;
                stopAuditionOscNote(midiPitch);

                const osc = ctx.createOscillator();
                const gain = ctx.createGain();
                osc.type = 'triangle';
                osc.frequency.setValueAtTime(freq, now);

                const targetGain = Math.max(0.05, Math.min(0.3, (velocity / 127) * 0.3));
                gain.gain.setValueAtTime(0.0001, now);
                gain.gain.linearRampToValueAtTime(targetGain, now + 0.01);

                osc.connect(gain);
                gain.connect(ctx.destination);
                osc.start(now);
                auditionOscMap.set(midiPitch, { osc, gain });
            } catch (err) {
                console.warn('[TMD Keyboard] Oscillator audition failed:', err);
            }
        }
    }

    function stopAuditionOscNote(midiPitch) {
        const existing = auditionOscMap.get(midiPitch);
        if (existing) {
            try {
                const ctx = getAudioContext();
                const now = ctx ? ctx.currentTime : 0;
                existing.gain.gain.linearRampToValueAtTime(0.0001, now + 0.05);
                setTimeout(() => {
                    try { existing.osc.stop(); } catch (_) {}
                }, 60);
            } catch (_) {}
            auditionOscMap.delete(midiPitch);
        }
    }

    function stopAuditionNote(midiPitch) {
        const auditionKey = 0x9900 | midiPitch;
        const node = activeNotes.get(auditionKey);
        if (node) {
            try {
                if (typeof node.stop === 'function') node.stop();
            } catch (_) {}
            activeNotes.delete(auditionKey);
        }
        stopAuditionOscNote(midiPitch);
    }

    function updateModeUI() {
        if (btnModeAudition && btnModeInsert) {
            if (keyboardMode === 'audition') {
                btnModeAudition.classList.add('active');
                btnModeInsert.classList.remove('active');
            } else {
                btnModeAudition.classList.remove('active');
                btnModeInsert.classList.add('active');
            }
        }
    }

    function renderKeyboard() {
        if (!keyboardContainer || !keyboardKeysContainer) return;

        updateModeUI();

        const containerWidth = keyboardContainer.clientWidth || window.innerWidth || 600;
        const whiteKeyCount = (typeof calculateWhiteKeyCountForWidth === 'function')
            ? calculateWhiteKeyCountForWidth(containerWidth)
            : 18;

        const keys = (typeof generateDynamicKeyboardKeys === 'function')
            ? generateDynamicKeyboardKeys(baseOctave, whiteKeyCount, currentKeySig)
            : [];

        if (keys.length > 0 && octaveDisplay) {
            octaveDisplay.textContent = `${keys[0].noteName}-${keys[keys.length - 1].noteName}`;
        }
        if (keyboardKeyBadge) {
            keyboardKeyBadge.textContent = `Key: ${currentKeySig}`;
        }

        keyboardKeysContainer.innerHTML = '';
        const pianoWrapper = document.createElement('div');
        pianoWrapper.className = 'piano-keys-wrapper';

        keys.forEach(key => {
            const keyEl = document.createElement('button');
            keyEl.type = 'button';
            keyEl.className = `piano-key ${key.isBlack ? 'black-key' : 'white-key'}`;
            keyEl.dataset.midi = String(key.midi);
            keyEl.dataset.noteName = key.noteName;
            keyEl.dataset.tmdNote = key.tmdNote;

            keyEl.innerHTML = `
                <div class="key-labels">
                  <span class="key-degree">${key.degreeLabel}</span>
                  <span class="key-notename">${key.noteName}</span>
                </div>
            `;

            const handlePress = (e) => {
                e.preventDefault();
                keyEl.classList.add('active');
                playAuditionNote(key.midi);
                if (keyboardMode === 'insert') {
                    vscode.postMessage({
                        command: 'insertNote',
                        note: key.tmdNote
                    });
                }
            };

            const handleRelease = (e) => {
                e.preventDefault();
                keyEl.classList.remove('active');
                stopAuditionNote(key.midi);
            };

            keyEl.addEventListener('mousedown', handlePress);
            keyEl.addEventListener('mouseup', handleRelease);
            keyEl.addEventListener('mouseleave', handleRelease);

            keyEl.addEventListener('touchstart', handlePress, { passive: false });
            keyEl.addEventListener('touchend', handleRelease);
            keyEl.addEventListener('touchcancel', handleRelease);

            pianoWrapper.appendChild(keyEl);
        });

        keyboardKeysContainer.appendChild(pianoWrapper);
    }

    function initEvents() {
        if (btnModeAudition) {
            btnModeAudition.addEventListener('click', (e) => {
                e.stopPropagation();
                keyboardMode = 'audition';
                updateModeUI();
            });
        }
        if (btnModeInsert) {
            btnModeInsert.addEventListener('click', (e) => {
                e.stopPropagation();
                keyboardMode = 'insert';
                updateModeUI();
            });
        }

        if (btnOctaveDown) {
            btnOctaveDown.addEventListener('click', (e) => {
                e.stopPropagation();
                if (baseOctave > 1) {
                    baseOctave--;
                    renderKeyboard();
                }
            });
        }
        if (btnOctaveUp) {
            btnOctaveUp.addEventListener('click', (e) => {
                e.stopPropagation();
                if (baseOctave < 6) {
                    baseOctave++;
                    renderKeyboard();
                }
            });
        }

        if (typeof ResizeObserver !== 'undefined') {
            const ro = new ResizeObserver(() => {
                renderKeyboard();
            });
            ro.observe(keyboardContainer);
        }

        window.addEventListener('message', event => {
            const message = event.data;
            if (message.command === 'updateKeySignature') {
                if (message.keySignature && message.keySignature !== currentKeySig) {
                    currentKeySig = message.keySignature;
                    renderKeyboard();
                }
            }
        });

        // Preload piano soundfont
        loadPianoInstrument().catch(() => {});
        renderKeyboard();
    }

    initEvents();
    vscode.postMessage({ command: 'ready' });
})();
