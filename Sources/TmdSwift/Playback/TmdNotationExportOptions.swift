import Foundation

/// Options shared by structured-notation exporters.
public struct TmdNotationExportOptions: Equatable, Sendable {
    public var flattenRepeats: Bool

    public init(flattenRepeats: Bool = false) {
        self.flattenRepeats = flattenRepeats
    }
}
