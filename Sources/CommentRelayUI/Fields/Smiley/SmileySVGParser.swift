// Sources/CommentRelayUI/Fields/Smiley/SmileySVGParser.swift
import Foundation

/// Parsed representation of one of the five smiley SVGs served by the
/// CommentRelay API. Only the narrow shape family used by the API is
/// supported — see `commentrelay-api/src/config/smiley-svgs.ts`.
///
/// Any deviation (malformed XML, missing expected elements, unsupported
/// mouth path) yields `nil` so the caller can fall back to a plain coloured
/// circle rather than render a partial smiley.
struct ParsedSmiley: Equatable {
    let faceFillHex: String
    let faceStrokeHex: String
    let featureHex: String
    let mouth: Mouth

    enum Mouth: Equatable {
        case path(d: String)
        case line(x1: Double, y1: Double, x2: Double, y2: Double)
    }
}

enum SmileySVGParser {
    static func parse(svg: String) -> ParsedSmiley? {
        guard !svg.isEmpty, let data = svg.data(using: .utf8) else { return nil }

        let collector = ElementCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        guard parser.parse() else { return nil }

        // Face: first circle with r=10
        guard let face = collector.circles.first(where: { attr($0, "r") == "10" }),
              let faceFill = attr(face, "fill"),
              let faceStroke = attr(face, "stroke")
        else { return nil }

        // Eyes: expect two circles with r=1.5 sharing the same fill
        let eyes = collector.circles.filter { attr($0, "r") == "1.5" }
        guard eyes.count == 2,
              let eyeFill = attr(eyes[0], "fill"),
              attr(eyes[1], "fill") == eyeFill
        else { return nil }

        // Mouth: either a <path d=...> or a <line x1 y1 x2 y2>
        let mouth: ParsedSmiley.Mouth
        if let pathEl = collector.paths.first, let d = attr(pathEl, "d") {
            // Validate we can actually render the path.
            guard SmileyPathParser.parse(d: d) != nil else { return nil }
            mouth = .path(d: d)
        } else if let lineEl = collector.lines.first,
                  let x1 = attr(lineEl, "x1").flatMap(Double.init),
                  let y1 = attr(lineEl, "y1").flatMap(Double.init),
                  let x2 = attr(lineEl, "x2").flatMap(Double.init),
                  let y2 = attr(lineEl, "y2").flatMap(Double.init) {
            mouth = .line(x1: x1, y1: y1, x2: x2, y2: y2)
        } else {
            return nil
        }

        return ParsedSmiley(
            faceFillHex: faceFill,
            faceStrokeHex: faceStroke,
            featureHex: eyeFill,
            mouth: mouth
        )
    }

    private static func attr(_ dict: [String: String], _ key: String) -> String? {
        dict[key]
    }
}

private final class ElementCollector: NSObject, XMLParserDelegate {
    var circles: [[String: String]] = []
    var paths: [[String: String]] = []
    var lines: [[String: String]] = []

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        switch elementName {
        case "circle": circles.append(attributeDict)
        case "path": paths.append(attributeDict)
        case "line": lines.append(attributeDict)
        default: break
        }
    }
}
