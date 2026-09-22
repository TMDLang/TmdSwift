# Macro Composing in TMD: S-Expression Architecture & Specification

## 1. Abstract & Motivation

In current Timebase Mark Down (TMD), musical arrangement follows a linear, imperative structure:
- **Concrete Coupling**: Paragraphs rigidly bind musical notation to a specific track and instrument at declaration time (e.g., `section:Piano@|0| { ... }`).
- **Repetitive Authoring (WET)**: Classical and polyphonic forms such as **Canons**, **Fugues**, **Passacaglias**, and **Variations** require copy-pasting the exact same musical material across multiple tracks, manually padding offset rests (`0`), and hand-transposing notes.
- **Flat Playback Orders**: The playback flow (`-> intro -> verse ->#`) only references flat section identifiers or simple modulation directives (`{?+2}`).

### Why S-Expressions (Lisp Dialect) in Playback Flow?
When designing macro functions for TMD, conventional functional syntax like `layer[canon(Theme, instruments:["Violin1", ...])]` introduces significant parser ambiguities:
- Square brackets `[...]` already represent **chords** in TMD (e.g. `[C]`, `[1]`, `[6m]`).
- Colons `:` are heavily overloaded for section instrument binding (`name:instrument`) and metadata tags.
- String quotes `"` are generally avoided in musical scores except for header metadata.

By adopting **S-Expressions** in the playback flow (`-> (op arg1 arg2 ...) ->`), TMD achieves:
1. **Zero Lexer Ambiguity**: Only uses tokens already present in TMD (`(`, `)`, identifiers, numbers).
2. **Minimal Parser Footprint**: A pure recursive S-Expression parser takes less than 30 lines of code.
3. **Infinite Composability**: Macro calls can be seamlessly nested without precedence or delimiter conflicts.
4. **Natural Ast Desugaring**: Musical motifs are evaluated and expanded into standard TMD conductor timelines before synthesis.

---

## 2. Core Concepts

### 2.1 Abstract Musical Material (Prototypes / Themes)
A musical paragraph declared **without** an instrument binding serves as an abstract musical theme (prototype):

```tmd
ThemeA {
    <4*>
    1 2 3 1 | 3 4 5 - | 5 6 5 4 | 3 - 1 - |
    2 5_ 1 - | - - - - |
}
```

- An abstract paragraph contains pure melodic, harmonic, and rhythmic units.
- It is not tied to any MIDI channel, track offset, or SoundFont instrument.
- It is not emitted into the final conductor timeline unless instantiated or referenced in the playback flow.

### 2.2 S-Expression Macro Playback Flow
The playback order transitions from a list of static symbols into an **evaluatable S-Expression pipeline**:

```tmd
-> Intro -> (canon ThemeA (Violin1 Violin2 Cello) 2) -> Outro ->#
```

When the compiler evaluates `(canon ...)`, it dynamically expands the prototype into concrete timeline tracks before audio synthesis or export.

---

## 3. Standard Macro Functions (S-Expressions)

### 3.1 `(canon <theme> (<instruments...>) <offset_bars>)`
Constructs a polyphonic canon by cloning an abstract theme across multiple voices, progressively offsetting each subsequent voice in time by `offset_bars`.

#### Example: Three-Voice Canon in D
```tmd
-> (canon Theme (Violin1 Violin2 Violin3) 2) ->#
```

**Compiler Desugaring:**
- `Violin1`: Starts at bar 0 (`@|0|`), plays `Theme`.
- `Violin2`: Starts at bar 2 (`@|+2|`), plays `Theme`.
- `Violin3`: Starts at bar 4 (`@|+4|`), plays `Theme`.

---

### 3.2 `(loop <theme> <instrument> <times>)`
Repeats an abstract theme sequentially for `<times>` iterations on the specified `<instrument>`.

#### Example: Basso Ostinato (Ground Bass)
```tmd
-> (loop Bass Cello 8) ->#
```

**Compiler Desugaring:**
- Generates a single continuous paragraph on `Cello` repeating `Bass` 8 times.

---

### 3.3 `(layer <expr1> <expr2> ...)`
Executes multiple expressions concurrently, aligning their start positions to the exact same measure timestamp.

