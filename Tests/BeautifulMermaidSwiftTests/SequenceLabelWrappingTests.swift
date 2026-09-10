import XCTest
@testable import BeautifulMermaid

/// `<br/>` reached only note text. Every other label was normalised to `<br>` and then
/// left alone, so the tag was measured as characters and drawn as literal text — wrapping
/// a label made its frame *wider*, which is the opposite of the point.
final class SequenceLabelWrappingTests: XCTestCase {

    private func lines(_ source: String) -> [String] {
        source
            .components(separatedBy: CharacterSet(charactersIn: "\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
    }

    private func diagram(_ label: String) throws -> PositionedSequenceDiagram {
        try layoutSequenceDiagram(parseSequenceDiagram(lines("""
        sequenceDiagram
            participant U as User
            participant API
            participant DB
            U->>+API: POST /login
            loop every 30s
                API->>API: \(label)
            end
            API-->>-U: 200 OK
        """)))
    }

    private static let long = "refresh the cache and revalidate every downstream token"
    private static let wrapped = "refresh the cache and<br/>revalidate every downstream token"

    // MARK: - Parsing

    func testBreaksBecomeRealNewlinesInMessageLabels() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            A->>B: first<br/>second<BR>third<br />fourth
        """))

        XCTAssertEqual(parsed.messages[0].label, "first\nsecond\nthird\nfourth")
        XCTAssertFalse(parsed.messages[0].label.contains("<br"),
                       "the tag used to survive into the drawn text")
    }

    func testBreaksBecomeRealNewlinesInActorAndBlockLabels() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            participant API as Payments<br/>API
            loop every 30s<br/>at most
                API->>API: poll
            end
        """))

