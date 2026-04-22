// Sources/CommentRelayUI/Fields/Smiley/SmileyContent.swift
import CommentRelayCore

/// Decides how a single smiley button at `position` should render.
/// Either the API's SVG parsed successfully, or we fall back to a plain
/// position-coloured circle. No partial states.
enum SmileyContent: Equatable {
    case parsed(ParsedSmiley)
    case fallback(position: Int)

    static func resolve(position: Int, options: [FieldOption]?) -> SmileyContent {
        guard let svg = options?.first(where: { $0.position == position })?.svg,
              let parsed = SmileySVGParser.parse(svg: svg) else {
            return .fallback(position: position)
        }
        return .parsed(parsed)
    }
}
