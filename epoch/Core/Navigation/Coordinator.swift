//
//  Coordinator.swift
//  epoch
//
//  Created by devon jerothe on 10/7/26.
//

import SwiftUI

@MainActor
@Observable
final class Coordinator {
    enum Destination: Hashable {
        case newStory
        case storyView(UUID)
        case storySettings(UUID)
        case settings
    }

//    enum SheetType: Identifiable {}

    /// Single stack rooted at Stories; secondary areas like Settings are pushed from the nav bar.
    var path = NavigationPath()

    func push(_ destination: Destination) {
        path.append(destination)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path = NavigationPath()
    }
}
