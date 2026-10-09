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
                    TabView(selection: $coordinator.currentTab) {
                        NavigationStack(path: $coordinator.storiesPath) {
                            Text("Stories View")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(theme.colors.base)
                                .navigationDestination(for: Coordinator.Destination.self) { destination in
                                    destinationView(for: destination)
                                }
                        }.tabItem {
                            Image(systemName: "message")
                            Text("Stories")
                        }
                        .tag(Coordinator.Tab.stories)

                        // Settings
                        NavigationStack(path: $coordinator.settingsPath) {
                            Text("Settings View")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(theme.colors.base)
                                .navigationDestination(for: Coordinator.Destination.self) { destination in
                                    destinationView(for: destination)
                                }
                        }.tabItem {
                            Image(systemName: "gearshape")
                            Text("Settings")
                        }
                    }
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
            .toolbarBackground(theme.colors.base, for: .navigationBar, .tabBar)
        }
    }

    @ViewBuilder
    private func destinationView(for destination: Coordinator.Destination) -> some View {
        switch destination {
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
