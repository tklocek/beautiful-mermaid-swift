// Ported from original/src/sequence/parser.ts
import Foundation
import ElkSwift

public struct SequenceDiagram: Sendable {
    public var actors: [SequenceActor]
    public var messages: [SequenceMessage]
    public var blocks: [SequenceBlock]
    public var notes: [SequenceNote]
}

public struct SequenceActor: Sendable {
    public var id: String
    public var label: String
    public var type: String
}

public struct SequenceMessage: Sendable {
    public var from: String
    public var to: String
    public var label: String
    public var lineStyle: String
    public var arrowHead: String
    public var activate: Bool
    public var deactivate: Bool
    /// 1-based index assigned by `autonumber`; nil when autonumbering is off.
    public var sequenceNumber: Int? = nil
}

public struct SequenceBlockDivider: Sendable {
    public var index: Int
    public var label: String
}

public struct SequenceBlock: Sendable {
    public var type: String
    public var label: String
    public var startIndex: Int
    public var endIndex: Int
    public var dividers: [SequenceBlockDivider]
}

public struct SequenceNote: Sendable {
    public var actorIds: [String]
    public var text: String
    public var position: String
    public var afterIndex: Int
}

public struct PositionedSequenceDiagram: Sendable {
    public var width: Double
    public var height: Double
    public var actors: [PositionedSequenceActor]
    public var lifelines: [SequenceLifeline]
    public var messages: [PositionedSequenceMessage]
    public var activations: [SequenceActivation]
    public var blocks: [PositionedSequenceBlock]
    public var notes: [PositionedSequenceNote]
}

public struct PositionedSequenceActor: Sendable {
    public var id: String
    public var label: String
    public var type: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
}

public struct SequenceLifeline: Sendable {
    public var actorId: String
    public var x: Double
    public var topY: Double
    public var bottomY: Double
}

public struct PositionedSequenceMessage: Sendable {
    public var from: String
    public var to: String
    public var label: String
    public var lineStyle: String
    public var arrowHead: String
    public var x1: Double
    public var x2: Double
    public var y: Double
    public var isSelf: Bool
    /// 1-based index assigned by `autonumber`; nil when autonumbering is off.
    public var sequenceNumber: Int? = nil
}

public struct SequenceActivation: Sendable {
    public var actorId: String
    public var x: Double
    public var topY: Double
    public var bottomY: Double
    public var width: Double
}

public struct PositionedSequenceBlockDivider: Sendable {
    public var y: Double
    public var label: String
}

public struct PositionedSequenceBlock: Sendable {
    public var type: String
    public var label: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var dividers: [PositionedSequenceBlockDivider]
}

public struct PositionedSequenceNote: Sendable {
    public var text: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var position: String
    public var actors: [String]
}

public enum SequenceParserError: Error, LocalizedError {
    case invalidHeader(expected: String, found: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidHeader(expected, found):
            return "Invalid sequence diagram header. Expected '\(expected)', found '\(found)'."
        }
    }
}

private struct _OpenBlock {
    var type: String
    var label: String
    var startIndex: Int
    var dividers: [SequenceBlockDivider]
}

public func parseSequenceDiagram(_ lines: [String]) throws -> SequenceDiagram {
    try _parseSequenceDiagramEntry(lines)
}