#### Example: Pachelbel's Canon Full Section
```tmd
-> (layer
     (canon Theme (Violin1 Violin2 Violin3) 2)
     (loop Bass Cello 10))
->#
```

---

### 3.4 Contrapuntal & Variation Combinators

Because S-Expressions are referentially transparent, classical contrapuntal transformations can be composed cleanly:

#### 1. `(transpose <semitones> <theme>)`
Transposes a theme by a signed number of semitones.
```tmd
(transpose +7 Theme)   /* Transpose up 7 semitones */
```

#### 2. `(reverse <theme>)`
Reverses the chronological order of notes (crab canon / cancrizans / retrograde).
```tmd
(reverse Theme)
```

#### 3. `(flip <theme> [<axis>])`
Inverts pitch intervals upside-down across an axis (defaults to tonic).
```tmd
(flip Theme)
```

#### 4. `(minor <theme>)` / `(major <theme>)`
Converts to parallel minor or major.

#### 5. `(vary <theme> <modifiers...>)`
Chains transformations cleanly in a flat sequence without nested parentheses:
```tmd
(vary Theme +7 reverse minor)
(vary Theme flip reverse)
```

> **Design Principle**: Rhythmic time-scaling (such as doubling/halving note durations) is intentionally excluded from individual theme transforms to preserve strict measure invariants. Rhythmic acceleration is handled natively by TMD tempo directives (`{!+10}`) across the conductor timeline.

---

## 4. AST & Grammar Specification

### 4.1 Grammar Update (EBNF)

```ebnf
(* Abstract Paragraphs without instruments *)
Paragraph         = ConcreteParagraph | AbstractParagraph ;
ConcreteParagraph = SectionName , ":" , InstrumentName , "@" , ParagraphOffset , "{" , ParagraphBody , "}" ;
AbstractParagraph = SectionName , "{" , ParagraphBody , "}" ;

(* Playback Flow with S-Expressions *)
PlaybackFlow      = "->" , FlowItem , { "->" , FlowItem } , "->#" ;
FlowItem          = SectionName 
                  | RelativeKeyFlowDirective 
                  | AbsoluteKeyFlowDirective 
                  | RelativeTempoFlowDirective 
                  | SExpr ;

SExpr             = "(" , { SExprAtom | SExpr } , ")" ;
SExprAtom         = Identifier | Number | SignedNumber ;
```

### 4.2 TypeScript AST Representation

```typescript
export type SExprAtom = string | number;
export type SExpr = SExprAtom | SExpr[];

export type Order =
  | { type: "name"; name: string }
  | { type: "relative"; value: number }
  | { type: "absolute"; value: number }
  | { type: "relativeTempo"; value: number }
  | { type: "macro"; expr: SExpr[] };
```

---

## 5. Architectural Execution Model

```
                    ┌────────────────────────────┐
                    │      TMD Source File       │
                    └─────────────┬──────────────┘
                                  │
                                  ▼
                    ┌────────────────────────────┐
                    │       TMD AST Parser       │
                    │  - Abstract Paragraphs     │
                    │  - Order S-Expressions     │
                    └─────────────┬──────────────┘
                                  │
                                  ▼
                    ┌────────────────────────────┐
                    │     Macro Evaluator (IR)   │
                    │  - (layer ...)             │
                    │  - (canon ...)             │
                    │  - (loop ...)              │
                    └─────────────┬──────────────┘
                                  │ (Desugared Concrete AST)
                                  ▼
                    ┌────────────────────────────┐
                    │    TMDMeasureChecker &     │
                    │    Playback Conductor      │
                    └─────────────┬──────────────┘
                                  │
         ┌────────────────────────┼────────────────────────┐
         ▼                        ▼                        ▼
  MIDI Export               WAV Synthesis           MusicXML / LilyPond
```

1. **AST Parsing**: Collects abstract prototypes into a symbol table and parses `Order.macro` trees.
2. **Desugaring Phase**: Expands S-Expression macros into standard `Paragraph` structures with concrete offsets and instruments.
3. **Execution & Export**: The existing rendering engine and exporters receive standard, fully resolved paragraphs without requiring underlying audio synthesis alterations.
