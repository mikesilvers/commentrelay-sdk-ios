// Sources/CommentRelayUI/Screens/FeedbackFormView.swift
import SwiftUI
import CommentRelayCore

public struct FeedbackFormView: View {
    @State public var viewModel: FeedbackFormViewModel
    /// CRLBS-132: free-tier attribution to render under the submit button.
    public let attribution: CommentRelayAttribution
    // Not @Sendable: main-actor SwiftUI action closure — mutates main-actor state.
    public let onSubmit: (CommentRelaySubmission) -> Void

    public init(viewModel: FeedbackFormViewModel,
                attribution: CommentRelayAttribution = .hidden,
                onSubmit: @escaping (CommentRelaySubmission) -> Void) {
        self._viewModel = State(initialValue: viewModel)
        self.attribution = attribution
        self.onSubmit = onSubmit
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // CRLBS-129: render the title in-content so it wraps to multiple
                // lines. A large navigationTitle is single-line and truncates.
                Text(viewModel.form.title)
                    .font(.largeTitle).bold()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                if let prompt = viewModel.form.moreFeedbackPrompt {
                    Text(prompt).font(.callout).foregroundStyle(.secondary)
                }

                ForEach(visibleFields(in: viewModel.form.fields, boolValues: viewModel.boolValues), id: \.field.id) { item in
                    renderer(for: item.field)
                        .padding(.leading, CGFloat(item.depth) * 12)
                }

                Button(Strings.formSubmit) {
                    onSubmit(viewModel.buildSubmission())
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!viewModel.isSubmittable)

                PoweredByFooter(attribution: attribution)
            }
            .padding()
        }
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
