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
    
    var displayText: String {
        switch self {
        case .idle: return ""
        case .checking: return "Đang kiểm tra..."
        case .available(let v, _): return "Có bản cập nhật v\(v)"
        case .downloading(let p): return "Đang tải... \(Int(p * 100))%"
        case .extracting: return "Đang giải nén..."
        case .installing: return "Đang cài đặt..."
        case .restarting: return "Khởi động lại..."
        case .failed(let msg): return "Lỗi: \(msg)"
        case .upToDate: return "Đã là bản mới nhất"
        }
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
    
    func performUpdate() {}
    func cancelUpdate() {
        state = .idle
        showUpdateSheet = false
    }
    func dismiss() {
        state = .idle
        showUpdateSheet = false
    }
}
