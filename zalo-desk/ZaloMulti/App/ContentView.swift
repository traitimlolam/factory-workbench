// ContentView.swift
// ZaloMulti
//
// Root view của Zalo Desk v2.5 — Giao diện thanh Rail bên trái (Zalo Blue),
// chuyển đổi mượt mà giữa Nick Chính và các Clone,
// kèm SheetPresenter native AppKit chuẩn xác 100%.

import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var store = CloneStore.shared
    @StateObject private var notifMonitor = NotificationMonitor.shared
    
    // nil = Nick Zalo Chính (Mặc định)
    @State private var selectedClone: CloneAccount? = nil
    @State private var activeTab: SidebarTab = .chat
    
    enum SidebarTab {
        case chat
        case clones
        case settings
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // LEFT RAIL SIDEBAR (Zalo Blue #0068FF)
            ZaloRailSidebar(
                selectedClone: $selectedClone,
                activeTab: $activeTab
            )
            .frame(width: 68)
            .background(Color(red: 0.0, green: 0.41, blue: 1.0))
            
            // MAIN CONTENT AREA
            ZStack {
                Color(NSColor.windowBackgroundColor)
                    .ignoresSafeArea()
                
                switch activeTab {
                case .chat, .clones:
                    AccountDetailView(
                        clone: selectedClone,
                        onOpenAddClone: {
                            SheetPresenter.presentAddClone(store: store)
                        }
                    )
                case .settings:
                    SettingsView()
                }
            }
            .frame(minWidth: 700, minHeight: 560)
        }
        .frame(minWidth: 768, minHeight: 560)
        .onReceive(store.$showAddCloneSheet) { show in
            if show {
                store.showAddCloneSheet = false
                SheetPresenter.presentAddClone(store: store)
            }
        }
        .alert("Lỗi", isPresented: $store.showError) {
            Button("OK") { store.showError = false }
        } message: {
            Text(store.errorMessage ?? "Đã xảy ra lỗi không xác định")
        }
    }
}

// MARK: - Left Rail Sidebar
struct ZaloRailSidebar: View {
    @ObservedObject var store = CloneStore.shared
    @ObservedObject var notifMonitor = NotificationMonitor.shared
    
    @Binding var selectedClone: CloneAccount?
    @Binding var activeTab: ContentView.SidebarTab
    
    var body: some View {
        VStack(spacing: 16) {
            // TOP: LOGO / HEADER
            VStack(spacing: 4) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 14)
                
                Text("Zalo Desk")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(.white.opacity(0.85))
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.horizontal, 10)
            
            // AVATAR STACK
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    // 1. Nick Zalo Chính
                    RailAvatarItem(
                        title: "Nick Chính",
                        initials: "Z",
                        systemIcon: "person.crop.circle.fill",
                        avatarColor: Color(red: 0.0, green: 0.55, blue: 1.0),
                        isSelected: selectedClone == nil,
                        badgeCount: notifMonitor.notifications.filter { !$0.isRead && $0.cloneId == nil }.count,
                        hasCustomImage: true
                    ) {
                        selectedClone = nil
                        activeTab = .chat
                    }
                    
                    // 2. Danh sách Clone Accounts
                    ForEach(store.clones) { clone in
                        RailAvatarItem(
                            title: clone.name,
                            initials: String(clone.name.prefix(2)).uppercased(),
                            systemIcon: nil,
                            avatarColor: Color(hex: clone.avatarColor),
                            isSelected: selectedClone?.id == clone.id,
                            badgeCount: notifMonitor.notifications.filter { !$0.isRead && $0.cloneId == clone.id }.count,
                            hasCustomImage: false
                        ) {
                            selectedClone = clone
                            activeTab = .chat
                        }
                    }
                    
