import Foundation

/// A General MIDI instrument selected from a TMD paragraph name.
public enum MIDIInstrument: Equatable, Sendable {
    // 0-7: Piano
    case piano
    case acousticGrandPiano
    case brightAcousticPiano
    case electricGrandPiano
    case honkyTonkPiano
    case electricPiano
    case electricPiano2
    case harpsichord
    case clavinet

    // 8-15: Chromatic Percussion
    case celesta
    case glockenspiel
    case musicBox
    case vibraphone
    case marimba
    case xylophone
    case tubularBells
    case dulcimer

    // 16-23: Organ
    case organ
    case drawbarOrgan
    case percussiveOrgan
    case rockOrgan
    case churchOrgan
    case reedOrgan
    case accordion
    case harmonica
    case tangoAccordion

    // 24-31: Guitar
    case guitar
    case nylonGuitar
    case steelGuitar
    case jazzGuitar
    case cleanGuitar
    case mutedGuitar
    case overdriveGuitar
    case distortionGuitar
    case guitarHarmonics

    // 32-39: Bass
    case bass
    case acousticBass
    case fingerBass
    case pickBass
    case fretlessBass
    case slapBass1
    case slapBass2
    case synthBass1
    case synthBass2

    // 40-47: Solo Strings
    case violin
    case viola
    case cello
    case contrabass
    case tremoloStrings
    case pizzicatoStrings
    case orchestralHarp
    case timpani

    // 48-55: Ensemble
    case strings
    case stringEnsemble1
    case stringEnsemble2
    case synthStrings1
    case synthStrings2
    case choir
    case choirAahs
    case voiceOohs
    case synthVoice
    case orchestraHit

    // 56-63: Brass
    case trumpet
    case trombone
    case tuba
    case mutedTrumpet
    case frenchHorn
    case brass
    case brassSection
    case synthBrass1
    case synthBrass2

    // 64-71: Reed
    case sopranoSax
    case altoSax
    case sax
    case tenorSax
    case baritoneSax
    case oboe
    case englishHorn
    case bassoon
    case clarinet

    // 72-79: Pipe
    case piccolo
    case flute
    case recorder
    case panFlute
    case blownBottle
    case shakuhachi
    case whistle
    case ocarina

    // 80-87: Synth Lead
    case leadSquare
    case leadSawtooth
    case leadCalliope
    case leadChiff
    case leadCharang
    case leadVoice
    case leadFifths
    case leadBassAndLead

    // 88-95: Synth Pad
    case pad
    case padNewAge
    case padWarm
    case padPolysynth
    case padChoir
    case padBowed
    case padMetallic
    case padHalo
    case padSweep

    // 96-103: Synth Effects
    case fxRain
    case fxSoundtrack
    case fxCrystal
    case fxAtmosphere
    case fxBrightness
    case fxGoblins
    case fxEchoes
    case fxSciFi

    // 104-111: Ethnic
    case sitar
    case banjo
    case shamisen
    case koto
    case kalimba
    case bagpipe
    case fiddle
    case shanai

    // 112-119: Percussive
    case tinkleBell
    case agogo
    case steelDrums
    case woodblock
    case taikoDrum
    case melodicTom
    case synthDrum
    case reverseCymbal

    // 120-127: Sound Effects
    case guitarFretNoise
    case breathNoise
    case seashore
    case birdTweet
    case telephoneRing
    case helicopter
    case applause
    case gunshot

    // Special
    case generic(program: UInt8)
    case percussion
    case unknown

