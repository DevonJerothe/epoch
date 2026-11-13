import EpochLLM
import SwiftUI

struct SettingsView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(Coordinator.self) private var coordinator
    @State private var viewModel: SettingsViewModel

    init(configuration: AIConfigurationManager) {
        _viewModel = State(initialValue: SettingsViewModel(configuration: configuration))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.xxl) {
                if viewModel.configuration.forcesFixtures {
                    helper("Fixtures are forced by a launch argument. The choices below are saved but not used in this run.")
                }
                narratorSection
                decisionSection
                illustratorSection
            }
            .padding(.horizontal, theme.spacing.pageMargin)
            .padding(.vertical, theme.spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.colors.paper)
        .navigationTitle("Settings")
        .task { await viewModel.load() }
        .confirmationDialog(
            "Remove this API key?",
            isPresented: Binding(
                get: { viewModel.pendingRemoval != nil },
                set: { isPresented in if !isPresented { viewModel.pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: viewModel.pendingRemoval
        ) { kind in
            Button("Remove \(kind.displayName) Key", role: .destructive) {
                Task { await viewModel.removeKey(for: kind) }
            }
        } message: { kind in
            Text("Epoch will delete the \(kind.displayName) key from this device's Keychain. You can add it again later.")
        }
    }

    private var narratorSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            eyebrow("Narrator")
            OptionWords(
                options: viewModel.configuration.availableTextProviders,
                selection: viewModel.textProvider, label: \.displayName,
                select: { viewModel.selectTextProvider($0) }
            )
            if viewModel.textProvider == .fixture {
                helper("Deterministic passages for development. No key is needed and no requests are sent.")
            } else {
                modelRow(.narrator, helper: "Epoch remembers a model for each provider, so switching does not lose it.")
                if let kind = viewModel.textProvider.credential {
                    credential(kind)
                }
            }
        }
    }

    private var decisionSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            eyebrow("Decisions")
            OptionWords(
                options: viewModel.configuration.availableDecisionProviders,
                selection: viewModel.decisionProvider, label: \.displayName,
                select: { viewModel.selectDecisionProvider($0) }
            )
            if viewModel.decisionProvider == .fixture {
                helper("Deterministic answers for development. No key is needed and no requests are sent.")
            } else {
                modelRow(.decisions, helper: "Judges intent, difficulty and outcomes. Its model is separate from the narrator's.")
                if let kind = viewModel.decisionProvider.credential {
                    if viewModel.decisionSharesNarratorKey {
                        helper("Uses the \(kind.displayName) key above.")
                    } else {
                        credential(kind)
                    }
                }
            }
        }
    }

    private var illustratorSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            eyebrow("Illustrator")
            OptionWords(
                options: viewModel.configuration.availableImageProviders,
                selection: viewModel.imageProvider, label: \.displayName,
                select: { viewModel.selectImageProvider($0) }
            )
            switch viewModel.imageProvider {
            case .off:
                helper("Stories are told without plates.")
            case .replicate:
                helper("Plates are drawn by \(ReplicateImageService.model).")
                credential(.replicate)
            case .fixture:
                helper("Flat sepia plates for development. No key is needed and no requests are sent.")
            }
        }
    }

    @ViewBuilder
    private func credential(_ kind: CredentialKind) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            if viewModel.isEditing(kind) {
                WritingLine {
                    SecureField(
                        "\(kind.displayName) API key",
                        text: Binding(
                            get: { viewModel.keyDrafts[kind] ?? "" },
                            set: { viewModel.keyDrafts[kind] = $0 }
                        )
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { Task { await viewModel.saveKey(for: kind) } }
                }
                HStack(spacing: theme.spacing.lg) {
                    // Quill once there is something to save; muted while there is not.
                    utilityButton(
                        viewModel.isSaving(kind) ? "Checking Key…" : "Save Key",
                        ink: viewModel.canSave(kind) ? theme.colors.quill : theme.colors.inkMuted
                    ) {
                        Task { await viewModel.saveKey(for: kind) }
                    }
                    .disabled(!viewModel.canSave(kind))
                    if viewModel.isStored(kind), !viewModel.isSaving(kind) {
                        utilityButton("Cancel") { viewModel.cancelReplacing(kind) }
                    }
                }
                helper(
                    viewModel.isStored(kind)
                        ? "Epoch checks the new key with \(kind.displayName), then replaces the one in the Keychain."
                        : "No key saved. Epoch checks it with \(kind.displayName), then keeps it in this device's Keychain."
                )
            } else {
                Text("\(kind.displayName) key saved in the Keychain.")
                    .epochTypography(.description)
                    .foregroundStyle(theme.colors.inkSoft)
                HStack(spacing: theme.spacing.lg) {
                    utilityButton("Replace") { viewModel.beginReplacing(kind) }
                    utilityButton("Remove") { viewModel.pendingRemoval = kind }
                }
            }
        }
    }

    /// The chosen model over a hairline; tapping opens the provider's list. Choosing is quill
    /// while it still waits on the reader.
    private func modelRow(_ role: ModelRole, helper text: String) -> some View {
        let model = viewModel.selectedModel(for: role)
        return VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Button {
                coordinator.push(.modelPicker(role))
            } label: {
                WritingLine {
                    HStack(spacing: theme.spacing.xs) {
                        Text(model.isEmpty ? "Choose a model" : model)
                            .foregroundStyle(model.isEmpty ? theme.colors.quill : theme.colors.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: theme.spacing.xs)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(theme.colors.inkMuted)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isEmpty ? "Choose a model" : "Model, \(model)")
            .accessibilityHint("Shows the models \(viewModel.configuration.providerName(for: role)) offers")
            helper(text)
        }
    }

    private func eyebrow(_ title: String) -> some View {
        Text(title)
            .epochTypography(.eyebrow)
            .foregroundStyle(theme.colors.inkMuted)
            .accessibilityAddTraits(.isHeader)
    }

    private func helper(_ text: String) -> some View {
        Text(text)
            .epochTypography(.caption)
            .foregroundStyle(theme.colors.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func utilityButton(_ title: String, ink: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .epochTypography(.ui)
            // The app root sets a foreground style, which wins over tint for button labels.
            .foregroundStyle(ink ?? theme.colors.inkSoft)
            .frame(minHeight: theme.sizes.minimumTapTarget)
    }
}

/// A filter row from DESIGN.md: sans words, the current one marked by weight, no segmented track.
private struct OptionWords<Option: Identifiable & Equatable>: View {
    @Environment(ThemeManager.self) private var theme
    let options: [Option]
    let selection: Option
    let label: KeyPath<Option, String>
    let select: (Option) -> Void

    var body: some View {
        HStack(spacing: theme.spacing.lg) {
            ForEach(options) { option in
                let isCurrent = option == selection
                Button(option[keyPath: label]) { select(option) }
                    .epochTypography(.ui)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? theme.colors.ink : theme.colors.inkMuted)
                    .frame(minHeight: theme.sizes.minimumTapTarget)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
    }
}

/// A text field set over a hairline, like the composer's writing line.
private struct WritingLine<Field: View>: View {
    @Environment(ThemeManager.self) private var theme
    @ViewBuilder let field: () -> Field

    var body: some View {
        VStack(spacing: theme.spacing.xs) {
            field()
                .epochTypography(.description)
                .foregroundStyle(theme.colors.ink)
                .frame(minHeight: theme.sizes.minimumTapTarget, alignment: .bottom)
            Rectangle()
                .fill(theme.colors.rule)
                .frame(height: theme.sizes.hairline)
        }
    }
}
