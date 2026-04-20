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

    private static func decode(_ raw: String) -> CommentRelayField {
        try! JSONDecoder().decode(CommentRelayField.self, from: Data(raw.utf8))
    }
}
