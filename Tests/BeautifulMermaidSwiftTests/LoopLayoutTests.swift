import XCTest
@testable import BeautifulMermaid

/// A loop is opened at the edge written last, and the diagram reads in the order it was written.
///
/// A chain closed by one edge back to its start gives every node one edge in and one out, and
/// ELK's default cycle breaker, which goes by those counts, could turn the *first* edge round:
/// the start was laid out at the bottom, the end at the top, and the whole diagram read upside
/// down — with the closing edge, the one that was actually added, drawn as if it led the way.
final class LoopLayoutTests: XCTestCase {

    private let source = """
    graph TD
        Start([Order placed]) --> Stock{In stock?}
        Stock -->|Yes| Pack[Pack the order]
        Stock -->|No| Tell[Tell the customer]
        Pack --> Ship[Hand to courier]
        Tell --> Ship
        Ship --> Done([Delivered])
        Done -->|Something went wrong| Start
    """

    private func laidOut(_ text: String) throws -> (nodes: [PositionedNode], edges: [PositionedEdge]) {
        let positioned = try GraphLayout().layout(try MermaidParser.parse(text))
        guard case .flowchart(let nodes, let edges, _) = positioned.content else {
            XCTFail("not a flowchart")
            return ([], [])
        }
        return (nodes, edges)
    }

    func testTheDiagramReadsInTheOrderItWasWritten() throws {
        let (nodes, _) = try laidOut(source)
        let y = Dictionary(nodes.map { ($0.id, $0.y) }, uniquingKeysWith: { first, _ in first })
        let order = ["Start", "Stock", "Pack", "Ship", "Done"].compactMap { y[$0] }
        XCTAssertEqual(order.count, 5)
        XCTAssertEqual(order, order.sorted(), "top to bottom as written, not upside down")
    }

    func testTheEdgeBackIsDrawnFromWhereItWasWrittenFrom() throws {
        let (nodes, edges) = try laidOut(source)
        let back = try XCTUnwrap(edges.first { $0.source == "Done" && $0.target == "Start" })
        let done = try XCTUnwrap(nodes.first { $0.id == "Done" })
        let start = try XCTUnwrap(nodes.first { $0.id == "Start" })
        let first = try XCTUnwrap(back.points.first), last = try XCTUnwrap(back.points.last)
        // It leaves the end and arrives at the start: the arrow head is at the start.
        XCTAssertLessThan(abs(first.y - (done.y + done.height / 2)), done.height / 2 + 1)
        XCTAssertLessThan(abs(last.y - (start.y + start.height / 2)), start.height / 2 + 1)
        XCTAssertTrue(back.hasArrowEnd)
        XCTAssertNotNil(back.labelPosition, "its words sit on it, like any other line's")
    }

    func testAGraphWithoutALoopIsLaidOutAsBefore() throws {
        let chain = "graph TD\n    A --> B\n    B --> C\n"
        let (nodes, edges) = try laidOut(chain)
        let y = Dictionary(nodes.map { ($0.id, $0.y) }, uniquingKeysWith: { first, _ in first })
        XCTAssertLessThan(try XCTUnwrap(y["A"]), try XCTUnwrap(y["B"]))
        XCTAssertLessThan(try XCTUnwrap(y["B"]), try XCTUnwrap(y["C"]))
        XCTAssertEqual(edges.map(\.source), ["A", "B"])
    }

    func testASelfLoopIsLeftToELK() throws {
        let (_, edges) = try laidOut("graph TD\n    A --> B\n    B --> B\n")
        XCTAssertEqual(edges.count, 2)
    }
}
