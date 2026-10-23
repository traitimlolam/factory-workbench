// ZaloMultiApp.swift
// ZaloMulti
//
// Entry point (@main) — khởi tạo app với CloneStore và window config.
// Auto-update kiểu Telegram: nhấn "Cập nhật" → tải + cài + khởi động lại.

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where !(window is NSPanel) {
                window.makeKeyAndOrderFront(self)
                return true
            }
        }
        return true
    }
}

@main
struct ZaloMultiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var updater = InAppUpdater.shared
    
    init() {
        // Security initialization
        AntiTamper.initialize()
        
        // Logger init
        DiagnosticLogger.info("APP", "Zalo Desk — khởi động")
        DiagnosticLogger.info("APP", "Log file: \(DiagnosticLogger.logFilePath)")
        
        // Pre-init singletons
        _ = CloneStore.shared
        _ = NotificationMonitor.shared
        
        let zaloInfo = ZaloCloneEngine().detectSourceZalo()
        DiagnosticLogger.info("APP", "Zalo Desktop: installed=\(zaloInfo.installed), version=\(zaloInfo.version ?? "N/A")")
    }
    
    var body: some Scene {
        WindowGroup("Zalo Desk") {
            ContentView()
                .frame(minWidth: 860, minHeight: 560)
                .onAppear {
                    // Migration: cleanup dữ liệu cũ
                    MigrationManager.shared.runMigrations()
                    MigrationManager.shared.cleanupOldVersionData()
                    
                    // Kiểm tra trạng thái hỗ trợ (delay để SwiftUI window sẵn sàng)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        DonateManager.checkAndPromptDonate()
                    }
                    
                    // Kiểm tra cập nhật ngầm (delay)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if SettingsManager.shared.settings.checkUpdateOnStartup {
                            DiagnosticLogger.info("APP", "Bắt đầu kiểm tra cập nhật...")
                            InAppUpdater.shared.checkForUpdates()
                        }
                    }
                }
                .onOpenURL { url in
                    DiagnosticLogger.info("URL", "Nhận URL: \(url.absoluteString)")
                    guard url.scheme == "zalodesk" else { return }
                    let host = url.host ?? ""
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    
                    if host == "add" || url.path.contains("add") {
                        let name = components?.queryItems?.first(where: { $0.name == "name" })?.value ?? "Nick Phụ 2"
                        let phone = components?.queryItems?.first(where: { $0.name == "phone" })?.value ?? ""
                        DiagnosticLogger.info("URL", "Kích hoạt addClone từ URL: name='\(name)', phone='\(phone)'")
                        CloneStore.shared.addClone(name: name, phone: phone)
                    } else if host == "open-add-sheet" {
                        SheetPresenter.presentAddClone(store: CloneStore.shared)
                    } else if host == "launch" {
                        if let indexStr = components?.queryItems?.first(where: { $0.name == "index" })?.value,
                           let index = Int(indexStr),
                           let clone = CloneStore.shared.clones.first(where: { $0.cloneIndex == index }) {
                            DiagnosticLogger.info("URL", "Launch clone index=\(index)")
                            CloneStore.shared.focusClone(clone)
                        }
                    }
                }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1060, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Thêm Clone Mới") {
                    DiagnosticLogger.info("UI", "Menu Tệp -> Thêm Clone Mới được chọn")
                    SheetPresenter.presentAddClone(store: CloneStore.shared)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Kiểm tra cập nhật...") {
                    InAppUpdater.shared.checkForUpdates(showUpToDatePrompt: true)
                    InAppUpdater.shared.showUpdateSheet = true
                }
            }
            CommandMenu("Clone") {
                Button("Dừng tất cả") {
                    CloneStore.shared.stopAllClones()
                }
                .keyboardShortcut("q", modifiers: [.command, .shift])
            }
        }
        
        Settings {
            SettingsView()
        }
    }
}
