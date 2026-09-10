// Ported from original/src/sequence/layout.ts
import Foundation
import ElkSwift

private enum _SEQ {
    static let padding: Double = 30
    static let actorGap: Double = 140
    static let actorHeight: Double = 40
    static let actorPadX: Double = 16
    static let headerGap: Double = 20
    static let messageRowHeight: Double = 40
    static let selfMessageHeight: Double = 30
    static let activationWidth: Double = 10
    static let blockPadX: Double = 10
    static let blockPadTop: Double = 40
    static let blockPadBottom: Double = 8
    static let blockHeaderExtra: Double = 28
    static let dividerExtra: Double = 24
    /// Height of a single-line block tab, matching the renderers.
    static let blockTabHeight: Double = 18
    /// Padding either side of a block's tab label, matching the renderers.
    static let blockTabPadX: Double = 16
    /// Where a self-message's label starts, relative to its lifeline.
    static let selfMessageLabelX: Double = 36
    /// Gap kept between a block frame's edge and the next actor's lifeline.
    static let lifelineClearance: Double = 10
    static let noteWidth: Double = 120
    static let notePadding: Double = 8
    static let noteGap: Double = 10
}

/// Widest line of a label, not the label laid end to end.
///
/// Labels carry real newlines once `<br/>` has been parsed, so measuring the raw string
/// both counted the break as text and reported the width of every line summed together.
/// Wrapping a label used to make its frame wider, which is the opposite of the point.
private func _labelWidth(_ text: String, _ fontSize: Double, _ fontWeight: Int) -> Double {
    text.components(separatedBy: "\n")
        .reduce(0.0) { max($0, original_src_styles.estimateTextWidth($1, fontSize, fontWeight)) }
}

/// Number of lines a label occupies.
private func _labelLineCount(_ text: String) -> Int {
    max(1, text.components(separatedBy: "\n").count)
}

public func layoutSequenceDiagram(
    _ diagram: SequenceDiagram,
    _ options: RenderOptions = RenderOptions()
) throws -> PositionedSequenceDiagram {
    try _layoutSequenceDiagramEntry(diagram, options)
}

