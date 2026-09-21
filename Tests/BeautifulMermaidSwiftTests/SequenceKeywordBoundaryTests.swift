import XCTest
@testable import BeautifulMermaid

/// A block keyword only opens a block when it is a *word*.
///
/// It used to open one whenever it was a prefix, because the label was matched with `\s*`
/// rather than `\s+`. A participant called `optimiser` therefore began an `opt` block
/// labelled `imiser->>B: tune`, and since that block's `end` never arrived — the author
/// wrote no block — it was still open at the end of the parse and thrown away with every
/// message inside it. The diagram simply lost those lines, with nothing to say it had.
final class SequenceKeywordBoundaryTests: XCTestCase {

    private func lines(_ source: String) -> [String] {
        source
            .components(separatedBy: CharacterSet(charactersIn: "\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
    }

    func testAParticipantNamedAfterAKeywordKeepsItsMessages() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            optimiser->>B: tune
            parser->>B: read
            android->>B: ping
            rectangle->>B: draw
            breakpoint->>B: stop
            critically->>B: warn
            loopback->>B: echo
            B->>optimiser: done
        """))

        XCTAssertEqual(parsed.messages.count, 8, "every line is a message; none of them opens a block")
        XCTAssertEqual(parsed.blocks.count, 0)
        XCTAssertEqual(parsed.messages.map(\.from),
                       ["optimiser", "parser", "android", "rectangle", "breakpoint",
                        "critically", "loopback", "B"])
    }

    func testAnElseLikeNameIsNotADivider() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            alt ready
                elsewhere->>B: go
                andrew->>B: follow
            else not ready
                A->>B: wait
            end
        """))

        XCTAssertEqual(parsed.blocks.count, 1)
        XCTAssertEqual(parsed.blocks[0].dividers.map(\.label), ["not ready"],
                       "only the real `else` divides the block")
        XCTAssertEqual(parsed.messages.map(\.from), ["elsewhere", "andrew", "A"])
    }

    func testTheKeywordsThemselvesStillOpenBlocks() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            loop every 30s
                A->>B: poll
            end
            par one
                A->>B: x
            and two
                A->>C: y
            end
            opt maybe
                A->>B: z
            end
        """))

        XCTAssertEqual(parsed.blocks.map(\.type).sorted(), ["loop", "opt", "par"])
        XCTAssertEqual(parsed.blocks.first { $0.type == "par" }?.dividers.map(\.label), ["two"])
    }

    func testABlockNeedsNoLabel() throws {
        let parsed = try parseSequenceDiagram(lines("""
        sequenceDiagram
            loop
                A->>B: poll
            end
        """))

        XCTAssertEqual(parsed.blocks.count, 1)
        XCTAssertEqual(parsed.blocks[0].type, "loop")
        XCTAssertEqual(parsed.blocks[0].label, "")
    }
}
