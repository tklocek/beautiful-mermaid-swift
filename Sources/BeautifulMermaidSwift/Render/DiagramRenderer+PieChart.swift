import Foundation
import CoreGraphics
#if targetEnvironment(macCatalyst)
import UIKit
#elseif canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension DiagramRenderer {

    func _drawPieChart(_ positioned: PositionedGraph, in context: CGContext, bounds: CGRect) {
        guard let chart = positioned.pieChartData else { return }

        _withFittedContext(context, bounds: bounds, contentWidth: max(1, chart.width), contentHeight: max(1, chart.height)) { ctx in
            let textColor = self.theme.foreground
            let mutedColor = self.theme.effectiveMuted()
            let bgColor = self.theme.background
            let accentHex = _hex(self.theme.effectiveAccent()) ?? CHART_ACCENT_FALLBACK
            let bgHex = _hex(bgColor)
            let center = CGPoint(x: chart.centerX, y: chart.centerY)

            if !self.theme.transparent {
                ctx.setFillColor(bgColor.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: chart.width, height: chart.height))
            }

            // Two passes. Filling and stroking each wedge in one pass lets the next
            // wedge's fill paint over the previous wedge's stroke, so separator widths
            // came out uneven, and stroking the whole wedge outline put a mitred join on
            // the very sharp centre vertex, which exceeded the miter limit and was
            // bevelled off — a notch where the slices should meet at a point.
            for slice in chart.slices {
                let colorHex = self._pieSliceHex(slice.colorIndex, accentHex: accentHex, bgHex: bgHex)

                ctx.beginPath()
                if slice.percentage >= 0.9999 {
                    ctx.addEllipse(in: CGRect(
                        x: chart.centerX - chart.radius,
                        y: chart.centerY - chart.radius,
                        width: chart.radius * 2,
                        height: chart.radius * 2
                    ))
                } else {
                    ctx.move(to: center)
                    ctx.addArc(
                        center: center,
                        radius: chart.radius,
                        startAngle: CGFloat(slice.startAngle),
                        endAngle: CGFloat(slice.endAngle),
                        clockwise: false
                    )
                    ctx.closePath()
                }
                ctx.setFillColor(BMColor(hex: colorHex).cgColor)
                ctx.fillPath()
            }

            // Separators are drawn as plain radii: a straight line has no join to mitre,
            // so the centre stays a clean point and every gap is the same width.
            //
            // The cap must be round. A butt cap ends flush and perpendicular to its own
            // radius, and three such ends do not tile the neighbourhood of the centre —
            // they leave slivers of slice colour between them, which reads as the lines
            // stopping just short of each other. Round caps overlap into a single disc of
            // radius lineWidth/2. At the rim the cap spills lineWidth/2 past the circle,
            // which is invisible: it is background colour drawn on background.
            if chart.slices.count > 1 {
                ctx.saveGState()
                ctx.setStrokeColor(bgColor.cgColor)
                ctx.setLineWidth(2)
                ctx.setLineCap(.round)
                for slice in chart.slices {
                    let angle = CGFloat(slice.startAngle)
                    ctx.move(to: center)
                    ctx.addLine(to: CGPoint(
                        x: center.x + cos(angle) * chart.radius,
                        y: center.y + sin(angle) * chart.radius
                    ))
                }
                ctx.strokePath()
                ctx.restoreGState()
            }

            let labelFont = BMFont.systemFont(ofSize: 12, weight: .semibold)
            for slice in chart.slices where slice.percentage >= 0.045 {
                let colorHex = self._pieSliceHex(slice.colorIndex, accentHex: accentHex, bgHex: bgHex)
                let labelColor = isDarkBackground(colorHex) ? BMColor.white : BMColor.black
                self.labelRenderer.drawText(
                    _formatPiePercent(slice.percentage),
                    at: CGPoint(x: slice.labelX, y: slice.labelY),
                    context: ctx,
                    color: labelColor,
                    font: labelFont,
                    alignment: .center
                )
            }

            if let title = chart.title {
                let titleFont = BMFont.systemFont(ofSize: 16, weight: .semibold)
                self.labelRenderer.drawText(
                    title.text,
                    at: CGPoint(x: title.x, y: title.y),
                    context: ctx,
                    color: textColor,
                    font: titleFont,
                    alignment: .center
                )
            }

            let legendFont = BMFont.systemFont(ofSize: 13, weight: .regular)
            for item in chart.legend {
                let colorHex = self._pieSliceHex(item.colorIndex, accentHex: accentHex, bgHex: bgHex)
                let swatch = CGRect(x: item.x, y: item.y - 6, width: 12, height: 12)
                ctx.setFillColor(BMColor(hex: colorHex).cgColor)
                ctx.fill(swatch)
                ctx.setStrokeColor(bgColor.cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(swatch)

                let text = chart.showData ? "\(item.label) \(_formatPieValue(item.value))" : item.label
                self.labelRenderer.drawText(
                    text,
                    at: CGPoint(x: item.x + 20, y: item.y),
                    context: ctx,
                    color: mutedColor,
                    font: legendFont,
                    alignment: .left
                )
            }
        }
    }

    /// Through the theme, so a caller's palette reaches the drawing — and so this path and
    /// the SVG one cannot answer differently, which is how a legend ends up disagreeing with
    /// the slices beside it.
    private func _pieSliceHex(_ index: Int, accentHex: String, bgHex: String?) -> String {
        _hex(theme.seriesColor(at: index)) ?? getSeriesColor(index, accentHex, bgHex)
    }
}
