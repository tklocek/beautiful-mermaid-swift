import XCTest
@testable import BeautifulMermaid

/// The themes derive most of their palette, and they write the derivation into the SVG:
///
///     --_line: var(--line, color-mix(in srgb, var(--fg) 50%, var(--bg)));
///
/// Resolving that with a regular expression whose fallback group was `[^)]+` stopped the
/// match at the first inner `)`, so substituting the outer `var()` left the tail of the
/// mix behind as literal text — `#939394 50%, #FFFFFF))`. Eight of the twelve derived
/// tokens came out like that, and the four written as a bare `color-mix()` were replaced
/// wholesale by a hardcoded `#666666` that ignored the theme. Edges, arrow heads, node
/// fills and borders all drew from those tokens.
final class SvgColorFlatteningTests: XCTestCase {

    private let flowchart = """
    graph TD
        Start([Order placed]) --> Stock{In stock?}
        Stock -->|Yes| Pack[Pack the order]
        Pack --> Done([Delivered])
    """

    private func svg(_ theme: DiagramTheme) throws -> String {
        try MermaidImageRenderer(theme: theme).renderSVG(from: flowchart)
    }

    private var themes: [(name: String, theme: DiagramTheme)] {
        [("zinc-light", .default), ("zinc-dark", .zincDark)]
    }

    // MARK: - The document

    func testNoColorFunctionSurvivesIntoTheOutput() throws {
        for (name, theme) in themes {
            let output = try svg(theme)
            XCTAssertFalse(output.contains("color-mix("), "\(name) still carries a mix")
            XCTAssertFalse(output.contains("var("), "\(name) still carries a variable")
        }
    }

    /// `#666666` is the last resort for an expression that cannot be worked out. Neither
    /// theme names that colour, so seeing it means something fell through.
    func testNothingFallsThroughToTheLastResort() throws {
        for (name, theme) in themes {
            XCTAssertFalse(try svg(theme).contains(_unresolvedColor), "\(name) gave up on a colour")
        }
    }

    /// The defect's own signature: a colour followed by the leftovers of the mix it was
    /// cut out of.
    func testNoAttributeCarriesTheTailOfAMix() throws {
        for (name, theme) in themes {
            for value in try Self.paintAttributes(in: svg(theme)) {
                XCTAssertNotNil(
                    _parseColor(value),
                    "\(name) paints with \"\(value)\", which is not a colour"
                )
            }
        }
    }

    func testOutputIsWellFormedXML() throws {
        for (name, theme) in themes {
            XCTAssertNoThrow(
                try XMLDocument(xmlString: svg(theme), options: []),
                "\(name) is not parseable as XML"
            )
        }
    }

    // MARK: - The values

    func testDerivedTokensTakeTheThemeColoursTheyName() throws {
        let theme = DiagramTheme.default
        let tokens = Self.derivedTokens(in: try svg(theme))

        XCTAssertEqual(tokens["_text"], _hex(theme.foreground))
        XCTAssertEqual(tokens["_line"], _hex(theme.effectiveLine()))
        XCTAssertEqual(tokens["_arrow"], _hex(theme.effectiveAccent()))
        XCTAssertEqual(tokens["_node-fill"], _hex(theme.effectiveSurface()))
        XCTAssertEqual(tokens["_node-stroke"], _hex(theme.effectiveBorder()))
    }

    /// The tokens with no `var()` to fall back on are the ones that were `#666666`. They
    /// are a real mix now: 12% of zinc-light's `#27272A` over white.
    func testBareMixesAreComputedRatherThanGuessed() throws {
        let tokens = Self.derivedTokens(in: try svg(.default))
        XCTAssertEqual(tokens["_inner-stroke"], "#E5E5E5")
        XCTAssertEqual(tokens["_group-hdr"], "#F4F4F4")
        XCTAssertEqual(tokens["_key-badge"], "#E9E9EA")
    }

