import Foundation

public enum TmdTestHelper {
    /// Discovers the path to the compiled `tmd` CLI binary across Xcode, standard swift-build,
    /// SPM runner directories, and CI runner environments (macOS, Linux, Windows).
    public static func findTmdExecutable() -> URL? {
        // 0. Environment variable explicitly set by build or CI runner
        if let envPath = ProcessInfo.processInfo.environment["TMD_BIN_PATH"], !envPath.isEmpty {
            let envURL = URL(fileURLWithPath: envPath)
            if FileManager.default.isExecutableFile(atPath: envURL.path) {
                return envURL
            }
        }

        // 1. Direct sibling of test runner process (e.g. .build/debug/tmd or .build/out/Products/Debug/tmd)
        let procArg0 = ProcessInfo.processInfo.arguments[0]
        let procURL = URL(fileURLWithPath: procArg0)
        let siblingURL = procURL.deletingLastPathComponent().appendingPathComponent("tmd")
        if FileManager.default.isExecutableFile(atPath: siblingURL.path) {
            return siblingURL
        }
        let siblingExeURL = procURL.deletingLastPathComponent().appendingPathComponent("tmd.exe")
        if FileManager.default.isExecutableFile(atPath: siblingExeURL.path) {
            return siblingExeURL
        }

        // 2. Walk up directory hierarchy from test runner or current working directory
        let searchBases = [
            FileManager.default.currentDirectoryPath,
            procURL.deletingLastPathComponent().path
        ]

        let candidates = [
            ".build/out/Products/Debug/tmd",
            ".build/out/Products/Debug/tmd.exe",
            ".build/apple/Products/Debug/tmd",
            ".build/debug/tmd",
            ".build/debug/tmd.exe",
            ".build/release/tmd",
            ".build/release/tmd.exe",
            "/usr/local/bin/tmd"
        ]

        for base in searchBases {
            let baseURL = URL(fileURLWithPath: base)
            for cand in candidates {
                let candidateURL = baseURL.appendingPathComponent(cand)
                if FileManager.default.isExecutableFile(atPath: candidateURL.path) {
                    return candidateURL
                }
            }
        }

        // 3. Search under .build recursively for executable named "tmd" or "tmd.exe"
        let buildDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build")
        if let enumerator = FileManager.default.enumerator(at: buildDir, includingPropertiesForKeys: [.isExecutableKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                let last = fileURL.lastPathComponent.lowercased()
                if last == "tmd" || last == "tmd.exe" {
                    if FileManager.default.isExecutableFile(atPath: fileURL.path) {
                        return fileURL
                    }
                }
            }
        }

        return nil
    }
}
