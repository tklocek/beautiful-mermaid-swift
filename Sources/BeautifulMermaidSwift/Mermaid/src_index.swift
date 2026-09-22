// Ported from original/src/index.ts
import Foundation
import ElkSwift

public struct RenderOptions: Sendable {
    public var bg: String?
    public var fg: String?
    public var line: String?
    public var accent: String?
    public var muted: String?
    public var surface: String?
    public var border: String?
    public var font: String?
    /// The colours series are drawn in, in order — see `DiagramColors.series`.
    public var series: [String]?
    public var transparent: Bool?
    public var interactive: Bool?

    public init(
        bg: String? = nil,
        fg: String? = nil,
        line: String? = nil,
        accent: String? = nil,
        muted: String? = nil,
        surface: String? = nil,
        border: String? = nil,
        font: String? = nil,
        series: [String]? = nil,
        transparent: Bool? = nil,
        interactive: Bool? = nil
    ) {
        self.bg = bg
        self.fg = fg
        self.line = line
        self.accent = accent
        self.muted = muted
        self.surface = surface
        self.border = border
        self.font = font
        self.series = series
        self.transparent = transparent
        self.interactive = interactive
    }
}

public struct DiagramColors: Sendable {
    public var bg: String
    public var fg: String
    public var line: String?
    public var accent: String?
    public var muted: String?
    public var surface: String?
    public var border: String?

    /// The colours series are drawn in — a pie's slices, a chart's bars and lines — in the
    /// order they are used, repeating once the series outnumber them.
    ///
    /// `nil` derives them from `accent`, which is what this library has always done and
    /// remains the right answer for a theme that names one accent and nothing else. It is
    /// not the only reasonable palette, and until now it was the only reachable one: a
    /// caller with a palette of its own — one shared with the rest of an application, or
    /// chosen for a qualitative scale rather than a ramp of one hue — had no way to say so,
    /// because every renderer derived its colours privately.
    public var series: [String]?

    public init(
        bg: String,
        fg: String,
        line: String? = nil,
        accent: String? = nil,
        muted: String? = nil,
        surface: String? = nil,
        border: String? = nil,
        series: [String]? = nil
    ) {
        self.bg = bg
        self.fg = fg
        self.line = line
        self.accent = accent
        self.muted = muted
        self.surface = surface
        self.border = border
        self.series = series
    }
}

private enum _IndexDefaults {
    static let bg = "#FFFFFF"
    static let fg = "#27272A"
}

private enum _DiagramRoutingType {
    case flowchart
    case sequence
    case `class`
    case er
    case xychart
    case piechart
}

private func _decodeXML(_ text: String) -> String {
    // Aligns with TS decodeXML intent for markdown-escaped Mermaid source.
    text
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&apos;", with: "'")
        .replacingOccurrences(of: "&amp;", with: "&")
}

/// The lines a diagram is actually made of.
///
/// Blank lines and `%%` comments carry no structure, so nothing downstream should see
/// them — including the type detection, which reads the first of these as the header.
private func _diagramLines(_ text: String) -> [String] {
    text
        .components(separatedBy: CharacterSet(charactersIn: "\n;"))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
}

/// - Parameter header: the diagram's declaration — `_diagramLines(_:).first`, never the
///   raw first line of the document. A document may open with comments or blank lines,
///   and a header read from those matches no prefix and silently routes to flowchart.
private func detectDiagramType(header: String) -> _DiagramRoutingType {
    let firstLine = header.lowercased()

    if firstLine.range(of: "^sequencediagram\\s*$", options: .regularExpression) != nil {
        return .sequence
    }
    if firstLine.range(of: "^classdiagram\\s*$", options: .regularExpression) != nil {
        return .class
    }
    if firstLine.range(of: "^erdiagram\\s*$", options: .regularExpression) != nil {
        return .er
    }
    if firstLine.hasPrefix("xychart") {
        return .xychart
    }
    if _isPieChartHeader(firstLine) {
        return .piechart
    }

    return .flowchart
}

private func buildColors(_ options: RenderOptions) -> DiagramColors {
    DiagramColors(
        bg: options.bg ?? _IndexDefaults.bg,
        fg: options.fg ?? _IndexDefaults.fg,
        line: options.line,
        accent: options.accent,
        muted: options.muted,
        surface: options.surface,
        border: options.border,
        series: options.series
    )
}

public func renderMermaidSVG(
    _ text: String,
    _ options: RenderOptions = RenderOptions()
) throws -> String {
    _ = ElkSwift.version

    let decodedText = _decodeXML(text)
    let colors = buildColors(options)
    let font = options.font ?? "Inter"
    let transparent = options.transparent ?? false
    // One line list, used both to choose the renderer and to feed it. Computing it twice
    // is how the two came to disagree about comments in the first place.
    let lines = _diagramLines(decodedText)
    let diagramType = detectDiagramType(header: lines.first ?? "")

    switch diagramType {
    case .sequence:
        let diagram = try parseSequenceDiagram(lines)
        let positioned = try layoutSequenceDiagram(diagram, options)
        return try renderSequenceSvg(positioned, colors, font, transparent)
    case .class:
        let diagram = try parseClassDiagram(lines)
        let positioned = try layoutClassDiagramSync(diagram, options: options)
        return try renderClassSvg(positioned, colors, font, transparent)
    case .er:
        let diagram = try parseErDiagram(lines)
        let positioned = try layoutErDiagramSync(diagram, options: options)
        return try renderErSvg(positioned, colors, font, transparent)
    case .xychart:
        let chart = parseXYChart(lines)
        let positioned = layoutXYChart(chart, options)
        return renderXYChartSvg(positioned, colors, font, transparent, interactive: options.interactive ?? false)
    case .piechart:
        let chart = parsePieChart(lines)
        let positioned = layoutPieChart(chart, options)
        return renderPieChartSvg(positioned, colors, font, transparent)
    case .flowchart:
        let graph = try parseMermaid(decodedText)
        let positioned = try layoutGraphSync(graph, options)
        return try renderSvg(positioned, colors, font, transparent)
    }
}

public func renderMermaidSVGAsync(
    _ text: String,
    _ options: RenderOptions = RenderOptions()
) async throws -> String {
    try renderMermaidSVG(text, options)
}

@available(*, deprecated, message: "Use renderMermaidSVG")
public func renderMermaidSync(
    _ text: String,
    _ options: RenderOptions = RenderOptions()
) throws -> String {
    try renderMermaidSVG(text, options)
}

@available(*, deprecated, message: "Use renderMermaidSVGAsync")
public func renderMermaid(
    _ text: String,
    _ options: RenderOptions = RenderOptions()
) async throws -> String {
    try await renderMermaidSVGAsync(text, options)
}

open class original_src_index {
    public init() {}

    // Marker to keep transpiled outputs linked to elk-swift runtime.
    public static let __elkVersion = ElkSwift.version
}
