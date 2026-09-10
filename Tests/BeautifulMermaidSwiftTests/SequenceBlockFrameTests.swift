import XCTest
@testable import BeautifulMermaid

/// Block frames used to be drawn before lifelines and activation bars, so both were
/// painted over the frame and its tab — clipping the tab's text — and the frame itself was
/// sized only from the actors it spans, so it enclosed neither its own tab label nor a
/// self-message's label.
final class SequenceBlockFrameTests: XCTestCase {

    private func lines(_ source: String) -> [String] {
        source
            .components(separatedBy: CharacterSet(charactersIn: "\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
    }

    private static let selfCallInLoop = """
    sequenceDiagram
        participant U as User
        participant API
        U->>+API: POST /login
        loop every 30s
            API->>API: refresh cache
        end
        API-->>-U: 200 OK
    """

    // MARK: - The frame must enclose what it frames

    func testFrameEnclosesASelfMessageLabel() throws {
        let positioned = try layoutSequenceDiagram(parseSequenceDiagram(lines(Self.selfCallInLoop)))
        let block = try XCTUnwrap(positioned.blocks.first)
        let selfMessage = try XCTUnwrap(positioned.messages.first(where: \.isSelf))

        let labelWidth = original_src_styles.estimateTextWidth(
            selfMessage.label,
            original_src_styles.FONT_SIZES.edgeLabel,
            original_src_styles.FONT_WEIGHTS.edgeLabel
        )
        let labelRight = selfMessage.x1 + 36 + labelWidth

        XCTAssertGreaterThanOrEqual(
            block.x + block.width, labelRight,
            "the self-call's label spills out of the frame that is meant to contain it"
        )
    }

    func testFrameEnclosesItsOwnTabLabel() throws {
        // A long label on a block spanning a single actor is the case that used to overhang.
        let positioned = try layoutSequenceDiagram(parseSequenceDiagram(lines("""
        sequenceDiagram
            participant API
            loop retry with exponential backoff until it succeeds
                API->>API: attempt
            end
        """)))
        let block = try XCTUnwrap(positioned.blocks.first)

        let tabText = "\(block.type) [\(block.label)]"
        let tabWidth = original_src_styles.estimateTextWidth(
            tabText,
            original_src_styles.FONT_SIZES.edgeLabel,
            original_src_styles.FONT_WEIGHTS.groupHeader
        ) + 16

        XCTAssertGreaterThanOrEqual(block.width, tabWidth,
                                    "the tab is wider than the frame it labels")
    }

    func testAWiderFrameWidensTheDiagram() throws {
        let positioned = try layoutSequenceDiagram(parseSequenceDiagram(lines(Self.selfCallInLoop)))
        let block = try XCTUnwrap(positioned.blocks.first)

        XCTAssertGreaterThanOrEqual(positioned.width, block.x + block.width,
                                    "the frame is drawn outside the diagram's own bounds")
    }

    // MARK: - A frame must not run across an uninvolved lifeline

    /// The actors a block does not contain must stay clear of it. Sizing the frame to
    /// enclose a self-message's label is only correct if the neighbouring actor is moved
    /// out of the way; otherwise the frame is drawn straight across their lifeline.
    private func assertFrameClearsUninvolvedLifelines(
        _ source: String,
        involved: Set<String>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let positioned = try layoutSequenceDiagram(parseSequenceDiagram(lines(source)))
        let block = try XCTUnwrap(positioned.blocks.first, file: file, line: line)

        for lifeline in positioned.lifelines where !involved.contains(lifeline.actorId) {
            let insideFrame = lifeline.x > block.x && lifeline.x < block.x + block.width
            XCTAssertFalse(
                insideFrame,
                "the frame (\(block.x)...\(block.x + block.width)) runs across "
                    + "\(lifeline.actorId)'s lifeline at \(lifeline.x)",
                file: file, line: line
            )
        }
    }

    func testFrameClearsUninvolvedLifelines() throws {
        try assertFrameClearsUninvolvedLifelines(Self.selfCallInLoop, involved: ["API"])
    }

    /// The case that motivated this: a label long enough that the frame containing it
    /// would otherwise reach past the next actor entirely.
    func testALongSelfMessageMovesTheNextActorRatherThanCrossingIt() throws {
        let source = """
        sequenceDiagram
            participant U as User
            participant API
            participant DB
            U->>+API: POST /login
            loop every 30s
                API->>API: refresh the cache and revalidate every downstream token
            end
            API-->>-U: 200 OK
        """
        try assertFrameClearsUninvolvedLifelines(source, involved: ["API"])
    }

    /// Room is reserved in proportion to the label, not by a fixed nudge.
    func testALongerLabelReservesMoreRoom() throws {
        func dbPosition(_ label: String) throws -> Double {
            let positioned = try layoutSequenceDiagram(parseSequenceDiagram(lines("""
            sequenceDiagram
                participant API
                participant DB
                API->>API: \(label)
            """)))
            return try XCTUnwrap(positioned.lifelines.first { $0.actorId == "DB" }).x
        }

        XCTAssertGreaterThan(
            try dbPosition("refresh the cache and revalidate every downstream token"),
            try dbPosition("x"),
            "the gap does not grow with the label it has to hold"
        )
    }

    // MARK: - Paint order

    func testLifelinesAndActivationsArePaintedBeneathBlocks() throws {
        let svg = try renderMermaidSVG(Self.selfCallInLoop)

        let lifeline = try XCTUnwrap(svg.range(of: "class=\"lifeline\""))
        let activation = try XCTUnwrap(svg.range(of: "class=\"activation\""))
        let block = try XCTUnwrap(svg.range(of: "class=\"block\""))

        XCTAssertTrue(lifeline.lowerBound < block.lowerBound,
                      "a dashed lifeline drawn last is stroked across the block's tab")
        XCTAssertTrue(activation.lowerBound < block.lowerBound,
                      "an activation drawn last is painted over the frame and its label")
    }

    func testMessagesStayAboveBlocks() throws {
        let svg = try renderMermaidSVG(Self.selfCallInLoop)

        let block = try XCTUnwrap(svg.range(of: "class=\"block\""))
        let message = try XCTUnwrap(svg.range(of: "class=\"message\""))

        XCTAssertTrue(block.lowerBound < message.lowerBound,
                      "arrows must remain readable on top of the frame")
    }
}
