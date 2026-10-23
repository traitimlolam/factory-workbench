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
            .frame(minWidth: 700, minHeight: 560)
        }
        .frame(minWidth: 768, minHeight: 560)
        .sheet(isPresented: $isShowingAddClone) {
            AddCloneView()
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
                        .contentShape(Circle())
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
                    label: "Tài khoản",
                    isActive: activeTab == .clones && !isShowingAddClone,
                    action: {
                        isShowingAddClone = false
                        activeTab = .clones
                    }
                )
            }
            
            Spacer()
            
            // BOTTOM SETTINGS & BRANDING
            VStack(spacing: 12) {
                SidebarIconButton(
                    iconName: "gearshape.fill",
                    label: "Cài đặt",
                    isActive: activeTab == .settings && !isShowingAddClone,
                    action: {
                        isShowingAddClone = false
                        activeTab = .settings
                    }
                )
                
                Text("Zalo Desk")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.6))
                    .padding(.bottom, 12)
            }
        }
    }
}

// MARK: - Avatar Component on Sidebar Rail
struct AccountRailAvatar: View {
    let avatarImageName: String
    let title: String
    let isSelected: Bool
    let unreadCount: Int
    let isRunning: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                // Avatar Frame with Selection Ring
                ZStack {
                    if isSelected {
                        Circle()
                            .stroke(Color.white, lineWidth: 2.5)
                            .frame(width: 48, height: 48)
                            .shadow(color: Color.black.opacity(0.25), radius: 3)
                    }
                    
                    Image(avatarImageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(Circle())
                }
                
                // Status Indicator (Green dot if active)
                if isRunning {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color(red: 0.0, green: 0.41, blue: 1.0), lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
                
                // Unread Badge
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.red))
                        .offset(x: 6, y: -28)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

// MARK: - Sidebar Icon Navigation Button
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
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 44, height: 44)
                }
                
                Image(systemName: iconName)
                    .font(.system(size: 19, weight: isActive ? .bold : .regular))
                    .foregroundColor(isActive ? .white : Color.white.opacity(0.75))
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

// MARK: - Account Detail Dashboard View
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
                        .fill(isRunning ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(isRunning ? "Đang hoạt động (Online)" : "Chưa khởi chạy")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 40)
            
            // Action Buttons
            VStack(spacing: 12) {
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
            }
            
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
                .frame(width: 22)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            Spacer()
        }
    }
}
