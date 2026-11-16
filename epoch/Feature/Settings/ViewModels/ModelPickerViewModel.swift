import EpochLLM
import Foundation
import Observation

/// Loads a provider's models for one role and narrows them as the player searches.
@MainActor
@Observable
final class ModelPickerViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed(ErrorDescription)
    }

    let role: ModelRole
    @ObservationIgnored private let configuration: AIConfigurationManager
    @ObservationIgnored private let errors: ErrorManager

    private(set) var state: State = .loading
    private(set) var models: [LLMModelInfo] = []
    var query = ""
    @ObservationIgnored private var loadCount = 0

    init(role: ModelRole, configuration: AIConfigurationManager, errors: ErrorManager? = nil) {
        self.role = role
        self.configuration = configuration
        self.errors = errors ?? .shared
    }

    var providerName: String { configuration.providerName(for: role) }
    var selectedID: String { configuration.selectedModel(for: role) }

    /// True when a model is chosen that the provider's list does not contain, e.g. one that
    /// was retired or belongs to a previous key.
    var selectionIsUnlisted: Bool {
        state == .loaded && !selectedID.isEmpty && !models.contains { $0.id == selectedID }
    }

    /// Models matching every word of the search, in the provider's order.
    var results: [LLMModelInfo] {
        Self.filter(models, query: query)
    }

    nonisolated static func filter(_ models: [LLMModelInfo], query: String) -> [LLMModelInfo] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return models }
        return models.filter { model in
            let haystack = [model.id, model.name, model.owner, model.summary, model.aliasTarget]
                .compactMap { $0 }
                .joined(separator: " ")
            return terms.allSatisfy { haystack.localizedStandardContains($0) }
        }
    }

    func load(refresh: Bool = false) async {
        // The first load and a pull-to-refresh can overlap; only the newest may set the state.
        loadCount += 1
        let thisLoad = loadCount
        state = .loading
        do {
            let loaded = try await configuration.availableModels(for: role, refresh: refresh)
            guard thisLoad == loadCount else { return }
            models = loaded
            state = .loaded
        } catch {
            // The failure is shown in place of the list, so no banner is raised for it.
            errors.report(error, context: "Loading \(providerName) models", presentation: .logOnly)
            guard thisLoad == loadCount else { return }
            guard let description = errors.describe(error) else {
                // Cancelled: fall back to whatever was already on screen.
                state = .loaded
                return
            }
            models = []
            state = .failed(description)
        }
    }

    func select(_ model: LLMModelInfo) {
        configuration.selectModel(model.id, for: role)
    }
}

/// How a model's details read in a list row. Each provider reports different facts, so every
/// part is optional and a row shows only what its provider supplied.
nonisolated enum ModelDetails {
    /// "GPT-4" when the provider names the model, otherwise its ID.
    static func title(_ model: LLMModelInfo) -> String {
        model.name ?? model.id
    }

    /// The ID, when the title is not already the ID.
    static func identifier(_ model: LLMModelInfo) -> String? {
        model.name == nil || model.name == model.id ? nil : model.id
    }

    /// Facts joined on one line, e.g. "$3.00 in · $15.00 out per M tokens · 200K context".
    static func facts(_ model: LLMModelInfo, calendar: Calendar = .current) -> String? {
        var facts: [String] = []
        if let pricing = price(model.pricing) { facts.append(pricing) }
        if let context = model.contextLength { facts.append("\(tokens(context)) context") }
        if let owner = model.owner { facts.append(owner) }
        if let released = model.released {
            var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            facts.append(released.formatted(style.year().month(.abbreviated)))
        }
        if let target = model.aliasTarget { facts.append("points to \(target)") }
        return facts.isEmpty ? nil : facts.joined(separator: " · ")
    }

    static func price(_ pricing: LLMModelPricing?) -> String? {
        guard let pricing else { return nil }
        switch (pricing.inputPerMillionTokens, pricing.outputPerMillionTokens) {
        case (0?, 0?):
            return "Free"
        case (let input?, let output?):
            return "\(dollars(input)) in · \(dollars(output)) out per M tokens"
        case (let input?, nil):
            return "\(dollars(input)) in per M tokens"
        case (nil, let output?):
            return "\(dollars(output)) out per M tokens"
        case (nil, nil):
            return nil
        }
    }

    /// Small prices keep enough digits to tell them apart: $0.042, not $0.04.
    static func dollars(_ value: Double) -> String {
        let digits = value == 0 || value >= 1 ? 2 : (value >= 0.01 ? 3 : 4)
        return "$" + value.formatted(
            .number.precision(.fractionLength(2...digits)).locale(Locale(identifier: "en_US_POSIX"))
        )
    }

    static func tokens(_ count: Int) -> String {
        switch count {
        case 1_000_000...:
            let millions = Double(count) / 1_000_000
            return millions.formatted(
                .number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US_POSIX"))
            ) + "M"
        case 1_000...:
            return "\(Int((Double(count) / 1_000).rounded()))K"
        default:
            return String(count)
        }
    }
}
