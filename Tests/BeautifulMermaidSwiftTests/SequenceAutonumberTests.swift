import XCTest
@testable import BeautifulMermaid

final class SequenceAutonumberTests: XCTestCase {

    private func lines(_ source: String) -> [String] {
        source
            .components(separatedBy: CharacterSet(charactersIn: "\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
    }

    private func numbers(_ source: String) throws -> [Int?] {
        try parseSequenceDiagram(lines(source)).messages.map { $0.sequenceNumber }
    }

    func testMessagesAreUnnumberedWithoutTheDirective() throws {
        let source = """
        sequenceDiagram
            A->>B: one
            B-->>A: two
        """

        XCTAssertEqual(try numbers(source), [nil, nil])
    }

    func testBareAutonumberStartsAtOneAndStepsByOne() throws {
        let source = """
        sequenceDiagram
            autonumber
            A->>B: one
            B-->>A: two
            A->>B: three
        """

        XCTAssertEqual(try numbers(source), [1, 2, 3])
    }

    func testAutonumberHonoursAnExplicitStart() throws {
        let source = """
        sequenceDiagram
            autonumber 10
            A->>B: one
            B-->>A: two
        """

        XCTAssertEqual(try numbers(source), [10, 11])
    }

    func testAutonumberHonoursAnExplicitStartAndStep() throws {
        let source = """
        sequenceDiagram
            autonumber 10 5
            A->>B: one
            B-->>A: two
            A->>B: three
        """

        XCTAssertEqual(try numbers(source), [10, 15, 20])
    }

    func testAutonumberOffStopsNumberingLaterMessages() throws {
        let source = """
        sequenceDiagram
            autonumber
            A->>B: one
            autonumber off
            B-->>A: two
            A->>B: three
        """

        XCTAssertEqual(try numbers(source), [1, nil, nil])
    }

    func testAutonumberCanRestartMidDiagram() throws {
        let source = """
        sequenceDiagram
            autonumber
            A->>B: one
            A->>B: two
            autonumber 100
            B-->>A: three
        """

        XCTAssertEqual(try numbers(source), [1, 2, 100])
    }

    func testDirectiveIsCaseInsensitiveAndNotMistakenForAMessage() throws {
        let source = """
        sequenceDiagram
            AutoNumber
            A->>B: one
        """

        let diagram = try parseSequenceDiagram(lines(source))
        XCTAssertEqual(diagram.messages.count, 1, "the directive must not be parsed as a message")
        XCTAssertEqual(diagram.messages[0].label, "one")
        XCTAssertEqual(diagram.actors.map { $0.id }, ["A", "B"], "the directive must not create an actor")
    }

    func testSelfMessagesAndBlockContentsAreNumbered() throws {
        let source = """
        sequenceDiagram
            autonumber
            A->>B: one
            loop every 30s
                B->>B: poll
            end
            B-->>A: done
        """

        XCTAssertEqual(try numbers(source), [1, 2, 3])
    }

    func testNumbersSurviveLayout() throws {
        let source = """
        sequenceDiagram
            autonumber 7
            A->>B: one
            B-->>A: two
        """

        let positioned = try layoutSequenceDiagram(parseSequenceDiagram(lines(source)))

        XCTAssertEqual(positioned.messages.map { $0.sequenceNumber }, [7, 8])
    }

    func testSvgRendersABadgePerNumberedMessage() throws {
        let source = """
        sequenceDiagram
            autonumber
            A->>B: one
            B-->>A: two
        """

        let svg = try renderMermaidSVG(source)

        XCTAssertEqual(svg.components(separatedBy: "class=\"sequence-number\"").count - 1, 2)
        XCTAssertTrue(svg.contains("data-sequence-number=\"1\""))
        XCTAssertTrue(svg.contains("data-sequence-number=\"2\""))
    }

    func testSvgOmitsBadgesWhenAutonumberIsAbsent() throws {
        let source = """
        sequenceDiagram
            A->>B: one
        """

        let svg = try renderMermaidSVG(source)

        XCTAssertFalse(svg.contains("sequence-number"))
    }

    func testAsciiPrefixesNumberedLabels() throws {
        let source = """
        sequenceDiagram
            autonumber
            A->>B: hello
        """

        let ascii = try renderSequenceAscii(
            source,
            AsciiConfig(useAscii: true, paddingX: 1, paddingY: 1, boxBorderPadding: 1, graphDirection: "TD")
        )

        XCTAssertTrue(ascii.contains("1. hello"), "expected a numbered label, got:\n\(ascii)")
    }
}
