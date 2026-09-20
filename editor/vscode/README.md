# TMD Language Support for VS Code

Official Visual Studio Code extension providing language support, syntax highlighting, and snippets for the **TMD (Timebase Mark Down)** format.

## Features

- **Syntax Highlighting**:
  - `::SCORE::` root score marker.
  - Song title `** Title **`.
  - Global tempo (`!= 120`), key signature (`?= C`), and time signature (`<4/4>`).
  - Paragraph definitions (`intro:Piano@|0|{ ... }`).
  - Section divisions (`<4*>`, `<16*>`).
  - Numbered musical notation (Jianpu) with accidentals (`1'`, `2,`) and octave marks (`1^`, `1_`).
  - Chord symbols (`[Cmaj7]`, `[1]`, `[6m]`).
  - Tuplets and rhythm modifiers (`%(---)`).
  - Arrangement execution flow (`-> intro -> A ->#`).
  - Block comments (`/* ... */`).
- **Snippets**:
  - `score`: Generates a minimal TMD score template.
  - `para`: Generates an instrument paragraph block.
  - `sec`: Inserts a section rhythmic grid.
  - `tup`: Inserts a tuplet group.
  - `ch`: Inserts a chord symbol.
- **Commands & Export Integrations** (via `tmd` CLI):
  - `TMD: Format Document` (`Shift + Option + F` standard format document provider)
  - `TMD: Check Measure Consistency` (live diagnostics and warnings in Problems panel)
  - `TMD: Open Song Inspector` (interactive visual dashboard for vocal range, key metrics, timeline, and chords)
  - `TMD: Play Audio Preview in Terminal` (editor top-right title bar & context menu)
  - `TMD: Open Web MIDI Player` (interactive webview player with piano, chiptune, and system synth)
  - `TMD: Refactor: Double Grid / Halve Grid / Duplicate Track / Generate Harmony / Rename...`
  - `TMD: Export to MIDI (.mid)`
  - `TMD: Export to MusicXML (.musicxml)`
  - `TMD: Export to ABC Notation (.abc)`
  - `TMD: Export to LilyPond (.ly)`
  - `TMD: Render to PDF via LilyPond (.pdf)`
  - `TMD: Render to WAV Audio (.wav)`
  - `TMD: Install AI Agent Skills`
- **Diagnostics & Formatting**:
  - Automatically checks beat counts in bar lines (`|`) on save and open.
  - Highlights incorrect measures with warning squigglies and details in VS Code's Problems view.
- **AI & GitHub Copilot Integration**:
  - **Copilot Chat Participant (`@tmd`)**:
    - `@tmd /check`: Inspects measure lengths, beat math, and structural errors.
    - `@tmd /compose`: Composes melodies, chords, and multi-track counterpoints.
    - `@tmd /fix`: Diagnoses and automatically fixes measure beat discrepancies.
    - `@tmd /explain`: Analyzes musical structure, chord progressions, and solfege.
  - **VS Code Language Model Tools**:
    - `tmd_check`: Programmatic validation tool for agent workflows.
    - `tmd_format`: Auto-indents and cleans TMD score layout.
    - `tmd_get_specification`: Returns complete TMD specification and Jianpu rules.
  - **Repository Copilot Instructions**:
    - Includes `.github/copilot-instructions.md` for seamless ambient Copilot code completion and chat guidance.
- **Language Configuration**:
  - Auto-closing pairs and surrounding brackets for `{}`, `[]`, `()`, `<>`, `/**/`, `****`.
  - Code folding for paragraph blocks `{ ... }`.

## Installation

### Local Installation (Symlink into Extensions)

You can link this folder directly into your VS Code extensions directory:

```bash
ln -s "$(pwd)/editor/vscode" ~/.vscode/extensions/tmd-vscode
```

Then reload VS Code, open any `.tmd` file (such as `sample/basic/三天三夜.tmd`), and enjoy full syntax highlighting!
