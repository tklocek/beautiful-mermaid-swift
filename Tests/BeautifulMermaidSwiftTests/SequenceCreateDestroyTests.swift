import XCTest
@testable import BeautifulMermaid

/// A participant can join the diagram partway down and leave before the end.
///
/// Neither line was known to the parser. `create participant C` matched nothing and was
/// dropped, so C appeared in the header row with everyone else — as though it had been
/// there from the first message — and `destroy C` was dropped too, leaving C's lifeline
/// running to the bottom of a diagram it had left. Both are silent: the drawing looks
/// finished, and says something the file does not.
final class SequenceCreateDestroyTests: XCTestCase {

    private func lines(_ source: String) -> [String] {
        source
            .components(separatedBy: CharacterSet(charactersIn: "\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
    }

    private static let colors = DiagramColors(bg: "#FFFFFF", fg: "#27272A")

    private static let source = """
    sequenceDiagram
        A->>B: hello
        create participant C
        B->>C: you exist now
        C->>B: thanks
        destroy C
        B-xC: and now you do not
        B->>A: done
    """

    func testTheLinesSayWhichMessageCreatesAndWhichDestroys() throws {
        let parsed = try parseSequenceDiagram(lines(Self.source))

        XCTAssertEqual(parsed.actors.map(\.id), ["A", "B", "C"])
        let c = try XCTUnwrap(parsed.actors.first { $0.id == "C" })
        XCTAssertEqual(c.createdAtMessage, 1, "the message below `create` is the one that creates it")
        XCTAssertEqual(c.destroyedAtMessage, 3, "and the one below `destroy` is the one that ends it")

        for other in parsed.actors where other.id != "C" {
            XCTAssertNil(other.createdAtMessage)
            XCTAssertNil(other.destroyedAtMessage)
        }
        XCTAssertEqual(parsed.messages.count, 5, "no line is lost to either keyword")
    }

    func testACreatedParticipantArrivesAtItsOwnMessage() throws {
        let laid = try layoutSequenceDiagram(parseSequenceDiagram(lines(Self.source)))

        let c = try XCTUnwrap(laid.actors.first { $0.id == "C" })
        let b = try XCTUnwrap(laid.actors.first { $0.id == "B" })
        XCTAssertGreaterThan(c.y, b.y, "it is not in the header row")

        // Its header sits above the message that creates it, so the arrow lands on the top
        // of its lifeline rather than through the middle of its box.
        let creating = laid.messages[1]
        XCTAssertLessThanOrEqual(c.y + c.height, creating.y)
        XCTAssertGreaterThan(c.y, laid.messages[0].y, "and below the message before it")

        let line = try XCTUnwrap(laid.lifelines.first { $0.actorId == "C" })
        XCTAssertEqual(line.topY, c.y + c.height, accuracy: 0.01, "the line starts under its own header")
    }

    func testADestroyedParticipantsLineStopsWhereItDied() throws {
        let laid = try layoutSequenceDiagram(parseSequenceDiagram(lines(Self.source)))

        let line = try XCTUnwrap(laid.lifelines.first { $0.actorId == "C" })
        XCTAssertTrue(line.endsDestroyed)
        XCTAssertEqual(line.bottomY, laid.messages[3].y, accuracy: 0.01)

        let survivor = try XCTUnwrap(laid.lifelines.first { $0.actorId == "A" })
        XCTAssertFalse(survivor.endsDestroyed)
        XCTAssertGreaterThan(survivor.bottomY, line.bottomY, "everyone else's line runs on")
    }

    func testTheCrossIsDrawn() throws {
        let svg = try renderSequenceSvg(
            layoutSequenceDiagram(parseSequenceDiagram(lines(Self.source))), Self.colors)

        XCTAssertTrue(svg.contains("class=\"destroy\" data-actor=\"C\""))
        // Two strokes, and nobody else's line carries them.
        XCTAssertEqual(svg.components(separatedBy: "class=\"destroy\"").count - 1, 1)
    }

    func testACreatedParticipantCanBeRenamedLikeAnyOther() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            A->>B: hi
            create actor D as Donald
            B->>D: hello
        """))

        let d = try XCTUnwrap(parsed.actors.first { $0.id == "D" })
        XCTAssertEqual(d.label, "Donald")
        XCTAssertEqual(d.type, "actor")
        XCTAssertEqual(d.createdAtMessage, 1)
    }

    func testADiagramWithoutEitherKeywordIsUnchanged() throws {
        let laid = try layoutSequenceDiagram(parseSequenceDiagram(lines("""
        sequenceDiagram
            A->>B: hi
            B->>A: hello
        """)))

        XCTAssertEqual(Set(laid.actors.map(\.y)).count, 1, "everyone still starts in one row")
        XCTAssertTrue(laid.lifelines.allSatisfy { !$0.endsDestroyed })
        XCTAssertEqual(Set(laid.lifelines.map(\.bottomY)).count, 1, "and every line ends together")
    }
}
