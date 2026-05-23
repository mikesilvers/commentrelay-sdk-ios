// Sources/CommentRelayUI/Fields/PhotoFieldView.swift
import SwiftUI
import PhotosUI
import CommentRelayCore

public struct PhotoAttachment: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var mimeType: String
    public var size: Int
    public var data: Data

    public init(id: UUID = UUID(), name: String, mimeType: String, size: Int, data: Data) {
        self.id = id; self.name = name; self.mimeType = mimeType; self.size = size; self.data = data
    }
}

public struct PhotoFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var attachments: [PhotoAttachment]
    @State private var pickerSelection: [PhotosPickerItem] = []

    public init(field: CommentRelayField, attachments: Binding<[PhotoAttachment]>) {
        self.field = field
        self._attachments = attachments
    }

    public var isValueAcceptable: Bool {
        field.isRequired ? !attachments.isEmpty : true
    }

    private var maxFiles: Int { field.maxFiles ?? 3 }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(field: field)

            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { att in
                            PhotoThumbnail(attachment: att) {
                                attachments.removeAll { $0.id == att.id }
                            }
                        }
                    }
                }
            }

            if attachments.count < maxFiles {
                PhotosPicker(selection: $pickerSelection,
                             maxSelectionCount: maxFiles - attachments.count,
                             matching: .images) {
                    Label(Strings.photoAdd, systemImage: "photo.badge.plus")
                }
                .onChange(of: pickerSelection) { _, new in
                    Task { await ingest(new) }
                }
            }
        }
    }

    @MainActor
    private func ingest(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let mime = "image/png"  // v1: no magic-byte inspection
            let name = "photo-\(UUID().uuidString.prefix(8)).png"
            attachments.append(PhotoAttachment(name: name, mimeType: mime, size: data.count, data: data))
        }
        pickerSelection = []
    }
}

private struct PhotoThumbnail: View {
    let attachment: PhotoAttachment
    // Not @Sendable: this is a SwiftUI Button action — it runs on the main
    // actor and mutates the main-actor `@Binding attachments`. Marking it
    // @Sendable wrongly forbids that and emits a strict-concurrency warning.
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnail
        }
        .frame(width: 64, height: 64)
        .clipped()
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.photoRemove)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        #if canImport(UIKit)
        if let img = UIImage(data: attachment.data) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            Color.gray
        }
        #else
        Color.gray
        #endif
    }
}
