// ContentView.swift
// Zalo Desk — Unified Multi-Account Manager for macOS
// Copyright © 2026 Nguyễn Trọng Hiếu

import SwiftUI

enum ActiveTab {
    case account(String) // "default" or clone UUID
    case addAccount
    case settings
}

struct ContentView: View {
    @ObservedObject var store = CloneStore.shared
    @ObservedObject var notifMonitor = NotificationMonitor.shared
    @State private var activeTab: ActiveTab = .account("default")
    
    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Vertical Rail (Zalo Electric Blue #0068FF)
            ZaloRailSidebar(activeTab: $activeTab)
                .frame(width: 68)
                .background(Color(red: 0.0, green: 0.41, blue: 1.0)) // #0068FF
            
            Divider()
            
            // MARK: - Main Content Area
            Group {
                switch activeTab {
                case .account(let accountId):
                    AccountDetailView(accountId: accountId, onAddNew: {
                        activeTab = .addAccount
                    })
                case .addAccount:
                    AddAccountInlineView(onFinish: {
                        if let lastClone = store.clones.last {
                            activeTab = .account(lastClone.id.uuidString)
                        } else {
                            activeTab = .account("default")
                        }
                    })
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 800, minHeight: 560)
        .onAppear {
            if let first = store.clones.first {
                activeTab = .account(first.id.uuidString)
            } else {
                activeTab = .account("default")
            }
        }
    }
}

// MARK: - Zalo Rail Sidebar
struct ZaloRailSidebar: View {
    @Binding var activeTab: ActiveTab
    @ObservedObject var store = CloneStore.shared
    @ObservedObject var notifMonitor = NotificationMonitor.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Window Traffic Light Spacer
            Spacer().frame(height: 38)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    // 1. Nick Chính (Default Account)
                    AvatarRailButton(
                        title: "Nick Chính",
                        initials: "CH",
                        isSelected: isSelected("default"),
                        isRunning: true,
                        unreadCount: 0,
                        action: {
                            activeTab = .account("default")
                            ProcessManager.focusDefaultZalo()
                        }
                    )
                    
                    // 2. Clone Accounts List
                    ForEach(store.clones) { clone in
                        AvatarRailButton(
                            title: clone.name,
                            initials: getInitials(clone.name),
                            isSelected: isSelected(clone.id.uuidString),
                            isRunning: clone.status == .running,
                            unreadCount: getUnreadCount(clone),
                            action: {
                                activeTab = .account(clone.id.uuidString)
                                store.focusClone(clone)
                            }
                        )
                    }
                    
                    // 3. (+) Add Account Button (Right below accounts!)
                    Button(action: {
                        activeTab = .addAccount
                    }) {
                        ZStack {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                                .background(Circle().fill(Color.white.opacity(0.15)))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Thêm tài khoản Zalo mới")
                    .padding(.top, 4)
                }
                .padding(.vertical, 8)
            }
            
            Spacer()
            
            // Bottom Controls
            VStack(spacing: 14) {
                Divider()
                    .background(Color.white.opacity(0.3))
                    .padding(.horizontal, 12)
                
                // Settings Gear
                Button(action: {
                    activeTab = .settings
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18))
                        .foregroundColor(activeTabIsSettings ? .white : Color.white.opacity(0.7))
                        .frame(width: 40, height: 40)
                        .background(activeTabIsSettings ? Color.white.opacity(0.25) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Cài đặt Zalo Desk")
                
                Spacer().frame(height: 12)
            }
        }
    }
    
    private var activeTabIsSettings: Bool {
        if case .settings = activeTab { return true }
        return false
    }
    
    private func isSelected(_ id: String) -> Bool {
        if case .account(let curId) = activeTab {
            return curId == id
        }
        return false
    }
    
    private func getInitials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            let first = parts[0].prefix(1)
            let last = parts[parts.count - 1].prefix(1)
            return "\(first)\(last)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    private func getUnreadCount(_ clone: CloneAccount) -> Int {
        // Count unread notifications matching this clone
        notifMonitor.notifications.filter { !$0.isRead && $0.cloneIndex == clone.cloneIndex }.count
    }
}

