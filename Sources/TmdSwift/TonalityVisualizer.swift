import Foundation

/// SVG and HTML interactive dashboard visualizer for TMD tonality profiles.
public enum TMDTonalityVisualizer {

    /// Generates a standalone, beautifully styled SVG dashboard containing:
    /// 1. Circle of Fifths dial with active nodes and curved trajectory paths.
    /// 2. Section Keyscape Timeline ribbon.
    /// 3. 12-Tone Pitch Class Distribution radar chart.
    public static func generateSVG(_ profile: TMDSongProfile, locale: TMDLocale? = nil) -> String {
        let localizer = TMDLocalizer(locale: locale ?? profile.locale)
        guard let tonality = profile.tonality else {
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"800\" height=\"200\"><text x=\"20\" y=\"40\" fill=\"#888\">No tonality data available</text></svg>"
        }

        let width = 900
        let height = 560

        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(width) \(height)" width="100%" height="100%" style="background:#0f172a; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
          <defs>
            <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stop-color="#1e293b"/>
              <stop offset="100%" stop-color="#0f172a"/>
            </linearGradient>
            <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
              <feGaussianBlur stdDeviation="6" result="blur"/>
              <feComposite in="SourceGraphic" in2="blur" operator="over"/>
            </filter>
            <radialGradient id="nodeActive" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stop-color="#38bdf8"/>
              <stop offset="100%" stop-color="#0284c7"/>
            </radialGradient>
          </defs>

          <!-- Background Card -->
          <rect width="\(width)" height="\(height)" fill="url(#bgGrad)" rx="16"/>

          <!-- Title Bar -->
          <text x="32" y="44" fill="#f8fafc" font-size="20" font-weight="bold">🎼 TMD Tonality Visualizer: \(xmlEscape(profile.title))</text>
          <text x="32" y="68" fill="#94a3b8" font-size="13">Declared Key: \(tonality.globalCorrelation.declaredKey) | Stability: \(tonality.globalCorrelation.stability.rawValue.capitalized) | K-S Correlation: \(String(format: "%0.2f", tonality.globalCorrelation.declaredKeyCorrelation)) | Diatonic: \(String(format: "%0.1f%%", tonality.globalPitchClasses.diatonicRatio * 100.0))</text>

        """

        // 1. Circle of Fifths (Left, Center (240, 260), Radius 140)
        svg += renderCircleOfFifthsSVG(tonality: tonality, localizer: localizer, cx: 220, cy: 260, r: 130)

        // 2. Pitch Class Radar Chart (Right, Center (650, 260), Radius 110)
        svg += renderRadarChartSVG(tonality: tonality, localizer: localizer, cx: 660, cy: 260, r: 110)

        // 3. Section Keyscape Ribbon (Bottom, x: 32, y: 460, width: 836, height: 48)
        svg += renderTimelineRibbonSVG(profile: profile, localizer: localizer, x: 32, y: 450, width: 836, height: 44)

        svg += "\n</svg>"
        return svg
    }

    /// Generates a complete, responsive HTML report containing the embedded SVG dashboard,
    /// inspection summary metrics, and section-by-section tonality breakdown.
    public static func generateHTML(_ profile: TMDSongProfile, locale: TMDLocale? = nil) -> String {
        let localizer = TMDLocalizer(locale: locale ?? profile.locale)
        let svg = generateSVG(profile, locale: localizer.locale)
        let textReport = TMDSongInspector.generateReport(profile, locale: localizer.locale)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(xmlEscape(localizer.text(.htmlTitle))) - \(xmlEscape(profile.title))</title>
          <style>
            :root {
              --bg: #090d16;
              --card: #131c2e;
              --border: #233047;
              --text: #f1f5f9;
              --sub: #94a3b8;
              --accent: #38bdf8;
            }
            body {
              margin: 0;
              padding: 24px;
              background: var(--bg);
              color: var(--text);
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            }
            .container {
              max-width: 960px;
              margin: 0 auto;
            }
            header {
              margin-bottom: 24px;
            }
            h1 {
              margin: 0 0 8px 0;
              font-size: 26px;
              font-weight: 700;
              color: var(--text);
            }
            .subtitle {
              color: var(--sub);
              font-size: 14px;
            }
            .card {
              background: var(--card);
              border: 1px solid var(--border);
              border-radius: 12px;
              overflow: hidden;
              margin-bottom: 24px;
              box-shadow: 0 8px 24px rgba(0,0,0,0.3);
            }
            .viz-wrap {
              padding: 16px;
            }
            pre {
              background: #0b1120;
              padding: 20px;
              border-radius: 8px;
              font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, Courier, monospace;
              font-size: 13px;
              line-height: 1.5;
              overflow-x: auto;
              color: #cbd5e1;
              border: 1px solid var(--border);
            }
          </style>
        </head>
        <body>
          <div class="container">
            <header>
              <h1>\(xmlEscape(localizer.text(.htmlTitle)))</h1>
              <div class="subtitle">\(xmlEscape(localizer.text(.htmlSong))): <strong>\(xmlEscape(profile.title))</strong> | \(xmlEscape(localizer.text(.htmlTempo))): \(profile.initialTempo) BPM | \(xmlEscape(localizer.text(.htmlKey))): \(profile.initialKey) \(xmlEscape(localizer.text(.major)))</div>
            </header>

            <div class="card">
              <div class="viz-wrap">
                \(svg)
              </div>
            </div>

            <div class="card" style="padding: 20px;">
              <h2 style="font-size: 18px; margin-top:0; color:var(--accent);">\(xmlEscape(localizer.text(.htmlDetailedReport)))</h2>
              <pre>\(xmlEscape(textReport))</pre>
            </div>
          </div>
        </body>
        </html>
        """
    }

