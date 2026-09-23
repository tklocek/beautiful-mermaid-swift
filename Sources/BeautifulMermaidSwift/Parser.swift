import Foundation
import ElkSwift

internal enum _ElkBridge {
    // Keeps explicit linkage to ElkSwift runtime.
    static var version: String { ElkSwift.version }
}

public enum MermaidParser {
    /// The lines a parser reads, and which line of the source each of them came from.
    ///
    /// Blank lines and comments are dropped, so the position of a line in the result says
    /// nothing about where it was written — `sourceLines[i]` is what says that, counting
    /// from 1 as an editor's gutter does. A parser that wants to hand the number on takes
    /// both; one that does not takes the first and is unchanged.
    ///
    /// Split on `\n` with a trailing `\r` removed rather than on the whole newline set,
    /// because a character-set split turns each `\r\n` into two elements and every line
    /// below the first one in a file written on Windows would be numbered one too high.
    private static func _diagramLines(from source: String) -> (text: [String], sourceLines: [Int]) {
        var text: [String] = [], sourceLines: [Int] = []
        for (index, raw) in source.components(separatedBy: "\n").enumerated() {
            var line = raw
            if line.hasSuffix("\r") { line.removeLast() }
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("%%") else { continue }
            text.append(line)
            sourceLines.append(index + 1)
        }
        return (text, sourceLines)
    }

    private static func _decodeXMLEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
         .replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&#39;", with: "'")
    }

    public static func parse(_ source: String) throws -> MermaidGraph {
        _ = _ElkBridge.version
        let decoded = _decodeXMLEntities(source)
        let (lines, sourceLines) = _diagramLines(from: decoded)
        let firstLine = lines.first?.lowercased() ?? ""

        if firstLine.hasPrefix("sequencediagram") {
            let parsed = try parseSequenceDiagram(lines, sourceLines: sourceLines)
            return MermaidGraph(type: .sequenceDiagram, payload: parsed)
        }
        if firstLine.hasPrefix("classdiagram") {
            let parsed = try parseClassDiagram(lines, sourceLines: sourceLines)
            return MermaidGraph(type: .classDiagram, payload: parsed)
        }
        if firstLine.hasPrefix("erdiagram") {
            let parsed = try parseErDiagram(lines, sourceLines: sourceLines)
            return MermaidGraph(type: .erDiagram, payload: parsed)
        }
        if firstLine.hasPrefix("xychart") {
            let chart = parseXYChart(lines, sourceLines: sourceLines)
            return MermaidGraph(type: .xyChart, payload: chart)
        }
        if _isPieChartHeader(firstLine) {
            let chart = parsePieChart(lines, sourceLines: sourceLines)
            return MermaidGraph(type: .pieChart, payload: chart)
        }

        // Flowchart + stateDiagram-v2 share the same parser entry in the original TS.
        let parsed = try parseMermaid(decoded)
        let parsedType: DiagramType = firstLine.hasPrefix("statediagram") ? .stateDiagram : .flowchart
        return MermaidGraph(type: parsedType, payload: parsed.payload)
    }
}