private func _layoutSequenceDiagramEntry(
    _ diagram: SequenceDiagram,
    _ options: RenderOptions
) throws -> PositionedSequenceDiagram {
    _ = options

    if diagram.actors.isEmpty {
        return PositionedSequenceDiagram(
            width: 0,
            height: 0,
            actors: [],
            lifelines: [],
            messages: [],
            activations: [],
            blocks: [],
            notes: []
        )
    }

    let actorWidths = diagram.actors.map { actor in
        let textW = _labelWidth(
            actor.label,
            original_src_styles.FONT_SIZES.nodeLabel,
            original_src_styles.FONT_WEIGHTS.nodeLabel
        )
        return max(textW + _SEQ.actorPadX * 2, 80)
    }

    // A self-message loops out to the right of its own lifeline and writes its label
    // beyond the loop, so it needs room before the next lifeline begins. Without this the
    // label — and any block frame sized to contain it — runs across the neighbouring
    // actor's lifeline.
    var selfMessageReach = [Double](repeating: 0, count: diagram.actors.count)
    do {
        var indexByID: [String: Int] = [:]
        for (i, actor) in diagram.actors.enumerated() {
            indexByID[actor.id] = i
        }
        for message in diagram.messages where message.from == message.to {
            guard let idx = indexByID[message.from] else { continue }
            let labelWidth = _labelWidth(
                message.label,
                original_src_styles.FONT_SIZES.edgeLabel,
                original_src_styles.FONT_WEIGHTS.edgeLabel
            )
            let reach = _SEQ.selfMessageLabelX + labelWidth + _SEQ.blockPadX + _SEQ.lifelineClearance
            selfMessageReach[idx] = max(selfMessageReach[idx], reach)
        }
    }

    var actorCenterX: [Double] = []
    var currentX = _SEQ.padding + actorWidths[0] / 2
    for i in 0..<diagram.actors.count {
        if i > 0 {
            let minGap = max(
                _SEQ.actorGap,
                (actorWidths[i - 1] + actorWidths[i]) / 2 + 40,
                selfMessageReach[i - 1] + actorWidths[i] / 2
            )
            currentX += minGap
        }
        actorCenterX.append(currentX)
    }

    var actorIndex: [String: Int] = [:]
    for i in 0..<diagram.actors.count {
        actorIndex[diagram.actors[i].id] = i
    }

    let actorY = _SEQ.padding
    let actors: [PositionedSequenceActor] = diagram.actors.enumerated().map { idx, actor in
        PositionedSequenceActor(
            id: actor.id,
            label: actor.label,
            type: actor.type,
            x: actorCenterX[idx],
            y: actorY,
            width: actorWidths[idx],
            height: _SEQ.actorHeight
        )
    }

    var messageY = actorY + _SEQ.actorHeight + _SEQ.headerGap
    var messages: [PositionedSequenceMessage] = []

    var extraSpaceBefore: [Int: Double] = [:]
    for block in diagram.blocks {
        extraSpaceBefore[block.startIndex] = max(extraSpaceBefore[block.startIndex] ?? 0, _SEQ.blockHeaderExtra)
        for div in block.dividers {
            extraSpaceBefore[div.index] = max(extraSpaceBefore[div.index] ?? 0, _SEQ.dividerExtra)
        }
    }

    var activationStacks: [String: [(startY: Double, depth: Int)]] = [:]
    var activations: [SequenceActivation] = []
    let nestingOffset = 4.0

    func openActivation(_ actorId: String, at y: Double) {
        var stack = activationStacks[actorId] ?? []
        stack.append((startY: y, depth: stack.count))
        activationStacks[actorId] = stack
    }

    func closeActivation(_ actorId: String, at y: Double) {
        var stack = activationStacks[actorId] ?? []
        guard !stack.isEmpty else { return }
        let top = stack.removeLast()
        activationStacks[actorId] = stack
        let idx = actorIndex[actorId] ?? 0
        activations.append(
            SequenceActivation(
                actorId: actorId,
                x: actorCenterX[idx] - _SEQ.activationWidth / 2 + Double(top.depth) * nestingOffset,
                topY: top.startY,
                bottomY: y,
                width: _SEQ.activationWidth
            )
        )
    }

    /// `activate` / `deactivate` statements take effect where they were written, so they
    /// are applied against the row of the message that follows them.
    func applyActivationEvents(after messageIndex: Int, at y: Double) {
        for event in diagram.activationEvents where event.afterIndex == messageIndex {
            if event.isActivate {
                openActivation(event.actorId, at: y)
            } else {
                closeActivation(event.actorId, at: y)
            }
        }
    }

    for msgIdx in 0..<diagram.messages.count {
        let msg = diagram.messages[msgIdx]
        let fromIdx = actorIndex[msg.from] ?? 0
        let toIdx = actorIndex[msg.to] ?? 0
        let isSelfMsg = msg.from == msg.to

        let extra = extraSpaceBefore[msgIdx] ?? 0
        if extra > 0 {
            messageY += extra
        }

        // Extra lines are drawn above the arrow, so a wrapped label needs the room before
        // its own row, not after it.
        let ownExtraLines = Double(_labelLineCount(msg.label) - 1)
        if ownExtraLines > 0 && !isSelfMsg {
            messageY += ownExtraLines * original_src_styles.FONT_SIZES.edgeLabel * original_src_text_metrics.LINE_HEIGHT_RATIO
        }

        // Push messageY down if a note sits between the previous message and this one
        for note in diagram.notes where note.afterIndex == msgIdx - 1 {
            let noteLines = note.text.components(separatedBy: "\n")
            let nonEmpty = noteLines.isEmpty ? [""] : noteLines
            let lineCount = Double(max(1, nonEmpty.count))
            let lineHeight = ceil(original_src_styles.FONT_SIZES.edgeLabel)
            let lineSpacing: Double = 4
            let noteH = lineCount * lineHeight + max(0, lineCount - 1) * lineSpacing + _SEQ.notePadding * 2
            let noteBottom = messageY + 4 + noteH
            let requiredY = noteBottom + _SEQ.noteGap
            messageY = max(messageY, requiredY)
        }

        applyActivationEvents(after: msgIdx - 1, at: messageY)

        let x1 = actorCenterX[fromIdx]
        let x2 = actorCenterX[toIdx]

        messages.append(
            PositionedSequenceMessage(
                from: msg.from,
                to: msg.to,
                label: msg.label,
                lineStyle: msg.lineStyle,
                arrowHead: msg.arrowHead,
                x1: x1,
                x2: x2,
                y: messageY,
                isSelf: isSelfMsg,
                sequenceNumber: msg.sequenceNumber
            )
        )

        if msg.activate {
            openActivation(msg.to, at: messageY)
        }

        if msg.deactivate {
            closeActivation(msg.from, at: messageY)
        }

        // A wrapped label is taller than the row was sized for, and its extra lines are
        // drawn above the arrow, so the room has to come from the gap before it.
        let extraLabelLines = Double(_labelLineCount(msg.label) - 1)
        let labelGrowth = extraLabelLines * original_src_styles.FONT_SIZES.edgeLabel * original_src_text_metrics.LINE_HEIGHT_RATIO

        messageY += isSelfMsg ? (_SEQ.selfMessageHeight + _SEQ.messageRowHeight) : _SEQ.messageRowHeight
        if isSelfMsg { messageY += labelGrowth }
    }

    applyActivationEvents(after: diagram.messages.count - 1, at: messageY - _SEQ.messageRowHeight / 2)

    for (actorId, stack) in activationStacks {
        for item in stack {
            let idx = actorIndex[actorId] ?? 0
            let xOffset = Double(item.depth) * nestingOffset
            activations.append(
                SequenceActivation(
                    actorId: actorId,
                    x: actorCenterX[idx] - _SEQ.activationWidth / 2 + xOffset,
                    topY: item.startY,
                    bottomY: messageY - _SEQ.messageRowHeight / 2,
                    width: _SEQ.activationWidth
                )
            )
        }
    }

    let blocks: [PositionedSequenceBlock] = diagram.blocks.map { block in
        let startMsg = block.startIndex < messages.count ? messages[block.startIndex] : nil
        let endMsg = block.endIndex < messages.count ? messages[block.endIndex] : nil
        // A wrapped tab is taller than the padding the frame reserves above its first
        // message, so the frame's ceiling has to rise with it.
        let tabLineCount = _labelLineCount("\(block.type)\(block.label.isEmpty ? "" : " [\(block.label)]")")
        let tabOverflow = max(
            0,
            _SEQ.blockTabHeight
                + Double(tabLineCount - 1) * original_src_styles.FONT_SIZES.edgeLabel * original_src_text_metrics.LINE_HEIGHT_RATIO
                - _SEQ.blockPadTop
        )
        let blockTop = (startMsg?.y ?? messageY) - _SEQ.blockPadTop - tabOverflow
        // A self-message's label sits beside its loop and grows downwards when wrapped, so
        // the frame's floor has to follow it.
        var trailingLabelGrowth = 0.0
        if block.startIndex <= block.endIndex {
            for mi in block.startIndex...block.endIndex where mi >= 0 && mi < messages.count {
                let m = messages[mi]
                guard m.isSelf else { continue }
                let extraLines = Double(_labelLineCount(m.label) - 1)
                let growth = extraLines * original_src_styles.FONT_SIZES.edgeLabel * original_src_text_metrics.LINE_HEIGHT_RATIO / 2
                trailingLabelGrowth = max(trailingLabelGrowth, growth)
            }
        }
        let blockBottom = (endMsg?.y ?? messageY) + _SEQ.blockPadBottom + 12 + trailingLabelGrowth

        var involvedActors = Set<Int>()
        if block.startIndex <= block.endIndex {
            for mi in block.startIndex...block.endIndex where mi >= 0 && mi < diagram.messages.count {
                let m = diagram.messages[mi]
                involvedActors.insert(actorIndex[m.from] ?? 0)
                involvedActors.insert(actorIndex[m.to] ?? 0)
            }
        }

        if involvedActors.isEmpty {
            for ai in 0..<diagram.actors.count {
                involvedActors.insert(ai)
            }
        }

        let minIdx = involvedActors.min() ?? 0
        let maxIdx = involvedActors.max() ?? max(0, diagram.actors.count - 1)
        let blockLeft = actorCenterX[minIdx] - actorWidths[minIdx] / 2 - _SEQ.blockPadX
        let blockRight = actorCenterX[maxIdx] + actorWidths[maxIdx] / 2 + _SEQ.blockPadX

        let positionedDividers: [PositionedSequenceBlockDivider] = block.dividers.map { divider in
            let msg = divider.index < messages.count ? messages[divider.index] : nil
            let msgY = msg?.y ?? messageY
            var offset = 28.0

            if !divider.label.isEmpty, let msg {
                let divLabelText = "[\(divider.label)]"
                let divLabelW = _labelWidth(
                    divLabelText,
                    original_src_styles.FONT_SIZES.edgeLabel,
                    original_src_styles.FONT_WEIGHTS.edgeLabel
                )
                let divLabelLeft = blockLeft + 8
                let divLabelRight = divLabelLeft + divLabelW

                let msgLabelW = _labelWidth(
                    msg.label,
                    original_src_styles.FONT_SIZES.edgeLabel,
                    original_src_styles.FONT_WEIGHTS.edgeLabel
                )
                let msgLabelLeft = msg.isSelf
                    ? msg.x1 + 36
                    : (msg.x1 + msg.x2) / 2 - msgLabelW / 2
                let msgLabelRight = msgLabelLeft + msgLabelW

                if divLabelRight > msgLabelLeft && divLabelLeft < msgLabelRight {
                    offset = 36
                }
            }

            return PositionedSequenceBlockDivider(y: msgY - offset, label: divider.label)
        }

        // A frame must enclose what it frames. The span above is derived purely from the
        // actors involved, which covers neither the block's own tab label nor a
        // self-message — that loops out to the right of its lifeline and puts its label
        // beyond the loop. Both used to spill past the right edge.
        var enclosingRight = blockRight

        let tabText = "\(block.type)\(block.label.isEmpty ? "" : " [\(block.label)]")"
        let tabWidth = _labelWidth(
            tabText,
            original_src_styles.FONT_SIZES.edgeLabel,
            original_src_styles.FONT_WEIGHTS.groupHeader
        ) + _SEQ.blockTabPadX
        enclosingRight = max(enclosingRight, blockLeft + tabWidth)

        if block.startIndex <= block.endIndex {
            for mi in block.startIndex...block.endIndex where mi >= 0 && mi < messages.count {
                let m = messages[mi]
                guard m.isSelf else { continue }
                let labelWidth = _labelWidth(
                    m.label,
                    original_src_styles.FONT_SIZES.edgeLabel,
                    original_src_styles.FONT_WEIGHTS.edgeLabel
                )
                enclosingRight = max(enclosingRight, m.x1 + _SEQ.selfMessageLabelX + labelWidth + _SEQ.blockPadX)
            }
        }

        return PositionedSequenceBlock(
            type: block.type,
            label: block.label,
            x: blockLeft,
            y: blockTop,
            width: enclosingRight - blockLeft,
            height: blockBottom - blockTop,
            dividers: positionedDividers
        )
    }

    let notes: [PositionedSequenceNote] = diagram.notes.map { note in
        let noteLines = note.text.components(separatedBy: "\n")
        let nonEmpty = noteLines.isEmpty ? [""] : noteLines
        let maxLineWidth = nonEmpty.map {
            _labelWidth(
                $0,
                original_src_styles.FONT_SIZES.edgeLabel,
                original_src_styles.FONT_WEIGHTS.edgeLabel
            )
        }.max() ?? 0
        let noteW = max(_SEQ.noteWidth, maxLineWidth + _SEQ.notePadding * 2)
        let lineCount = Double(max(1, nonEmpty.count))
        let lineHeight = ceil(original_src_styles.FONT_SIZES.edgeLabel)
        let lineSpacing: Double = 4
        let noteH = lineCount * lineHeight + max(0, lineCount - 1) * lineSpacing + _SEQ.notePadding * 2

        let refMsg = note.afterIndex >= 0 && note.afterIndex < messages.count ? messages[note.afterIndex] : nil
        let noteY = (refMsg?.y ?? actorY + _SEQ.actorHeight) + 4

        let firstActorIdx = actorIndex[note.actorIds.first ?? ""] ?? 0
        let noteX: Double
        if note.position == "left" {
            noteX = actorCenterX[firstActorIdx] - actorWidths[firstActorIdx] / 2 - noteW - _SEQ.noteGap
        } else if note.position == "right" {
            noteX = actorCenterX[firstActorIdx] + actorWidths[firstActorIdx] / 2 + _SEQ.noteGap
        } else {
            if note.actorIds.count > 1 {
                let lastActorIdx = actorIndex[note.actorIds.last ?? ""] ?? firstActorIdx
                noteX = (actorCenterX[firstActorIdx] + actorCenterX[lastActorIdx]) / 2 - noteW / 2
            } else {
                noteX = actorCenterX[firstActorIdx] - noteW / 2
            }
        }

        return PositionedSequenceNote(
            text: note.text,
            x: noteX,
            y: noteY,
            width: noteW,
            height: noteH,
            position: note.position,
            actors: note.actorIds
        )
    }

    let diagramBottom = messageY + _SEQ.padding

    var globalMinX = _SEQ.padding
    var globalMaxX = 0.0

    for actor in actors {
        globalMinX = min(globalMinX, actor.x - actor.width / 2)
        globalMaxX = max(globalMaxX, actor.x + actor.width / 2)
    }
    for block in blocks {
        globalMinX = min(globalMinX, block.x)
        globalMaxX = max(globalMaxX, block.x + block.width)
    }
    for note in notes {
        globalMinX = min(globalMinX, note.x)
        globalMaxX = max(globalMaxX, note.x + note.width)
    }
    for msg in messages where msg.isSelf {
        let loopW = 30.0
        let labelPadding = 8.0
        let labelLeft = msg.x1 + loopW + labelPadding
        let labelWidth = _labelWidth(
            msg.label,
            original_src_styles.FONT_SIZES.edgeLabel,
            original_src_styles.FONT_WEIGHTS.edgeLabel
        )
        globalMaxX = max(globalMaxX, labelLeft + labelWidth + 8)
    }

    let shiftX = globalMinX < _SEQ.padding ? _SEQ.padding - globalMinX : 0

    var shiftedActors = actors
    var shiftedMessages = messages
    var shiftedActivations = activations
    var shiftedBlocks = blocks
    var shiftedNotes = notes

    if shiftX > 0 {
        for i in shiftedActors.indices {
            shiftedActors[i].x += shiftX
        }
        for i in shiftedMessages.indices {
            shiftedMessages[i].x1 += shiftX
            shiftedMessages[i].x2 += shiftX
        }
        for i in shiftedActivations.indices {
            shiftedActivations[i].x += shiftX
        }
        for i in shiftedBlocks.indices {
            shiftedBlocks[i].x += shiftX
        }
        for i in shiftedNotes.indices {
            shiftedNotes[i].x += shiftX
        }
        for i in actorCenterX.indices {
            actorCenterX[i] += shiftX
        }
    }

    let lifelines: [SequenceLifeline] = diagram.actors.enumerated().map { idx, actor in
        SequenceLifeline(
            actorId: actor.id,
            x: actorCenterX[idx],
            topY: actorY + _SEQ.actorHeight,
            bottomY: diagramBottom - _SEQ.padding
        )
    }

    let diagramWidth = globalMaxX + shiftX + _SEQ.padding
    let diagramHeight = diagramBottom

    return PositionedSequenceDiagram(
        width: max(diagramWidth, 200),
        height: max(diagramHeight, 100),
        actors: shiftedActors,
        lifelines: lifelines,
        messages: shiftedMessages,
        activations: shiftedActivations,
        blocks: shiftedBlocks,
        notes: shiftedNotes
    )
}

open class original_src_sequence_layout {
    public init() {}

    public static let __elkVersion = ElkSwift.version

    public static func layoutSequenceDiagram(
        _ diagram: SequenceDiagram,
        _ options: RenderOptions = RenderOptions()
    ) throws -> PositionedSequenceDiagram {
        try _layoutSequenceDiagramEntry(diagram, options)
    }
}
