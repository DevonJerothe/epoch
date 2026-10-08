//
//  Coordinator.swift
//  epoch
//
//  Created by devon jerothe on 10/7/26.
//

import SwiftUI

@Observable
class Coordinator {
    enum Tab {
        case stories
        case settings
    }
    
    enum Destination: Hashable {
        case storyView(UUID)
        case storySettings(UUID)
    }
    
//    enum SheetType: Identifiable {}
    
    var currentTab: Tab = .stories
    
    var storiesPath = NavigationPath()
    var settingsPath = NavigationPath()
    
    private func getCurrentPath() -> NavigationPath {
        switch currentTab {
        case .stories:
            return self.storiesPath
        case .settings:
            return self.settingsPath
        }
    }
}
