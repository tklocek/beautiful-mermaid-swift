import Foundation
import CoreGraphics
#if targetEnvironment(macCatalyst)
import UIKit
#elseif canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

func _hex(_ color: BMColor) -> String? {
    #if targetEnvironment(macCatalyst) || canImport(UIKit)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
    #elseif canImport(AppKit)
    guard let rgb = color.usingColorSpace(.deviceRGB) else { return nil }
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
    #else
    return nil
    #endif

    let ri = Int(max(0, min(255, (r * 255).rounded())))
    let gi = Int(max(0, min(255, (g * 255).rounded())))
    let bi = Int(max(0, min(255, (b * 255).rounded())))
    return String(format: "#%02X%02X%02X", ri, gi, bi)
}

func _flattenKnownSvgTokens(_ svg: String, theme: DiagramTheme) -> String {
    let bg = _hex(theme.background) ?? "#FFFFFF"
    let fg = _hex(theme.foreground) ?? "#27272A"
    let line = _hex(theme.effectiveLine()) ?? fg
    let muted = _hex(theme.effectiveMuted()) ?? line
    let surface = _hex(theme.effectiveSurface()) ?? bg
    let border = _hex(theme.effectiveBorder()) ?? line

    let replacements: [(token: String, value: String)] = [
        ("_line", line),
        ("_arrow", line),
        ("_node-fill", surface),
        ("_node-stroke", border),
        ("_group-fill", surface),
        ("_group-hdr", surface),
        ("_inner-stroke", border),
        ("_text", fg),
        ("_text-sec", muted),
        ("_text-muted", muted),
        ("_state-end-outer", fg),
        ("_state-end-inner", bg),
    ]

    var out = svg
    for item in replacements {
        let pattern = #"var\(\s*--\#(item.token)\s*(?:,\s*[^)]*)?\)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(location: 0, length: (out as NSString).length)
            out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: item.value)
        }
    }
    return out
}

/// What a `var()` or `color-mix()` becomes when it cannot be worked out.
///
/// It should never be reached for a theme that names its colours: every `var()` the
/// renderers emit either resolves or carries a fallback. It is here so a colour nobody
/// anticipated leaves valid CSS behind rather than a fragment of one.
let _unresolvedColor = "#666666"

func _resolveSvgCssVariables(_ svg: String) -> String {
    var variables = _cssVariableDefinitions(in: svg)
    guard !variables.isEmpty else { return svg }

    // Definitions lean on each other — `--_line` is written in terms of `--line`, `--fg`
    // and `--bg` — so settle them among themselves before substituting into the document,
    // leaving anything still unknown verbatim for the pass that follows. Bounded rather
    // than run to a fixed point, because a cycle would otherwise spin here forever.
    for _ in 0..<8 {
        var changed = false
        // Sorted so a diagram renders the same way twice: mutually dependent definitions
        // can settle differently depending on which is visited first.
        for name in variables.keys.sorted() {
            guard let value = variables[name] else { continue }
            let resolved = _substitutingColorFunctions(value, variables: variables, unresolved: nil)
            if resolved != value {
                variables[name] = resolved
                changed = true
            }
        }
        if !changed { break }
    }

    return _substitutingColorFunctions(svg, variables: variables, unresolved: _unresolvedColor)
}

