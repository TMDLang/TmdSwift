# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.6] - 2026-09-19

### Added
- **Song Profile & Inspector (`tmd inspect`)**:
  - Added `TMDSongInspector` providing song timeline analysis, section durations in seconds and measures, peak track arrangement density, chord vocabulary, and vocal/instrument pitch ranges with exact highest/lowest notes, semitones, and octave spans.
  - Added `tmd inspect <file> [--json]` command for terminal output and automated JSON pipelines.
  - Added VS Code extension integration with `tmd.inspectSong`, LM Tool `tmd_inspect`, and `@tmd /inspect` Copilot prompt.
- **Score Refactoring & Arranging Operations (`tmd refactor`)**:
  - Added commands for `double-grid`, `halve-grid`, `rename-instrument`, `rename-section`, `duplicate-track`, `generate-harmony`, `extract-instrument`, and `inline-orders`.
  - Added VS Code refactoring commands with input prompts.
- **Documentation & Architecture**:
  - Added `docs/FAQ.md` addressing architectural design choices, comparison with DAW / LilyPond / ABC, and background on creator Chen, Chih-Han (阿怪).
  - Documented "Divide and Conquer: Composable Music Architecture" and human-AI feedback loops in `README.md`.
  - Added Hero Image with VS Code extension preview in `README.md`.

## [0.1.5] - 2026-09-11

### Added
- **REAPER Project (.rpp) Exporter (`TmdReaper`)**:
  - Export multi-track TMD scores to Cockos REAPER project files with tempo envelopes, section markers, and inline MIDI data.
- **ChordPro Notation Exporter (`TmdChordPro`)**:
  - Export lead sheets and harmonic charts directly to ChordPro format (`.cho`).
- **VOCALOID Exporters (`TmdVocaloid`)**:
  - Export vocal tracks to VOCALOID2 (`.vsq`) and VOCALOID3/4 (`.vsqx`) formats with phoneme resolution (kana/romaji to X-SAMPA).
- **Full 128 General MIDI Instrument Mapping**:
  - Added complete coverage of all 128 GM instruments and numeric program changes.
- **Improved Syntax Error Reporting**:
  - The parser now reports expected tokens upon encountering syntax errors to aid debugging.
- **Sample Scores & Demos**:
  - Added *The ZONBLE Fugue* (Baroque chamber orchestra), *RSA Asymmetric Cryptography Symphony*, and diverse band arrangements.
  - Linked official vocal and instrumental demos for the project theme song *Legacy*.

## [0.1.4] - 2026-09-07

### Added
- **Windows / Linux CI & Release Automation**:
  - Added comprehensive multi-platform CI pipeline (`.github/workflows/ci.yml`) covering macOS, Ubuntu Linux, and Windows x64.
  - Added automated GitHub Release deployment workflow (`.github/workflows/release.yml`) producing Linux static binaries (`x86_64`, `aarch64`), macOS Universal Binaries (`arm64` + `x86_64`), and Windows x64 zip bundles packaged with required Swift runtime DLLs.
- **VS Code Extension TMD Export Integration**:
  - Added export commands to VS Code extension (`editor/vscode/extension.js` and `package.json`):
    - Export to MIDI (`.mid`), MusicXML (`.musicxml`), ABC Notation (`.abc`), LilyPond (`.ly`), PDF via LilyPond (`.pdf`), and offline WAV audio (`.wav`).
    - Audio preview playback directly in terminal from editor title bar and context menu.
    - Added one-click command to install AI agent skills (`tmd.installSkills`).


## [0.1.3] - 2026-09-06

### Added
- **AI Agent Skill Target (`TmdSkill`)**:
  - Added `TmdSkill` framework target and `tmd --install-skills` CLI command to automatically deploy TMD skill documentation (`SKILL.md`) to Codex, Claude Code, Antigravity, and Gemini agent directories.
  - Added comprehensive AI composition methodology covering Modular Section-Based Chunking, motif-driven architecture, human composition principles, and counterpoint techniques (Strict Canon with measure offsets `@|+N|` and Fugue structures).
- **AI Co-Composing Documentation**:
  - Added `docs/AI-Co-Composing-With-TMD.md` detailing collaborative patterns: melody arranging, motif continuation, re-harmonization, song structuring, and audio validation loops.
- **AI Collaboration Section in README**:
  - Highlighted AI co-composition capabilities and one-click skill installation instructions.

### Fixed
- **WAV Audio Offline Rendering Truncation**:
  - Fixed rendered WAV files clipping before final notes decayed. Durations are now computed precisely via CoreAudio's `MusicSequenceGetSecondsForBeats` with dynamic tempo mapping plus a 2.5-second release reverb tail.
- **CI Test Graph Stability**:
  - Configured `swift test --no-parallel` to prevent macOS system-level CoreAudio AUGraph concurrency collisions during test execution.

## [0.1.2] - 2026-09-05

### Added
- **Sample Scores & Syntax Enhancements**:
  - Added comprehensive sample scores including `sample/zk3.tmd` and `sample/zk3_symphony.tmd`.
  - Added chord octave shifting support (`[6_m]`, `[1^]`).
  - Added support for tie extensions and negative measure offsets.

### Fixed
- Fixed section divider parsing issues and legacy section marker compatibility.

## [0.1.1] - 2026-09-04

### Fixed
- Fixed integer arithmetic overflow handling during fast tempo tick calculations.

## [0.1.0] - 2026-09-04

### Added
- Initial public release of `TmdSwift`.
- Modern Swift parser, tokenizer, AST, and formatter for TMD (Timebase Mark Down).
- Multi-track Standard MIDI (SMF Type 1) exporter (`TmdMIDI`).
- MusicXML 4.0 Partwise exporter (`TmdMusicXML`).
- LilyPond source and PDF rendering exporter (`TmdLilyPond`).
- ABC Notation v2.1+ exporter (`TmdABC`).
- CoreAudio offline WAV synthesizer (`TmdAudio`).
- Command-line tool `tmd` (`TmdCLI`).
- Initial VS Code syntax highlighting extension (`editor/vscode`).
