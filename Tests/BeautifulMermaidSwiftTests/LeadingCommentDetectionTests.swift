import XCTest
@testable import BeautifulMermaid

/// A `%%` comment above the declaration is ordinary Mermaid, and `MermaidParser.parse`
/// has always skipped one. The SVG and ASCII renderers detected the diagram type from the
/// literal first line instead, so a leading comment routed every document to the flowchart
/// renderer — which then rejected the header it found on line 2.
final class LeadingCommentDetectionTests: XCTestCase {

    /// Bodies whose declaration is on line 1, paired with a marker that only that kind's
    /// renderer emits — so that a test cannot pass by rendering the wrong kind.
    private static let diagrams: [(name: String, body: String, marker: String)] = [
        ("sequence", "sequenceDiagram\n    Alice ->> Bob: hello", "lifeline"),
        ("class", "classDiagram\n    class Animal\n    Animal : +int age", "Animal"),
        ("er", "erDiagram\n    CUSTOMER ||--o{ ORDER : places", "CUSTOMER"),
        ("xychart", "xychart-beta\n    x-axis [jan, feb]\n    bar [10, 20]", "jan"),
        ("piechart", "pie title Traffic\n    \"Direct\" : 60\n    \"Search\" : 40", "Direct"),
        ("flowchart", "graph TD\n    A[Start] --> B[End]", "Start"),
    ]

    // MARK: - SVG

    func testLeadingCommentDoesNotChangeTheRenderedSVG() throws {
        for (name, body, marker) in Self.diagrams {
            let plain = try renderMermaidSVG(body)
            XCTAssertTrue(plain.contains(marker), "\(name): baseline render lost its content")

            let commented = try renderMermaidSVG("%% a note about this diagram\n" + body)
            XCTAssertEqual(commented, plain, "\(name): a leading comment changed the rendering")
        }
    }

    func testBlankLinesAndSeveralCommentsAboveTheDeclaration() throws {
        for (name, body, _) in Self.diagrams {
            let plain = try renderMermaidSVG(body)
            let noisy = try renderMermaidSVG("\n%% one\n\n%%{init: {\"theme\": \"base\"}}%%\n   \n" + body)
            XCTAssertEqual(noisy, plain, "\(name): leading blank lines or directives changed the rendering")
        }
    }

    /// Detection splits on `;` as well as newlines, and must keep doing so.
    func testSemicolonSeparatedDiagramWithALeadingComment() throws {
        let svg = try renderMermaidSVG("%% a note\nsequenceDiagram; Alice ->> Bob: hi")
        XCTAssertTrue(svg.contains("lifeline"), "semicolon-separated sequence lost its kind")
    }

    // MARK: - ASCII

    func testAsciiDetectionSkipsLeadingComments() {
        for (name, body, _) in Self.diagrams {
            let expected = original_src_ascii_index.detectDiagramType(body)
            let actual = original_src_ascii_index.detectDiagramType("%% a note\n\n" + body)
            XCTAssertEqual(actual, expected, "\(name): ASCII detection was thrown off by a leading comment")
        }
    }
}