/// Every `--name: value` declaration in the document, from the `<svg>` element's own
/// style attribute as much as from the `<style>` block.
func _cssVariableDefinitions(in svg: String) -> [String: String] {
    let ns = svg as NSString
    guard let regex = try? NSRegularExpression(pattern: "--([a-zA-Z0-9_-]+)\\s*:\\s*([^;\\\"]+)") else {
        return [:]
    }

    var variables: [String: String] = [:]
    for match in regex.matches(in: svg, range: NSRange(location: 0, length: ns.length))
    where match.numberOfRanges >= 3 {
        let name = ns.substring(with: match.range(at: 1))
        variables[name] = ns.substring(with: match.range(at: 2))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return variables
}

// MARK: - CSS colour functions

/// `css` with every `var()` and `color-mix()` replaced by the colour it stands for.
///
/// A scanner rather than a regular expression because both functions nest, and the shape
/// the themes emit nests two deep:
///
///     var(--line, color-mix(in srgb, var(--fg) 50%, var(--bg)))
///
/// A `[^)]` fallback group stops at the first inner `)`, so the match ends halfway
/// through the mix and substituting it leaves the tail behind as literal text —
/// `#939394 50%, #FFFFFF))`, which is not a colour and paints as black or nothing.
///
/// `unresolved` is what to put in place of a call that cannot be worked out; `nil` leaves
/// such a call standing, which is what the pass over the definitions themselves wants.
func _substitutingColorFunctions(
    _ css: String,
    variables: [String: String],
    unresolved: String?
) -> String {
    var out = ""
    var index = css.startIndex

    while index < css.endIndex {
        guard let call = _nextColorFunction(in: css, from: index) else {
            out += css[index...]
            return out
        }

        out += css[index..<call.start]
        let arguments = _substitutingColorFunctions(
            String(css[call.arguments]),
            variables: variables,
            unresolved: unresolved
        )
        // A call left standing keeps the arguments already worked out, so the next pass
        // over it starts from the progress this one made.
        out += _evaluateColorFunction(call.name, arguments: arguments, variables: variables, unresolved: unresolved)
            ?? "\(call.name)(\(arguments))"
        index = call.end
    }
    return out
}

/// The first `var(` or `color-mix(` at or after `start`, with the range of its arguments
/// and the index just past its closing parenthesis.
private func _nextColorFunction(
    in css: String,
    from start: String.Index
) -> (name: String, start: String.Index, arguments: Range<String.Index>, end: String.Index)? {
    var index = start
    while index < css.endIndex {
        for opening in ["var(", "color-mix("] where css[index...].hasPrefix(opening) {
            let open = css.index(index, offsetBy: opening.count)
            guard let close = _closingParenthesis(in: css, openedBefore: open) else { continue }
            return (String(opening.dropLast()), index, open..<close, css.index(after: close))
        }
        index = css.index(after: index)
    }
    return nil
}

/// The `)` closing the group that `open` is the first character inside of.
private func _closingParenthesis(in css: String, openedBefore open: String.Index) -> String.Index? {
    var depth = 1
    var index = open
    while index < css.endIndex {
        switch css[index] {
        case "(":
            depth += 1
        case ")":
            depth -= 1
            if depth == 0 { return index }
        default:
            break
        }
        index = css.index(after: index)
    }
    return nil
}

/// The value of one call whose arguments are already substituted, or `nil` when it cannot
/// be worked out and `unresolved` says to leave it standing.
private func _evaluateColorFunction(
    _ name: String,
    arguments: String,
    variables: [String: String],
    unresolved: String?
) -> String? {
    switch name {
    case "var":
        let parts = _splitTopLevelArguments(arguments)
        let key = parts.first.map { $0.hasPrefix("--") ? String($0.dropFirst(2)) : $0 } ?? ""
        if let defined = variables[key], !defined.isEmpty {
            return defined
        }
        // A `var()` carrying a fallback always resolves — that is the point of the
        // fallback — so only a bare unknown name is left to `unresolved`.
        let fallback = parts.dropFirst().joined(separator: ", ")
        return fallback.isEmpty ? unresolved : fallback
    case "color-mix":
        return _evaluateColorMix(arguments: arguments) ?? unresolved
    default:
        return unresolved
    }
}

/// `arguments` split on the commas that separate them, ignoring commas nested inside a
/// function call of their own.
func _splitTopLevelArguments(_ arguments: String) -> [String] {
    var parts: [String] = []
    var current = ""
    var depth = 0

    for character in arguments {
        switch character {
        case "(":
            depth += 1
            current.append(character)
        case ")":
            depth -= 1
            current.append(character)
        case "," where depth == 0:
            parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
            current = ""
        default:
            current.append(character)
        }
    }
    parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
    return parts
}

/// `color-mix(in srgb, <colour> <percentage>, <colour> <percentage>)` as a flat colour.
///
/// Only sRGB is implemented. Another colour space returns nil rather than being mixed as
/// though it were sRGB, so a space we cannot honour is visible instead of silently wrong.
func _evaluateColorMix(arguments: String) -> String? {
    let parts = _splitTopLevelArguments(arguments)
    guard
        parts.count == 3,
        parts[0].lowercased().split(separator: " ").map(String.init) == ["in", "srgb"],
        let first = _parseColorMixComponent(parts[1]),
        let second = _parseColorMixComponent(parts[2])
    else { return nil }

    // CSS Color 5: one percentage implies the other, neither means half and half, and a
    // pair that does not add to 100 is normalised rather than rejected.
    let firstPercentage: Double
    let secondPercentage: Double
    switch (first.percentage, second.percentage) {
    case (nil, nil):
        firstPercentage = 50
        secondPercentage = 50
    case (let given?, nil):
        firstPercentage = given
        secondPercentage = 100 - given
    case (nil, let given?):
        firstPercentage = 100 - given
        secondPercentage = given
    case (let a?, let b?):
        firstPercentage = a
        secondPercentage = b
    }

    let total = firstPercentage + secondPercentage
    guard total > 0 else { return nil }
    let firstWeight = firstPercentage / total
    let secondWeight = secondPercentage / total

    // Mixed premultiplied, so mixing into `transparent` keeps the visible colour and only
    // thins it, rather than dragging it towards black.
    let alpha = first.color.alpha * firstWeight + second.color.alpha * secondWeight
    func channel(_ a: Double, _ b: Double) -> Double {
        guard alpha > 0 else { return 0 }
        return (a * first.color.alpha * firstWeight + b * second.color.alpha * secondWeight) / alpha
    }

    return _formatColor(_RGBA(
        red: channel(first.color.red, second.color.red),
        green: channel(first.color.green, second.color.green),
        blue: channel(first.color.blue, second.color.blue),
        alpha: alpha
    ))
}

/// One side of a mix: a colour, and how much of it, in either order.
private func _parseColorMixComponent(_ text: String) -> (color: _RGBA, percentage: Double?)? {
    var color: _RGBA?
    var percentage: Double?

    for field in text.split(separator: " ", omittingEmptySubsequences: true) {
        if field.hasSuffix("%") {
            guard let value = Double(field.dropLast()) else { return nil }
            percentage = value
        } else if let parsed = _parseColor(String(field)) {
            color = parsed
        } else {
            return nil
        }
    }

    guard let color else { return nil }
    return (color, percentage)
}

/// A colour kept in 0...1 so a mix is not rounded to bytes twice.
struct _RGBA: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

/// Hex in any of CSS's four lengths, or `transparent`. Anything else — a named colour, a
/// gradient — returns nil, and the caller leaves the expression alone.
func _parseColor(_ text: String) -> _RGBA? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value == "transparent" {
        return _RGBA(red: 0, green: 0, blue: 0, alpha: 0)
    }

    guard value.hasPrefix("#") else { return nil }
    var digits = Array(value.dropFirst())
    // #rgb and #rgba say each digit twice.
    if digits.count == 3 || digits.count == 4 {
        digits = digits.flatMap { [$0, $0] }
    }
    guard digits.count == 6 || digits.count == 8 else { return nil }

    func channel(_ pair: ArraySlice<Character>) -> Double? {
        UInt8(String(pair), radix: 16).map { Double($0) / 255 }
    }
    guard
        let red = channel(digits[0..<2]),
        let green = channel(digits[2..<4]),
        let blue = channel(digits[4..<6]),
        let alpha = digits.count == 8 ? channel(digits[6..<8]) : 1
    else { return nil }

    return _RGBA(red: red, green: green, blue: blue, alpha: alpha)
}

/// Hex while the colour is opaque, `rgba()` once it is not — `#RRGGBBAA` is the one form
/// of hex the platform rasterisers are shaky on.
func _formatColor(_ color: _RGBA) -> String {
    func byte(_ value: Double) -> Int {
        Int((max(0, min(1, value)) * 255).rounded())
    }
    guard color.alpha < 1 else {
        return String(format: "#%02X%02X%02X", byte(color.red), byte(color.green), byte(color.blue))
    }
    let alpha = (max(0, color.alpha) * 1000).rounded() / 1000
    return "rgba(\(byte(color.red)), \(byte(color.green)), \(byte(color.blue)), \(alpha))"
}
