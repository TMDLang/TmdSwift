# TmdSwift

A modern Swift implementation of the **TMD** (Timebase Mark Down) markup language parser, toolkit, and music notation exporter.

![TMD in Visual Studio Code](assets/vscode_screenshot.png)

In memory of **Chen, Chih-Han / [aguai](https://github.com/aguai)** (阿怪, 1974–2019).

Original project: [https://github.com/aguai/TMDLang](https://github.com/aguai/TMDLang)

## About TMD

### Origins & Heritage

**TMD** (Timebase Mark Down) was originally conceived and designed by the celebrated Taiwanese songwriter, composer, and producer **Chen, Chih-Han / [aguai](https://github.com/aguai) (阿怪, 1974–2019)**, renowned for Mandopop classics such as A-Mei's 《三天三夜》 (*Three Days and Three Nights*).

### The Markdown of Music

Just as **Markdown** freed writers from the tedious tags of HTML, **TMD brings that same simplicity to music**.

Formats like MusicXML, LilyPond, or multi-track MIDI are like HTML or PostScript: indispensable for web renderers, synthesizers, and print shops, but painful and unnatural for humans to write by hand. Most digital tools push creators into one of two extremes:
- **An Audio Engineering mindset** (DAWs like Logic, Pro Tools, Cubase): Faders, decibel meters, audio tracks, and millisecond waveforms.
- **A Desktop Publishing mindset** (Engravers like Sibelius, Finale, LilyPond): Stem directions, collision avoidance, beam slants, and printable paper layout.

Even traditional plain-text notation like **ABC notation** falls short for modern songs. Designed decades ago for single-melody folk tunes, ABC becomes "rest hell" in multi-instrument arrangements: whenever an instrument rests for an entire section, ABC requires padding dozens of empty-measure rests (`| z4 | z4 | z4 |`) just to keep tracks aligned, cluttering the score and exhausting LLM context windows. Furthermore, because ABC relies on absolute staff pitch rather than movable-do scale degrees, transposing a song or adjusting an arrangement means recalculating every note by hand.

**TMD is the Markdown to their HTML.**

It provides a **music-native Intermediate Representation (IR)**—as natural and clean as a songwriter's lead sheet, yet structured enough to be **compiled, analyzed, refactored, and seamlessly understood by both humans and AI**:
- **No "Rest Hell" in Multi-Track Arrangements**: Instruments declare their exact entry measure with an offset (e.g. `verse:Guitar@|+4|{ ... }`). Silent measures require zero tokens and zero visual clutter.
- **Sections are Modular Building Blocks**: `intro`, `verse`, and `chorus` are self-contained blocks defined once and kept compact. If an instrument does not play in a section (e.g. Drums entering only in the Chorus), you simply omit that track entirely—no empty measures, zero rest clutter. Because sections are completely modular, creators can instantly preview individual sections or solo tracks in MIDI/audio without having to listen through the entire score from the beginning.
- **Arrangement as the Song's Road Map**: The playback order—including dynamic key changes and section repetitions—is declared cleanly at the end (`-> intro -> verse -> chorus -> {?+1} -> chorus ->#`), mirroring how musicians rehearse and structure arrangements in their minds.
- **Relative Pitch & Movable-Do (Jianpu) Thinking**: Melodies are written in numbered scale degrees (`1`–`7`), octaves (`^`, `_`), and accidentals (`'`, `,`). Transposing a song for a singer's vocal range is as simple as changing `?= C` to `?= Eb`—the melody itself remains untouched.
- **Measure Consistency as a Helpful Typechecker**: Just as a Markdown linter catches broken links, `tmd check` verifies measure beat counts against time signatures to catch rhythmic typos early.
- **Song Profile as a Macro Diagnostic**: Instead of measuring track volume in decibels, `tmd inspect` analyzes what songwriters actually care about: vocal range and tessitura (lowest/highest note, span in semitones), section duration ratios, harmonic vocabulary, and arrangement density.

### Designed for Songwriters, Not Print Shops nor Archives

Publishing engravers (like LilyPond or Sibelius) and historic tune archives (like ABC notation) are exceptional at what they do—the former excels at publication-grade sheet layout, while the latter is peerless for indexing and archiving world folk melodies.

However, their workflow assumes the composition is already finished: the song was drafted on manuscript paper or scribbled in a notebook, and only entered into the software once finalized.

The iterative creative workflow of a pop songwriter and producer like **aguai (阿怪)** is fundamentally different. Songwriting is an active, messy, living process: humming melodies in movable-do, auditioning chords, testing whether a singer can hit high notes, experimenting with band arrangements, and restructuring song forms on the fly. 

**TMD moves that creative notebook directly onto the computer—and makes it effortlessly mutable.**

Instead of wrestling with mouse clicks in a DAW or fixed notation engravers, songwriters can sketch, mutate, and re-arrange musical ideas in seconds, co-creating interactively alongside AI. Yet, because of its semantic purity as an IR, a single `.tmd` score can be seamlessly compiled and exported into virtually any downstream musical format:
- **MIDI (.mid)**: Multi-track SMF Type 1 for importing into any digital audio workstation.
- **REAPER Project (.rpp)**: Complete with tempo markers, region markers, and multi-track MIDI.
- **MusicXML (.musicxml)**: W3C MusicXML 4.0 for notation software (MuseScore, Sibelius, Finale, Dorico).
- **LilyPond (.ly & .pdf)**: For publication-grade engraved sheet music.
- **ABC Notation (.abc)**: For lightweight web score rendering (`abcjs`).
- **Vocal Synthesizers (.vsqx, .vsq, .ust)**: For VOCALOID2/3/4 and UTAU/OpenUtau tuning.
- **WAV Audio (.wav)**: Built-in synthesis via CoreAudio and SoundFont banks.

### Automated Refactoring & Macro Song Inspection

Beyond AI pair-programming and multi-format exports, TMD empowers songwriters with an entire suite of automated refactoring tools and macro inspection utilities:

- **Song Inspector & Tessitura Profiler (`tmd inspect`)**:
  - **Vocal Range Verification**: Instantly calculates the exact lowest and highest notes (with absolute MIDI pitch and note names like `C4`, `A#5`), span in semitones, and the specific sections where vocal peaks occur. Songwriters can immediately verify whether a singer can comfortably hit the notes or if a key transposition is needed.
  - **Song Structure & Timeline Timing**: Calculates precise playback seconds and measure counts for every section (`intro`, `verse`, `chorus`) across the timeline.
  - **Arrangement Density & Peak Concurrency**: Analyzes orchestration density section by section, identifying the peak concurrent track count and dynamically built-up sections.
  - **Harmonic Vocabulary & Modulations**: Lists all distinct chords used across the piece and tracks key modulation history.
  - **Structured JSON Output**: Use `--json` to feed musical profile data into web dashboards, automated tests, or external analytics scripts.

- **Music Score Refactoring Suite (`tmd refactor`)**:
  - **Resolution Scaling (`double-grid` / `halve-grid`)**: Scale rhythm subdivision grids up (`<4*>` to `<8*>`) by padding units with ties, or halve them down, without breaking measure math.
  - **Global Renaming (`rename-instrument` / `rename-section`)**: Safely rename an instrument or section across all paragraphs, tracks, and playback order sequences simultaneously.
  - **Track Extraction (`extract-instrument`)**: Extract all tracks belonging to a specific instrument (e.g. Lead Vocal, Bass) into an isolated TMD document for rehearsal, stems, or solo printing.
  - **Track Duplication & Octave Doubling (`duplicate-track`)**: Duplicate any existing melody track with optional octave shifts (`--octave 1`) to instantly create doubled leads or sub-bass lines.
  - **Automatic Diatonic Harmony (`generate-harmony`)**: Generate parallel diatonic harmony tracks (e.g. parallel 3rds up or down) following the score's key signature.
  - **Inline Playback Orders (`inline-orders`)**: Unroll and inline repeating sections and relative key changes into a linear, single-pass score when preparing final arrangements.

### The TmdSwift Implementation

**TmdSwift** re-implements the original parser into a clean, modern Swift architecture featuring:
- A two-stage Lexer + TokenParser pipeline.
- Normalized musical AST structures (`Beat`, `Note`, `Unit`, `Section`, `Paragraph`, `Order`, `Sheet`).
- Formatter to serialize AST back to standard TMD syntax.
- Exporters for MIDI, REAPER, MusicXML, LilyPond, ABC, VOCALOID, UTAU, and WAV audio.
- A command-line interface (`tmd`) powered by `swift-argument-parser`.

## Co-Composing with AI Using TMD

Because TMD is concise, human-readable, and free of syntactic noise, it serves as the ideal shared language between creators and Large Language Models (LLMs). While AI can generate valid LilyPond or MusicXML, those formats are hostile to human reading and editing. TMD balances expressive power with human readability, allowing creators and AI agents to pair-program music interactively.

### Equip Your AI Assistant in One Command

`TmdSwift` comes with an official AI Agent skill (`SKILL.md`) covering TMD syntax, modular section chunking, human composition principles, motif development, and counterpoint rules. You can install it directly into your local AI environment (supporting Codex, Claude Code, Antigravity, and Gemini):

```bash
tmd --install-skills
```

### What AI Can Help You Achieve

1. **Arranging Accompaniments from Melody**:
   Draft a vocal line or melody in TMD, then prompt the AI to generate supporting tracks (bass lines, rhythm guitar grooves, string pads, or drum patterns) with specific entry offsets (`@|+4|`).

2. **Motif Development & Continuation**:
   Define a short 2-bar or 4-bar melodic motif, and let the AI develop it into complete phrases through inversion, retrograde, rhythmic variations, or antecedent-consequent question-and-answer phrasing.

3. **Re-Harmonization & Chord Exploration**:
   Provide a melody and have the AI propose multiple chord progressions—from standard pop and rock progressions to modal jazz substitutions and Neo-Soul extensions (`[Cmaj7]`, `[Am7]`, `[Dm7-5]`).

4. **Macro Song Structuring & Modulations**:
   Compose core song blocks (`intro`, `verse`, `chorus`, `bridge`) and have the AI plan the overarching playback sequence (`-> intro -> A -> B -> {?+1} -> B ->#`), complete with key modulations and emotional dynamics.

5. **Textural Layering & Dynamic Contrast**:
   Use measure entry offsets (`@|0|`, `@|+4|`, `@|-1|`) to guide the AI in orchestrating gradual instrumentation build-ups, pick-up measures (anticipation notes), and dynamic contrast across sections.

6. **Style & Metric Variations**:
   Prompt the AI to adapt a 4/4 ballad into a 3/4 waltz, re-groove straight rhythms into syncopated Funk/R&B patterns, or add tuplet ornaments `(1 2 3)%(--)`.

See [`docs/AI-Co-Composing-With-TMD.md`](docs/AI-Co-Composing-With-TMD.md) for concrete workflows, step-by-step examples, and copy-pasteable prompt templates.

## Platform Support

| Platform | Parser & AST (`TmdSwift`) | MIDI Exporter (`TmdMIDI`) | MusicXML (`TmdMusicXML`) | LilyPond (`TmdLilyPond`) | ABC (`TmdABC`) | WAV Audio (`TmdAudio`) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **macOS** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ *(Built-in Roland GS DLS / Custom SF2)* |
| **Linux (Ubuntu)** | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ *(Requires external synth / planned)* |
| **Windows** | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ *(Requires external synth / planned)* |
| **iOS / iPadOS** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ *(CoreAudio / Custom SF2)* |

## Installation & Build

Requires Swift 6.0+ / Xcode 16+.

### Install on macOS / Linux from Homebrew tap

```bash
brew tap zonble/tmd
brew tap --trust zonble/tmd  # allow this third-party tap
brew install tmd
```

If Homebrew refuses to install from an untrusted third-party tap, run the `brew tap --trust zonble/tmd` line and install again.

On Linux, the Homebrew formula builds `tmd` with Homebrew's `swift` package (`brew install swift`). Without Homebrew, install Swift 6 from your distribution or Swift.org.

### Using Mint

You can install the `tmd` CLI tool via [Mint](https://github.com/yonaskolb/Mint):

```bash
mint install zonble/TmdSwift
```

### Build from Source

```bash
git clone https://github.com/zonble/TmdSwift.git
cd TmdSwift
swift build -c release
```

## CLI Usage (`tmd`)

The `tmd` CLI tool provides comprehensive score compilation, export, verification, inspection, and refactoring commands:

### Compilation, Export & Rendering

```bash
# Parse and print score summary
tmd sample/basic/三天三夜.tmd -p

# Play score in terminal using macOS default sound bank
tmd sample/basic/三天三夜.tmd --play

# Export to Standard MIDI file (.mid)
tmd sample/basic/三天三夜.tmd -m score.mid

# Export to REAPER project (.rpp) with tempo and section markers
tmd sample/basic/三天三夜.tmd -r score.rpp

# Export to MusicXML 4.0 (for MuseScore, Sibelius, Finale, Dorico)
tmd sample/basic/三天三夜.tmd -x score.musicxml

# Export to LilyPond (.ly) source file or render directly to PDF
tmd sample/basic/三天三夜.tmd -l score.ly
tmd sample/basic/三天三夜.tmd --pdf-output score.pdf

# Export to ABC notation (.abc) for web score sharing (abcjs)
tmd sample/basic/三天三夜.tmd -a score.abc

# Export vocal track to VOCALOID (.vsq, .vsqx) or UTAU (.ust)
tmd sample/basic/三天三夜.tmd --vsqx-output score.vsqx
tmd sample/basic/三天三夜.tmd -u score.ust

# Render to offline WAV audio file (macOS built-in DLS or custom SoundFont)
tmd sample/basic/三天三夜.tmd -w score.wav
tmd sample/basic/三天三夜.tmd -w score.wav --soundfont /path/to/soundfont.sf2
```

### Inspection, Diagnostics & AI Skills

```bash
# Check measure consistency (detect beat count discrepancies between bar lines '|')
tmd check sample/basic/三天三夜.tmd

# Inspect song profile (vocal tessitura, pitch ranges, duration, chord vocabulary, density)
tmd inspect sample/basic/三天三夜.tmd

# Inspect song profile in structured JSON format
tmd inspect sample/basic/三天三夜.tmd --json

# Generate document symbol outline (sections and tracks with line/col offsets)
tmd outline sample/basic/三天三夜.tmd

# Install TMD skill definition into local AI agent environments (Codex, Antigravity, Claude, etc.)
tmd --install-skills
```

### Formatting & Refactoring

```bash
# Format score with standardized indentation, spacing, and preserved comments
tmd format sample/basic/三天三夜.tmd -i

# Double grid resolution (<4*> -> <8*>) padding units with ties
tmd refactor double-grid sample/basic/三天三夜.tmd -i

# Halve grid resolution (<8*> -> <4*>) collapsing ties
tmd refactor halve-grid sample/basic/三天三夜.tmd -i

# Rename instrument or section globally across paragraphs and orders
tmd refactor rename-instrument sample/basic/三天三夜.tmd --source "Piano" --target "Keys" -i
tmd refactor rename-section sample/basic/三天三夜.tmd --source "verse" --target "A" -i

# Duplicate track with optional octave transposition
tmd refactor duplicate-track sample/basic/三天三夜.tmd --source "Lead" --target "LeadOct" --octave 1 -i

# Generate parallel diatonic harmony for an instrument (e.g. 3rd above: interval 2)
tmd refactor generate-harmony sample/basic/三天三夜.tmd --source "Vocal" --target "Harmony" --interval 2 -i

# Unroll / inline playback orders into a linear score
tmd refactor inline-orders sample/basic/三天三夜.tmd -i
```

## Swift Package Usage

Add `TmdSwift` to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/zonble/TmdSwift.git", branch: "main")
]
```

Then import the modules:

```swift
import TmdSwift
import TmdMIDI
import TmdMusicXML
import TmdLilyPond
import TmdABC

// Parse TMD from file or URL
guard let sheet = try TmdParser.parse(filePathOrURL: "sample/basic/三天三夜.tmd") else {
    fatalError("Failed to parse")
}

// Inspect summary
print(sheet.summary())

// Export to MIDI Data
let midiData = TMDMIDIGenerator.generateMIDI(from: sheet)

// Export to MusicXML string
let musicXML = TMDMusicXMLGenerator.generateMusicXML(from: sheet)

// Export to LilyPond string
let lilyPond = TMDLilyPondGenerator.generateLilyPond(from: sheet)

// Export to ABC notation string
let abc = TMDABCGenerator.generateABC(from: sheet)
```

## Modules

- **`TmdSwift`**: Lexer, Parser, AST data structures, and TMD source formatter.
- **`TmdMIDI`**: Binary SMF Type 1 multi-track MIDI file generator.
- **`TmdMusicXML`**: W3C MusicXML 4.0 Partwise generator.
- **`TmdLilyPond`**: LilyPond engraving source generator.
- **`TmdABC`**: Standard ABC Notation (v2.1+) generator.
- **`TmdAudio`**: Offline WAV audio synthesizer using CoreAudio / DLS SoundFont.
- **`TmdSkill`**: AI agent skill definitions and automated installation utilities for AI co-pilots.
- **`TmdUtils`**: Cross-platform file path normalizer and character encoding detector.
- **`TmdCLI`**: Command-line interface executable (`tmd`).

## Editor Support

You can edit TMD files with syntax highlighting, snippets, and export tools in both desktop and terminal editors:

### 1. Visual Studio Code

The repository includes an official VS Code extension in [`editor/vscode`](editor/vscode):
- **Syntax Highlighting & Snippets**: Full grammar for TMD metadata, tracks, numbered notation, chords, tuplets, and arrangement flow.
- **Export & Playback Commands** (via `tmd` CLI):
  - `TMD: Play Audio Preview in Terminal` (editor top-right title bar & context menu)
  - `TMD: Export to MIDI (.mid)`
  - `TMD: Export to MusicXML (.musicxml)`
  - `TMD: Export to ABC Notation (.abc)`
  - `TMD: Export to LilyPond (.ly)`
  - `TMD: Render to PDF via LilyPond (.pdf)`
  - `TMD: Render to WAV Audio (.wav)`
  - `TMD: Install AI Agent Skills`

To install locally:
```bash
ln -s "$(pwd)/editor/vscode" ~/.vscode/extensions/tmd-vscode
```

### 2. zago (Terminal Editor with Native TMD Integration)

[**zago**](https://github.com/zonble/zago) is a modern modal terminal editor (with Web & desktop editions) that provides first-class native TMD score support:
- **Real-time TMD Playback**: Press `Ctrl+P` or use `:tmd play` to preview scores directly within the terminal or browser (via Web MIDI / JZZ synth).
- **Export Menu & Shortcuts**: Press `Ctrl+E` or run `:tmd export <format>` to export to MIDI, MusicXML, ABC, LilyPond, PDF, or WAV on the fly.
- **Syntax Highlighting**: Dedicated TMD syntax highlighting and buffer status notifications.

## Documentation & Language Specification

For the formal TMD language specification implemented in TmdSwift, please refer to:
- English: [`docs/TMD-Language-Specification.en.md`](docs/TMD-Language-Specification.en.md)
- Traditional Chinese: [`docs/TMD-Language-Specification.zh-TW.md`](docs/TMD-Language-Specification.zh-TW.md)

Historical draft notes and original design concepts are preserved in [`docs/Band-Score.syntax.zh_TW.md`](docs/Band-Score.syntax.zh_TW.md).

## License

MIT License
