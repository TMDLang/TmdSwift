# TMD S-Expression Standard Macro Library Specification

This document defines the complete standard function catalog for TMD S-Expressions in the playback flow (`-> (...) ->`).

Functions are divided into three architectural tiers:
1. **Core Structural Combinators** (Temporal layout & routing)
2. **Classical Form Generators** (Macro desugaring into multi-track arrangements)
3. **Motivic Transformation Operators** (Pure contrapuntal & musical modifications)

---

## 1. Core Structural Combinators (Temporal Layout)

These are the fundamental building blocks responsible for time placement and multi-track concurrency.

| Function | Signature | Description |
| :--- | :--- | :--- |
| **`play`** | `(play <material> <instrument> [:at <measure_offset>])` | Instantiates abstract musical material onto a specific instrument track at a given measure offset (default `:at 0`). |
| **`layer`** | `(layer <expr1|section1> <expr2|section2> ...)` | **Parallel Concurrency**: Evaluates child expressions or bare concrete section names starting at the exact same measure timestamp. Total duration equals `max(child_durations)`. |
| **`seq`** | `(seq <expr1|section1> <expr2|section2> ...)` | **Sequential Composition**: Evaluates child expressions or bare concrete section names one after another in chronological order. Total duration equals `sum(child_durations)`. |
| **`loop`** | `(loop <section> <times>)` or `(loop <material> <instrument> <times>)` | Repeats musical material consecutively `<times>` times. If `<section>` already has a bound instrument, the instrument argument can be omitted. |

---

## 2. Polyphonic Generators

| Function | Signature | Description |
| :--- | :--- | :--- |
| **`canon`** | `(canon <theme> (<instruments...>) <offset_bars>)` or `(canon <inst1> <theme1> <inst2> <theme2> <offset_bars>)` | **Canon (Staggered Entry)**: Staggers copies of `<theme>` (or successive themes) across instruments delayed by `<offset_bars>`. |

> **Architectural Note on Fugues and Counterpoint**:
> High-level forms with tonal answers (Tonal Answer vs. Real Answer) and counterpoint rule constraints (avoiding parallel fifths/octaves, leading-tone resolution) are NOT hardcoded as macro syntax sugars.
> In TMD's AI-assisted workflow, **AI models directly author the musical counterpoint sections** (e.g., `Subject`, `Answer`, `Countersubject`), while the deterministic TMD S-expression engine handles timeline offsets, measure arithmetic, and playback routing without hallucination.

---

## 3. Motivic Transformation Operators & Variations

Musical transformations can be applied either as discrete pure functions or as flat modifiers in a single `(vary ...)` call.

### A. The Unified `vary` Combinator (Zero Sub-Parentheses)
Chain any sequence of modifications without nested parentheses:
```lisp
;; Flat syntax (clean & ergonomic):
(vary Theme +7 reverse minor)
(vary Theme flip reverse)
(vary Theme -5 minor)
```

Supported flat tokens:
- **Signed integers (`+7`, `-2`, `+12`)**: Chromatic transposition in semitones.
- **`reverse`**: Chronological reversal of notes within bars.
- **`flip`**: Melodic inversion / pitch reflection upside-down.
- **`minor`**: Converts natural major scale degrees to parallel minor (flattens 3rd, 6th, 7th).
- **`major`**: Restores minor scale degrees to parallel major.

### B. Discrete Pure Operators
| Operator | Signature | Description |
| :--- | :--- | :--- |
| **`transpose`** | `(transpose <semitones> <material>)` | Shifts pitches by signed semitones. |
| **`reverse`** | `(reverse <material>)` | Reverses chronological note order. |
| **`flip`** | `(flip <material> [<axis>])` | Inverts melodic contour upside-down. |
| **`minor`** | `(minor <material>)` | Flattens 3, 6, 7 to parallel minor. |
| **`major`** | `(major <material>)` | Restores flattened 3, 6, 7 to parallel major. |
| **`vary`** | `(vary <material> <modifiers...>)` | Flat or composite variation chain. |

---

## 4. Current Implementation Status

All documented operators in Sections 1–3 are fully implemented, verified with strict TDD test suites, and provide source code line/column error tracking.
