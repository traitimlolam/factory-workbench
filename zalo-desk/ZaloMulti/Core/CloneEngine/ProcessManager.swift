// ProcessManager.swift
// ZaloMulti

import Foundation
import AppKit
import Combine

@MainActor
final class ProcessManager: ObservableObject {
    @Published var runningProcesses: [UUID: Int32] = [:]
    
    init() {
        DiagnosticLogger.info("PROCESS", "ProcessManager khởi tạo")
    }
    
    @discardableResult
    func launchClone(_ clone: CloneAccount) throws -> Int32 {
        DiagnosticLogger.info("LAUNCH", "Bắt đầu launch clone '\(clone.name)' (index=\(clone.cloneIndex))")
        
        let appURL = URL(fileURLWithPath: clone.appPath)
        guard FileManager.default.fileExists(atPath: clone.appPath) else {
            throw CloneError.zaloNotFound
        }
        
        if let existingPID = runningProcesses[clone.id], Self.isRunning(pid: existingPID) {
            Self.focusClone(pid: existingPID, bundleID: clone.bundleID)
            return existingPID
        }
        
        // Đảm bảo các thư mục data biệt lập tồn tại
        let fm = FileManager.default
        let cloneZaloData = "\(clone.dataPath)/ZaloData"
        try? fm.createDirectory(atPath: cloneZaloData, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: "\(clone.dataPath)/Library/Application Support", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: "\(clone.dataPath)/tmp", withIntermediateDirectories: true)
        
        // Khởi chạy app bundle chuẩn macOS bằng NSWorkspace (kích hoạt wrapper script và export HOME an toàn)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.addsToRecentItems = false
        
        var launchedPID: pid_t = 0
        let semaphore = DispatchSemaphore(value: 0)
        
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, error in
            if let app = app {
                launchedPID = app.processIdentifier
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 4.0)
        
        if launchedPID > 0 {
            runningProcesses[clone.id] = launchedPID
            DiagnosticLogger.success("LAUNCH", "✅ Đã launch clone '\(clone.name)' với PID=\(launchedPID)")
            return launchedPID
        } else {
            // Fallback: dò qua bundleID
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: clone.bundleID).first {
                runningProcesses[clone.id] = running.processIdentifier
                return running.processIdentifier
            }
            throw CloneError.launchFailed("Không thể khởi chạy ứng dụng clone")
        }
    }
    
    func stopClone(_ clone: CloneAccount) {
        DiagnosticLogger.info("STOP", "Dừng clone '\(clone.name)' — graceful quit")
        
        let cloneId = clone.id
        let cloneIndex = clone.cloneIndex
        let appName = "ZaloClone\(clone.cloneIndex).app"
        let pid = runningProcesses[clone.id]
        
        // Step 1: Gửi Apple Event quit (graceful — cho Zalo thời gian lưu session)
        let bundleID = clone.bundleID
        let script = "tell application id \"\(bundleID)\" to quit"
        let appleScript = Process()
        appleScript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        appleScript.arguments = ["-e", script]
        appleScript.standardOutput = FileHandle.nullDevice
        appleScript.standardError = FileHandle.nullDevice
        try? appleScript.run()
        
        // Step 2: Chờ tối đa 5 giây cho Zalo tự thoát (flush session data)
        Task {
            for i in 0..<10 {
                try? await Task.sleep(for: .milliseconds(500))
                let stillRunning: Bool
                if let p = pid {
                    stillRunning = Self.isRunning(pid: p)
                } else {
                    stillRunning = Self.checkCloneRunning(cloneIndex: cloneIndex, knownPID: nil)
                }
                if !stillRunning {
                    DiagnosticLogger.success("STOP", "Clone '\(clone.name)' tự thoát sau \(Double(i+1)*0.5)s")
                    self.runningProcesses.removeValue(forKey: cloneId)
                    return
                }
            }
            
            // Step 3: Sau 5s vẫn chạy → SIGTERM
            DiagnosticLogger.warning("STOP", "Clone '\(clone.name)' chưa thoát sau 5s → SIGTERM")
            if let p = pid, Self.isRunning(pid: p) {
                kill(p, SIGTERM)
            }
            let termProc = Process()
            termProc.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            termProc.arguments = ["-f", appName]
            termProc.standardOutput = FileHandle.nullDevice
            termProc.standardError = FileHandle.nullDevice
            try? termProc.run()
            termProc.waitUntilExit()
            
            // Chờ thêm 3s cho SIGTERM
            try? await Task.sleep(for: .seconds(3))
            
            // Step 4: Force kill nếu vẫn còn
            if Self.checkCloneRunning(cloneIndex: cloneIndex, knownPID: nil) {
                DiagnosticLogger.warning("STOP", "Clone '\(clone.name)' vẫn chạy → SIGKILL")
                let forceKill = Process()
                forceKill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                forceKill.arguments = ["-9", "-f", appName]
                forceKill.standardOutput = FileHandle.nullDevice
                forceKill.standardError = FileHandle.nullDevice
                try? forceKill.run()
                forceKill.waitUntilExit()
            }
            
            self.runningProcesses.removeValue(forKey: cloneId)
        }
    }
    
    func stopAllClones() {
        DiagnosticLogger.info("STOP", "Dừng tất cả clones — graceful quit")
        
        // Step 1: Gửi quit cho tất cả clone bằng osascript
        for (id, pid) in runningProcesses {
            let script = """
            tell application "System Events"
                set procs to every process whose unix id is \(pid)
                repeat with p in procs
                    tell p to quit
                end repeat
            end tell
            """
            let appleScript = Process()
            appleScript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            appleScript.arguments = ["-e", script]
            appleScript.standardOutput = FileHandle.nullDevice
            appleScript.standardError = FileHandle.nullDevice
            try? appleScript.run()
        }
        
        // Step 2: Chờ 5 giây cho tất cả clone tự thoát
        Task {
            try? await Task.sleep(for: .seconds(5))
            
            // Step 3: SIGTERM cho ai vẫn còn
            if Self.checkCloneRunning(cloneIndex: 0, knownPID: nil) ||
               !runningProcesses.isEmpty {
                let killProc = Process()
                killProc.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                killProc.arguments = ["-f", "ZaloMulti/Clones/ZaloClone"]
                killProc.standardOutput = FileHandle.nullDevice
                killProc.standardError = FileHandle.nullDevice
                try? killProc.run()
                killProc.waitUntilExit()
            }
            
            // Step 4: Chờ thêm 3s rồi force kill
            try? await Task.sleep(for: .seconds(3))
            let forceKill = Process()
            forceKill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            forceKill.arguments = ["-9", "-f", "ZaloMulti/Clones/ZaloClone"]
            forceKill.standardOutput = FileHandle.nullDevice
            forceKill.standardError = FileHandle.nullDevice
            try? forceKill.run()
            forceKill.waitUntilExit()
            
            self.runningProcesses.removeAll()
            DiagnosticLogger.success("STOP", "Tất cả clones đã dừng")
        }
    }
    
    nonisolated static func isRunning(pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }
    
    nonisolated static func checkCloneRunning(cloneIndex: Int, knownPID: Int32?) -> Bool {
        if let pid = knownPID, isRunning(pid: pid) {
            return true
        }
        
        let patterns = [
            "ZaloClone\(cloneIndex).app",
            "ZaloClone\(cloneIndex).app/Contents/MacOS/Zalo"
        ]
        
        for pattern in patterns {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            proc.arguments = ["-f", pattern]
            
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            
            do {
                try proc.run()
                proc.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                
                if !output.isEmpty {
                    return true
                }
            } catch {}
        }
        
        return false
    }

    // MARK: - Single-Active Seamless Switcher
    
    static func focusDefaultZalo() {
        switchToDefaultZalo()
    }

    static func focusClone(pid: Int32, bundleID: String? = nil) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }
        if let bundleID = bundleID, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }
    }
    
    static func switchToDefaultZalo() {
        DiagnosticLogger.info("SWITCH", "🔄 Đang chuyển sang Zalo Chính...")
        
        let script = """
        tell application "System Events"
            set targetPos to missing value
            set targetSize to missing value
            
            -- Lấy vị trí cửa sổ đang hiển thị để giữ nguyên khung hình
            repeat with p in (every process)
                try
                    set pName to name of p
                    if (pName contains "Zalo.orig" or pName contains "ZaloClone") and (visible of p is true) then
                        if (count of windows of p) > 0 then
                            set targetPos to position of first window of p
                            set targetSize to size of first window of p
                            exit repeat
                        end if
                    end if
                end try
            end repeat
            
            -- Ẩn tất cả clone
            repeat with p in (every process)
                try
                    set pName to name of p
                    if pName contains "Zalo.orig" or pName contains "ZaloClone" then
                        set visible of p to false
                    end if
                end try
            end repeat
            
            -- Hiện Zalo mặc định
            repeat with p in (every process whose name is "Zalo")
                try
                    set visible of p to true
                    set frontmost of p to true
                    if targetPos is not missing value and targetSize is not missing value then
                        set position of first window of p to targetPos
                        set size of first window of p to targetSize
                    end if
                end try
            end repeat
        end tell
        """
        runAppleScript(script)
        
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.vng.zalo").first {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        } else {
            let url = URL(fileURLWithPath: "/Applications/Zalo.app")
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        }
    }
    
    static func switchToClone(_ targetClone: CloneAccount, store: CloneStore) {
        DiagnosticLogger.info("SWITCH", "🔄 Đang chuyển sang Clone '\(targetClone.name)' (index=\(targetClone.cloneIndex))...")
        
        let targetPID: Int32
        if let existingPID = targetClone.processID, isRunning(pid: existingPID) {
            targetPID = existingPID
        } else {
            store.launchClone(targetClone)
            if let updated = store.clones.first(where: { $0.id == targetClone.id }), let newPID = updated.processID {
                targetPID = newPID
            } else {
                DiagnosticLogger.error("SWITCH", "Không thể lấy PID của clone \(targetClone.name)")
                return
            }
        }
        
        let script = """
        tell application "System Events"
            set targetPos to missing value
            set targetSize to missing value
            
            -- Lấy vị trí cửa sổ đang hiển thị
            repeat with p in (every process)
                try
                    set pName to name of p
                    if (pName is "Zalo" or pName contains "Zalo.orig" or pName contains "ZaloClone") and (visible of p is true) then
                        if (count of windows of p) > 0 then
                            set targetPos to position of first window of p
                            set targetSize to size of first window of p
                            exit repeat
                        end if
                    end if
                end try
            end repeat
            
            -- Ẩn Zalo mặc định
            repeat with p in (every process whose name is "Zalo")
                try
                    set visible of p to false
                end try
            end repeat
            
            -- Ẩn các clone khác
            repeat with p in (every process)
                try
                    set pName to name of p
                    if (pName contains "Zalo.orig" or pName contains "ZaloClone") and unix id of p is not \(targetPID) then
                        set visible of p to false
                    end if
                end try
            end repeat
            
            -- Hiện và focus clone mục tiêu
            repeat with p in (every process)
                try
                    if unix id of p is \(targetPID) then
                        set visible of p to true
                        set frontmost of p to true
                        if targetPos is not missing value and targetSize is not missing value then
                            set position of first window of p to targetPos
                            set size of first window of p to targetSize
                        end if
                    end if
                end try
            end repeat
        end tell
        """
        runAppleScript(script)
        
        if let app = NSRunningApplication(processIdentifier: targetPID) {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        } else if let app = NSRunningApplication.runningApplications(withBundleIdentifier: targetClone.bundleID).first {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }
    
    private static func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", source]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {
                DiagnosticLogger.warning("SWITCH", "osascript error: \(error)")
            }
        }
    }
}
