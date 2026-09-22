# TMD Language Specification (TmdSwift Implementation)

Version: 0.1 (corresponding to the current TmdSwift parser)  
Language: English ([繁體中文版](TMD-Language-Specification.zh-TW.md))

## 1. Purpose of this Document

This document defines the TMD (Timebase Mark Down) text format accepted by the current TmdSwift implementation. It describes the **behavior currently implemented**, rather than proposals for future features. For historical design notes, original TMDLang documents, and unimplemented syntax proposals, please refer to [`Band-Score.syntax.zh_TW.md`](Band-Score.syntax.zh_TW.md).

TMD is a plain-text format for describing song structure, instrument tracks, movable-do numbered musical notation (jianpu), chords, and playback arrangement order. A parsed TMD file forms an abstract syntax tree (`Sheet`), which can then be consumed by MIDI, MusicXML, LilyPond, ABC, or WAV audio rendering modules.

## 2. Minimal File Structure

```text
::SCORE::
** Song Title **
!= 120
?= C
<4/4>

verse:Piano@|0|{
    <4*>
    1 2 3 4
}

-> verse ->#
```

A file must begin with `::SCORE::`. Following this marker, header fields (song title, tempo, key, time signature), paragraph blocks, and the playback order declaration may appear. The parser allows flexibility in the order of these elements; when the same header field appears multiple times, the subsequent value overrides the preceding one.

## 3. Whitespace and Comments

Whitespace, tabs, and newlines are ignored as separators. The following forms are lexically equivalent:

```text
!=120
!= 120
! = 120
```

Block comments use `/*` and `*/` and can span multiple lines:

```text
/* This text is ignored and will not become musical data */
```

There is currently no single-line comment syntax. An unclosed block comment will be ignored through to the end of the file.

## 4. Song Title, Tempo, Key, and Time Signature

### 4.1 Title

```text
** Three Days and Three Nights **
```

Identifiers, numbers, and scale-degree digits enclosed between `**` delimiters are concatenated into the title, separated by single spaces. The title is optional; if omitted, `Sheet.name` defaults to an empty string.

### 4.2 Tempo

```text
!= 133
!= 120.5
```

Tempo is stored as a `Double` representing beats per minute (BPM). Both integer and decimal values are supported. Inside sections, `{!=145}` or `{!+30}` can also be used to alter the absolute or relative playback tempo downstream.

### 4.3 Key Signature

```text
?= A'
? = C
```

The key signature is stored as a string without strict validation at the parser level. Thus, `C`, `A'`, `Bb`, or any token readable as an identifier can be accepted. Key modulation such as `{?+5}` represents relative transposition in the playback order rather than this header field.

### 4.4 Time Signature

```text
<4/4>
<3/4>
```

The first number indicates the number of beats per measure, and the second indicates the note value of each beat. The time signature is parsed and stored as `Beat(count:noteValue)`.

## 5. Paragraphs and Tracks

The paragraph syntax is structured as follows:

```text
sectionName:instrumentName@{
    section+
}

sectionName:instrumentName@|startMeasure|{
    section+
}

/* Abstract Material / Theme Prototype (no instrument binding, referenced by S-expression macros) */
sectionName{
    section+
}
```

For example:

```text
intro:Piano@|0|{
    <4*>
    1 2 3 4
}

intro:Guitar@|+4|{
    <16*>
    1_ - 1_ -
}

/* Abstract canon theme prototype */
Theme{
    <4*>
    3^ 2^ 1^ 7 | 6 5 6 7 | 1^ 7 6 5 | 4 3 4 2 |
}
```

The components have the following meanings:

| Field | Meaning |
| --- | --- |
| Section Name | e.g. `intro`, `A`, `verse`, `chorus`, `Theme` |
| Instrument Name | e.g. `Piano`, `Guitar`, `CHORD`; omitted for abstract themes |
| Start Measure | Expressed as an integer offset; defaults to `0` if omitted |

The start measure can be positive, zero, or negative. A negative offset indicates an upbeat or early entry, such as `@|-1|`.

Multiple instrument paragraphs can share the same section name. Each is stored independently as a `Paragraph` and is not merged at the parser stage. Paragraphs without an instrument binding are preserved as abstract prototypes (`instrument` is empty) and are instantiated dynamically via S-expression macros in the playback flow.

## 6. Sections and Basic Rhythm Units

Each section begins with `<n*>`:

```text
<4*>
<16*>
```

`n` is stored as `Section.noteLength`, indicating the base division unit (e.g. `4` for quarter notes, `16` for sixteenth notes) used by musical units in this section. The section continues parsing units until the next `<n*>`, closing brace `}`, or end-of-file is reached.

The barline symbol `|` can be used within sections for visual formatting. It is ignored by the parser.

## 7. Musical Units