// MARK: - Avatar Rail Button
struct AvatarRailButton: View {
    let title: String
    let initials: String
    let isSelected: Bool
    let isRunning: Bool
    let unreadCount: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottomTrailing) {
                    // Avatar circle
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 42, height: 42)
                        
                        Text(initials)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: isSelected ? 2.5 : 0)
                    )
                    
                    // Green running dot indicator
                    if isRunning {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color(red: 0.0, green: 0.41, blue: 1.0), lineWidth: 1.5))
                            .offset(x: 2, y: 2)
                    }
                }
                
                // Red unread badge
                if unreadCount > 0 {
                    ZStack {
                        Capsule()
                            .fill(Color.red)
                            .frame(minWidth: 16, height: 16)
                        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                    }
                    .offset(x: 6, y: -4)
                }
            }
            .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

// MARK: - Account Detail View
struct AccountDetailView: View {
    let accountId: String
    let onAddNew: () -> Void
    @ObservedObject var store = CloneStore.shared
    
    var clone: CloneAccount? {
        if accountId == "default" { return nil }
        return store.clones.first { $0.id.uuidString == accountId }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header Card
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.0, green: 0.41, blue: 1.0).opacity(0.12))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 72, height: 72)
                        .foregroundColor(Color(red: 0.0, green: 0.41, blue: 1.0))
                }
                
                Text(clone?.name ?? "Nick Zalo Chính")
                    .font(.title2)
                    .fontWeight(.bold)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill((clone?.status == .running || accountId == "default") ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text((clone?.status == .running || accountId == "default") ? "Đang hoạt động (Online)" : "Chưa mở cửa sổ chat")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 40)
            
            // Primary Switch Button
            Button(action: {
                if let c = clone {
                    store.focusClone(c)
                } else {
                    ProcessManager.focusDefaultZalo()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 15))
                    Text("Mở Cửa Sổ Chat (1 Chạm Chuyển Đổi)")
                        .fontWeight(.semibold)
                }
                .frame(minWidth: 260)
                .frame(height: 38)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.0, green: 0.41, blue: 1.0))
            
            // Info Highlights
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "shield.checkmark.fill", text: "Dữ liệu biệt lập 100% trong phân vùng an toàn")
                FeatureRow(icon: "phone.fill", text: "Hỗ trợ đầy đủ gọi thoại, gọi video & gửi file lớn")
                FeatureRow(icon: "bell.badge.fill", text: "Thông báo tin nhắn mới hiển thị trực tiếp trên Avatar")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .frame(maxWidth: 420)
            
            Spacer()
            
            // Footer Action
            if let c = clone {
                HStack(spacing: 16) {
                    if c.status == .running {
                        Button("Dừng tài khoản này") {
                            store.stopClone(c)
                        }
                        .foregroundColor(.red)
                    }
                    Button("Xoá tài khoản") {
                        store.deleteClone(c)
                    }
                    .foregroundColor(.secondary)
                }
                .font(.footnote)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Feature Row
struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(Color(red: 0.0, green: 0.41, blue: 1.0))
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Add Account Inline View
struct AddAccountInlineView: View {
    let onFinish: () -> Void
    @ObservedObject var store = CloneStore.shared
    @State private var name = ""
    @State private var phone = ""
    @State private var isCreating = false
    @State private var isDone = false
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 30)
            
            Image(systemName: "person.crop.circle.badge.plus")
                .resizable()
                .frame(width: 60, height: 50)
                .foregroundColor(Color(red: 0.0, green: 0.41, blue: 1.0))
            
            Text("Thêm Tài Khoản Zalo Mới")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Mỗi tài khoản sẽ sở hữu một phân vùng dữ liệu biệt lập hoàn toàn.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tên gợi nhớ (Ví dụ: Tiểu My, Zalo Bán Hàng)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    TextField("Nhập tên gợi nhớ...", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Số điện thoại (Không bắt buộc)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    TextField("Nhập số điện thoại...", text: $phone)
                        .textFieldStyle(.roundedBorder)
                }
                
                if isCreating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(store.engine.progressMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: 360)
            
            Button(action: {
                createAccount()
            }) {
                Text(isCreating ? "Đang tạo tài khoản..." : "Tạo & Mở Quét Mã QR")
                    .fontWeight(.semibold)
                    .frame(minWidth: 200, height: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.0, green: 0.41, blue: 1.0))
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func createAccount() {
        isCreating = true
        Task {
            do {
                let nextIdx = (store.clones.map(\.cloneIndex).max() ?? 0) + 1
                let clone = try await store.engine.createClone(index: nextIdx, name: name, phone: phone)
                store.clones.append(clone)
                store.saveClones()
                isCreating = false
                isDone = true
                store.focusClone(clone)
                onFinish()
            } catch {
                isCreating = false
                store.errorMessage = error.localizedDescription
                store.showError = true
            }
        }
    }
}
