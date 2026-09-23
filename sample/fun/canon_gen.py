#!/usr/bin/env python3
"""
TMD Canon Generator with Pentatonic Scale Engine & Macro / S-Expression Architecture
Generates musically coherent, harmonious, polyphonic canon scores in TMD format using
Pentatonic scales (五聲音階 - 宮商角徵羽 / Major & Minor Pentatonic).

Pentatonic guarantees zero minor second / tritone dissonance during canonic overlap,
making random counterpoint inherently harmonious and melodic.
"""

import argparse
import random
import sys
from typing import List, Tuple, Optional


class CanonGenerator:
    """
    Algorithmic generator for TMD Canons based on Pentatonic scales.
    - Major Pentatonic: 1, 2, 3, 5, 6 (宮 商 角 徵 羽)
    - Minor Pentatonic: 1, 3, 4, 5, 7, (羽 宮 商 角 徵 in movable-do, or 6, 1, 2, 3, 5)
    - Harmonic foundation: Pentatonic Ground Bass (Basso Ostinato)
    - Multi-voice canonic delays (@|+2|, @|+4| or (canon Theme ... 2))
    - S-Expression Macro & Unrolled CLI output modes
    """

    # Major Pentatonic scale degrees (宮、商、角、徵、羽)
    MAJOR_PENTATONIC_SCALE = [
        "1_", "2_", "3_", "5_", "6_",
        "1", "2", "3", "5", "6",
        "1^", "2^", "3^", "5^", "6^",
        "1^^"
    ]

    # Minor Pentatonic scale degrees (羽調式 / 6_ 1 2 3 5 or 1 3, 4 5 7,)
    # If key is Am, notes are A, C, D, E, G -> 6_ 1 2 3 5 (or relative to A: 1 3 4 5 7)
    # In TMD numbered notation relative to key:
    # In Minor key (?= Am), 1 is A (tonic), minor pentatonic is typically represented as:
    # 1, 3 (C), 4 (D), 5 (E), 7, (G) or standard modal degrees.
    # For universal TMD transposition, standard Major Pentatonic is [1, 2, 3, 5, 6].
    # Minor Pentatonic in natural degrees: [1, 3, 4, 5, 7] or [6_, 1, 2, 3, 5].
    MINOR_PENTATONIC_SCALE = [
        "6__", "1_", "2_", "3_", "5_",
        "6_", "1", "2", "3", "5",
        "6", "1^", "2^", "3^", "5^",
        "6^"
    ]

    # Pentatonic Ground Bass archetypes (4 to 8 measures)
    PENTATONIC_BASS_PATTERNS = {
        # Minor key (羽調式 / Am)
        "minor": [
            # 6_ -> 1 -> 2 -> 3 -> 5 -> 3 -> 2 -> 1
            ["6__", "1_", "2_", "3_", "5_", "3_", "2_", "1_"],
            # 6_ -> 5_ -> 3_ -> 2_ -> 1_ -> 2_ -> 3_ -> 5_
            ["6__", "5__", "3__", "2__", "1__", "2__", "3__", "5__"],
            # 4-measure cycle: 6_ -> 2_ -> 3_ -> 6_
            ["6__", "2__", "3__", "6__"],
            # 4-measure cycle: 6_ -> 1_ -> 5_ -> 6_
            ["6__", "1_", "5__", "6__"],
        ],
        # Major key (宮調式 / C or D)
        "major": [
            # 1 -> 5_ -> 6_ -> 3_ -> 4(omit/replace with 2_) -> 1 -> 5_ -> 1
            ["1_", "5__", "6__", "3__", "2__", "1__", "5__", "1_"],
            # 1 -> 2 -> 3 -> 5 -> 6 -> 5 -> 3 -> 2
            ["1_", "2_", "3_", "5_", "6_", "5_", "3_", "2_"],
            # 4-measure cycle: 1 -> 6_ -> 5_ -> 1
            ["1_", "6__", "5__", "1_"],
            # 4-measure cycle: 1 -> 3 -> 5 -> 2
            ["1_", "3_", "5_", "2_"],
        ]
    }

    # Pentatonic Chord Pillars (associated consonant tone clusters for each bass note)
    PENTATONIC_CHORD_TONES_MAJOR = {
        "1_": ["1", "3", "5", "1^"],
        "2_": ["2", "5", "6", "2^"],
        "3_": ["3", "5", "1^", "3^"],
        "5_": ["5", "2^", "5^", "1^"],
        "6_": ["6", "1^", "3^", "6^"],
        "1__": ["1_", "3_", "5_", "1"],
        "2__": ["2_", "5_", "6_", "2"],
        "3__": ["3_", "5_", "1", "3"],
        "5__": ["5_", "2", "5", "1"],
        "6__": ["6_", "1", "3", "6"],
    }

    PENTATONIC_CHORD_TONES_MINOR = {
        "6__": ["6_", "1", "3", "6"],
        "1_": ["1", "3", "5", "1^"],
        "2_": ["2", "5", "6", "2^"],
        "3_": ["3", "5", "1^", "3^"],
        "5_": ["5", "1^", "3^", "5^"],
        "1__": ["1_", "3_", "5_", "1"],
        "2__": ["2_", "5_", "6_", "2"],
        "3__": ["3_", "5_", "1", "3"],
        "5__": ["5_", "1", "3", "5"],
    }

    def __init__(
        self,
        title: str = "Pentatonic Canon",
        tempo: int = 96,
        key: str = "C",
        time_sig: str = "4/4",
        num_voices: int = 3,
        offset_bars: int = 2,
        num_variations: int = 3,
        canon_type: str = "standard",
        use_macro: bool = True,
        seed: Optional[int] = None,
    ):
        self.title = title
        self.tempo = tempo
        self.key = key
        self.time_sig = time_sig
        self.num_voices = num_voices
        self.offset_bars = offset_bars
        self.num_variations = num_variations
        self.canon_type = canon_type.lower()
        self.use_macro = use_macro

        if seed is not None:
            random.seed(seed)

        self.is_minor = "m" in self.key
        self.scale = self.MINOR_PENTATONIC_SCALE if self.is_minor else self.MAJOR_PENTATONIC_SCALE
        self.voice_instruments = [f"Violin{i+1}" for i in range(self.num_voices)]
        self.bass_instrument = "Cello"

    def generate_header(self) -> str:
        mode_desc = "羽調式 (Minor Pentatonic)" if self.is_minor else "宮調式 (Major Pentatonic)"
        type_desc = {
            "standard": "Standard Polyphonic Canon (輪唱卡農)",
            "crab": "Crab Canon / Cancrizans (螃蟹卡農 / 逆行卡農)",
            "mirror": "Mirror Canon / Inversion (倒影卡農 / 鏡像卡農)",
            "table": "Table Canon / Retrograde Inversion (桌子卡農 / 雙倒影逆行卡農)",
        }.get(self.canon_type, "Standard Polyphonic Canon")
        return f"""::SCORE::
** {self.title} **
~ "composer: CanonGenerator (Pentatonic Algorithmic Engine)"
~ "style: {mode_desc}, Form: {type_desc}"
!= {self.tempo}
?= {self.key}
<{self.time_sig}>
"""

    def select_or_gen_bass(self) -> List[str]:
        """Selects a pentatonic ground bass pattern."""
        category = "minor" if self.is_minor else "major"
        patterns = self.PENTATONIC_BASS_PATTERNS[category]
        return list(random.choice(patterns))

    def format_bass_macro(self, bass_notes: List[str]) -> Tuple[str, int]:
        """Formats the Ground Bass as an abstract macro paragraph."""
        total_measures = len(bass_notes)
        lines = [
            "/* Pentatonic Ground Bass Prototype (Basso Ostinato) */",
            "Bass {",
            "    <4*>",
        ]
        bar_chunks = [f"{note} - - -" for note in bass_notes]
        for i in range(0, len(bar_chunks), 2):
            lines.append(f"    | {' | '.join(bar_chunks[i:i+2])} |")
        lines.append("}\n")
        return "\n".join(lines), total_measures

    def _get_chord_tones(self, bass_degree: str) -> List[str]:
        mapping = self.PENTATONIC_CHORD_TONES_MINOR if self.is_minor else self.PENTATONIC_CHORD_TONES_MAJOR
        if bass_degree in mapping:
            return mapping[bass_degree]
        # Fallback to general pentatonic scale
        return self.scale[5:10]

    def _step_in_scale(self, current_tone: str, max_steps: int = 2) -> str:
        """Finds next tone by moving step-wise within the pure pentatonic scale."""
        try:
            idx = self.scale.index(current_tone)
        except ValueError:
            idx = len(self.scale) // 2

        step = random.choice([-1, 1, -2, 2, 0])
        new_idx = max(0, min(len(self.scale) - 1, idx + step))
        return self.scale[new_idx]

    def generate_theme_bars(self, bass_notes: List[str], variation_idx: int) -> List[Tuple[str, List[str]]]:
        """
        Generates measure units for a variation with rich rhythmic variety.
        Mixes long notes, dotted rhythms, running passages, syncopation, and rests
        so notes have contrasting lengths instead of robotic isochronous grids.
        """
        style = variation_idx % 5
        measures = []

        if style == 0:
            # Style 0: Lyrical Cantabile with Long Notes & Dotted Rhythms (<4*>)
            # Patterns:
            # - Half note + two quarter notes: "1 - 2 3"
            # - Dotted half note + quarter note: "1 - - 2"
            # - Quarter note + half note + quarter: "1 2 - 3"
            # - Sustained whole note: "1 - - -"
            for b_note in bass_notes:
                tones = self._get_chord_tones(b_note)
                pattern_type = random.choice(["half_quarters", "dotted_quarter", "quarter_half", "two_halves"])
                t1 = random.choice(tones)
                t2 = self._step_in_scale(t1, max_steps=1)
                t3 = self._step_in_scale(t2, max_steps=2)

                if pattern_type == "half_quarters":
                    measures.append(f"{t1} - {t2} {t3}")
                elif pattern_type == "dotted_quarter":
                    measures.append(f"{t1} - - {t2}")
                elif pattern_type == "quarter_half":
                    measures.append(f"{t1} {t2} - {t3}")
                else: # two_halves
                    measures.append(f"{t1} - {t2} -")
            return [("<4*>", measures)]

        elif style == 1:
            # Style 1: Flowing Baroque Lilt with Mixed Durations (<8*>)
            # Mixes quarter notes, dotted eighths, and eighth notes:
            # - Quarter note followed by running eighths: "1 - 2 3 5 3 2 1"
            # - Two quarters and four eighths: "1 - 2 - 3 5 3 2"
            # - Dotted rhythm (long-short): "1 - 1 2 - 2 3 5"
            # - Resting breath: "1 - 0 2 3 5 3 1"
            for b_note in bass_notes:
                tones = self._get_chord_tones(b_note)
                curr = random.choice(tones)
                pattern_choice = random.choice([1, 2, 3, 4])

                if pattern_choice == 1:
                    # Quarter note + 6 running eighth notes
                    run = [f"{curr} -"]
                    for _ in range(6):
                        curr = self._step_in_scale(curr, max_steps=1)
                        run.append(curr)
                    measures.append(" ".join(run))

                elif pattern_choice == 2:
                    # Two quarters + 4 eighth notes
                    t1 = curr
                    t2 = self._step_in_scale(t1, max_steps=1)
                    curr = t2
                    run = [f"{t1} -", f"{t2} -"]
                    for _ in range(4):
                        curr = self._step_in_scale(curr, max_steps=1)
                        run.append(curr)
                    measures.append(" ".join(run))

                elif pattern_choice == 3:
                    # Dotted lilt / syncopation: "1 - 2 3 - 5 6 5"
                    t1 = curr
                    t2 = self._step_in_scale(t1, max_steps=1)
                    t3 = self._step_in_scale(t2, max_steps=1)
                    t4 = self._step_in_scale(t3, max_steps=1)
                    t5 = self._step_in_scale(t4, max_steps=1)
                    measures.append(f"{t1} - {t2}  {t3} - {t4}  {t5} {t4}")

                else:
                    # Baroque breath & entry: "0 1 2 3 5 - 3 2"
                    t1 = curr
                    t2 = self._step_in_scale(t1, max_steps=1)
                    t3 = self._step_in_scale(t2, max_steps=1)
                    t4 = self._step_in_scale(t3, max_steps=2)
                    t5 = self._step_in_scale(t4, max_steps=1)
                    t6 = self._step_in_scale(t5, max_steps=1)
                    measures.append(f"0 {t1} {t2} {t3}  {t4} - {t5} {t6}")

            return [("<8*>", measures)]

        elif style == 2:
            # Style 2: Virtuosic Flourish & Turns with Sustained Pillars (<16*>)
            # Contrasts rapid 16th-note arabesques with sustained anchor beats:
            # - Beat 1: Quarter note (sustained anchor) | Beats 2-4: 16th-note runs
            # - Beat 1-2: 16th-note flourish | Beat 3: Quarter note | Beat 4: 16th flourish
            for b_note in bass_notes:
                tones = self._get_chord_tones(b_note)
                curr = random.choice(tones)
                flourish_type = random.choice(["head_anchor", "center_anchor", "wave_with_rest"])

                if flourish_type == "head_anchor":
                    # Beat 1: "1 - - -" (quarter note anchor)
                    groups = [f"{curr} - - -"]
                    for _ in range(3):
                        g = []
                        for _ in range(4):
                            curr = self._step_in_scale(curr, max_steps=1)
                            g.append(curr)
                        groups.append(" ".join(g))
                    measures.append("  ".join(groups))

                elif flourish_type == "center_anchor":
                    # Beat 1: 16th run | Beat 2: Quarter anchor | Beat 3-4: 16th run
                    g1 = []
                    for _ in range(4):
                        curr = self._step_in_scale(curr, max_steps=1)
                        g1.append(curr)
                    anchor = self._step_in_scale(curr, max_steps=2)
                    curr = anchor
                    g3 = []
                    g4 = []
                    for _ in range(4):
                        curr = self._step_in_scale(curr, max_steps=1)
                        g3.append(curr)
                    for _ in range(4):
                        curr = self._step_in_scale(curr, max_steps=1)
                        g4.append(curr)
                    groups = [" ".join(g1), f"{anchor} - - -", " ".join(g3), " ".join(g4)]
                    measures.append("  ".join(groups))

                else:
                    # Beat 1: 16th run | Beat 2: 16th run | Beat 3: Rest & entry | Beat 4: 16th run
                    g1 = [curr]
                    for _ in range(3):
                        curr = self._step_in_scale(curr, max_steps=1)
                        g1.append(curr)
                    g2 = []
                    for _ in range(4):
                        curr = self._step_in_scale(curr, max_steps=1)
                        g2.append(curr)
                    t_entry = self._step_in_scale(curr, max_steps=1)
                    curr = t_entry
                    g4 = []
                    for _ in range(4):
                        curr = self._step_in_scale(curr, max_steps=1)
                        g4.append(curr)
                    groups = [" ".join(g1), " ".join(g2), f"0 0 {t_entry} {curr}", " ".join(g4)]
                    measures.append("  ".join(groups))

            return [("<16*>", measures)]

        elif style == 3:
            # Style 3: Staccato Dialogue & Echo Rests (<8*>)
            # Like Pachelbel Variation 5 ("1^ 0 7 0 6 0 1^ 0") or syncopated echo
            for b_note in bass_notes:
                tones = self._get_chord_tones(b_note)
                curr = random.choice(tones)
                dialogue_choice = random.choice(["staccato_steps", "offbeat_syncopation", "echo_chords"])

                if dialogue_choice == "staccato_steps":
                    bar = []
                    for _ in range(4):
                        bar.append(f"{curr} 0")
                        curr = self._step_in_scale(curr, max_steps=2)
                    measures.append(" ".join(bar))

                elif dialogue_choice == "offbeat_syncopation":
                    # Offbeat syncopation: "0 1 0 2 0 3 5 -"
                    t1 = curr
                    t2 = self._step_in_scale(t1, max_steps=1)
                    t3 = self._step_in_scale(t2, max_steps=1)
                    t4 = self._step_in_scale(t3, max_steps=2)
                    measures.append(f"0 {t1}  0 {t2}  0 {t3}  {t4} -")

                else:
                    # Echo: "1 - 0 1  2 - 0 2"
                    t1 = curr
                    t2 = self._step_in_scale(t1, max_steps=1)
                    measures.append(f"{t1} - 0 {t1}  {t2} - 0 {t2}")

            return [("<8*>", measures)]

        else:
            # Style 4: Pastoral Sicilienne / Triplet-feel Syncopations (<8*>)
            # Characterized by lilting dotted rhythms and suspensions:
            # - "1 - - 2  3 - 2 -" (dotted quarter + eighth + two quarters)
            # - "1 - 2 3  5 - - -" (quarter + two eighths + half note anchor)
            for b_note in bass_notes:
                tones = self._get_chord_tones(b_note)
                t1 = random.choice(tones)
                t2 = self._step_in_scale(t1, max_steps=1)
                t3 = self._step_in_scale(t2, max_steps=1)
                t4 = self._step_in_scale(t3, max_steps=2)
                measures.append(f"{t1} - - {t2}  {t3} - {t4} -")
            return [("<8*>", measures)]

    def generate_theme_section_macro(self, bass_notes: List[str], variation_idx: int) -> str:
        """Generates one variation section as an abstract macro paragraph."""
        var_name = "Theme" if variation_idx == 0 else f"Var{variation_idx}"
        lines = [
            f"/* Pentatonic Variation {variation_idx} ({var_name}) */",
            f"{var_name} {{"
        ]
        subsections = self.generate_theme_bars(bass_notes, variation_idx)
        for grid, bars in subsections:
            lines.append(f"    {grid}")
            for bar in bars:
                lines.append(f"    | {bar} |")
        lines.append("}\n")
        return "\n".join(lines)

    def generate_concrete_sections(self, bass_notes: List[str]) -> str:
        """Generates concrete intro and outro sections in pentatonic harmony."""
        intro_bars = " | ".join([f"{n} - - -" for n in bass_notes[:self.offset_bars]]) + " |"
        outro_lines = [
            "/* Concrete Pentatonic Intro & Outro */",
            f"intro:{self.bass_instrument}@|0|{{",
            "    <4*>",
            f"    | {intro_bars}",
            "}\n",
        ]
        
        # Outro tonic resolution
        tonic_bass = "6__" if self.is_minor else "1_"
        tonic_high = "6" if self.is_minor else "1^"
        tonic_mid = "1" if self.is_minor else "5"
        tonic_third = "3" if self.is_minor else "3"

        outro_lines.append(f"outro:{self.bass_instrument}@|0|{{ <1*> {tonic_bass}--- | }}")
        cadence_notes = [tonic_high, tonic_mid, tonic_third]
        for i, voice in enumerate(self.voice_instruments):
            note = cadence_notes[i % len(cadence_notes)]
            outro_lines.append(f"outro:{voice}@|0|{{ <1*> {note}--- | }}")
        outro_lines.append("")
        return "\n".join(outro_lines)

    def generate_playback_flow_macro(self, var_names: List[str], bass_measures: int) -> str:
        """Generates S-Expression playback flow supporting standard, crab, mirror, and table canons."""
        theme_sequence = f"({' '.join(var_names)})" if len(var_names) > 1 else var_names[0]
        voice_sequence = f"({' '.join(self.voice_instruments)})"
        total_theme_bars = len(var_names) * bass_measures

        if self.canon_type == "crab":
            # Crab Canon / Cancrizans:
            # Voice 1 plays forward, Voice 2 plays backward (retrograde), simultaneously
            loop_count = len(var_names)
            v1 = self.voice_instruments[0]
            v2 = self.voice_instruments[1] if len(self.voice_instruments) > 1 else "Violin2"
            lines = [
                "/* S-Expression Playback Flow: Crab Canon (Cancrizans / 螃蟹卡農) */",
                "-> intro",
                "-> (layer",
                f"     (play {theme_sequence} {v1})",
                f"     (play (reverse {theme_sequence}) {v2})",
                f"     (loop Bass {self.bass_instrument} {loop_count}))",
                "-> outro",
                "->#\n",
            ]
            return "\n".join(lines)

        elif self.canon_type == "mirror":
            # Mirror Canon / Melodic Inversion:
            # Voice 1 plays original, Voice 2 plays upside-down (flipped around tonic axis)
            loop_count = len(var_names)
            v1 = self.voice_instruments[0]
            v2 = self.voice_instruments[1] if len(self.voice_instruments) > 1 else "Violin2"
            lines = [
                "/* S-Expression Playback Flow: Mirror Canon (Inversion / 倒影鏡像卡農) */",
                "-> intro",
                "-> (layer",
                f"     (play {theme_sequence} {v1})",
                f"     (play (flip {theme_sequence}) {v2})",
                f"     (loop Bass {self.bass_instrument} {loop_count}))",
                "-> outro",
                "->#\n",
            ]
            return "\n".join(lines)

        elif self.canon_type == "table":
            # Table Canon / Tafelkanon:
            # Retrograde Inversion (upside-down & backward): two players read the same sheet from opposite sides
            loop_count = len(var_names)
            v1 = self.voice_instruments[0]
            v2 = self.voice_instruments[1] if len(self.voice_instruments) > 1 else "Violin2"
            lines = [
                "/* S-Expression Playback Flow: Table Canon (Tafelkanon / 雙倒影逆行桌子卡農) */",
                "-> intro",
                "-> (layer",
                f"     (play {theme_sequence} {v1})",
                f"     (play (flip (reverse {theme_sequence})) {v2})",
                f"     (loop Bass {self.bass_instrument} {loop_count}))",
                "-> outro",
                "->#\n",
            ]
            return "\n".join(lines)

        else:
            # Standard Staggered Polyphonic Canon
            total_canon_bars = total_theme_bars + (self.num_voices - 1) * self.offset_bars
            loop_count = (total_canon_bars + bass_measures - 1) // bass_measures
            lines = [
                "/* S-Expression Playback Flow: Standard Polyphonic Canon (輪唱卡農) */",
                "-> intro",
                "-> (layer",
                f"     (canon {theme_sequence} {voice_sequence} {self.offset_bars})",
                f"     (loop Bass {self.bass_instrument} {loop_count}))",
                "-> outro",
                "->#\n",
            ]
            return "\n".join(lines)

    def generate_unrolled_score(self, bass_notes: List[str]) -> str:
        """
        Generates standard TMD score unrolled without macros.
        Compatible with classical TMD compilers (e.g. TmdSwift / tmd CLI tool).
        """
        parts = [self.generate_header()]

        # Generate all variation bars
        var_data = []
        for v in range(self.num_variations):
            var_data.append(self.generate_theme_bars(bass_notes, v))

        bass_measures = len(bass_notes)
        total_theme_bars = self.num_variations * bass_measures
        total_canon_bars = total_theme_bars + (self.num_voices - 1) * self.offset_bars
        loop_count = (total_canon_bars + bass_measures - 1) // bass_measures
        section_total_measures = loop_count * bass_measures

        # Intro
        parts.append(self.generate_concrete_sections(bass_notes))

        # Canon section: Cello Ground Bass
        cello_lines = [
            f"canon:{self.bass_instrument}@|0|{{",
            "    <4*>",
        ]
        for l in range(loop_count):
            bar_chunks = [f"{n} - - -" for n in bass_notes]
            for i in range(0, len(bar_chunks), 2):
                cello_lines.append(f"    | {' | '.join(bar_chunks[i:i+2])} |")
        cello_lines.append("}\n")
        parts.append("\n".join(cello_lines))

        # Canon section: Canonic voices with progressive offsets and trailing rest padding
        for v_idx, voice in enumerate(self.voice_instruments):
            offset = v_idx * self.offset_bars
            voice_lines = [
                f"canon:{voice}@|+{offset}|{{"
            ]
            for v_num, subsections in enumerate(var_data):
                voice_lines.append(f"    /* Variation {v_num} */")
                for grid, bars in subsections:
                    voice_lines.append(f"    {grid}")
                    for bar in bars:
                        voice_lines.append(f"    | {bar} |")

            # Trailing rests to pad until section_total_measures
            played_measures = offset + total_theme_bars
            remaining_measures = section_total_measures - played_measures
            if remaining_measures > 0:
                voice_lines.append("    <4*>")
                for _ in range(remaining_measures):
                    voice_lines.append("    | 0 - - - |")

            voice_lines.append("}\n")
            parts.append("\n".join(voice_lines))

        # Standard Playback Flow
        parts.append("-> intro -> canon -> outro ->#\n")
        return "\n".join(parts)

    def generate(self) -> str:
        """Generates the score according to mode (macro vs unrolled)."""
        bass_notes = self.select_or_gen_bass()
        if not self.use_macro:
            return self.generate_unrolled_score(bass_notes)

        parts = [self.generate_header()]

        # 1. Ground Bass
        bass_code, bass_measures = self.format_bass_macro(bass_notes)
        parts.append(bass_code)

        # 2. Themes / Variations
        var_names = []
        for v in range(self.num_variations):
            name = "Theme" if v == 0 else f"Var{v}"
            var_names.append(name)
            parts.append(self.generate_theme_section_macro(bass_notes, v))

        # 3. Intro & Outro
        parts.append(self.generate_concrete_sections(bass_notes))

        # 4. Playback Flow
        parts.append(self.generate_playback_flow_macro(var_names, bass_measures))

        return "\n".join(parts)


