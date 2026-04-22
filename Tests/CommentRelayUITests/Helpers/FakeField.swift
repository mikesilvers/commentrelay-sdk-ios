// Tests/CommentRelayUITests/Helpers/FakeCategory.swift
import Foundation
import CommentRelayCore

enum FakeField {
    static func textbox(id: String = "f1", label: String = "Describe the issue", required: Bool = true, sortOrder: Int = 1, parentId: String? = nil) -> CommentRelayField {
        let parent = parentId.map { ",\"parent_field_id\":\"\($0)\"" } ?? ""
        return decode(#"{"id":"\#(id)","field_type":"textbox","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":\#(sortOrder),"max_files":null\#(parent)}"#)
    }
    static func email(id: String = "fe", label: String = "Email", required: Bool = true, sortOrder: Int = 1, parentId: String? = nil) -> CommentRelayField {
        let parent = parentId.map { ",\"parent_field_id\":\"\($0)\"" } ?? ""
        return decode(#"{"id":"\#(id)","field_type":"email","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":\#(sortOrder),"max_files":null\#(parent)}"#)
    }
    static func phone(id: String = "fp", label: String = "Phone", required: Bool = false) -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"phone","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":null}"#)
    }
    static func numeric(id: String = "fn", label: String = "Rating", required: Bool = false) -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"numeric","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":null}"#)
    }
    static func trueFalse(id: String = "ft", label: String = "Reproducible?", sortOrder: Int = 1, parentId: String? = nil) -> CommentRelayField {
        let parent = parentId.map { ",\"parent_field_id\":\"\($0)\"" } ?? ""
        return decode(#"{"id":"\#(id)","field_type":"true_false","label":"\#(label)","is_required":false,"is_gate":false,"sort_order":\#(sortOrder),"max_files":null\#(parent)}"#)
    }
    static func informational(id: String = "fi", label: String = "This is informational copy.") -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"informational","label":"\#(label)","is_required":false,"is_gate":false,"sort_order":1,"max_files":null}"#)
    }

    static func smileyRating(id: String = "fs", label: String = "How do you feel?", required: Bool = false) -> CommentRelayField {
        let raw = #"""
        {"id":"\#(id)","field_type":"smiley_rating","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":null,
          "options":[
            {"position":1,"label":"very_unhappy","svg":"<svg/>"},
            {"position":2,"label":"unhappy","svg":"<svg/>"},
            {"position":3,"label":"neutral","svg":"<svg/>"},
            {"position":4,"label":"happy","svg":"<svg/>"},
            {"position":5,"label":"very_happy","svg":"<svg/>"}
          ]
        }
        """#
        return decode(raw)
    }

    static func smileyRatingNoOptions(id: String = "fs", label: String = "How do you feel?") -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"smiley_rating","label":"\#(label)","is_required":false,"is_gate":false,"sort_order":1,"max_files":null}"#)
    }

    static func smileyRatingWithRealSVG(id: String = "fs", label: String = "How do you feel?") -> CommentRelayField {
        // Uses the verbatim SVGs the API actually serves.
        let opts = zip(1...5, SmileySVGFixtures.all).map { (pos, svg) -> String in
            let escaped = svg.replacingOccurrences(of: "\"", with: "\\\"")
            let posLabel = ["very_unhappy","unhappy","neutral","happy","very_happy"][pos - 1]
            return #"{"position":\#(pos),"label":"\#(posLabel)","svg":"\#(escaped)"}"#
        }.joined(separator: ",")
        let raw = #"""
        {"id":"\#(id)","field_type":"smiley_rating","label":"\#(label)","is_required":false,"is_gate":false,"sort_order":1,"max_files":null,
          "options":[\#(opts)]
        }
        """#
        return decode(raw)
    }

    static func colorScale(id: String = "fc", label: String = "Rate the color", required: Bool = false) -> CommentRelayField {
        var opts = ""
        for i in 1...10 {
            let r = 255 - (i * 25)
            let g = i * 25
            let hex = String(format: "#%02X%02X00", max(0, r), min(255, g))
            opts += #"{"position":\#(i),"color":"\#(hex)","label":null}"#
            if i != 10 { opts += "," }
        }
        let raw = #"""
        {"id":"\#(id)","field_type":"color_scale","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":null,
          "options":[\#(opts)]
        }
        """#
        return decode(raw)
    }

    static func photo(id: String = "fph", label: String = "Screenshot", maxFiles: Int = 3, required: Bool = false) -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"photo","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":\#(maxFiles)}"#)
    }

    static func attachment(id: String = "fa", label: String = "File", maxFiles: Int = 3, required: Bool = false) -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"attachment","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":\#(maxFiles)}"#)
    }

    private static func decode(_ raw: String) -> CommentRelayField {
        try! JSONDecoder().decode(CommentRelayField.self, from: Data(raw.utf8))
    }
}
