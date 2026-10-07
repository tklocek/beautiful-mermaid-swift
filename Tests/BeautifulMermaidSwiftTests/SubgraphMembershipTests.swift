import XCTest
@testable import BeautifulMermaid

/// A node written inside two subgraphs belongs to exactly one: the first subgraph to close
/// that names it. That is Mermaid's rule (`flowDb.addSubGraph` drops every node an earlier
/// subgraph already holds), so an inner subgraph keeps a node its enclosing one also names,
/// and an earlier sibling keeps a node a later sibling repeats.
///
/// One owner matters to the layout as much as to the picture: ELK indexes shapes by
/// identifier, so a node handed over as a child of two compound nodes is defined twice, the
/// later definition wins, and an edge that was meant to leave the first subgraph through its
/// port starts outside it instead. ELK asserts on that in a Debug build.
final class SubgraphMembershipTests: XCTestCase {

    private let siblings = """
    flowchart TD
        subgraph Stage0
            N38["Step 38"] --> N39["Step 39"]
            N39 --> N40["Step 40"]
        end
        subgraph Stage1
            N40 --> N41["Step 41"]
        end
    """

    private func laidOut(_ text: String) throws -> (nodes: [PositionedNode], edges: [PositionedEdge], groups: [PositionedGroup]) {
        let positioned = try GraphLayout().layout(try MermaidParser.parse(text))
        switch positioned.content {
        case .flowchart(let nodes, let edges, let groups), .stateDiagram(let nodes, let edges, let groups):
            return (nodes, edges, groups)
        default:
            XCTFail("not a graph")
            return ([], [], [])
        }
    }

    private func subgraphs(of text: String) throws -> [original_src_types.MermaidSubgraph] {
        try XCTUnwrap(MermaidParser.parse(text).payload as? ParsedGraphModel).subgraphs
    }

    private func contains(_ group: PositionedGroup, _ node: PositionedNode) -> Bool {
        node.x >= group.x && node.y >= group.y
            && node.x + node.width <= group.x + group.width
            && node.y + node.height <= group.y + group.height
    }

    func testANodeNamedInTwoSiblingsBelongsToTheFirst() throws {
        let byId = Dictionary(uniqueKeysWithValues: try subgraphs(of: siblings).map { ($0.id, $0) })
        XCTAssertEqual(byId["Stage0"]?.nodeIds, ["N38", "N39", "N40"])
        XCTAssertEqual(byId["Stage1"]?.nodeIds, ["N41"])
    }

    func testTheLayoutDrawsItInsideTheFirstAndTheEdgeStillCrossesOver() throws {
        try assertStep40IsDrawnInStage0(siblings)
    }

    func testWritingTheLabelAgainInTheSecondSubgraphChangesNothing() throws {
        // Generated diagrams write a node in full on both sides of every edge; this is the
        // form that handed ELK the same identifier twice.
        try assertStep40IsDrawnInStage0(siblings.replacingOccurrences(of: "N40 --> N41", with: "N40[\"Step 40\"] --> N41"))
    }

    private func assertStep40IsDrawnInStage0(_ source: String) throws {
        let (nodes, edges, groups) = try laidOut(source)
        let step40 = try XCTUnwrap(nodes.first { $0.id == "N40" })
        XCTAssertEqual(nodes.filter { $0.id == "N40" }.count, 1, "drawn once")
        let stage0 = try XCTUnwrap(groups.first { $0.id == "Stage0" })
        let stage1 = try XCTUnwrap(groups.first { $0.id == "Stage1" })
        XCTAssertTrue(contains(stage0, step40))
        XCTAssertFalse(contains(stage1, step40))
        let crossing = try XCTUnwrap(edges.first { $0.source == "N40" && $0.target == "N41" })
        XCTAssertGreaterThanOrEqual(crossing.points.count, 2)
    }

    func testTheInnerSubgraphKeepsANodeItsEnclosingOneAlsoNames() throws {
        let nested = """
        flowchart LR
            subgraph Outer
                a --> b
                subgraph Inner
                    b --> c
                end
            end
        """
        let outer = try XCTUnwrap(subgraphs(of: nested).first { $0.id == "Outer" })
        let inner = try XCTUnwrap(outer.children.first { $0.id == "Inner" })
        XCTAssertEqual(outer.nodeIds, ["a"])
        XCTAssertEqual(inner.nodeIds, ["b", "c"])
        let (nodes, _, groups) = try laidOut(nested)
        let b = try XCTUnwrap(nodes.first { $0.id == "b" })
        let innerGroup = try XCTUnwrap(groups.first { $0.id == "Outer" }?.children.first { $0.id == "Inner" })
        XCTAssertTrue(contains(innerGroup, b))
    }

    func testAStateNamedInTwoCompositesBelongsToTheFirst() throws {
        let states = """
        stateDiagram-v2
            state First {
                Idle --> Busy
            }
            state Second {
                Busy --> Done
            }
        """
        let byId = Dictionary(uniqueKeysWithValues: try subgraphs(of: states).map { ($0.id, $0) })
        XCTAssertEqual(byId["First"]?.nodeIds, ["Idle", "Busy"])
        XCTAssertEqual(byId["Second"]?.nodeIds, ["Done"])
        let (nodes, _, groups) = try laidOut(states)
        let busy = try XCTUnwrap(nodes.first { $0.id == "Busy" })
        XCTAssertTrue(contains(try XCTUnwrap(groups.first { $0.id == "First" }), busy))
    }
}
