// Sources/CommentRelayUI/Shared/Color+Hex.swift
import SwiftUI

extension Color {
    /// Parses `#RRGGBB` or `#RRGGBBAA`. Returns `.gray` on malformed input.
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespaces).trimmingPrefix("#")
        var value: UInt64 = 0
        Scanner(string: String(trimmed)).scanHexInt64(&value)
        let length = trimmed.count
        let r, g, b, a: Double
        switch length {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            self = .gray
            return
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
