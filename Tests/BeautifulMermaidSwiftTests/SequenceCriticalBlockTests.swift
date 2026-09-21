import XCTest
@testable import BeautifulMermaid

/// `critical` is divided by `option`, the way `alt` is divided by `else`.
///
/// Neither half of that worked. `option` was not a divider, so it fell through to the
/// message parser, which cannot read it either — and before the keyword-boundary fix it was
/// read as `opt` plus the text `ion …`, which opened a block per branch. Those blocks were
/// never closed, so the `critical` frame and everything in it was dropped at the end of the
/// parse: a whole construct, silently absent from the drawing.
final class SequenceCriticalBlockTests: XCTestCase {

    private func lines(_ source: String) -> [String] {
        source
            .components(separatedBy: CharacterSet(charactersIn: "\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
    }

    private static let source = """
    sequenceDiagram
        critical Establish a connection to the DB
            Service-->>DB: connect
        option Network timeout
            Service-->>Service: log error
        option Credentials rejected
            Service-->>Service: log a different error
        end
    """

    func testACriticalBlockIsOneBlockWithItsOptions() throws {
        let parsed = try parseSequenceDiagram(lines(Self.source))

        XCTAssertEqual(parsed.blocks.count, 1)
        XCTAssertEqual(parsed.blocks[0].type, "critical")
        XCTAssertEqual(parsed.blocks[0].label, "Establish a connection to the DB")
        XCTAssertEqual(parsed.blocks[0].dividers.map(\.label),
                       ["Network timeout", "Credentials rejected"])
        XCTAssertEqual(parsed.messages.count, 3, "no branch is lost on the way in")
    }

    func testTheFrameEnclosesEveryBranch() throws {
        let laid = try layoutSequenceDiagram(parseSequenceDiagram(lines(Self.source)))

        XCTAssertEqual(laid.blocks.count, 1)
        let frame = laid.blocks[0]
        XCTAssertEqual(frame.dividers.count, 2)

        for divider in frame.dividers {
            XCTAssertGreaterThan(divider.y, frame.y, "a divider inside its own frame")
            XCTAssertLessThan(divider.y, frame.y + frame.height)
        }
        for message in laid.messages {
            XCTAssertGreaterThan(message.y, frame.y)
            XCTAssertLessThan(message.y, frame.y + frame.height)
        }
    }

    func testAnOptionOutsideAnyBlockIsNotADivider() throws {
        // Nothing is open, so there is nothing to divide. The line is not a message either,
        // and dropping it is better than attaching it to whatever comes next.
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            option stray
            A->>B: hi
        """))

        XCTAssertEqual(parsed.blocks.count, 0)
        XCTAssertEqual(parsed.messages.count, 1)
    }
}
