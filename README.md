# TmdSwift

A modern Swift implementation of the **TMD** (Timebase Mark Down) markup language parser, toolkit, and music notation exporter.

In memory of **Chen, Chih-Han / [aguai](https://github.com/aguai)** (阿怪, 1974–2019).

Original project: [https://github.com/aguai/TMDLang](https://github.com/aguai/TMDLang)

## About TMD

### Origins & Heritage

**TMD** (Timebase Mark Down) was originally conceived and designed by the celebrated Taiwanese songwriter, composer, and producer **Chen, Chih-Han / [aguai](https://github.com/aguai) (阿怪, 1974–2019)**, renowned for Mandopop classics such as A-Mei's 《三天三夜》 (*Three Days and Three Nights*).

### Core Philosophy: An Intermediate Representation (IR) for Music

Most digital music tools treat music as one of two paradigms:
1. **An Audio Engineering problem** (DAWs like Logic, Pro Tools, Cubase): Faders, decibel meters, audio tracks, and millisecond waveforms.
2. **A Desktop Publishing problem** (Engravers like Sibelius, Finale, LilyPond): Stem directions, collision avoidance, beam slants, and printable paper layout.

**TMD treats music as Source Code.**

TMD is designed as a **music-native Intermediate Representation (IR)**—a format that is **compilable, analyzable, refactorable, and seamlessly understood by both humans and AI**:
- **Sections are Modules**: `intro`, `verse`, and `chorus` are self-contained, reusable blocks.
- **Arrangement is Control Flow**: `-> intro -> verse -> chorus -> {?+1} -> chorus ->#` represents the executable flow of the song, complete with dynamic key modulations.
- **Relative Pitch & Jianpu Thinking**: Melody notes are expressed as movable-do scale degrees (`1`–`7`), octaves (`^`, `_`), and accidentals (`'`, `,`), making transpositions and melodic contours intuitive without staff clutter.
- **Consistency Check is a Typechecker**: The TMD compiler inspects beat counts against time signatures in each measure like a strict linter.
- **Song Inspector is a Profiler**: Instead of measuring track volume in decibels, the `tmd inspect` profiler analyzes real songwriting invariants: vocal range and tessitura (lowest/highest note, span in semitones), section duration ratios, harmonic vocabulary, and arrangement density.

### Designed for Songwriters, Not Print Shops

TMD was created for people who write, produce, and arrange songs, rather than orchestra sight-readers or sheet music engravers. Yet, because of its semantic purity as an IR, a single `.tmd` score can be compiled and exported into virtually any downstream musical format:
- **MIDI (.mid)**: Multi-track SMF Type 1 for importing into any digital audio workstation.
- **REAPER Project (.rpp)**: Complete with tempo markers, region markers, and multi-track MIDI.
- **MusicXML (.musicxml)**: W3C MusicXML 4.0 for notation software (MuseScore, Sibelius, Finale, Dorico).
- **LilyPond (.ly & .pdf)**: For publication-grade engraved sheet music.
- **ABC Notation (.abc)**: For lightweight web score rendering (`abcjs`).
- **Vocal Synthesizers (.vsqx, .vsq, .ust)**: For VOCALOID2/3/4 and UTAU/OpenUtau tuning.
- **WAV Audio (.wav)**: Built-in synthesis via CoreAudio and SoundFont banks.

### Why TMD Excels in Human-AI Musical Co-Creation

When collaborating with Large Language Models (LLMs) on musical tasks, standard notation formats often introduce friction:
- **Drastically Reduced Syntax Noise**: Unlike MusicXML's verbose XML tree tags or LilyPond's complex macro typography, TMD uses concise Markdown-like syntax. This minimizes LLM token consumption and drastically reduces syntax hallucinations.
- **No Multi-Track "Rest Hell" (TMD vs. ABC Notation)**: In ABC notation, arranging multiple parallel instruments across an entire song requires padding inactive instruments with dozens of consecutive measure rests (`| z4 | z4 | z4 |`), which easily desynchronizes LLM context windows. In TMD, instruments specify their exact entry point with an offset (`@|+4|`), and silent measures require zero syntax tokens.
- **Composable Motifs & Dynamic Key Modulations**: An AI agent can express dynamic modulations (`{?+2}`), melodic continuation, and counterpoint as high-level musical constructs rather than recalculating raw MIDI ticks.

### The TmdSwift Implementation

**TmdSwift** re-implements the original parser into a clean, modern Swift architecture featuring:
- A two-stage Lexer + TokenParser pipeline.
- Normalized musical AST structures (`Beat`, `Note`, `Unit`, `Section`, `Paragraph`, `Order`, `Sheet`).
- Formatter to serialize AST back to standard TMD syntax.
- **Multi-track MIDI (SMF Type 1)** exporter (`TmdMIDI`).
- **REAPER Project (.rpp)** exporter (`TmdReaper`) with tempo envelopes, section markers, and inline MIDI data.
- **MusicXML 4.0** notation exporter (`TmdMusicXML`) for MuseScore, Sibelius, and web renderers.
- **LilyPond** engraver exporter (`TmdLilyPond`) for publication-grade score typesetting and PDF rendering.
- **ABC Notation** exporter (`TmdABC`) for web sheet rendering (`abcjs`) and text-based score sharing.
- **Offline WAV Audio** synthesizer (`TmdAudio`) powered by CoreAudio DLS SoundFont.
- A command-line interface (`tmd`) powered by `swift-argument-parser`.

## Co-Composing with AI Using TMD

Because TMD is a concise, text-based, and human-readable musical notation DSL, it serves as an ideal bridge between human musical ideas and generative AI / Large Language Models (LLMs). Instead of wrestling with opaque binary formats (MIDI) or unstructured audio waveforms, creators and AI agents can pair-program music interactively in TMD.

### Equip Your AI Assistant in One Command

`TmdSwift` comes with an official AI Agent skill (`SKILL.md`) covering TMD syntax, modular section chunking, human composition principles, motif development, and counterpoint rules. You can install it directly into your local AI environment (supporting Codex, Claude Code, Antigravity, and Gemini):

```bash
tmd --install-skills
```

Once installed, your AI agent will automatically understand how to compose, arrange, debug, and orchestrate music using TMD.

### What AI Can Help You Achieve

1. **Arranging Accompaniments from Melody**:
   Draft a vocal line or melody in TMD, then prompt the AI to generate supporting tracks (bass lines, rhythm guitar grooves, string pads, or drum patterns) with specific entry offsets (`@|+4|`).

2. **Motif Development & Continuation**:
   Define a short 2-bar or 4-bar melodic motif, and let the AI develop it into complete phrases through inversion, retrograde, rhythmic variations, or antecedent-consequent question-and-answer phrasing.

3. **Re-Harmonization & Chord Exploration**:
   Provide a melody and have the AI propose multiple chord progressions—from standard pop and rock progressions to modal jazz substitutions and Neo-Soul extensions (`[Cmaj7]`, `[Am7]`, `[Dm7-5]`).

4. **Macro Song Structuring & Modulations**:
   Compose core song blocks (`intro`, `verse`, `chorus`, `bridge`) and have the AI plan the overarching playback sequence (`-> intro -> A -> B -> {?+1} -> B ->#`), complete with key modulations and emotional dynamics.

5. **Textural Layering & Arrangement Build-Up**:
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
