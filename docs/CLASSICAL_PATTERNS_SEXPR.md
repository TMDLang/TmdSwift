# Classical Music Design Patterns in TMD S-Expressions

This specification maps classical musical forms and software design patterns (originally conceptualized in [Swift by zonble](https://gist.github.com/zonble/1f8df143f7bc69dfce5df324b618461a)) into **Timebase Mark Down (TMD) S-Expressions**.

Because TMD uses S-Expressions `(...)` exclusively within the playback flow (`-> (...) ->`), these musical design patterns can be expressed without conflicting with TMD's existing tokens (chords `[...]`, paragraphs `{...}`, beat grids `<...>`, and track bindings).

---

## 1. Canon: Prototype + Temporal Decorator

```
Prototype (Theme)
    ↓ clone
Instance₀ ────────────────────── (Violin 1 @ 0)
Instance₁ ── delay(2) ────────── (Violin 2 @ +2)
Instance₂ ──── delay(4) ──────── (Violin 3 @ +4)
```

### Pattern Mapping
- **Design Pattern**: Prototype (cloning an abstract theme) + Decorator (decorating each instance with temporal offset `@|+delay|`).
- **S-Expression Signature**:
  ```lisp
  (canon <theme> (<instruments...>) <offset_measures>)
  ```

### Example:
```tmd
Theme {
    <4*>
    3^ 2^ 1^ 7 | 6 5 6 7 | 1^ 7 6 5 | 4 3 4 2 |
}

-> (canon Theme (Violin1 Violin2 Violin3) 2) ->#
```

---

## 2. Ostinato: Infinite Loop / Generator

```
┌──────────────────────────────┐
│ loop(GroundBass, Cello, 8)   │
└──────────────────────────────┘
```

### Pattern Mapping
- **Design Pattern**: Loop / Iterator / Stream Generator.
- **S-Expression Signature**:
  ```lisp
  (loop <theme> <instrument> <iterations>)
  ```

### Example:
```tmd
GroundBass {
    <4*>
    1_ 5__ 6__ 3__ | 4__ 1__ 4__ 5__ |
}

-> (loop GroundBass Cello 8) ->#
```

---

## 3. Passacaglia: Immutable Base + Strategy Layer

```
                Immutable Ground Bass
                          │
             ┌────────────┼────────────┐
             ↓            ↓            ↓
         Strategy A   Strategy B   Strategy C
             ↓            ↓            ↓
         Var 1 (Flute) Var 2 (Oboe) Var 3 (Violin)
```

### Pattern Mapping
- **Design Pattern**: Immutable Base + Strategy + Composite Layering.
- **S-Expression Signature**:
  ```lisp
  (layer
    (loop GroundBass Cello <total_iterations>)
    (seq <var1> <var2> <var3> ...))
  ```

### Example:
```tmd
GroundBass {
    <4*>
    1_ 5__ 6__ 3__ | 4__ 1__ 4__ 5__ |
}

Var1 { <8*>  1 3 5 4 3 1 3 2 | 1 6_ 1 5 4 6 5 4 | }
Var2 { <16*> 1^ 7 1^ 1 7_ 5 2 3 1 1^ 7 6 7 3 5 6 | }

-> (layer
     (loop GroundBass Cello 4)
     (seq
       (play Var1 Flute)
       (play Var2 Violin)
       (play (invert Var1) Oboe)
       (play (diminish Var1 0.5) Piccolo)))
->#
```

---

## 4. Rondo: Recurring Flow (ABACA / ABACABA)

```
Refrain (A) ──> Episode 1 (B) ──> Refrain (A) ──> Episode 2 (C) ──> Refrain (A)
```

### Pattern Mapping
- **Design Pattern**: Recurring Interleaving Flow.
- Expressed naturally in TMD's native linear flow or sequential combinator without fragile syntax sugars:
  ```lisp
  (seq (play ThemeA Piano) (play EpisodeB Piano) (play ThemeA Piano) (play EpisodeC Piano) (play ThemeA Piano))
  ```
  Or directly in TMD playback flow:
  ```tmd
  -> ThemeA -> EpisodeB -> ThemeA -> EpisodeC -> ThemeA ->#
  ```

---

## 5. Fugue: Independent Polyphonic Counterpoint Sections

```
               Subject (AI Generated)
                  │
         ┌────────┼────────┐
         ↓        ↓        ↓
      Voice 1  Voice 2  Voice 3
         │        │        │
     Original  Answer  Countersubject
     (Tonic)  (Tonal)      │
         │        │        │
         └────────┴────────┘
```

### Pattern Mapping
- **Architectural Division**:
  - **AI Generation**: Musical counterpoint rules (such as tonal answers where 1–5 answers as 5–1, avoiding parallel fifths/octaves) are written directly by AI models as dedicated section prototypes (`Subject`, `Answer`, `Countersubject`).
  - **TMD S-Expression Engine**: Handles deterministic timeline scheduling and staggered entry via `canon`, `play`, and `layer` without audio drift or measure corruption.

### Example (Fugal Staggered Exposition):
```tmd
Subject {
    <4*>
    1 5_ 1 2 | 3 2 1 7, | 1 - - - |
}

Answer {
    /* Tonal answer authored by AI to conform with modal harmony */
    <4*>
    5 1 5 6 | 7 6 5 4' | 5 - - - |
}

/* Fugal Exposition using atomic primitives */
-> (layer
     (play Subject Voice1)
     (canon Voice1 Subject Voice2 Answer 4))
->#
```

---

## 6. Variations: Functional Strategy Pipeline

```
Theme
  │
  ├── (vary Theme +7)
  ├── (minor Theme)
  ├── (flip Theme)
  ├── (reverse Theme)
  └── (vary Theme +7 reverse minor)
```

### Pattern Mapping
- **Design Pattern**: Strategy Pattern as Pure Transformation Functions.
- **S-Expression Combinators**:
  - `(minor <theme>)`: Flattens degrees 3, 6, 7 to tonic parallel minor.
  - `(major <theme>)`: Restores flattened degrees to parallel major.
  - `(flip <theme> [<axis>])`: Melodic inversion.
  - `(reverse <theme>)`: Reverses note order chronologically within bars.
  - `(transpose <semitones> <theme>)`: Pitch transposition in semitones.
  - `(vary <theme> <modifiers...>)`: Flat composition without nested parentheses.

### Example:
```tmd
Theme {
    <4*>
    1 1 5 5 | 6 6 5 - | 4 4 3 3 | 2 2 1 - |
}

-> (play Theme Piano)
-> (play (minor Theme) Piano)
-> (play (flip Theme) Flute)
-> (play (reverse Theme) Violin)
-> (play (vary Theme +7 reverse minor) Cello)
->#
```

---

## 7. Sonata-Allegro: Hierarchical Finite State Machine (FSM)

```
        ┌────────────────────────┐
        │       Exposition       │
        │ Theme 1 (Tonic)        │
        │ Bridge / Modulation    │
        │ Theme 2 (Dominant)     │
        └───────────┬────────────┘
                    ↓
        ┌────────────────────────┐
        │      Development       │
        │ Fragmentation & Drama  │
        │ Cycle through Keys     │
        └───────────┬────────────┘
                    ↓
        ┌────────────────────────┐
        │     Recapitulation     │
        │ Theme 1 (Tonic)        │
        │ Theme 2 (Tonic! Solved)│
        └────────────────────────┘
```

### Pattern Mapping
- **Design Pattern**: State Machine / Structural Template.
- **S-Expression Signature**:
  ```lisp
  (sonata
    :theme1 ThemeA
    :theme2 ThemeB
    :key D
    :development (...))
  ```
  Or expressed transparently via TMD playback sequence with modulations:
  ```tmd
  /* Exposition: Theme 1 in Tonic, Theme 2 in Dominant (+7) */
  -> Theme1
  -> Bridge
  -> {?+7} -> Theme2

  /* Development: Motifs fragmented and transformed */
  -> (layer
       (play (retrograde Theme1) Violin)
       (play (diminish Theme2 0.5) Flute))
  -> {?-3} -> Theme1
  -> {?+5} -> Theme2

  /* Recapitulation: Both themes resolved in Tonic */
  -> {?=D}
  -> Theme1
  -> Theme2
  -> Coda
  ->#
  ```

---

## 8. Suite: Composite Pattern

```
                     Suite (Baroque Dance Collection)
                                    │
         ┌──────────────┬───────────┴───────────┬──────────────┐
         ↓              ↓                       ↓              ↓
     Allemande       Courante               Sarabande        Gigue
      (4/4, slow)   (3/2 or 3/4)            (3/4, grave)    (6/8, fast)
```

### Pattern Mapping
- **Design Pattern**: Composite / Pipeline.
- **S-Expression Signature**:
  ```lisp
  (suite <movement1> <movement2> ...)
  ```
  In TMD, sequential composition is natively represented by sequential `->` or an S-Expression `(seq ...)`:
  ```tmd
  -> (seq Allemande Courante Sarabande Gigue) ->#
  ```

---

## Summary Matrix

| Musical Form | Gang of Four (GoF) Pattern | TMD S-Expression Syntax |
| :--- | :--- | :--- |
| **Canon** | Prototype + Decorator | `(canon Theme (V1 V2 V3) 2)` |
| **Ostinato / Ground Bass** | Iterator / Infinite Loop | `(loop Bass Cello 8)` |
| **Passacaglia** | Immutable Base + Strategy Layer | `(layer (loop Bass C 4) (seq Var1 Var2))` |
| **Rondo** | Recurring Callback / Interleaver | `(rondo Refrain (Ep1 Ep2))` |
| **Fugue** | Prototype + Strategy + Stretto | `(layer (play Sub V1 :at 0) (play (transpose +7 Sub) V2 :at 4))` |
| **Theme & Variations** | Strategy Pattern Pipeline | `(seq Theme (minor Theme) (invert Theme))` |
| **Sonata-Allegro** | Finite State Machine (FSM) | `(sonata :theme1 T1 :theme2 T2 :key D ...)` |
| **Suite** | Composite | `(seq Allemande Courante Sarabande Gigue)` |