        XCTAssertEqual(parsed.actors[0].label, "Payments\nAPI")
        XCTAssertEqual(parsed.blocks[0].label, "every 30s\nat most")
    }

    func testALiteralBackslashNAlsoBreaksTheLine() throws {
        // The other diagram kinds accept it through normalizeBrTags; sequence diagrams
        // used to be the odd one out.
        let parsed = try parseSequenceDiagram(lines(#"""
        sequenceDiagram
            participant API as Payments\nAPI
            loop every 30s\nat most
                API->>API: first\nsecond
            end
        """#))

        XCTAssertEqual(parsed.messages[0].label, "first\nsecond")
        XCTAssertEqual(parsed.actors[0].label, "Payments\nAPI")
        XCTAssertEqual(parsed.blocks[0].label, "every 30s\nat most")
    }

    func testBothBreakFormsMixFreely() throws {
        let parsed = try parseSequenceDiagram(lines(#"""
        sequenceDiagram
            A->>B: one<br/>two\nthree<BR>four
        """#))

        XCTAssertEqual(parsed.messages[0].label, "one\ntwo\nthree\nfour")
    }

    func testTheTwoBreakFormsLayOutIdentically() throws {
        let withTag = try diagram("refresh the cache and<br/>revalidate every token")
        let withEscape = try diagram(#"refresh the cache and\nrevalidate every token"#)

        XCTAssertEqual(withTag.width, withEscape.width, accuracy: 0.001)
        XCTAssertEqual(
            try XCTUnwrap(withTag.blocks.first).width,
            try XCTUnwrap(withEscape.blocks.first).width,
            accuracy: 0.001
        )
    }

    // MARK: - Measurement

    func testWrappingMakesTheFrameNarrowerNotWider() throws {
        let straight = try XCTUnwrap(diagram(Self.long).blocks.first)
        let broken = try XCTUnwrap(diagram(Self.wrapped).blocks.first)

        XCTAssertLessThan(broken.width, straight.width,
                          "wrapping a label must not widen the frame that holds it")
    }

    func testWrappingLetsTheNextActorMoveBackIn() throws {
        func dbX(_ label: String) throws -> Double {
            try XCTUnwrap(diagram(label).lifelines.first { $0.actorId == "DB" }).x
        }

        XCTAssertLessThan(try dbX(Self.wrapped), try dbX(Self.long))
    }

    func testTheFrameStillEnclosesTheWidestLine() throws {
        let positioned = try diagram(Self.wrapped)
        let block = try XCTUnwrap(positioned.blocks.first)
        let message = try XCTUnwrap(positioned.messages.first(where: \.isSelf))

        let widestLine = message.label
            .components(separatedBy: "\n")
            .map {
                original_src_styles.estimateTextWidth(
                    $0,
                    original_src_styles.FONT_SIZES.edgeLabel,
                    original_src_styles.FONT_WEIGHTS.edgeLabel
                )
            }
            .max() ?? 0

        XCTAssertGreaterThanOrEqual(block.x + block.width, message.x1 + 36 + widestLine)
    }

    func testAWrappedLabelStillClearsUninvolvedLifelines() throws {
        let positioned = try diagram(Self.wrapped)
        let block = try XCTUnwrap(positioned.blocks.first)

        for lifeline in positioned.lifelines where lifeline.actorId != "API" {
            XCTAssertFalse(
                lifeline.x > block.x && lifeline.x < block.x + block.width,
                "\(lifeline.actorId)'s lifeline is inside a frame it takes no part in"
            )
        }
    }

    // MARK: - The block tab holds its own label

    /// The tab's grey panel is drawn from its own measurements, not the frame's, so it has
    /// to grow with a wrapped label in both directions or the text spills out of it.
    func testTheTabGrowsTallerForAWrappedLabel() throws {
        func tabHeight(_ blockLabel: String) throws -> Double {
            let svg = try renderMermaidSVG("""
            sequenceDiagram
                participant API
                loop \(blockLabel)
                    API->>API: poll
                end
            """)
            // The tab is the second <rect> in the block group: frame first, then tab.
            let group = try XCTUnwrap(svg.range(of: "class=\"block\""))
            let after = svg[group.upperBound...]
            let rects = after.components(separatedBy: "<rect").dropFirst()
            let tab = try XCTUnwrap(rects.dropFirst().first)
            let raw = try XCTUnwrap(tab.components(separatedBy: "height=\"").dropFirst().first?
                .components(separatedBy: "\"").first)
            return try XCTUnwrap(Double(raw))
        }

        XCTAssertGreaterThan(try tabHeight("every 30s<br/>at most"), try tabHeight("every 30s"))
    }

    func testTheTabIsMeasuredOnItsWidestLineNotItsFirst() throws {
        func tabWidth(_ blockLabel: String) throws -> Double {
            let svg = try renderMermaidSVG("""
            sequenceDiagram
                participant API
                loop \(blockLabel)
                    API->>API: poll
                end
            """)
            let group = try XCTUnwrap(svg.range(of: "class=\"block\""))
            let after = svg[group.upperBound...]
            let rects = after.components(separatedBy: "<rect").dropFirst()
            let tab = try XCTUnwrap(rects.dropFirst().first)
            let raw = try XCTUnwrap(tab.components(separatedBy: "width=\"").dropFirst().first?
                .components(separatedBy: "\"").first)
            return try XCTUnwrap(Double(raw))
        }

        // Short first line, long second: measuring the first line alone would under-size it.
        let narrowFirstLine = try tabWidth("x<br/>a considerably longer second line")
        let justTheFirstLine = try tabWidth("x")

        XCTAssertGreaterThan(narrowFirstLine, justTheFirstLine)
    }

    // MARK: - Vertical room

    func testAWrappedLabelIsGivenRoomAboveItsArrow() throws {
        func height(_ label: String) throws -> Double {
            try layoutSequenceDiagram(parseSequenceDiagram(lines("""
            sequenceDiagram
                participant A
                participant B
                A->>B: \(label)
            """))).height
        }

        XCTAssertGreaterThan(try height("one<br/>two"), try height("one"),
                             "extra lines are drawn above the arrow and need the room")
    }

    func testAWrappedSelfMessageStaysInsideItsFrame() throws {
        let positioned = try diagram("first line<br/>second line<br/>third line")
        let block = try XCTUnwrap(positioned.blocks.first)
        let message = try XCTUnwrap(positioned.messages.first(where: \.isSelf))

        let lineHeight = original_src_styles.FONT_SIZES.edgeLabel * original_src_text_metrics.LINE_HEIGHT_RATIO
        let labelBottom = message.y + 10 + lineHeight

        XCTAssertGreaterThanOrEqual(block.y + block.height, labelBottom,
                                    "the label runs out through the floor of its own frame")
    }
}
