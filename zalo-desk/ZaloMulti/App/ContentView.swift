// ContentView.swift
// Zalo Desk — Unified Multi-Account Manager for macOS
// Copyright © 2026 Nguyễn Trọng Hiếu. All rights reserved.

import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var store = CloneStore.shared
    @StateObject private var notifMonitor = NotificationMonitor.shared
    
    // nil = Nick Zalo Chính (Mặc định)
    @State private var selectedClone: CloneAccount? = nil
    @State private var activeTab: SidebarTab = .chat
    @State private var isShowingAddClone: Bool = false
    
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
                activeTab: $activeTab,
                isShowingAddClone: $isShowingAddClone
            )
            .frame(width: 68)
            .background(Color(red: 0.0, green: 0.41, blue: 1.0))
            
            // MAIN CONTENT AREA
            ZStack {
                Color(NSColor.windowBackgroundColor)
                    .ignoresSafeArea()
                
                if isShowingAddClone {
                    AddCloneView(onDismiss: {
                        isShowingAddClone = false
                    })
                    .transition(.opacity)
                } else {
                    switch activeTab {
                    case .chat, .clones:
                        AccountDetailView(
                            clone: selectedClone,
                            onOpenAddClone: {
                                isShowingAddClone = true
                            }
                        )
                    case .settings:
                        SettingsView()
                    }
                }
            }
            .frame(minWidth: 700, minHeight: 560)
        }
        .frame(minWidth: 768, minHeight: 560)
    }
}

// MARK: - Left Rail Sidebar
struct ZaloRailSidebar: View {
    @ObservedObject private var store = CloneStore.shared
    @ObservedObject private var notifMonitor = NotificationMonitor.shared
    
    @Binding var selectedClone: CloneAccount?
    @Binding var activeTab: ContentView.SidebarTab
    @Binding var isShowingAddClone: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // macOS Window Controls Spacing
            Color.clear
                .frame(height: 38)
            
            // AVATAR STACK
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    // 1. Nick Zalo Chính (Avatar người dùng thật của Sếp)
                    AccountRailAvatar(
                        avatarImageName: "UserAvatar",
                        title: "Nick Chính",
                        isSelected: selectedClone == nil && !isShowingAddClone,
                        unreadCount: 0,
                        isRunning: true,
                        action: {
                            selectedClone = nil
                            isShowingAddClone = false
                            activeTab = .chat
                            ProcessManager.focusDefaultZalo()
                        }
                    )
                    
                    // 2. Danh sách Clones (nếu có)
                    ForEach(store.clones) { clone in
                        let unread = notifMonitor.notifications.filter {
                            !$0.isRead && ($0.cloneId == clone.id || $0.cloneName == clone.name)
                        }.count
                        
                        AccountRailAvatar(
                            avatarImageName: "UserAvatar",
                            title: clone.name,
                            isSelected: selectedClone?.id == clone.id && !isShowingAddClone,
                            unreadCount: unread,
                            isRunning: clone.status == .running,
                            action: {
                                selectedClone = clone
                                isShowingAddClone = false
                                activeTab = .chat
                                store.focusClone(clone)
                            }
                        )
                    }
                    
                    // 3. Nút Thêm Tài Khoản (+)
                    Button(action: {
                        isShowingAddClone = true
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
                    }
                    .buttonStyle(.plain)
                    .help("Thêm tài khoản Zalo mới (+)")
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 340)
            
            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            
            // SECONDARY NAVIGATION
            VStack(spacing: 14) {
                SidebarIconButton(
                    iconName: "message.fill",
                    label: "Tin nhắn",
                    isActive: activeTab == .chat && !isShowingAddClone,
                    action: {
                        isShowingAddClone = false
                        activeTab = .chat
                        if let c = selectedClone {
                            store.focusClone(c)
                        } else {
                            ProcessManager.focusDefaultZalo()
                        }
                    }
                )
                
                SidebarIconButton(
                    iconName: "person.2.fill",
                    label: "Danh sách Nick",
                    isActive: activeTab == .clones && !isShowingAddClone,
                    action: {
                        isShowingAddClone = false
                        activeTab = .clones
                    }
                )
            }
            
