import Foundation

/// BCP-47-like identifier for user-facing library output.
///
/// This is intentionally a string-backed value rather than an enum so a new
/// language can be added without changing the public API.
public struct TMDLocale: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public static let zhHant = TMDLocale(rawValue: "zh-Hant")
    public static let en = TMDLocale(rawValue: "en")
}

/// Stable resource keys used by TMD's Swift-library reports.
public enum TMDLocalizationKey: String, Sendable {
    case reportTitle = "report.title"
    case duration = "report.duration"
    case measuresTotal = "report.measuresTotal"
    case keyAndTempo = "report.keyAndTempo"
    case analysisScope = "report.analysisScope"
    case structure = "report.structure"
    case density = "report.density"
    case tracksConcurrently = "report.tracksConcurrently"
    case harmony = "report.harmony"
    case tonalityDiagnosis = "report.tonalityDiagnosis"
    case mood = "report.mood"
    case modulationJourney = "report.modulationJourney"
    case tonalCore = "report.tonalCore"
    case tonalMetrics = "report.tonalMetrics"
    case correlation = "report.correlation"
    case stability = "report.stability"
    case diatonicPurity = "report.diatonicPurity"
    case candidateKeys = "report.candidateKeys"
    case circleOfFifths = "report.circleOfFifths"
    case sectionDetails = "report.sectionDetails"
    case nonDiatonic = "report.nonDiatonic"
    case instrumentRanges = "report.instrumentRanges"
    case notes = "report.notes"
    case semitones = "report.semitones"
    case octaves = "report.octaves"
    case major = "key.major"
    case modulationNone = "tonality.modulation.none"
    case modulationStart = "tonality.modulation.start"
    case modulationStep = "tonality.modulation.step"
    case summaryStable = "tonality.summary.stable"
    case summaryModulating = "tonality.summary.modulating"
    case summaryClean = "tonality.summary.clean"
    case summaryColor = "tonality.summary.color"
    case moodCleanMajor = "tonality.mood.cleanMajor"
    case moodContemporaryMajor = "tonality.mood.contemporaryMajor"
    case moodModal = "tonality.mood.modal"
    case circleOfFifthsTitle = "visualizer.circleOfFifths"
    case pitchClassDistributionTitle = "visualizer.pitchClassDistribution"
    case timelineTitle = "visualizer.timeline"
    case htmlTitle = "visualizer.htmlTitle"
    case htmlSong = "visualizer.htmlSong"
    case htmlTempo = "visualizer.htmlTempo"
    case htmlKey = "visualizer.htmlKey"
    case htmlDetailedReport = "visualizer.htmlDetailedReport"
}

/// Built-in localizer for Swift-library output.
///
/// The catalog is compiled into the library so command-line distributions do
/// not need to install a companion SwiftPM resource bundle.
public struct TMDLocalizer: Sendable {
    public let locale: TMDLocale
    public let fallbackLocale: TMDLocale

    public init(locale: TMDLocale = .zhHant, fallbackLocale: TMDLocale = .en) {
        self.locale = locale
        self.fallbackLocale = fallbackLocale
    }

    public func text(_ key: TMDLocalizationKey, arguments: [String] = []) -> String {
        let localized = lookup(key.rawValue, locale: locale)
        let fallback = lookup(key.rawValue, locale: fallbackLocale)
        let template = localized == key.rawValue ? fallback : localized
        return arguments.enumerated().reduce(template) { result, item in
            result.replacingOccurrences(of: "{\(item.offset)}", with: item.element)
        }
    }

    private func lookup(_ key: String, locale: TMDLocale) -> String {
        TMDLocalizationCatalog.values[locale.rawValue]?[key] ?? key
    }
}

internal struct TMDReportStrings: Sendable {
    let localizer: TMDLocalizer

    var locale: TMDLocale { localizer.locale }
    var songProfile: String { localizer.text(.reportTitle) }
    var duration: String { localizer.text(.duration) }
    var measuresTotal: String { localizer.text(.measuresTotal) }
    var keyAndTempo: String { localizer.text(.keyAndTempo) }
    var analysisScope: String { localizer.text(.analysisScope) }
    var structure: String { localizer.text(.structure) }
    var density: String { localizer.text(.density) }
    var tracksConcurrently: String { localizer.text(.tracksConcurrently) }
    var harmony: String { localizer.text(.harmony) }
    var tonalityDiagnosis: String { localizer.text(.tonalityDiagnosis) }
    var mood: String { localizer.text(.mood) }
    var modulationJourney: String { localizer.text(.modulationJourney) }
    var tonalCore: String { localizer.text(.tonalCore) }
    var tonalMetrics: String { localizer.text(.tonalMetrics) }
    var correlation: String { localizer.text(.correlation) }
    var stability: String { localizer.text(.stability) }
    var diatonicPurity: String { localizer.text(.diatonicPurity) }
    var candidateKeys: String { localizer.text(.candidateKeys) }
    var circleOfFifths: String { localizer.text(.circleOfFifths) }
    var sectionDetails: String { localizer.text(.sectionDetails) }
    var nonDiatonic: String { localizer.text(.nonDiatonic) }
    var instrumentRanges: String { localizer.text(.instrumentRanges) }
    var major: String { localizer.text(.major) }
}
