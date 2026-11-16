import EpochLLM
import SwiftUI

/// A searchable list of the models a provider offers for one role. Rows are things the reader
/// can act on, so hairlines separate them.
struct ModelPickerView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(Coordinator.self) private var coordinator
    @State private var viewModel: ModelPickerViewModel

    init(role: ModelRole, configuration: AIConfigurationManager) {
        _viewModel = State(initialValue: ModelPickerViewModel(role: role, configuration: configuration))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch viewModel.state {
                case .loading:
                    loading
                case .failed(let failure):
                    failed(failure)
                case .loaded:
                    loaded
                }
            }
            .padding(.horizontal, theme.spacing.pageMargin)
            .padding(.vertical, theme.spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.colors.paper)
        .navigationTitle(viewModel.role == .narrator ? "Narrator Model" : "Decision Model")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.query, prompt: "Search \(viewModel.providerName) models")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .refreshable { await viewModel.load(refresh: true) }
        .task { await viewModel.load() }
    }

    private var loading: some View {
        HStack(spacing: theme.spacing.sm) {
            ProgressView()
                .tint(theme.colors.inkSoft)
            note("Asking \(viewModel.providerName) for its models")
        }
        .frame(minHeight: theme.sizes.minimumTapTarget)
    }

    private func failed(_ failure: ErrorDescription) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.xs) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(theme.colors.rubric)
                    .accessibilityHidden(true)
                Text(failure.title)
                    .epochTypography(.ui)
                    .foregroundStyle(theme.colors.ink)
            }
            Text(failure.message)
                .epochTypography(.description)
                .foregroundStyle(theme.colors.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: theme.spacing.lg) {
                if failure.recovery == .openSettings {
                    // Settings is the screen beneath this one.
                    action("Back to Settings") { coordinator.pop() }
                } else {
                    action("Try Again") { Task { await viewModel.load(refresh: true) } }
                }
            }
        }
    }

    @ViewBuilder
    private var loaded: some View {
        if viewModel.selectionIsUnlisted {
            note("\(viewModel.selectedID) is selected, but \(viewModel.providerName) does not list it for this key.")
                .padding(.bottom, theme.spacing.sm)
        }
        let results = viewModel.results
        if results.isEmpty {
            note(
                viewModel.models.isEmpty
                    ? "\(viewModel.providerName) lists no models for this key."
                    : "No models match \u{201C}\(viewModel.query)\u{201D}."
            )
        } else {
            note("\(results.count) of \(viewModel.models.count) models")
                .padding(.bottom, theme.spacing.xs)
            ForEach(results) { model in
                ModelRow(model: model, isSelected: model.id == viewModel.selectedID) {
                    viewModel.select(model)
                    coordinator.pop()
                }
                Rectangle()
                    .fill(theme.colors.rule)
                    .frame(height: theme.sizes.hairline)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .epochTypography(.caption)
            .foregroundStyle(theme.colors.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(title, action: perform)
            .epochTypography(.ui)
            .foregroundStyle(theme.colors.quill)
            .frame(minHeight: theme.sizes.minimumTapTarget)
    }
}

/// One model: its name, then whatever its provider reports about it. Only a retirement date
/// takes a meaning ink.
private struct ModelRow: View {
    @Environment(ThemeManager.self) private var theme
    let model: LLMModelInfo
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
                VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                    Text(ModelDetails.title(model))
                        .epochTypography(.ui)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(theme.colors.ink)
                    if let identifier = ModelDetails.identifier(model) {
                        Text(identifier)
                            .epochTypography(.ui)
                            .foregroundStyle(theme.colors.inkMuted)
                    }
                    if let facts = ModelDetails.facts(model) {
                        Text(facts)
                            .epochTypography(.ui)
                            .foregroundStyle(theme.colors.inkSoft)
                    }
                    if let retirement = model.retirementDate {
                        Text("Retires \(retirement)")
                            .epochTypography(.ui)
                            .foregroundStyle(theme.colors.rubric)
                    }
                    if let summary = model.summary, !summary.isEmpty {
                        Text(summary)
                            .epochTypography(.caption)
                            .foregroundStyle(theme.colors.inkMuted)
                            .lineLimit(3)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: theme.spacing.xs)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.colors.quill)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, theme.spacing.sm)
            .frame(maxWidth: .infinity, minHeight: theme.sizes.minimumTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