    // MARK: - Private SVG Sub-Renderers

    private static func renderCircleOfFifthsSVG(tonality: TMDTonalityProfile, localizer: TMDLocalizer, cx: Int, cy: Int, r: Int) -> String {
        // Circle of Fifths order starting from 12 o'clock (0: C, 1: G, 2: D, ..., 11: F)
        let fifthsCircle: [(name: String, step: Int)] = [
            ("C", 0), ("G", 1), ("D", 2), ("A", 3), ("E", 4), ("B", 5),
            ("F#", 6), ("Db", -5), ("Ab", -4), ("Eb", -3), ("Bb", -2), ("F", -1)
        ]

        var activeSteps = Set<Int>()
        for sec in tonality.sections {
            activeSteps.insert(sec.fifthsPosition)
        }

        var s = "\n  <!-- Circle of Fifths -->\n"
        s += "  <text x=\"\(cx)\" y=\"\(cy - r - 30)\" fill=\"#e2e8f0\" font-size=\"14\" font-weight=\"600\" text-anchor=\"middle\">\(xmlEscape(localizer.text(.circleOfFifthsTitle)))</text>\n"
        s += "  <circle cx=\"\(cx)\" cy=\"\(cy)\" r=\"\(r)\" fill=\"none\" stroke=\"#334155\" stroke-width=\"2\" stroke-dasharray=\"4,4\"/>\n"

        // Trajectory connector lines
        var coordsByStep: [Int: (x: Double, y: Double)] = [:]
        for (i, item) in fifthsCircle.enumerated() {
            let angle = (Double(i) * 30.0 - 90.0) * Double.pi / 180.0
            let px = Double(cx) + Double(r) * cos(angle)
            let py = Double(cy) + Double(r) * sin(angle)
            coordsByStep[item.step] = (px, py)
        }

        let path = tonality.circleOfFifthsPath
        if path.count > 1 {
            var pathData = ""
            for (idx, step) in path.enumerated() {
                if let pt = coordsByStep[step] {
                    pathData += idx == 0 ? "M \(String(format: "%0.1f", pt.x)) \(String(format: "%0.1f", pt.y))" : " L \(String(format: "%0.1f", pt.x)) \(String(format: "%0.1f", pt.y))"
                }
            }
            s += "  <path d=\"\(pathData)\" fill=\"none\" stroke=\"#38bdf8\" stroke-width=\"3\" stroke-linecap=\"round\" stroke-linejoin=\"round\" filter=\"url(#glow)\" opacity=\"0.8\"/>\n"
        }

        // Draw 12 nodes
        for (i, item) in fifthsCircle.enumerated() {
            let angle = (Double(i) * 30.0 - 90.0) * Double.pi / 180.0
            let px = Double(cx) + Double(r) * cos(angle)
            let py = Double(cy) + Double(r) * sin(angle)
            let isActive = activeSteps.contains(item.step)

            let fill = isActive ? "url(#nodeActive)" : "#1e293b"
            let stroke = isActive ? "#7dd3fc" : "#475569"
            let textFill = isActive ? "#ffffff" : "#94a3b8"
            let nodeRadius = isActive ? 18 : 13
            let weight = isActive ? "bold" : "normal"
            let filter = isActive ? " filter=\"url(#glow)\"" : ""

            s += "  <circle cx=\"\(String(format: "%0.1f", px))\" cy=\"\(String(format: "%0.1f", py))\" r=\"\(nodeRadius)\" fill=\"\(fill)\" stroke=\"\(stroke)\" stroke-width=\"2\"\(filter)/>\n"
            s += "  <text x=\"\(String(format: "%0.1f", px))\" y=\"\(String(format: "%0.1f", py + 4.5))\" fill=\"\(textFill)\" font-size=\"11\" font-weight=\"\(weight)\" text-anchor=\"middle\">\(item.name)</text>\n"
        }

        return s
    }

