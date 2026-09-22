# TMD (Timebase Mark Down) Grammar Specification (EBNF)

This document formally defines the syntax and grammar of the TMD (Timebase Mark Down) musical notation DSL using Extended Backus–Naur Form (ISO/IEC 14977 variant).

---

## 1. Complete EBNF Grammar

```ebnf
(* =========================================================================
   TMD (Timebase Mark Down) Grammar Specification
   Complies with the implementation in src/core/parser.ts
   ========================================================================= *)

Score                   = ScoreHeader , [ SongTitle ] , { HeaderDirective } , { Paragraph } , [ PlaybackFlow ] ;

(* --- Header Components --- *)
ScoreHeader             = "::SCORE::" ;
SongTitle               = "**" , TitleContent , "**" ;
TitleContent            = { ? any character except newline or "**" ? } ;

HeaderDirective         = TempoDirective
                        | KeySignatureDirective
                        | TimeSignatureDirective
                        | MetadataDirective
                        | Comment ;

TempoDirective          = "!=" , Whitespace , Number ;
KeySignatureDirective   = "?=" , Whitespace , KeySignature ;
TimeSignatureDirective  = "<" , Number , "/" , Number , ">" ;

MetadataDirective       = CreditDirective | NamedMetadataDirective ;
CreditDirective         = "~" , Whitespace , StringLiteral ;
NamedMetadataDirective  = "=~:" , [ "__" ] , Identifier , [ "__" ] , "=" , Whitespace , StringLiteral ;

(* --- Paragraphs (Instrument Tracks & Abstract Material) --- *)
Paragraph               = ConcreteParagraph | AbstractParagraph ;
ConcreteParagraph       = ParagraphHeader , "{" , ParagraphBody , "}" ;
AbstractParagraph       = SectionName , "{" , ParagraphBody , "}" ;
ParagraphHeader         = SectionName , ":" , InstrumentName , "@" , ParagraphOffset ;
SectionName             = Identifier ;
InstrumentName          = Identifier ;
ParagraphOffset         = ParagraphPipeOffset | Identifier | Number ;
ParagraphPipeOffset     = "|" , [ "+" | "-" ] , Number , "|" ;

ParagraphBody           = ProgramBody | TrackBody ;
ProgramBody             = TripleQuotedString ;
TrackBody               = { MeasurePipe | SectionBlock } ;

(* --- Sections & Musical Content --- *)
SectionBlock            = NoteLengthSpecifier , { MeasurePipe | ParagraphDirective | TupletGroup | UnitGroup | SingleUnit } ;
NoteLengthSpecifier     = "<" , [ "*" ] , Number , [ "*" ] , ">" ;

MeasurePipe             = "|" ;

ParagraphDirective      = DirectiveBrace
                        | RelativeTempoDirective
                        | TempoChangeDirective
                        | RelativeKeyDirective
                        | AbsoluteKeyDirective
                        | InlineTimeSignature ;

DirectiveBrace          = "{" , ( RelativeTempoDirective | TempoChangeDirective | RelativeKeyDirective | AbsoluteKeyDirective | InlineTimeSignature ) , "}" ;

RelativeTempoDirective  = "!+" , Number ;
TempoChangeDirective    = "!=" , Number ;
RelativeKeyDirective    = "{?" , [ "+" | "-" ] , Number , "}" ;
AbsoluteKeyDirective    = "{?=" , KeySignature , "}" ;
InlineTimeSignature     = "{" , "<" , Number , "/" , Number , ">" , "}" ;

(* --- Tuplets and Groups --- *)
TupletGroup             = "%(" , { MeasurePipe | ParagraphDirective | UnitGroup | SingleUnit } , ")" ;
UnitGroup               = "(" , { MeasurePipe | ParagraphDirective | UnitGroup | SingleUnit } , ")" , [ TupletRatioSpecifier ] ;
TupletRatioSpecifier    = "%(" , { "-" } , ")" ;

(* --- Musical Units --- *)
SingleUnit              = NumberSequenceUnit
                        | NoteUnit
                        | ChordUnit
                        | PercussionUnit
                        | RestUnit
                        | TieUnit ;

NumberSequenceUnit      = JianpuDigits ;   (* Consecutive digits e.g. 1234 or 1020 parsed into multiple notes/rests *)
NoteUnit                = ScaleDegree , { NoteModifier } ;
ScaleDegree             = "1" | "2" | "3" | "4" | "5" | "6" | "7" ;
NoteModifier            = SharpAccidental | FlatAccidental | OctaveUp | OctaveDown ;
SharpAccidental         = "'" ;
FlatAccidental          = "," ;
OctaveUp                = "^" ;
OctaveDown              = "_" ;

RestUnit                = "0" ;
TieUnit                 = "-" ;

ChordUnit               = "[" , ChordContent , "]" ;
ChordContent            = ChordRoot , [ ChordQuality ] , [ "/" , BassRoot ] ;
ChordRoot               = ( PitchLetter | ScaleDegree ) , [ AccidentalModifier ] , [ OctaveModifier ] ;
BassRoot                = ( PitchLetter | ScaleDegree ) , [ AccidentalModifier ] , [ OctaveModifier ] ;
PitchLetter             = "C" | "D" | "E" | "F" | "G" | "A" | "B" ;
AccidentalModifier      = "'" | "#" | "," | "b" ;
OctaveModifier          = { "^" } | { "_" } ;
ChordQuality            = Identifier ;

PercussionUnit          = PercussionPattern ;
PercussionPattern       = { DrumStroke }+ ;
DrumStroke              = "D" | "d"   (* Bass Drum / Kick: MIDI 36 *)
                        | "B" | "b"   (* Bass Drum / Kick alias: MIDI 36 *)
                        | "S" | "s"   (* Snare Drum: MIDI 38 *)
                        | "X" | "x"   (* Closed Hi-Hat: MIDI 42 *)
                        | "O" | "o"   (* Open Hi-Hat: MIDI 46 *)
                        | "T" | "t"   (* Low-Mid Tom / Tom: MIDI 45 *)
                        | "C" | "c" ; (* Crash Cymbal: MIDI 49 *)

(* --- Playback Flow --- *)
PlaybackFlow            = "->" , FlowItem , { "->" , FlowItem } , "->#" ;
FlowItem                = SectionName
                        | RelativeKeyFlowDirective
                        | AbsoluteKeyFlowDirective
                        | MacroSExpr ;

RelativeKeyFlowDirective = "{?" , [ "+" | "-" ] , Number , "}" ;
AbsoluteKeyFlowDirective = "{?=" , KeySignature , "}" ;

MacroSExpr              = "(" , MacroOperator , { MacroArgument } , ")" ;
MacroOperator           = Identifier ;
MacroArgument           = MacroSExpr | Identifier | Number | SignedNumber | InstrumentList | ThemeList ;
InstrumentList          = "(" , { Identifier } , ")" ;
ThemeList               = "(" , { Identifier } , ")" ;
SignedNumber            = ( "+" | "-" ) , Number ;

(* --- Lexical Tokens & Terminals --- *)
KeySignature            = PitchLetter , [ "'" | "#" | "," | "b" ] , [ "m" ] ;
TripleQuotedString      = '"""' , { ? any character ? } , '"""' ;
StringLiteral           = '"' , { ? any character except quote or newline ? } , '"' ;
Identifier              = ( Letter | "_" ) , { Letter | Digit | "_" | "-" } ;
Number                  = [ "+" | "-" ] , Digit , { Digit } , [ "." , Digit , { Digit } ] ;
JianpuDigits            = { "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" }+ ;

Letter                  = "A" | ... | "Z" | "a" | ... | "z" ;
Digit                   = "0" | "1" | ... | "9" ;
Comment                 = "/*" , { ? any character ? } , "*/" ;
Whitespace              = { " " | "\t" | "\r" | "\n" } ;
```