### 7.1 Numbered Musical Notation (Jianpu)

Core scale degrees are `1` through `7`:

```text
1 2 3 4 5 6 7
```

Accidentals immediately follow the degree:

```text
1'     /* Sharp 1 (C# in C) */
2,     /* Flat 2 (Db in C) */
```

Octave displacement uses `^` (higher) or `_` (lower), with multiple characters stacking octaves:

```text
1^     /* One octave up */
1^^    /* Two octaves up */
1_     /* One octave down */
1__    /* Two octaves down */
1'^    /* Sharp 1, one octave up */
```

Accidentals strictly precede octave markers.

### 7.2 Chords

Chords are delimited by square brackets:

```text
[Cmaj7]
[Am]
[1]
[6m]
```

### 7.3 Ties and Sustained Notes

A single `-` represents a tie extending duration by one base unit:

```text
1 - - -
[Cmaj7] -
```

### 7.4 Tuplets and Rhythmic Groupings

Parentheses group multiple units into a subdivision, followed by `%(...)` defining the base duration:

```text
(1 2 3)%(--)
(7, 1)%(--)
```

## 8. Playback Flow, Modulation, and S-Expression Macros

Playback orders begin with `->` and terminate strictly with `->#`:

```text
-> intro -> A -> B ->#
```

### 8.1 Section Identifiers
Section names are stored in `Order.name`:

```text
-> intro
```

### 8.2 Modulation Directives
Relative key modulation:

```text
-> {?-3}
-> {?+3}
```

Absolute key modulation:

```text
-> {?=C}
-> {?=A'}
```

### 8.3 S-Expression Macro Directives
The playback flow natively supports S-expression macros for deterministic multi-track scheduling without manual measure bookkeeping:

```text
-> (canon Theme (Violin1 Violin2 Violin3) 2)
-> (layer (canon Theme (V1 V2) 2) (loop Bass Cello 8))
```

Supported core operators:
- `(play <theme> <instrument>)`: Binds an abstract theme prototype to a specific instrument track.
- `(loop <theme> <instrument> <times>)`: Repeats a theme sequentially (e.g. ground bass / ostinato).
- `(canon <theme> (<instruments...>) <offset_bars>)`: Staggers theme entries across instruments by `<offset_bars>`.
- `(layer <expr1> <expr2> ...)`: Plays child expressions concurrently from the same measure timestamp.
- `(seq <expr1> <expr2> ...)`: Chains child expressions chronologically.
- `(vary <theme> <modifiers...>)`: Flat motivic transformations, supporting semitone transposition (`+7`, `-5`, `+12`), melodic inversion `flip`, retrograde `reverse`, and modal parallel shifts `minor` / `major`.

`->#` marks the termination of the playback order.

## 9. AST Mapping

| TMD Concept | AST Type |
| --- | --- |
| Time Signature | `Beat` |
| Note | `Note` |
| Chord | `ChordSymbol` |
| Unit / Rest / Drum | `Unit` |
| Tuplet / Group | `UnitGroup` |
| `<n*>` Section | `Section` |
| Paragraph / Track | `Paragraph` (empty `instrument` for abstract prototypes) |
| Playback Order | `Order` (`name`, `relative`, `absolute`, `macro`) |
| Score | `Sheet` |

## 10. Exporter Integration

All exporters (MIDI, MusicXML, LilyPond, ABC, WAV, REAPER, ChordPro) automatically desugar S-expression macros via `TMDMacroEvaluator` before generation.

## 11. Complete Example (Canon in D with S-Expression Macros)

```tmd
::SCORE::
** Canon in D **
~ "composer: Johann Pachelbel"
~ "arranger: S-Expression Edition"
!= 56
?= D
<4/4>

/* Ground Bass Prototype (2 bars) */
Bass {
    <4*>
    1_ 5__ 6__ 3__ | 4__ 1__ 4__ 5__ |
}

/* Canon Theme Prototype (4 bars) */
Theme {
    <4*>
    3^ 2^ 1^ 7 | 6 5 6 7 | 1^ 7 6 5 | 4 3 4 2 |
}

/* Intro: Cello establishes ground bass */
intro:Cello@|0|{
    <4*>
    1_ 5__ 6__ 3__ | 4__ 1__ 4__ 5__ |
}

/* Outro: Tutti cadence */
outro:Violin1@|0|{ <1*> 1^--- | }
outro:Violin2@|0|{ <1*> 3--- | }
outro:Violin3@|0|{ <1*> 1--- | }
outro:Cello@|0|{   <1*> 1_--- | }

/* Playback Flow: Cello loops ground bass 4 times while 3 violins enter staggered by 2 bars */
-> intro
-> (layer
     (canon Theme (Violin1 Violin2 Violin3) 2)
     (loop Bass Cello 4))
-> outro
->#
```
