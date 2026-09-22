import XCTest
@testable import BeautifulMermaid

/// A caller may supply the colours series are drawn in.
///
/// Until now every renderer derived them privately from the theme's accent — a ramp of one
/// hue at alternating lightness. That is a reasonable default and stays the default; what it
/// could not be was overridden, so an application with a palette of its own had two charts
/// that did not match: the ones this library draws, and the ones it draws itself.
final class SeriesPaletteTests: XCTestCase {

    private let palette = ["#ff0000", "#00ff00", "#0000ff"]

    private var themed: DiagramTheme {
        DiagramTheme(background: BMColor(hex: "#ffffff"), foreground: BMColor(hex: "#000000"),
                     accent: BMColor(hex: "#3b82f6"),
                     series: palette.map { BMColor(hex: $0) })
    }

    // MARK: - The palette itself

    func testAPaletteIsUsedInOrder() {
        let theme = themed
        for (index, hex) in palette.enumerated() {
            XCTAssertTrue(theme.seriesColor(at: index).bmColorEquals(BMColor(hex: hex)),
                          "series \(index) did not come from the palette")
        }
    }

    func testItWrapsRatherThanRunningOut() {
        let theme = themed
        XCTAssertTrue(theme.seriesColor(at: 3).bmColorEquals(BMColor(hex: palette[0])))
        XCTAssertTrue(theme.seriesColor(at: 7).bmColorEquals(BMColor(hex: palette[1])))
    }

    func testWithoutOneTheDerivedRampIsUnchanged() {
        let theme = DiagramTheme(background: BMColor(hex: "#ffffff"),
                                 foreground: BMColor(hex: "#000000"),
                                 accent: BMColor(hex: "#3b82f6"))
        XCTAssertNil(theme.series)
        XCTAssertTrue(theme.seriesColor(at: 0).bmColorEquals(theme.effectiveAccent()),
                      "the first series has always been the accent itself")

        let derived = getSeriesColor(2, "#3b82f6", "#ffffff")
        XCTAssertTrue(theme.seriesColor(at: 2).bmColorEquals(BMColor(hex: derived)),
                      "the ramp must be exactly what it was before this option existed")
    }

    func testAnEmptyPaletteIsNoPaletteAtAll() {
        let theme = DiagramTheme(background: BMColor(hex: "#ffffff"),
                                 foreground: BMColor(hex: "#000000"),
                                 accent: BMColor(hex: "#3b82f6"), series: [])
        XCTAssertTrue(theme.seriesColor(at: 1).bmColorEquals(BMColor(hex: getSeriesColor(1, "#3b82f6", "#ffffff"))))
    }

    // MARK: - Both renderers, one answer

    func testThePieSvgPaintsTheSuppliedColours() throws {
        let svg = try MermaidImageRenderer(theme: themed).renderSVG(from: """
        pie
            "One" : 40
            "Two" : 35
            "Three" : 25
        """)
        for hex in palette {
            XCTAssertTrue(svg.lowercased().contains(hex), "the SVG never mentions \(hex)")
        }
    }

    func testTheXYChartSvgPaintsThemToo() throws {
        let svg = try MermaidImageRenderer(theme: themed).renderSVG(from: """
        xychart-beta
            x-axis [Jan, Feb, Mar]
            bar [10, 20, 30]
            line [5, 15, 25]
        """)
        XCTAssertTrue(svg.lowercased().contains(palette[0]))
        XCTAssertTrue(svg.lowercased().contains(palette[1]))
    }

    /// The two renderers must not answer differently — a legend that disagrees with the
    /// slices beside it is the shape that defect takes.
    func testTheDrawnPieUsesTheSameColoursAsTheSvg() throws {
        let theme = themed
        let source = "pie\n    \"One\" : 40\n    \"Two\" : 60"

        let drawn = try XCTUnwrap(MermaidImageRenderer(theme: theme).renderImage(from: source, scale: 1))
        let pixels = try XCTUnwrap(drawn.bmPixelData())

        // The first slice is the palette's first colour, so it has to be *on* the drawing.
        XCTAssertTrue(pixels.contains(red: 255, green: 0, blue: 0),
                      "the drawn pie has no pure red in it, so it ignored the palette")
        XCTAssertTrue(pixels.contains(red: 0, green: 255, blue: 0),
                      "the drawn pie has no pure green in it, so it ignored the palette")
    }
}

private extension BMImage {
    /// The image's pixels, for asking whether a colour reached the drawing.
    func bmPixelData() -> PixelSheet? {
        guard let cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return PixelSheet(bytes: bytes)
    }
}

private struct PixelSheet {
    let bytes: [UInt8]

    /// Spelled out a step at a time on purpose. Written as one chained expression over
    /// `stride(...).contains { }`, with three `Int` conversions and three comparisons inside
    /// a closure, this takes the type checker longer than it is willing to spend — and how
    /// much longer depends on the machine, so a version that compiles here can fail on a
    /// build server.
    func contains(red: UInt8, green: UInt8, blue: UInt8, tolerance: Int = 6) -> Bool {
        let wantedRed = Int(red)
        let wantedGreen = Int(green)
        let wantedBlue = Int(blue)

        var index = 0
        while index + 3 < bytes.count {
            let pixelRed = Int(bytes[index])
            let pixelGreen = Int(bytes[index + 1])
            let pixelBlue = Int(bytes[index + 2])

            if abs(pixelRed - wantedRed) <= tolerance,
               abs(pixelGreen - wantedGreen) <= tolerance,
               abs(pixelBlue - wantedBlue) <= tolerance {
                return true
            }
            index += 4
        }
        return false
    }
}