            Spacer()
            
            // SETTINGS & BRANDING
            VStack(spacing: 12) {
                SidebarIconButton(
                    iconName: "gearshape.fill",
                    label: "Cài đặt",
                    isActive: activeTab == .settings,
                    action: {
                        isShowingAddClone = false
                        activeTab = .settings
                    }
                )
                
                Text("Zalo Desk")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 10)
            }
        }
    }
}

// MARK: - Account Rail Avatar Component
struct AccountRailAvatar: View {
    let avatarImageName: String
    let title: String
    let isSelected: Bool
    let unreadCount: Int
    let isRunning: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottomTrailing) {
                    // Profile Image
                    Image(avatarImageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: isSelected ? 2.5 : 0)
                        )
                        .shadow(color: Color.black.opacity(isSelected ? 0.3 : 0), radius: 3)
                    
                    // Running Dot Indicator
                    if isRunning {
                        Circle()
                            .fill(Color(red: 0.15, green: 0.85, blue: 0.4))
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(Color(red: 0.0, green: 0.41, blue: 1.0), lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                }
                
                // Unread Badge
                if unreadCount > 0 {
                    ZStack {
                        Capsule()
                            .fill(Color.red)
                            .frame(minWidth: 16, minHeight: 16, maxHeight: 16)
                        
                        Text("\(min(unreadCount, 99))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                    }
                    .offset(x: 6, y: -4)
                }
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

// MARK: - Sidebar Icon Button Component
struct SidebarIconButton: View {
    let iconName: String
    let label: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if isActive {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 40, height: 40)
                }
                
                Image(systemName: iconName)
                    .font(.system(size: 18))
                    .foregroundColor(isActive ? .white : .white.opacity(0.7))
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

// MARK: - Account Detail & Quick Launcher
struct AccountDetailView: View {
    let clone: CloneAccount?
    let onOpenAddClone: () -> Void
    @ObservedObject private var store = CloneStore.shared
    
    var accountName: String {
        clone?.name ?? "Nick Zalo Chính"
    }
    
    var isRunning: Bool {
        clone?.status == .running || clone == nil
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header Profile Card
            VStack(spacing: 14) {
                // Large Avatar
                Image("UserAvatar")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(red: 0.0, green: 0.41, blue: 1.0), lineWidth: 3))
                    .shadow(radius: 4)
                
                Text(accountName)
                    .font(.system(size: 22, weight: .bold))
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Đang hoạt động (Online)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
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
                .frame(minWidth: 260, minHeight: 38, maxHeight: 38)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.0, green: 0.41, blue: 1.0))
            
            // Feature Highlights
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "shield.checkmark.fill", text: "Dữ liệu biệt lập 100%, bảo vệ an toàn cho Bot & Khách")
                FeatureRow(icon: "phone.fill", text: "Hỗ trợ đầy đủ gọi điện Zalo & gửi file dung lượng lớn")
                FeatureRow(icon: "bell.badge.fill", text: "Thông báo tin nhắn mới trực tiếp trên icon Sidebar")
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            .padding(.horizontal, 40)
            .padding(.top, 10)
            
            Spacer()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Color(red: 0.0, green: 0.41, blue: 1.0))
                .font(.system(size: 16))
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Cài đặt Zalo Desk")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 30)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Phiên bản: 2.3.0 (Bản quyền Nguyễn Trọng Hiếu)")
                Text("Cơ chế: Native macOS Multi-Instance Orchestration")
                Text("Bảo mật: Phân tách phân vùng dữ liệu độc lập")
            }
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .padding()
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
            
            Spacer()
        }
        .padding()
    }
}
