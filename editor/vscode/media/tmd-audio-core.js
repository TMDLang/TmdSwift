/**
 * TMD Audio Core Engine (Shared Web Audio / MIDI Player)
 * Compatible with Song Inspector Webview and Markdown Preview Embeds.
 * Uses JZZ.js, JZZ.synth.Tiny.js (pure offline synthesis), and optional SoundFont fallback.
 */
(function (global) {
    class TMDAudioCore {
        constructor(options = {}) {
            this.options = Object.assign({
                defaultSynth: 'tiny', // 'tiny' or 'soundfont'
                onProgress: null,
                onStateChange: null,
                onEnded: null,
                onNote: null
            }, options);

            this.audioContext = null;
            this.tinySynth = null;
            this.smf = null;
            this.player = null;
            this.durationSec = 0;
            this.totalTicks = 0;
            this.state = 'stopped'; // 'playing', 'paused', 'stopped'
            this.progressTimer = null;
            this.midiBytes = null;
            this._jzzInitialized = false;
        }

        _initJZZ() {
            if (this._jzzInitialized) return;
            this._jzzInitialized = true;
            if (typeof JZZ !== 'undefined') {
                try {
                    if (typeof synthTiny === 'function') synthTiny(JZZ);
                    if (typeof smf === 'function') smf(JZZ);
                    JZZ();
                    if (JZZ.synth && JZZ.synth.Tiny) {
                        this.tinySynth = JZZ.synth.Tiny();
                    }
                } catch (e) {
                    console.warn('[TMDAudioCore] JZZ initialization note:', e);
                }
            }
        }

        getAudioContext() {
            this._initJZZ();
            if (!this.audioContext) {
                try {
                    if (typeof JZZ !== 'undefined' && JZZ.lib && typeof JZZ.lib.getAudioContext === 'function') {
                        this.audioContext = JZZ.lib.getAudioContext();
                    }
                } catch (_) {}
                if (!this.audioContext && typeof AudioContext !== 'undefined') {
                    this.audioContext = new AudioContext();
                } else if (!this.audioContext && typeof webkitAudioContext !== 'undefined') {
                    this.audioContext = new webkitAudioContext();
                }
            }
            if (this.audioContext && this.audioContext.state === 'suspended') {
                this.audioContext.resume().catch(() => {});
            }
            return this.audioContext;
        }

        loadMidiBase64(base64Str) {
            this.stop();
            try {
                this._initJZZ();
                const binaryStr = atob(base64Str);
                if (typeof JZZ === 'undefined' || !JZZ.MIDI || !JZZ.MIDI.SMF) {
                    throw new Error('JZZ MIDI SMF parser not available');
                }
                this.smf = new JZZ.MIDI.SMF(binaryStr);
                this.player = this.smf.player();
                
                // Connect to TinySynth
                if (this.tinySynth) {
                    this.player.connect(this.tinySynth);
                }

                // Compute duration
                const durMs = (typeof this.player.durationMS === 'function')
                    ? this.player.durationMS()
                    : (this.player.duration ? this.player.duration() : 0);
                this.durationSec = durMs > 0 ? (durMs / 1000) : 0;
                this.totalTicks = (typeof this.player.duration === 'function') ? this.player.duration() : 0;

                // Handle onEnded
                this.player.on('end', () => {
                    this._setState('stopped');
                    this._stopProgressTimer();
                    if (this.options.onProgress) {
                        this.options.onProgress(this.durationSec, this.durationSec, 1.0);
                    }
                    if (this.options.onEnded) {
                        this.options.onEnded();
                    }
                });

                return {
                    durationSec: this.durationSec,
                    totalTicks: this.totalTicks
                };
            } catch (err) {
                console.error('[TMDAudioCore] Failed to load MIDI base64:', err);
                return null;
            }
        }

        play() {
            this.getAudioContext();
            if (!this.player) return;

            try {
                if (this.state === 'paused') {
                    this.player.resume();
                } else {
                    this.player.play();
                }
                this._setState('playing');
                this._startProgressTimer();
            } catch (err) {
                console.error('[TMDAudioCore] Error during play:', err);
            }
        }

        pause() {
            if (!this.player || this.state !== 'playing') return;
            try {
                this.player.pause();
                this._setState('paused');
                this._stopProgressTimer();
            } catch (err) {
                console.error('[TMDAudioCore] Error during pause:', err);
            }
        }

        stop() {
            if (!this.player) return;
            try {
                this.player.stop();
                this._setState('stopped');
                this._stopProgressTimer();
                if (this.options.onProgress) {
                    this.options.onProgress(0, this.durationSec, 0);
                }
            } catch (err) {
                console.error('[TMDAudioCore] Error during stop:', err);
            }
        }

        seekFraction(fraction) {
            if (!this.player) return;
            fraction = Math.max(0, Math.min(1, fraction));
            try {
                const targetTick = Math.floor(fraction * this.totalTicks);
                this.player.jump(targetTick);
                const currentSec = fraction * this.durationSec;
                if (this.options.onProgress) {
                    this.options.onProgress(currentSec, this.durationSec, fraction);
                }
            } catch (err) {
                console.warn('[TMDAudioCore] Seek failed:', err);
            }
        }

        _setState(newState) {
            this.state = newState;
            if (this.options.onStateChange) {
                this.options.onStateChange(newState);
            }
        }

        _startProgressTimer() {
            this._stopProgressTimer();
            this.progressTimer = setInterval(() => {
                if (!this.player || this.state !== 'playing') return;
                const posMs = (typeof this.player.positionMS === 'function') ? this.player.positionMS() : 0;
                const currentSec = posMs / 1000;
                const fraction = this.durationSec > 0 ? Math.min(1, currentSec / this.durationSec) : 0;
                if (this.options.onProgress) {
                    this.options.onProgress(currentSec, this.durationSec, fraction);
                }
            }, 80);
        }

        _stopProgressTimer() {
            if (this.progressTimer) {
                clearInterval(this.progressTimer);
                this.progressTimer = null;
            }
        }

        static formatTime(seconds) {
            if (isNaN(seconds) || seconds < 0) seconds = 0;
            const mins = Math.floor(seconds / 60);
            const secs = Math.floor(seconds % 60);
            return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
        }
    }

    global.TMDAudioCore = TMDAudioCore;
})(typeof window !== 'undefined' ? window : this);
