import XCTest
@testable import BeautifulMermaid

/// `svgOpenTag` writes the CSS variables every renderer's stylesheet reads, so what it emits
/// is load-bearing for every diagram kind at once.
///
/// It is tested here because the expression that built them was rewritten for compile time —
/// 2,950 ms of type checking for one array literal — and a rewrite that changed the output by
/// a semicolon would change every diagram this library draws.
final class SvgOpenTagTests: XCTestCase {

    func testEveryColourGivenBecomesAVariable() {
        let colors = original_src_theme.DiagramColors(bg: "#fff", fg: "#000", line: "#111", accent: "#222",
                                   muted: "#333", surface: "#444", border: "#555")
        let tag = original_src_theme.svgOpenTag(100, 50, colors)

        XCTAssertTrue(tag.contains("--bg:#fff;--fg:#000;--line:#111;--accent:#222;--muted:#333;--surface:#444;--border:#555"))
        XCTAssertTrue(tag.contains("background:var(--bg)"))
        XCTAssertTrue(tag.contains("viewBox=\"0 0 100 50\""))
    }

    func testAColourLeftOutLeavesNoVariableBehind() {
        let colors = original_src_theme.DiagramColors(bg: "#fff", fg: "#000", accent: "#222")
        let tag = original_src_theme.svgOpenTag(10, 10, colors)

        XCTAssertTrue(tag.contains("--bg:#fff;--fg:#000;--accent:#222"))
        XCTAssertFalse(tag.contains("--line"))
        XCTAssertFalse(tag.contains(";;"), "an absent colour left an empty declaration behind")
    }

    func testTransparentDropsTheBackgroundButKeepsTheVariable() {
        let colors = original_src_theme.DiagramColors(bg: "#fff", fg: "#000")
        let tag = original_src_theme.svgOpenTag(10, 10, colors, true)

        XCTAssertTrue(tag.contains("--bg:#fff"))
        XCTAssertFalse(tag.contains("background:var(--bg)"))
    }
}
