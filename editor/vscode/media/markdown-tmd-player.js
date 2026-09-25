/**
 * TMD Markdown Embed Player Script
 * Runs in VS Code Markdown Preview webview.
 * Coordinates audio playback using TMDAudioCore with lazy initialization and single-active-player enforcement.
 */
(function () {
    let vscode = null;
    try {
        if (typeof acquireVsCodeApi === 'function') {
            vscode = acquireVsCodeApi();
        }
    } catch (_) {
        // acquireVsCodeApi already acquired by VS Code markdown system
    }

    let activePlayer = null;

    function initTmdCards() {
        try {
            const cards = document.querySelectorAll('.tmd-markdown-card:not([data-initialized])');
            cards.forEach((card) => {
                card.setAttribute('data-initialized', 'true');
                setupCard(card);
            });
        } catch (e) {
            console.warn('[TMD Player] initTmdCards error:', e);
        }
    }

    function setupCard(card) {
        try {
            const midiBase64 = card.getAttribute('data-midi');
            const encodedTmd = card.getAttribute('data-tmd');
            let tmdContent = '';
            try {
                tmdContent = decodeURIComponent(encodedTmd || '');
            } catch (_) {
                tmdContent = encodedTmd || '';
            }

            const btnPlay = card.querySelector('.tmd-btn-play');
            const btnStop = card.querySelector('.tmd-btn-stop');
            const btnOpen = card.querySelector('.tmd-btn-open');
            const slider = card.querySelector('.tmd-slider');
            const timeDisplay = card.querySelector('.tmd-time-display');

            if (!midiBase64) {
                if (btnPlay) {
                    btnPlay.disabled = true;
                    btnPlay.title = 'No MIDI data available';
                }
                return;
            }

            let audioCore = null;

            function getOrCreateAudioCore() {
                if (!audioCore && window.TMDAudioCore) {
                    audioCore = new window.TMDAudioCore({
                        onProgress: (currentSec, totalSec, fraction) => {
                            if (slider && !slider.matches(':active')) {
                                slider.value = Math.floor(fraction * 1000);
                            }
                            if (timeDisplay) {
                                timeDisplay.textContent = `${window.TMDAudioCore.formatTime(currentSec)} / ${window.TMDAudioCore.formatTime(totalSec)}`;
                            }
                        },
                        onStateChange: (state) => {
                            if (!btnPlay) return;
                            const icon = btnPlay.querySelector('.tmd-btn-icon');
                            const label = btnPlay.querySelector('.tmd-btn-label');
                            if (state === 'playing') {
                                if (icon) icon.textContent = '⏸';
                                if (label) label.textContent = 'Pause';
                            } else {
                                if (icon) icon.textContent = '▶';
                                if (label) label.textContent = 'Play';
                            }
                        },
                        onEnded: () => {
                            if (activePlayer === audioCore) {
                                activePlayer = null;
                            }
                        }
                    });
                    const info = audioCore.loadMidiBase64(midiBase64);
                    if (info && timeDisplay) {
                        timeDisplay.textContent = `00:00 / ${window.TMDAudioCore.formatTime(info.durationSec)}`;
                    }
                }
                return audioCore;
            }

            // Play/Pause button
            if (btnPlay) {
                btnPlay.addEventListener('click', () => {
                    try {
                        const core = getOrCreateAudioCore();
                        if (!core) return;

                        if (core.state === 'playing') {
                            core.pause();
                        } else {
                            if (activePlayer && activePlayer !== core) {
                                activePlayer.stop();
                            }
                            activePlayer = core;
                            core.play();
                        }
                    } catch (err) {
                        console.error('[TMD Player] Play error:', err);
                    }
                });
            }

            // Stop button
            if (btnStop) {
                btnStop.addEventListener('click', () => {
                    try {
                        if (audioCore) {
                            audioCore.stop();
                        }
                        if (activePlayer === audioCore) {
                            activePlayer = null;
                        }
                    } catch (err) {
                        console.error('[TMD Player] Stop error:', err);
                    }
                });
            }

            // Timeline slider
            if (slider) {
                slider.addEventListener('input', (e) => {
                    try {
                        const core = getOrCreateAudioCore();
                        if (core) {
                            const fraction = parseInt(e.target.value, 10) / 1000;
                            core.seekFraction(fraction);
                        }
                    } catch (_) {}
                });
            }

            // Try in Editor button
            if (btnOpen) {
                btnOpen.addEventListener('click', (e) => {
                    e.preventDefault();
                    if (vscode) {
                        vscode.postMessage({
                            command: 'tmd.openEmbeddedSnippet',
                            text: tmdContent
                        });
                    } else if (navigator.clipboard && navigator.clipboard.writeText) {
                        navigator.clipboard.writeText(tmdContent).then(() => {
                            const originalText = btnOpen.innerHTML;
                            btnOpen.innerHTML = '<span>✓ Copied to Clipboard</span>';
                            setTimeout(() => {
                                btnOpen.innerHTML = originalText;
                            }, 2000);
                        }).catch(() => {});
                    }
                });
            }
        } catch (e) {
            console.warn('[TMD Player] setupCard error:', e);
        }
    }

    // Safely wait for document.body to be ready before initializing or observing
    function startObserving() {
        if (document.body) {
            initTmdCards();
            try {
                const observer = new MutationObserver(() => {
                    initTmdCards();
                });
                observer.observe(document.body, { childList: true, subtree: true });
            } catch (e) {
                console.warn('[TMD Player] MutationObserver note:', e);
            }
        } else {
            window.addEventListener('DOMContentLoaded', startObserving);
        }
    }

    if (document.readyState === 'loading') {
        window.addEventListener('DOMContentLoaded', startObserving);
    } else {
        startObserving();
    }
})();
