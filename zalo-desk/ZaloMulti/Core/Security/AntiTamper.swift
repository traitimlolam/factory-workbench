// AntiTamper.swift
// ZaloDesk

import Foundation

enum AntiTamper {
    static var isDebuggerAttached: Bool { false }
    static func denyDebuggerAttach() {}
    static var isCodeSignatureValid: Bool { true }
    static var hasInjectedLibraries: Bool { false }
    static var hasSuspiciousEnvironment: Bool { false }
    static var hasAnalysisToolsRunning: Bool { false }
    static func performFullCheck() -> Bool { true }
    static func initialize() {}
}