    func testDerivedTokensFollowTheThemeIntoDark() throws {
        let light = Self.derivedTokens(in: try svg(.default))
        let dark = Self.derivedTokens(in: try svg(.zincDark))
        XCTAssertNotEqual(light["_inner-stroke"], dark["_inner-stroke"])
        XCTAssertEqual(dark["_node-fill"], _hex(DiagramTheme.zincDark.effectiveSurface()))
    }

    // MARK: - The evaluator

    /// The exact shape that broke: a mix nested inside a `var()` fallback.
    func testVariableWinsOverTheMixItFallsBackTo() {
        let resolved = _substitutingColorFunctions(
            "var(--line, color-mix(in srgb, var(--fg) 50%, var(--bg)))",
            variables: ["line": "#939394", "fg": "#27272A", "bg": "#FFFFFF"],
            unresolved: _unresolvedColor
        )
        XCTAssertEqual(resolved, "#939394")
    }

    func testMixIsUsedWhenTheVariableIsAbsent() {
        let resolved = _substitutingColorFunctions(
            "var(--line, color-mix(in srgb, var(--fg) 50%, var(--bg)))",
            variables: ["fg": "#000000", "bg": "#FFFFFF"],
            unresolved: _unresolvedColor
        )
        XCTAssertEqual(resolved, "#808080")
    }

    func testMixWithoutPercentagesIsHalfAndHalf() {
        XCTAssertEqual(_evaluateColorMix(arguments: "in srgb, #000000, #FFFFFF"), "#808080")
    }

    /// CSS normalises a pair that does not add to 100 rather than rejecting it.
    func testPercentagesThatDoNotAddUpAreNormalised() {
        XCTAssertEqual(_evaluateColorMix(arguments: "in srgb, #000000 25%, #FFFFFF 25%"), "#808080")
    }

    /// Mixing into `transparent` has to thin the colour, not drag it towards black — the
    /// difference between premultiplied and naive channel mixing.
    func testMixingIntoTransparentKeepsTheColour() {
        XCTAssertEqual(
            _evaluateColorMix(arguments: "in srgb, #FF0000 20%, transparent"),
            "rgba(255, 0, 0, 0.2)"
        )
    }

    func testShorthandHexIsUnderstood() {
        XCTAssertEqual(_parseColor("#abc"), _parseColor("#AABBCC"))
    }

    /// A space we cannot honour is left standing rather than mixed as though it were
    /// sRGB, so a wrong colour cannot pass for a right one.
    func testAnUnsupportedColourSpaceIsDeclined() {
        XCTAssertNil(_evaluateColorMix(arguments: "in oklch, #000000 50%, #FFFFFF"))
    }

    /// Only a bare unknown name has nothing to fall back on.
    func testAnUnknownVariableWithNoFallbackGivesUp() {
        XCTAssertEqual(
            _substitutingColorFunctions("var(--nope)", variables: [:], unresolved: _unresolvedColor),
            _unresolvedColor
        )
    }

    func testNestingInsideAnUnrelatedFunctionIsLeftIntact() {
        let resolved = _substitutingColorFunctions(
            "drop-shadow(0 1px 3px color-mix(in srgb, var(--fg) 20%, transparent))",
            variables: ["fg": "#FF0000"],
            unresolved: _unresolvedColor
        )
        XCTAssertEqual(resolved, "drop-shadow(0 1px 3px rgba(255, 0, 0, 0.2))")
    }

    // MARK: - Reading the output

    /// Every `fill=` and `stroke=` value in the document, minus the ones that name
    /// something other than a colour.
    private static func paintAttributes(in svg: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: #"(?:fill|stroke)="([^"]*)""#)
        let ns = svg as NSString
        return regex.matches(in: svg, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
            .filter { $0 != "none" && !$0.hasPrefix("url(") && !$0.hasPrefix("rgba(") }
    }

    /// The `--_name: value` declarations from the document's style block.
    private static func derivedTokens(in svg: String) -> [String: String] {
        _cssVariableDefinitions(in: svg).filter { $0.key.hasPrefix("_") }
    }
}