    /// Resolves a human-readable TMD instrument name.
    public static func resolve(_ name: String) -> MIDIInstrument {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 1. Direct number check (e.g. "40", "prog:40", "program:40", "prg40", "p40")
        if let directProg = UInt8(trimmed), directProg <= 127 {
            return .generic(program: directProg)
        }
        for prefix in ["prog:", "program:", "prg:", "p:", "prog", "program", "prg"] {
            if trimmed.hasPrefix(prefix) {
                let suffix = trimmed.dropFirst(prefix.count).trimmingCharacters(
                    in: .whitespacesAndNewlines)
                if let prog = UInt8(suffix), prog <= 127 {
                    return .generic(program: prog)
                }
            }
        }

        // 2. Percussion channel check
        let drumAliases = [
            "drum", "drums", "groove", "percussion", "beat", "drumkit", "kit", "cajon", "snare",
            "kick", "hihat", "爵士鼓", "打擊", "鼓",
        ]
        if drumAliases.contains(where: { trimmed.contains($0) })
            || (trimmed.contains("perc") && !trimmed.contains("percussive"))
        {
            return .percussion
        }

        // 3. Priority ordered aliases table (specific words must come before generic substrings)
        let aliases: [(MIDIInstrument, [String])] = [
            // Sound Effects (120-127)
            (.guitarFretNoise, ["fretnoise", "guitar_fret", "fxgret"]),
            (.breathNoise, ["breathnoise", "breath"]),
            (.seashore, ["seashore", "ocean"]),
            (.birdTweet, ["birdtweet", "bird"]),
            (.telephoneRing, ["telephonering", "telephone", "phone"]),
            (.helicopter, ["helicopter", "chopper"]),
            (.applause, ["applause", "clapping", "cheer"]),
            (.gunshot, ["gunshot", "gun"]),

            // Percussive & Bells (112-119)
            (.steelDrums, ["steeldrum", "steelpan"]),
            (.tinkleBell, ["tinklebell", "tinkle"]),
            (.taikoDrum, ["taiko"]),
            (.melodicTom, ["melodictom", "tom"]),
            (.synthDrum, ["synthdrum"]),
            (.reverseCymbal, ["reversecymbal", "cymbal"]),
            (.woodblock, ["woodblock"]),
            (.agogo, ["agogo"]),

            // Ethnic (104-111)
            (.shamisen, ["shamisen"]),
            (.bagpipe, ["bagpipe", "bagpipes"]),
            (.kalimba, ["kalimba", "mbira"]),
            (.shanai, ["shanai", "shehnai", "suona", "嗩吶"]),
            (.sitar, ["sitar"]),
            (.banjo, ["banjo"]),
            (.koto, ["guzheng", "zheng", "koto", "古箏", "琵琶"]),
            (.fiddle, ["fiddle", "erhu", "二胡"]),

            // Synth Effects (96-103)
            (.fxSoundtrack, ["soundtrack"]),
            (.fxAtmosphere, ["atmosphere"]),
            (.fxBrightness, ["brightness"]),
            (.fxGoblins, ["goblins"]),
            (.fxCrystal, ["crystal"]),
            (.fxEchoes, ["echoes"]),
            (.fxSciFi, ["scifi", "sci-fi"]),
            (.fxRain, ["fxrain", "rain"]),

            // Synth Pads (88-95)
            (.padPolysynth, ["polysynth"]),
            (.padNewAge, ["newage"]),
            (.padMetallic, ["metallic"]),
            (.padChoir, ["choirpad"]),
            (.padBowed, ["bowed"]),
            (.padSweep, ["sweep"]),
            (.padHalo, ["halo"]),
            (.padWarm, ["warm", "pad"]),

            // Guitar (24-31) - Prioritize lead guitar and compound guitar names before generic synth lead
            (.guitarHarmonics, ["guitarharmonics", "harmonics"]),
            (.distortionGuitar, ["distortion", "dist", "fuzz", "heavy", "metal"]),
            (
                .overdriveGuitar,
                [
                    "overdrive", "od", "rockguitar", "leadguitar", "lead-guitar", "electricguitar",
                    "electric-guitar", "電吉他",
                ]
            ),
            (.cleanGuitar, ["cleanguitar", "electricclean"]),
            (.mutedGuitar, ["mutedguitar"]),
            (.jazzGuitar, ["jazzguitar"]),
            (.nylonGuitar, ["nylon", "classicalguitar", "ukulele", "uke"]),
            (
                .steelGuitar,
                [
                    "steelguitar", "steel", "acousticguitar", "guitar", "gtr", "mandolin", "木吉他",
                    "吉他",
                ]
            ),

            // Synth Leads (80-87)
            (.leadBassAndLead, ["basslead"]),
            (.leadVoice, ["voicelead"]),
            (.leadSawtooth, ["sawtooth", "sawlead", "saw"]),
            (.leadCalliope, ["calliope"]),
            (.leadCharang, ["charang"]),
            (.leadChiff, ["chiff"]),
            (.leadFifths, ["fifths", "fifth"]),
            (.leadSquare, ["square", "leadsynth", "lead_synth", "lead"]),

            // Pipe (72-79)
            (.shakuhachi, ["shakuhachi", "xiao", "簫"]),
            (.panFlute, ["panflute"]),
            (.blownBottle, ["bottle"]),
            (.recorder, ["recorder"]),
            (.ocarina, ["ocarina"]),
            (.piccolo, ["piccolo", "短笛"]),
            (.flute, ["flute", "pipe", "dizi", "長笛", "竹笛"]),
            (.whistle, ["whistle"]),

            // Reed (64-71) - Put compound names before sax/horn/bass
            (.englishHorn, ["englishhorn", "coranglais"]),
            (.frenchHorn, ["frenchhorn", "法國號"]),
            (.bassoon, ["bassoon", "fagott", "低音管"]),
            (.clarinet, ["clarinet", "單簧管", "豎笛"]),
            (.oboe, ["oboe", "雙簧管"]),
            (.baritoneSax, ["baritonesax", "barisax"]),
            (.sopranoSax, ["sopranosax"]),
            (.tenorSax, ["tenorsax"]),
            (.altoSax, ["altosax"]),
            (.sax, ["sax", "saxophone", "薩克斯風"]),

            // Brass (56-63)
            (.mutedTrumpet, ["mutedtrumpet"]),
            (.synthBrass1, ["synthbrass"]),
            (.trumpet, ["trumpet", "cornet", "flugelhorn", "小號"]),
            (.trombone, ["trombone", "euphonium", "長號"]),
            (.tuba, ["tuba", "低音號"]),
            (.frenchHorn, ["horn"]),
            (.brass, ["brass", "銅管"]),

            // Ensemble & Choir (48-55)
            (.orchestraHit, ["orchestrahit", "orchhit", "orchestra", "hit"]),
            (.synthVoice, ["synthvoice"]),
            (.voiceOohs, ["voiceooh", "oohs", "voice"]),
            (
                .choir,
                [
                    "choiraah", "aahs", "choir", "vocal", "singer", "vox", "chorus", "miku", "utau",
                    "teto", "sing", "soprano", "alto", "tenor", "baritone", "主唱", "人聲", "合唱",
                ]
            ),
            (.synthStrings1, ["synthstrings"]),
            (.stringEnsemble2, ["slowstrings"]),
            (.stringEnsemble1, ["string", "strings", "str", "弦樂"]),

            // Solo Strings (40-47)
            (.pizzicatoStrings, ["pizzicato", "pizz", "pluck"]),
            (.tremoloStrings, ["tremolo"]),
            (.harpsichord, ["harpsichord", "cembalo"]),
            (.orchestralHarp, ["harp"]),
            (.timpani, ["timpani", "kettledrum"]),
            (
                .contrabass,
                [
                    "contrabass", "doublebass", "uprightbass", "upright", "stringbass", "低音提琴",
                ]
            ),
            (.cello, ["cello", "violoncello", "大提琴"]),
            (.viola, ["viola", "中提琴"]),
            (.violin, ["violin", "小提琴"]),

            // Bass (32-39)
            (.fretlessBass, ["fretless"]),
            (.slapBass1, ["slapbass", "slap"]),
            (.synthBass1, ["synthbass"]),
            (.acousticBass, ["acousticbass"]),
            (.pickBass, ["pickbass"]),
            (.fingerBass, ["fingerbass", "electricbass"]),
            (.bass, ["bass", "sub", "貝斯"]),

            // Organ (16-23)
            (.tangoAccordion, ["tangoaccordion", "bandoneon", "tango"]),
            (.percussiveOrgan, ["percussiveorgan", "percussive"]),
            (.rockOrgan, ["rockorgan"]),
            (.churchOrgan, ["churchorgan", "church"]),
            (.reedOrgan, ["reedorgan", "reed", "sheng", "笙"]),
            (.accordion, ["accordion"]),
            (.harmonica, ["harmonica"]),
            (.organ, ["organ", "drawbar", "b3", "hammond"]),

            // Chromatic Percussion (8-15)
            (.glockenspiel, ["glockenspiel", "glock"]),
            (.tubularBells, ["tubularbell", "tubular", "chimes", "bell"]),
            (.vibraphone, ["vibraphone", "vibes", "vibe"]),
            (.musicBox, ["musicbox"]),
            (.xylophone, ["xylophone"]),
            (.marimba, ["marimba"]),
            (.dulcimer, ["dulcimer", "santur"]),
            (.celesta, ["celesta"]),
            (.koto, ["pipa", "lute"]),

            // Piano & Generic Role Fallbacks (0-7)
            (.electricPiano2, ["dx7", "fmep"]),
            (.electricPiano, ["electricpiano", "epiano", "ep", "rhodes", "wurlitzer"]),
            (.honkyTonkPiano, ["honkytonk", "honky"]),
            (.brightAcousticPiano, ["brightpiano", "brightacoustic", "bright"]),
            (.electricGrandPiano, ["electricgrand"]),
            (.clavinet, ["clavinet", "clavi", "clav"]),
            (.leadSquare, ["synth", "syn", "arp", "arpeggio", "melody", "motif", "主旋律"]),
            (
                .piano,
                [
                    "piano", "pno", "keyboard", "keys", "grand", "chord", "chords", "harmony",
                    "accompaniment", "accomp", "鋼琴", "和弦",
                ]
            ),
        ]

        return aliases.first { _, terms in terms.contains { trimmed.contains($0) } }?.0 ?? .unknown
    }

