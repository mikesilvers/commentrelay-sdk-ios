// Sources/CommentRelayUI/Fields/Smiley/SmileyPathParser.swift
import SwiftUI
import CoreGraphics

/// Parses the narrow subset of SVG path `d` attributes that the CommentRelay
/// API emits for smiley mouths: `M/m`, `L/l`, `C/c`, and `Z/z`.
///
/// Anything outside that subset — or a malformed argument count — yields `nil`.
/// An empty input yields an empty `Path` (not `nil`).
enum SmileyPathParser {
    static func parse(d: String) -> Path? {
        let tokens = tokenize(d)
        var i = 0
        var path = Path()
        var cursor = CGPoint.zero

        func num() -> CGFloat? {
            guard i < tokens.count, let v = Double(tokens[i]) else { return nil }
            i += 1
            return CGFloat(v)
        }

        while i < tokens.count {
            let cmd = tokens[i]
            i += 1
            switch cmd {
            case "M":
                guard let x = num(), let y = num() else { return nil }
                cursor = CGPoint(x: x, y: y)
                path.move(to: cursor)
            case "m":
                guard let dx = num(), let dy = num() else { return nil }
                cursor = CGPoint(x: cursor.x + dx, y: cursor.y + dy)
                path.move(to: cursor)
            case "L":
                guard let x = num(), let y = num() else { return nil }
                cursor = CGPoint(x: x, y: y)
                path.addLine(to: cursor)
            case "l":
                guard let dx = num(), let dy = num() else { return nil }
                cursor = CGPoint(x: cursor.x + dx, y: cursor.y + dy)
                path.addLine(to: cursor)
            case "C":
                guard let c1x = num(), let c1y = num(),
                      let c2x = num(), let c2y = num(),
                      let x = num(), let y = num() else { return nil }
                let end = CGPoint(x: x, y: y)
                path.addCurve(to: end,
                              control1: CGPoint(x: c1x, y: c1y),
                              control2: CGPoint(x: c2x, y: c2y))
                cursor = end
            case "c":
                guard let dc1x = num(), let dc1y = num(),
                      let dc2x = num(), let dc2y = num(),
                      let dx = num(), let dy = num() else { return nil }
                let end = CGPoint(x: cursor.x + dx, y: cursor.y + dy)
                path.addCurve(to: end,
                              control1: CGPoint(x: cursor.x + dc1x, y: cursor.y + dc1y),
                              control2: CGPoint(x: cursor.x + dc2x, y: cursor.y + dc2y))
                cursor = end
            case "Z", "z":
                path.closeSubpath()
            default:
                return nil
            }
        }
        return path
    }

    private static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var i = s.startIndex
        let end = s.endIndex
        while i < end {
            let c = s[i]
            if c.isLetter {
                tokens.append(String(c))
                i = s.index(after: i)
            } else if c == "-" || c == "." || c.isNumber {
                var num = ""
                if c == "-" {
                    num.append(c)
                    i = s.index(after: i)
                }
                var sawDot = false
                while i < end {
                    let cc = s[i]
                    if cc.isNumber {
                        num.append(cc)
                        i = s.index(after: i)
                    } else if cc == "." && !sawDot {
                        num.append(cc)
                        sawDot = true
                        i = s.index(after: i)
                    } else {
                        break
                    }
                }
                if num == "-" || num == "." || num.isEmpty {
                    tokens.append(num)  // will fail Double() parse; caller returns nil
                } else {
                    tokens.append(num)
                }
            } else {
                i = s.index(after: i)
            }
        }
        return tokens
    }
}
