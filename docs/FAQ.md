# Frequently Asked Questions (FAQ)

### Why not use mature formats like MIDI, MusicXML, or ABC notation?

**Those formats are designed to store finished songs; TMD is designed to write them.** 

- **MusicXML** is an interchange format for notation programs, far too verbose to draft or edit by hand.
- **MIDI** is a 1983 binary hardware protocol that lacks musical semantics (no concept of song sections, chords, or movable-do scale degrees) and cannot be diffed in Git.
- **ABC notation** was built decades ago to archive single-melody folk tunes. In modern multi-instrument arrangements, it devolves into "rest hell" (`| z4 | z4 |`), cluttering the score and exhausting LLM context windows.

TMD acts as the Markdown of music: a clean, plain-text authoring scratchpad that compiles into all of them.

### Why not just write in LilyPond directly?

LilyPond is a desktop publishing engraver built to lay out sheet music for print shops, not a songwriting tool. While AI can generate valid LilyPond, humans find reading and editing it painful and slow. TMD is clean enough for humans and AI to co-create interactively, yet compiles directly to LilyPond whenever you need engraved sheet music.

### What about DAWs like Logic Pro, Cubase, or Ableton?

DAWs treat music as audio engineering—faders, tracks, and millisecond waveforms. They are indispensable for mixing and production, but heavy and cumbersome for sketching modular song forms, testing vocal ranges, or version-controlling ideas in Git. TMD complements DAWs by letting you draft and iterate rapidly, then export to Standard MIDI (`.mid`) or REAPER (`.rpp`) projects.

### Who was aguai (阿怪)?

**Chen, Chih-Han / aguai (阿怪, 1974–2019)** was a celebrated Taiwanese pop songwriter, composer, and producer. He wrote iconic Mandopop classics such as A-Mei's 《三天三夜》 (*Three Days and Three Nights*) and designed the original TMD language specification to capture the practical mental model of professional pop songwriting.

### Does TMD lock me into a proprietary ecosystem?

No. TMD is an open, MIT-licensed intermediate representation (IR). A single `.tmd` file compiles cleanly into multi-track MIDI, REAPER, MusicXML, LilyPond, ABC, VOCALOID, UTAU, or WAV audio.