    private static func renderRadarChartSVG(tonality: TMDTonalityProfile, localizer: TMDLocalizer, cx: Int, cy: Int, r: Int) -> String {
        let pitchClassNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let weights = tonality.globalPitchClasses.weights
        let maxWeight = max(0.001, weights.max() ?? 1.0)

        var s = "\n  <!-- Pitch Class Radar Chart -->\n"
        s += "  <text x=\"\(cx)\" y=\"\(cy - r - 30)\" fill=\"#e2e8f0\" font-size=\"14\" font-weight=\"600\" text-anchor=\"middle\">\(xmlEscape(localizer.text(.pitchClassDistributionTitle)))</text>\n"

        // Concentric web circles
        for step in [0.25, 0.5, 0.75, 1.0] {
            s += "  <circle cx=\"\(cx)\" cy=\"\(cy)\" r=\"\(Double(r) * step)\" fill=\"none\" stroke=\"#1e293b\" stroke-width=\"1\"/>\n"
        }

        // Spokes and labels
        for i in 0..<12 {
            let angle = (Double(i) * 30.0 - 90.0) * Double.pi / 180.0
            let x2 = Double(cx) + Double(r) * cos(angle)
            let y2 = Double(cy) + Double(r) * sin(angle)
            let labelX = Double(cx) + Double(r + 18) * cos(angle)
            let labelY = Double(cy) + Double(r + 18) * sin(angle) + 4.0

            s += "  <line x1=\"\(cx)\" y1=\"\(cy)\" x2=\"\(String(format: "%0.1f", x2))\" y2=\"\(String(format: "%0.1f", y2))\" stroke=\"#24324d\" stroke-width=\"1\"/>\n"
            s += "  <text x=\"\(String(format: "%0.1f", labelX))\" y=\"\(String(format: "%0.1f", labelY))\" fill=\"#94a3b8\" font-size=\"10\" text-anchor=\"middle\">\(pitchClassNames[i])</text>\n"
        }

        // Polygon points
        var points: [String] = []
        for i in 0..<12 {
            let angle = (Double(i) * 30.0 - 90.0) * Double.pi / 180.0
            let normalized = weights[i] / maxWeight
            let dist = Double(r) * normalized
            let px = Double(cx) + dist * cos(angle)
            let py = Double(cy) + dist * sin(angle)
            points.append("\(String(format: "%0.1f,%0.1f", px, py))")
        }

        let polyStr = points.joined(separator: " ")
        s += "  <polygon points=\"\(polyStr)\" fill=\"#38bdf8\" fill-opacity=\"0.35\" stroke=\"#38bdf8\" stroke-width=\"2\" filter=\"url(#glow)\"/>\n"

        return s
    }

    private static func renderTimelineRibbonSVG(profile: TMDSongProfile, localizer: TMDLocalizer, x: Int, y: Int, width: Int, height: Int) -> String {
        let sections = profile.timing.sections
        let totalDuration = max(0.001, profile.timing.totalDurationSeconds)

        var s = "\n  <!-- Section Keyscape Timeline Ribbon -->\n"
        s += "  <text x=\"\(x)\" y=\"\(y - 12)\" fill=\"#e2e8f0\" font-size=\"14\" font-weight=\"600\">\(xmlEscape(localizer.text(.timelineTitle)))</text>\n"
        s += "  <rect x=\"\(x)\" y=\"\(y)\" width=\"\(width)\" height=\"\(height)\" fill=\"#1e293b\" rx=\"8\"/>\n"

        // Color palette for keys based on fifths distance
        let keyColors = [
            "#38bdf8", // C
            "#60a5fa", // G
            "#818cf8", // D
            "#a78bfa", // A
            "#c084fc", // E
            "#e879f9", // B
            "#f472b6", // F#
            "#fb7185", // Db
            "#f87171", // Ab
            "#fb923c", // Eb
            "#fbbf24", // Bb
            "#34d399", // F
        ]

        var currentX = Double(x)
        for (idx, sec) in sections.enumerated() {
            let secWidth = (sec.durationSeconds / totalDuration) * Double(width)
            let colorIdx = (sec.keyOffset % 12 + 12) % 12
            let color = keyColors[colorIdx]

            s += "  <rect x=\"\(String(format: "%0.1f", currentX))\" y=\"\(y)\" width=\"\(String(format: "%0.1f", secWidth))\" height=\"\(height)\" fill=\"\(color)\" fill-opacity=\"0.85\" stroke=\"#0f172a\" stroke-width=\"1.5\" rx=\"4\"/>\n"
            if secWidth > 40 {
                let textX = currentX + secWidth / 2.0
                let keyLabel: String
                if let tonality = profile.tonality, idx < tonality.sections.count {
                    keyLabel = tonality.sections[idx].declaredKey
                } else {
                    keyLabel = "\(sec.keyOffset)"
                }
                s += "  <text x=\"\(String(format: "%0.1f", textX))\" y=\"\(y + height / 2 + 5)\" fill=\"#ffffff\" font-size=\"11\" font-weight=\"bold\" text-anchor=\"middle\">\(xmlEscape(sec.name)) [\(keyLabel)]</text>\n"
            }
            currentX += secWidth
        }

        return s
    }

    private static func xmlEscape(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
           .replacingOccurrences(of: "'", with: "&apos;")
    }
}
