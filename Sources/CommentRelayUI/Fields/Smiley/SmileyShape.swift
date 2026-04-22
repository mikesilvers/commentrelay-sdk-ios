// Sources/CommentRelayUI/Fields/Smiley/SmileyShape.swift
import SwiftUI

/// Renders a `ParsedSmiley` inside a square `size × size` frame, mirroring
/// the API's 24×24 viewBox. Everything scales linearly from that viewBox
/// into the requested size.
struct SmileyShape: View {
    let parsed: ParsedSmiley
    let size: CGFloat

    private var unit: CGFloat { size / 24 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Face: cx=12 cy=12 r=10 → box (2,2) size 20×20
            Circle()
                .fill(Color(hex: parsed.faceFillHex))
                .overlay(
                    Circle().strokeBorder(
                        Color(hex: parsed.faceStrokeHex),
                        lineWidth: unit
                    )
                )
                .frame(width: 20 * unit, height: 20 * unit)
                .offset(x: 2 * unit, y: 2 * unit)

            // Left eye: cx=8.5 cy=9.5 r=1.5 → box (7,8) size 3×3
            Circle()
                .fill(Color(hex: parsed.featureHex))
                .frame(width: 3 * unit, height: 3 * unit)
                .offset(x: 7 * unit, y: 8 * unit)

            // Right eye: cx=15.5 cy=9.5 → box (14,8) size 3×3
            Circle()
                .fill(Color(hex: parsed.featureHex))
                .frame(width: 3 * unit, height: 3 * unit)
                .offset(x: 14 * unit, y: 8 * unit)

            // Mouth: path or line in the 0..24 viewBox
            MouthShape(mouth: parsed.mouth)
                .stroke(
                    Color(hex: parsed.featureHex),
                    style: StrokeStyle(lineWidth: 1.5 * unit, lineCap: .round)
                )
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}

private struct MouthShape: Shape {
    let mouth: ParsedSmiley.Mouth

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24
        let sy = rect.height / 24
        switch mouth {
        case .line(let x1, let y1, let x2, let y2):
            var p = Path()
            p.move(to: CGPoint(x: x1 * sx, y: y1 * sy))
            p.addLine(to: CGPoint(x: x2 * sx, y: y2 * sy))
            return p
        case .path(let d):
            guard let parsed = SmileyPathParser.parse(d: d) else { return Path() }
            return parsed.applying(CGAffineTransform(scaleX: sx, y: sy))
        }
    }
}
