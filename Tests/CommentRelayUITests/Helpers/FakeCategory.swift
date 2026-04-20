// Tests/CommentRelayUITests/Helpers/FakeCategory.swift
import Foundation
import CommentRelayCore

enum FakeField {
    static func textbox(id: String = "f1", label: String = "Describe the issue", required: Bool = true) -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"textbox","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":null}"#)
    }
    static func email(id: String = "fe", label: String = "Email", required: Bool = true) -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"email","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":null}"#)
    }
    static func phone(id: String = "fp", label: String = "Phone", required: Bool = false) -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"phone","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":null}"#)
    }
    static func numeric(id: String = "fn", label: String = "Rating", required: Bool = false) -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"numeric","label":"\#(label)","is_required":\#(required),"is_gate":false,"sort_order":1,"max_files":null}"#)
    }
    static func trueFalse(id: String = "ft", label: String = "Reproducible?") -> CommentRelayField {
        decode(#"{"id":"\#(id)","field_type":"true_false","label":"\#(label)","is_required":false,"is_gate":false,"sort_order":1,"max_files":null}"#)
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

    private static func decode(_ raw: String) -> CommentRelayField {
        try! JSONDecoder().decode(CommentRelayField.self, from: Data(raw.utf8))
    }
}