    /// Returns whether `name` resolves to a recognized instrument or role alias.
    public static func isRecognized(_ name: String) -> Bool {
        resolve(name) != .unknown
    }

    /// The zero-based General MIDI program (0-127).
    public var program: UInt8 {
        switch self {
        // 0-7: Piano
        case .piano, .acousticGrandPiano, .unknown: 0
        case .brightAcousticPiano: 1
        case .electricGrandPiano: 2
        case .honkyTonkPiano: 3
        case .electricPiano: 4
        case .electricPiano2: 5
        case .harpsichord: 6
        case .clavinet: 7

        // 8-15: Chromatic Percussion
        case .celesta: 8
        case .glockenspiel: 9
        case .musicBox: 10
        case .vibraphone: 11
        case .marimba: 12
        case .xylophone: 13
        case .tubularBells: 14
        case .dulcimer: 15

        // 16-23: Organ
        case .organ, .drawbarOrgan: 16
        case .percussiveOrgan: 17
        case .rockOrgan: 18
        case .churchOrgan: 19
        case .reedOrgan: 20
        case .accordion: 21
        case .harmonica: 22
        case .tangoAccordion: 23

        // 24-31: Guitar
        case .nylonGuitar: 24
        case .guitar, .steelGuitar: 25
        case .jazzGuitar: 26
        case .cleanGuitar: 27
        case .mutedGuitar: 28
        case .overdriveGuitar: 29
        case .distortionGuitar: 30
        case .guitarHarmonics: 31

        // 32-39: Bass
        case .acousticBass: 32
        case .bass, .fingerBass: 33
        case .pickBass: 34
        case .fretlessBass: 35
        case .slapBass1: 36
        case .slapBass2: 37
        case .synthBass1: 38
        case .synthBass2: 39

        // 40-47: Strings
        case .violin: 40
        case .viola: 41
        case .cello: 42
        case .contrabass: 43
        case .tremoloStrings: 44
        case .pizzicatoStrings: 45
        case .orchestralHarp: 46
        case .timpani: 47

        // 48-55: Ensemble
        case .strings, .stringEnsemble1: 48
        case .stringEnsemble2: 49
        case .synthStrings1: 50
        case .synthStrings2: 51
        case .choir, .choirAahs: 52
        case .voiceOohs: 53
        case .synthVoice: 54
        case .orchestraHit: 55

        // 56-63: Brass
        case .trumpet: 56
        case .trombone: 57
        case .tuba: 58
        case .mutedTrumpet: 59
        case .frenchHorn: 60
        case .brass, .brassSection: 61
        case .synthBrass1: 62
        case .synthBrass2: 63

        // 64-71: Reed
        case .sopranoSax: 64
        case .sax, .altoSax: 65
        case .tenorSax: 66
        case .baritoneSax: 67
        case .oboe: 68
        case .englishHorn: 69
        case .bassoon: 70
        case .clarinet: 71

        // 72-79: Pipe
        case .piccolo: 72
        case .flute: 73
        case .recorder: 74
        case .panFlute: 75
        case .blownBottle: 76
        case .shakuhachi: 77
        case .whistle: 78
        case .ocarina: 79

        // 80-87: Synth Lead
        case .leadSquare: 80
        case .leadSawtooth: 81
        case .leadCalliope: 82
        case .leadChiff: 83
        case .leadCharang: 84
        case .leadVoice: 85
        case .leadFifths: 86
        case .leadBassAndLead: 87

        // 88-95: Synth Pad
        case .padNewAge: 88
        case .pad, .padWarm: 89
        case .padPolysynth: 90
        case .padChoir: 91
        case .padBowed: 92
        case .padMetallic: 93
        case .padHalo: 94
        case .padSweep: 95

        // 96-103: Synth Effects
        case .fxRain: 96
        case .fxSoundtrack: 97
        case .fxCrystal: 98
        case .fxAtmosphere: 99
        case .fxBrightness: 100
        case .fxGoblins: 101
        case .fxEchoes: 102
        case .fxSciFi: 103

        // 104-111: Ethnic
        case .sitar: 104
        case .banjo: 105
        case .shamisen: 106
        case .koto: 107
        case .kalimba: 108
        case .bagpipe: 109
        case .fiddle: 110
        case .shanai: 111

        // 112-119: Percussive
        case .tinkleBell: 112
        case .agogo: 113
        case .steelDrums: 114
        case .woodblock: 115
        case .taikoDrum: 116
        case .melodicTom: 117
        case .synthDrum: 118
        case .reverseCymbal: 119

        // 120-127: Sound Effects
        case .guitarFretNoise: 120
        case .breathNoise: 121
        case .seashore: 122
        case .birdTweet: 123
        case .telephoneRing: 124
        case .helicopter: 125
        case .applause: 126
        case .gunshot: 127

        // Special
        case .generic(let prog): min(prog, 127)
        case .percussion: 0
        }
    }

    /// Whether the instrument must use General MIDI channel 10.
    public var isPercussion: Bool {
        self == .percussion
    }
}
