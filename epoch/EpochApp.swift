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

    var body: some Scene {
        WindowGroup {
            Group {
                if let error = database.startUpError {
                    ContentUnavailableView {
                        Label("Database Unavailable", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(error.localizedDescription)
                    } actions: {
                        Button("Retry") { database.setup() }
                    }
                } else {
                    NavigationStack(path: $coordinator.path) {
                        Text("Stories View")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(theme.colors.base)
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
            .environment(theme)
            .preferredColorScheme(theme.colorScheme)
            .tint(theme.colors.amber)
            .foregroundStyle(theme.colors.textPrimary)
            .epochTypography(.uiBody)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.base)
            .toolbarBackground(theme.colors.base, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func destinationView(for destination: Coordinator.Destination) -> some View {
        switch destination {
        case .newStory:
            Text("New Story")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.colors.base)
        case .settings:
            Text("Settings View")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.colors.base)
                .navigationTitle("Settings")
        case .storyView(let uUID):
            Text("story: \(uUID)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.colors.base)
        case .storySettings(let uUID):
            Text("story settings: \(uUID)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.colors.base)
        }
    }
}
