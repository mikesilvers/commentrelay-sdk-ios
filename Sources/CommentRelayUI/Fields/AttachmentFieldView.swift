// Sources/CommentRelayUI/Fields/AttachmentFieldView.swift
import SwiftUI
import UniformTypeIdentifiers
import CommentRelayCore

public struct AttachmentFieldView: FieldRenderer {
    public let field: CommentRelayField
    @Binding public var attachments: [PhotoAttachment]
    @State private var isImporterPresented: Bool = false

    public init(field: CommentRelayField, attachments: Binding<[PhotoAttachment]>) {
        self.field = field
        self._attachments = attachments
    }

    public var isValueAcceptable: Bool {
        field.isRequired ? !attachments.isEmpty : true
    }

    private var maxFiles: Int { field.maxFiles ?? 3 }
    private let allowedTypes: [UTType] = [.pdf, .plainText]

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(field: field)

            ForEach(attachments) { att in
                AttachmentRow(attachment: att) {
                    attachments.removeAll { $0.id == att.id }
                }
            }

            if attachments.count < maxFiles {
                Button {
                    isImporterPresented = true
                } label: {
                    Label(Strings.attachmentAdd, systemImage: "paperclip")
                }
                .buttonStyle(.bordered)
                .fileImporter(isPresented: $isImporterPresented,
                              allowedContentTypes: allowedTypes,
                              allowsMultipleSelection: true) { result in
                    if case .success(let urls) = result { ingest(urls) }
                }
            }
        }
    }

    private func ingest(_ urls: [URL]) {
        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            attachments.append(PhotoAttachment(name: url.lastPathComponent, mimeType: mime, size: data.count, data: data))
        }
    }
}

private struct AttachmentRow: View {
    let attachment: PhotoAttachment
    let onRemove: @Sendable () -> Void

    var body: some View {
        HStack {
            Image(systemName: "doc.fill")
            Text(attachment.name).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.photoRemove)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }
}
