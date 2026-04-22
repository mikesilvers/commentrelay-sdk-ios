// Sources/CommentRelayUI/Screens/FeedbackFormView.swift
import SwiftUI
import CommentRelayCore

public struct FeedbackFormView: View {
    @State public var viewModel: FeedbackFormViewModel
    public let onSubmit: @Sendable (CommentRelaySubmission) -> Void

    public init(viewModel: FeedbackFormViewModel, onSubmit: @escaping @Sendable (CommentRelaySubmission) -> Void) {
        self._viewModel = State(initialValue: viewModel)
        self.onSubmit = onSubmit
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let prompt = viewModel.category.moreFeedbackPrompt {
                    Text(prompt).font(.callout).foregroundStyle(.secondary)
                }

                ForEach(visibleFields(in: viewModel.category.fields, boolValues: viewModel.boolValues), id: \.field.id) { item in
                    renderer(for: item.field)
                        .padding(.leading, CGFloat(item.depth) * 12)
                }

                Button(Strings.formSubmit) {
                    onSubmit(viewModel.buildSubmission())
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!viewModel.isSubmittable)
            }
            .padding()
        }
        .navigationTitle(viewModel.category.title)
    }

    @ViewBuilder
    private func renderer(for field: CommentRelayField) -> some View {
        switch field.fieldType {
        case .textbox:
            TextboxFieldView(field: field, value: textBinding(field.id))
        case .email:
            EmailFieldView(field: field, value: textBinding(field.id))
        case .phone:
            PhoneFieldView(field: field, value: textBinding(field.id))
        case .numeric:
            NumericFieldView(field: field, value: textBinding(field.id))
        case .trueFalse:
            TrueFalseFieldView(field: field, value: boolBinding(field.id))
        case .informational:
            InformationalFieldView(field: field)
        case .smileyRating:
            SmileyRatingFieldView(field: field, selectedPosition: intBinding(field.id))
        case .colorScale:
            ColorScaleFieldView(field: field, selectedPosition: intBinding(field.id))
        case .photo:
            PhotoFieldView(field: field, attachments: photoBinding(field.id))
        case .attachment:
            AttachmentFieldView(field: field, attachments: photoBinding(field.id))
        case .unknown:
            EmptyView()
        }
    }

    // MARK: - Binding helpers

    private func textBinding(_ id: String) -> Binding<String> {
        Binding(get: { viewModel.textValues[id] ?? "" }, set: { viewModel.setText(id, $0) })
    }

    private func boolBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { viewModel.boolValues[id] ?? false }, set: { viewModel.setBool(id, $0) })
    }

    private func intBinding(_ id: String) -> Binding<Int?> {
        Binding(get: { viewModel.intValues[id] }, set: { viewModel.setInt(id, $0) })
    }

    private func photoBinding(_ id: String) -> Binding<[PhotoAttachment]> {
        Binding(get: { viewModel.photoValues[id] ?? [] }, set: { viewModel.setPhotos(id, $0) })
    }
}
