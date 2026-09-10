import XCTest
@testable import BeautifulMermaid

/// `box ... end` groups participants under a shared heading. The keyword was unknown, so
/// the opening line was dropped — and its `end` was then handed to the block stack, where
/// it closed whichever `loop` or `alt` happened to be open.
final class SequenceParticipantBoxTests: XCTestCase {

    private func lines(_ source: String) -> [String] {
        source
            .components(separatedBy: CharacterSet(charactersIn: "\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
    }

    private func layout(_ source: String) throws -> PositionedSequenceDiagram {
        try layoutSequenceDiagram(parseSequenceDiagram(lines(source)))
    }

    // MARK: - Parsing

    func testABoxCollectsTheParticipantsDeclaredInside() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            box Service layer
            participant API
            participant DB
            end
            participant U
            API->>DB: q
        """))

        XCTAssertEqual(parsed.boxes.count, 1)
        XCTAssertEqual(parsed.boxes[0].label, "Service layer")
        XCTAssertEqual(parsed.boxes[0].actorIds, ["API", "DB"])
        XCTAssertEqual(parsed.actors.map(\.id), ["API", "DB", "U"], "U is declared outside the box")
    }

    func testSeveralBoxesKeepTheirOwnParticipants() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            box Front
            participant U
            end
            box Back
            participant API
            participant DB
            end
            U->>API: q
        """))

        XCTAssertEqual(parsed.boxes.map(\.label), ["Front", "Back"])
        XCTAssertEqual(parsed.boxes.map(\.actorIds), [["U"], ["API", "DB"]])
    }

    func testABoxNeedsNoLabel() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            box
            participant A
            end
            A->>A: x
        """))

        XCTAssertEqual(parsed.boxes.count, 1)
        XCTAssertEqual(parsed.boxes[0].label, "")
    }

    /// The defect this keyword's absence caused, rather than the missing feature itself.
    func testABoxEndDoesNotCloseAnEnclosingBlock() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            participant API
            participant DB
            loop retry
                box Group
                participant X
                end
                API->>DB: first
                API->>DB: second
            end
        """))

        XCTAssertEqual(parsed.blocks.count, 1)
        let loop = try XCTUnwrap(parsed.blocks.first)
        XCTAssertEqual(loop.type, "loop")
        XCTAssertEqual(loop.startIndex, 0)
        XCTAssertEqual(loop.endIndex, 1, "the loop must still hold both of its messages")
    }

    func testAnEmptyBoxIsDropped() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            box Nobody
            end
            A->>B: x
        """))

        XCTAssertTrue(parsed.boxes.isEmpty)
    }

    // MARK: - Layout

    func testTheBoxSpansTheParticipantsItHolds() throws {
        let positioned = try layout("""
        sequenceDiagram
            box Service layer
            participant API
            participant DB
            end
            API->>DB: q
        """)

        let box = try XCTUnwrap(positioned.participantBoxes.first)
        let api = try XCTUnwrap(positioned.actors.first { $0.id == "API" })
        let db = try XCTUnwrap(positioned.actors.first { $0.id == "DB" })

        XCTAssertLessThan(box.x, api.x - api.width / 2)
        XCTAssertGreaterThan(box.x + box.width, db.x + db.width / 2)
    }

    func testTheHeadersDropToLeaveRoomForTheBoxLabel() throws {
        func headerY(_ source: String) throws -> Double {
            try XCTUnwrap(layout(source).actors.first).y
        }

        let withBox = try headerY("""
        sequenceDiagram
            box Group
            participant API
            end
            API->>API: x
        """)
        let withoutBox = try headerY("""
        sequenceDiagram
            participant API
            API->>API: x
        """)

        XCTAssertGreaterThan(withBox, withoutBox)
    }

    func testALongLabelWidensTheBox() throws {
        func width(_ label: String) throws -> Double {
            try XCTUnwrap(layout("""
            sequenceDiagram
                box \(label)
                participant API
                end
                API->>API: x
            """).participantBoxes.first).width
        }

        XCTAssertGreaterThan(
            try width("a considerably longer heading than the participant it holds"),
            try width("S")
        )
    }

    func testTheBoxStaysInsideTheDiagramBounds() throws {
        let positioned = try layout("""
        sequenceDiagram
            box a considerably longer heading than the participant it holds
            participant API
            end
            API->>API: x
        """)
        let box = try XCTUnwrap(positioned.participantBoxes.first)

        XCTAssertGreaterThanOrEqual(box.x, 0)
        XCTAssertLessThanOrEqual(box.x + box.width, positioned.width)
    }

    // MARK: - Rendering

    func testTheBoxIsDrawnBehindTheHeaders() throws {
        let svg = try renderMermaidSVG("""
        sequenceDiagram
            box Service layer
            participant API
            participant DB
            end
            API->>DB: q
        """)

        let box = try XCTUnwrap(svg.range(of: "class=\"participant-box\""))
        let actor = try XCTUnwrap(svg.range(of: "class=\"actor\""))

        XCTAssertTrue(box.lowerBound < actor.lowerBound,
                      "the headers must sit on top of the group that contains them")
        XCTAssertTrue(svg.contains("data-label=\"Service layer\""))
    }

    func testNoBoxMeansNoBoxElement() throws {
        let svg = try renderMermaidSVG("""
        sequenceDiagram
            participant API
            API->>API: x
        """)

        XCTAssertFalse(svg.contains("participant-box"))
    }
}
