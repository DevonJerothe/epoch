//
//  epochApp.swift
//  epoch
//
//  Created by devon jerothe on 9/11/26.
//

import SwiftUI

@main
struct epochApp: App {

    @State private var coordinator: Coordinator = .init()
    @State private var database = DBManager.shared
    @State private var theme = ThemeManager()
    @State private var errors = ErrorManager.shared
    @State private var aiConfiguration = AIConfigurationManager.shared

    var body: some Scene {
        WindowGroup {
            // A ZStack, not a Group: a Group would re-run the startup task each time the branch changes.
            ZStack {
                switch database.state {
                case .loading:
                    ProgressView()
                        .tint(theme.colors.inkSoft)
                        .accessibilityLabel("Opening your stories")
                case .failed(let error):
                    ContentUnavailableView {
                        Label("Database Unavailable", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(error.localizedDescription)
                    } actions: {
                        Button("Retry") {
                            Task { await database.start() }
                        }
                    }
                case .ready:
                    NavigationStack(path: $coordinator.path) {
                        Text("Stories View")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(theme.colors.paper)
                            .navigationTitle("Stories")
                            .navigationBarTitleDisplayMode(.large)
                            .toolbar {
                                ToolbarItemGroup(placement: .topBarTrailing) {
                                    Button("Settings", systemImage: "gearshape") {
                                        coordinator.push(.settings)
                                    }
                                    Button("New Story", systemImage: "plus") {
                                        coordinator.push(.newStory)
                                    }
                                    .tint(theme.colors.quill)
                                }
                            }
                            .navigationDestination(for: Coordinator.Destination.self) { destination in
                                destinationView(for: destination)
                            }
                    }
                    .environment(coordinator)
                    .environment(database)
                }
            }
            // Database-dependent content stays gated until startup finishes off the main actor.
            .task { await database.start() }
            .errorPresentation(errors, theme: theme) { coordinator.showSettings() }
            .environment(theme)
            .preferredColorScheme(theme.colorScheme)
            .tint(theme.colors.inkSoft)
            .foregroundStyle(theme.colors.ink)
            .epochTypography(.ui)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.paper)
            .toolbarBackground(theme.colors.paper, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func destinationView(for destination: Coordinator.Destination) -> some View {
        switch destination {
        case .newStory:
            Text("New Story")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.colors.paper)
        case .settings:
            SettingsView(configuration: aiConfiguration)
        case .storyView(let uUID):
            Text("story: \(uUID)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.colors.paper)
        case .storySettings(let uUID):
            Text("story settings: \(uUID)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.colors.paper)
        }
    }
}