---

## 2. Syntax Notes and Semantics

### 2.1 Score Header & Directives
- **Header**: Every TMD score begins with `::SCORE::`.
- **Title**: Enclosed in `** ... **` (e.g. `** Song Title **`).
- **Tempo (`!=`)**: Sets beats per minute (e.g. `!= 120` or `!= 85.5`).
- **Key Signature (`?=`)**: Movable-do tonic letter with optional accidental (e.g. `?= C`, `?= F#`, `?= Bb`, `?= A'm`).
- **Time Signature (`<N/D>`)**: Default meter, e.g. `<4/4>`, `<3/4>`, `<6/8>`.
- **Credits & Metadata**:
  - Direct credit: `~ "lyrics: aguai"`, `~ "詞：阿怪"`
  - Named metadata: `=~:__ALBUM__= "May 1998"`

### 2.2 Paragraphs (Tracks)
- Format: `section_name:instrument_name@offset{ ... }`
  - `offset`: Entry measure offset inside pipes, e.g., `@|0|`, `@|+4|`, `@|-1|`, or unpiped `@0`.
  - Content can be musical notation blocks or a triple-quoted program block `"""..."""`.

### 2.3 Notes and Scale Degrees
- Numbers `1` to `7` correspond to movable-do solfege ($1=Do, 2=Re, \dots, 7=Ti$).
- `0` denotes a musical rest.
- `-` denotes a tie / elongation of the preceding note or beat.
- Modifiers:
  - Octaves: `^` raises 1 octave (e.g., `1^`), `_` lowers 1 octave (e.g., `5_`).
  - Accidentals: `'` sharp, `,` flat (e.g., `4'`, `7,`).
- Compact sequences without spaces like `1234` or `1020` are parsed as individual sequential units.

### 2.4 Chords
- Delimited by square brackets `[...]`.
- Supports scale degrees or pitch names: `[1]`, `[4]`, `[5]`, `[C]`, `[Am7]`, `[G7/B]`, `[1maj7]`, `[4/5]`.

### 2.5 Percussion and Drum Tokens
Drum and percussion tracks (such as `:Drums`, `:Groove`, `:Percussion`, or `:Drum-Kick`) accept dedicated percussion stroke tokens composed of stroke characters:
- **`D` / `d`** or **`B` / `b`**: Bass Drum (Kick) — MIDI pitch 36
- **`S` / `s`**: Snare Drum — MIDI pitch 38
- **`X` / `x`**: Closed Hi-Hat — MIDI pitch 42
- **`O` / `o`**: Open Hi-Hat — MIDI pitch 46
- **`T` / `t`**: Tom (Low-Mid Tom) — MIDI pitch 45
- **`C` / `c`**: Crash Cymbal — MIDI pitch 49

Strokes can be written individually (`D - S -`), grouped in beats (`(xxxx)`), or combined into multi-hit unit patterns (e.g., `XxTS`).

### 2.6 Tuplets & Sub-divisions
- Parenthesized groups `( 1 2 3 )` or `(xxxx)` represent sub-divisions of a beat.
- Tuplet modifier `%(-)` or `%()` specifies custom proportional length.

### 2.7 Playback Order Flow
- Format: `-> intro -> verse -> chorus -> {?+2} -> chorus ->#`
- Terminated strictly with `->#`.
- Supports inline transposition directives:
  - `{?+2}`: Transpose up 2 semitones.
  - `{?=D}`: Modulate tonic to D.