def main():
    parser = argparse.ArgumentParser(description="TMD Pentatonic Canon Generator (宮商角徵羽)")
    parser.add_argument("--title", type=str, default="Pentatonic Canon", help="Score title")
    parser.add_argument("--tempo", type=int, default=96, help="Tempo in BPM")
    parser.add_argument("--key", type=str, default="C", help="Key signature (e.g. C, G, D, Am)")
    parser.add_argument("--voices", type=int, default=3, help="Number of canonic voices (e.g. 3)")
    parser.add_argument("--offset", type=int, default=2, help="Staggered delay offset in bars (e.g. 2)")
    parser.add_argument("--variations", type=int, default=3, help="Number of variation sections")
    parser.add_argument(
        "--type",
        type=str,
        default="standard",
        choices=["standard", "crab", "mirror", "table"],
        help="Type of canon: standard (staggered), crab (retrograde), mirror (inversion), table (retrograde-inversion)"
    )
    parser.add_argument("--unrolled", action="store_true", help="Output unrolled TMD score without macros (CLI compiler compatible)")
    parser.add_argument("--output", "-o", type=str, default=None, help="Output .tmd file path (default: stdout)")
    parser.add_argument("--seed", type=int, default=None, help="Random seed for reproducible scores")

    args = parser.parse_args()

    gen = CanonGenerator(
        title=args.title,
        tempo=args.tempo,
        key=args.key,
        num_voices=args.voices,
        offset_bars=args.offset,
        num_variations=args.variations,
        canon_type=args.type,
        use_macro=not args.unrolled,
        seed=args.seed,
    )

    tmd_score = gen.generate()

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(tmd_score)
        print(f"Pentatonic canon score written to {args.output}", file=sys.stderr)
    else:
        print(tmd_score)


if __name__ == "__main__":
    main()
