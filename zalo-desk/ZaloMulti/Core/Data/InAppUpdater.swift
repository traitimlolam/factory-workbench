// InAppUpdater.swift
// ZaloDesk

import Foundation
import AppKit

enum UpdateState: Equatable {
    case idle
    case checking
    case available(version: String, notes: String)
    case downloading(progress: Double)
    case extracting
    case installing
    case restarting
    case failed(message: String)
    case upToDate

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

@MainActor
final class InAppUpdater: ObservableObject {
    static let shared = InAppUpdater()
    
    @Published var state: UpdateState = .upToDate
    @Published var downloadProgress: Double = 0
    @Published var showUpdateSheet = false
    
    private init() {}
    
    func checkForUpdates(showUpToDatePrompt: Bool = false) {
        state = .upToDate
    }
}