private func _parseSequenceDiagramEntry(_ lines: [String]) throws -> SequenceDiagram {
    guard let header = lines.first else {
        return SequenceDiagram(actors: [], messages: [], blocks: [], notes: [])
    }

    if header.range(of: #"^sequencediagram\s*$"#, options: [.regularExpression, .caseInsensitive]) == nil {
        throw SequenceParserError.invalidHeader(expected: "sequenceDiagram", found: header)
    }

    var diagram = SequenceDiagram(actors: [], messages: [], blocks: [], notes: [])
    var actorIds = Set<String>()
    var blockStack: [_OpenBlock] = []
    // nil = autonumbering off. Mermaid allows `autonumber`, `autonumber <start>`,
    // `autonumber <start> <step>` and `autonumber off`, switchable mid-diagram.
    var autonumberNext: Int?
    var autonumberStep = 1

    if lines.count <= 1 {
        return diagram
    }

    for rawLine in lines.dropFirst() {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty {
            continue
        }

        if let m = _match(#"^autonumber(?:\s+(\S+))?(?:\s+(\S+))?\s*$"#, line, caseInsensitive: true) {
            let start = m.count > 1 ? m[1] : ""
            let step = m.count > 2 ? m[2] : ""
            if start.lowercased() == "off" {
                autonumberNext = nil
            } else {
                autonumberNext = Int(start) ?? 1
                autonumberStep = Int(step) ?? 1
            }
            continue
        }

        if let m = _match(#"^(participant|actor)\s+(\S+?)(?:\s+as\s+(.+))?$"#, line) {
            let type = m[1].lowercased()
            let id = m[2]
            let label = _normalizeLineBreaks((m.count > 3 ? m[3] : "").isEmpty ? id : m[3])
            if !actorIds.contains(id) {
                actorIds.insert(id)
                diagram.actors.append(SequenceActor(id: id, label: label, type: type))
            }
            continue
        }

        if let m = _match(#"^Note\s+(left of|right of|over)\s+([^:]+):\s*(.+)$"#, line, caseInsensitive: true) {
            let positionRaw = m[1].lowercased()
            let actorTokens = m[2].split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            let text = _normalizeLineBreaks(m[3].trimmingCharacters(in: .whitespacesAndNewlines))
            for id in actorTokens where !id.isEmpty {
                _ensureActor(&diagram, &actorIds, id)
            }
            let pos: String = positionRaw == "left of" ? "left" : (positionRaw == "right of" ? "right" : "over")
            diagram.notes.append(
                SequenceNote(
                    actorIds: actorTokens,
                    text: text,
                    position: pos,
                    afterIndex: diagram.messages.count - 1
                )
            )
            continue
        }

        if let m = _match(#"^(loop|alt|opt|par|critical|break|rect)\s*(.*)$"#, line) {
            blockStack.append(
                _OpenBlock(
                    type: m[1],
                    label: _normalizeLineBreaks(m[2].trimmingCharacters(in: .whitespacesAndNewlines)),
                    startIndex: diagram.messages.count,
                    dividers: []
                )
            )
            continue
        }

        if let m = _match(#"^(else|and)\s*(.*)$"#, line), !blockStack.isEmpty {
            _ = m[1]
            blockStack[blockStack.count - 1].dividers.append(
                SequenceBlockDivider(
                    index: diagram.messages.count,
                    label: _normalizeLineBreaks(m[2].trimmingCharacters(in: .whitespacesAndNewlines))
                )
            )
            continue
        }

        if line == "end", !blockStack.isEmpty {
            let completed = blockStack.removeLast()
            diagram.blocks.append(
                SequenceBlock(
                    type: completed.type,
                    label: completed.label,
                    startIndex: completed.startIndex,
                    endIndex: max(diagram.messages.count - 1, completed.startIndex),
                    dividers: completed.dividers
                )
            )
            continue
        }

        if var msg = _parseSequenceMessage(line) {
            if let number = autonumberNext {
                msg.sequenceNumber = number
                autonumberNext = number + autonumberStep
            }
            _ensureActor(&diagram, &actorIds, msg.from)
            _ensureActor(&diagram, &actorIds, msg.to)
            diagram.messages.append(msg)
            continue
        }
    }

    return diagram
}

private func _parseSequenceMessage(_ line: String) -> SequenceMessage? {
    if let m = _match(#"^(\S+?)\s*(--?>?>|--?[)x]|--?>>|--?>)\s*([+-]?)(\S+?)\s*:\s*(.+)$"#, line) {
        return _buildMessage(from: m[1], arrow: m[2], activation: m[3], to: m[4], label: m[5])
    }
    if let m = _match(#"^(\S+?)\s*(->>|-->>|-\)|--\)|-x|--x|->|-->)\s*([+-]?)(\S+?)\s*:\s*(.+)$"#, line) {
        return _buildMessage(from: m[1], arrow: m[2], activation: m[3], to: m[4], label: m[5])
    }
    return nil
}

private func _buildMessage(from: String, arrow: String, activation: String, to: String, label: String) -> SequenceMessage {
    let lineStyle = arrow.hasPrefix("--") ? "dashed" : "solid"
    let arrowHead = (arrow.contains(">>") || arrow.contains("x")) ? "filled" : "open"
    return SequenceMessage(
        from: from,
        to: to,
        label: _normalizeLineBreaks(label.trimmingCharacters(in: .whitespacesAndNewlines)),
        lineStyle: lineStyle,
        arrowHead: arrowHead,
        activate: activation == "+",
        deactivate: activation == "-"
    )
}

private func _ensureActor(_ diagram: inout SequenceDiagram, _ actorIds: inout Set<String>, _ id: String) {
    if actorIds.contains(id) {
        return
    }
    actorIds.insert(id)
    diagram.actors.append(SequenceActor(id: id, label: id, type: "participant"))
}

/// Turns either of Mermaid's line breaks into a real newline.
///
/// Any of `<br>`, `<br/>` or `<br />` is accepted, in any case — the documentation writes
/// `<br/>`, but authors write all three — as is a literal `\\n`. Both forms match
/// `original_src_multiline_utils.normalizeBrTags`, which the other diagram kinds go
/// through; sequence diagrams used to accept neither outside of notes, so a break was
/// measured and drawn as literal text.
private func _normalizeLineBreaks(_ text: String) -> String {
    text
        .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        .replacingOccurrences(of: "\\n", with: "\n")
}

private func _match(_ pattern: String, _ text: String, caseInsensitive: Bool = false) -> [String]? {
    let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
        return nil
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range) else {
        return nil
    }
    var out: [String] = []
    out.reserveCapacity(match.numberOfRanges)
    for idx in 0..<match.numberOfRanges {
        let r = match.range(at: idx)
        if let rr = Range(r, in: text) {
            out.append(String(text[rr]))
        } else {
            out.append("")
        }
    }
    return out
}

open class original_src_sequence_parser {
    public init() {}

    // Marker to keep transpiled outputs linked to elk-swift runtime.
    public static let __elkVersion = ElkSwift.version

    // Export inventory from TypeScript source:
    // - export function parseSequenceDiagram
    public static func parseSequenceDiagram(_ lines: [String]) throws -> SequenceDiagram {
        try _parseSequenceDiagramEntry(lines)
    }
}
