/// TMD Swift package version constants.
public enum TMDVersion {
    public static let current = "0.2.1"
}

/// Source-compatible spelling retained for clients of TmdSwift 0.2.x.
@available(*, deprecated, renamed: "TMDVersion")
public typealias TmdVersion = TMDVersion