                    // 3. Nút Thêm Tài Khoản (+)
                    Button(action: {
                        SheetPresenter.presentAddClone(store: store)
                    }) {
                        ZStack {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                .background(Circle().fill(Color.white.opacity(0.12)))
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Thêm tài khoản Zalo mới (+)")
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
            
            Spacer()
            
            // BOTTOM UTILITY ICONS
            VStack(spacing: 14) {
                RailIconButton(
                    icon: "message.fill",
                    label: "Tin nhắn",
                    isActive: activeTab == .chat
                ) {
                    activeTab = .chat
                }
                
                RailIconButton(
                    icon: "person.2.fill",
                    label: "Tài khoản",
                    isActive: activeTab == .clones
                ) {
                    activeTab = .clones
                }
                
                RailIconButton(
                    icon: "gearshape.fill",
                    label: "Cài đặt",
                    isActive: activeTab == .settings
                ) {
                    activeTab = .settings
                }
            }
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Rail Avatar Item
struct RailAvatarItem: View {
    let title: String
    let initials: String
    let systemIcon: String?
    let avatarColor: Color
    let isSelected: Bool
    let badgeCount: Int
    var hasCustomImage: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    // Selection indicator ring
                    if isSelected {
                        Circle()
                            .stroke(Color.white, lineWidth: 2.5)
                            .frame(width: 48, height: 48)
                    }
                    
                    // Avatar Circle
                    if hasCustomImage, let img = NSImage(named: "AppAvatar") {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else if let icon = systemIcon {
                        Circle()
                            .fill(avatarColor)
                            .frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    } else {
                        Circle()
                            .fill(avatarColor)
                            .frame(width: 40, height: 40)
                        Text(initials)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                // Badge đỏ khi có tin nhắn chưa đọc
                if badgeCount > 0 {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 18, height: 18)
                        Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: 2, y: -2)
                }
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

// MARK: - Rail Icon Button
struct RailIconButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if isActive {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 44, height: 44)
                }
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isActive ? .white : .white.opacity(0.65))
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

// MARK: - Account Detail View
struct AccountDetailView: View {
    let clone: CloneAccount?
    var onOpenAddClone: () -> Void
    @ObservedObject var store = CloneStore.shared
    
    var displayName: String {
        clone?.name ?? "Nick Zalo Chính"
    }
    
    var isRunning: Bool {
        if let c = clone {
            return c.status == .running
        }
        return true
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Big Avatar
            ZStack {
                if clone == nil, let img = NSImage(named: "AppAvatar") {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 90, height: 90)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
                } else {
                    Circle()
                        .fill(Color(hex: clone?.avatarColor ?? "#0068FF"))
                        .frame(width: 90, height: 90)
                        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
                    
                    Text(clone != nil ? String(clone!.name.prefix(2)).uppercased() : "Z")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            
            VStack(spacing: 6) {
                Text(displayName)
                    .font(.system(size: 22, weight: .bold))
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(isRunning ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(isRunning ? "Đang hoạt động (Online)" : "Chưa khởi chạy")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            
            // Action Buttons
            VStack(spacing: 12) {
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
                    .frame(minWidth: 260, minHeight: 38, maxHeight: 38)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                // Secondary Add Clone Button
                Button(action: {
                    onOpenAddClone()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15))
                        Text("Thêm Tài Khoản Zalo Mới (+)")
                            .fontWeight(.medium)
                    }
                    .frame(minWidth: 260, minHeight: 34, maxHeight: 34)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.top, 8)
            
            // Feature Highlights Box
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("Dữ liệu biệt lập 100%, bảo vệ an toàn cho Bot & Khách")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.blue)
                    Text("Hỗ trợ đầy đủ gọi điện Zalo & gửi file dung lượng lớn")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(.orange)
                    Text("Thông báo tin nhắn mới trực tiếp trên icon Sidebar")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            .padding(.top, 16)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Sheet Presenter (Native AppKit Floating Modal Window)
final class ModalSheetWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        self.close()
    }
}

@MainActor
final class SheetPresenter: NSObject, NSWindowDelegate {
    static let shared = SheetPresenter()
    private var activeModalWindow: NSWindow?
    
    static func presentAddClone(store: CloneStore) {
        DiagnosticLogger.info("UI", "SheetPresenter.presentAddClone được kích hoạt!")
        if let existing = shared.activeModalWindow, existing.isVisible {
            DiagnosticLogger.info("UI", "Cửa sổ AddClone đã tồn tại -> Focus lên frontmost")
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let view = AddCloneView(onDismiss: {
            dismissCurrent()
        })
        .environmentObject(store)
        
        let hostingController = NSHostingController(rootView: view)
        let window = ModalSheetWindow(contentViewController: hostingController)
        window.title = "Thêm Tài Khoản Zalo Clone"
        window.setContentSize(NSSize(width: 480, height: 360))
        window.styleMask = [.titled, .closable]
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        window.delegate = shared
        
        shared.activeModalWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DiagnosticLogger.success("UI", "✅ Đã hiển thị cửa sổ AddClone thành công!")
    }
    
    static func dismissCurrent() {
        if let win = shared.activeModalWindow {
            DiagnosticLogger.info("UI", "SheetPresenter: Đóng cửa sổ modal")
            win.close()
            shared.activeModalWindow = nil
        }
    }
    
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            Self.shared.activeModalWindow = nil
            DiagnosticLogger.info("UI", "SheetPresenter: Cửa sổ modal đã đóng và giải phóng")
        }
    }
}
