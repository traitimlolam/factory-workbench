// SidebarView.swift
// ZaloDesk

import SwiftUI

struct SidebarView: View {
    @ObservedObject var store = CloneStore.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // 0. Chuyển nhanh tài khoản (1 chạm)
            QuickSwitcherView()
            
            Spacer()
            
            Divider()
            
            // 1. Đóng tất cả Clone
            Button(action: { store.stopAllClones() }) {
                Label("Đóng tất cả Clone", systemImage: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            Divider()
            
            // 2. Footer Stats
            SidebarFooterView()
                .padding()
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - Quick Switcher View (1 Chạm chuyển Nick)
struct QuickSwitcherView: View {
    @ObservedObject var store = CloneStore.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CHUYỂN NHANH NICK")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("1 chạm")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.clones) { clone in
                        Button(action: {
                            store.focusClone(clone)
                        }) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(clone.status == .running ? Color.green : Color.secondary)
                                    .frame(width: 8, height: 8)
                                
                                Text(clone.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if clone.status == .running {
                                    Image(systemName: "arrow.up.forward.app.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "play.circle")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.8))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
}

// MARK: - Footer Stats
struct SidebarFooterView: View {
    @ObservedObject var store = CloneStore.shared
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Zalo Desk Native ARM64")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 0) {
                VStack {
                    Text("\(store.runningCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                    Text("đang mở")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Divider().frame(height: 30)
                
                VStack {
                    Text("\(store.totalCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("tổng nick")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
    }
}
