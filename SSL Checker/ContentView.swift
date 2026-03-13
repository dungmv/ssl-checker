//
//  ContentView.swift
//  SSL Checker
//
//  Created by Mai Dũng on 20/1/26.
//

import SwiftUI
import SwiftData

// MARK: - Date Formatters

private let ddMMYYYYFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "dd/MM/yyyy"
    return f
}()

private let fullDateTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "dd/MM/yyyy HH:mm"
    return f
}()

// MARK: - Helpers

private func daysRemaining(to date: Date) -> Int {
    Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
}

// MARK: - Domain Detail Popup

struct DomainDetailSheet: View {
    let domain: SSLDomain
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Thông tin domain") {
                    DetailRow(label: "Domain", value: domain.host, icon: "globe")
                }

                Section("SSL Certificate") {
                    if let expiry = domain.expiryDate {
                        let days = daysRemaining(to: expiry)
                        DetailRow(
                            label: "Ngày hết hạn",
                            value: ddMMYYYYFormatter.string(from: expiry),
                            icon: "calendar.badge.clock",
                            valueColor: expiryColor(days: days)
                        )
                        DetailRow(
                            label: "Số ngày còn lại",
                            value: days > 0 ? "\(days) ngày" : (days == 0 ? "Hết hạn hôm nay" : "Đã hết hạn \(-days) ngày"),
                            icon: "hourglass",
                            valueColor: expiryColor(days: days)
                        )
                    } else {
                        DetailRow(label: "Ngày hết hạn", value: "Không có thông tin", icon: "calendar.badge.exclamationmark", valueColor: .secondary)
                    }
                }

                Section("Kiểm tra") {
                    DetailRow(
                        label: "Thời gian kiểm tra",
                        value: fullDateTimeFormatter.string(from: domain.lastChecked),
                        icon: "clock"
                    )
                    DetailRow(
                        label: "IP Server",
                        value: domain.ipAddress ?? "Không xác định",
                        icon: "server.rack"
                    )
                }
            }
            .navigationTitle("Chi tiết SSL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }

    private func expiryColor(days: Int) -> Color {
        if days < 7 { return .red }
        if days < 30 { return .orange }
        return .green
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    let icon: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(valueColor)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SSLDomain.host) private var domains: [SSLDomain]
    
    @State private var newHost = ""
    @State private var isRefreshing = false
    @State private var selectedDomain: SSLDomain?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Domain (e.g. google.com)", text: $newHost)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onSubmit {
                                addDomain()
                            }
                        
                        Button(action: addDomain) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(newHost.isEmpty ? .gray : .blue)
                        }
                        .disabled(newHost.isEmpty)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Add New Domain")
                }

                Section {
                    ForEach(domains) { domain in
                        Button {
                            selectedDomain = domain
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(domain.host)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                
                                HStack {
                                    if let expiry = domain.expiryDate {
                                        let days = daysRemaining(to: expiry)
                                        Text("Expires: \(ddMMYYYYFormatter.string(from: expiry))")
                                            .font(.subheadline)
                                            .foregroundStyle(expiryDateColor(for: expiry))
                                        
                                        Spacer()
                                        
                                        // Days remaining badge
                                        let badgeText: String = {
                                            if days > 0 { return "\(days) ngày" }
                                            if days == 0 { return "Hôm nay" }
                                            return "Hết hạn"
                                        }()
                                        Text(badgeText)
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(expiryDateColor(for: expiry).opacity(0.15))
                                            .foregroundStyle(expiryDateColor(for: expiry))
                                            .clipShape(Capsule())
                                    } else {
                                        Text("No expiry info")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        
                                        Spacer()
                                        
                                        Text("—")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteDomains)
                } header: {
                    if !domains.isEmpty {
                        Text("Monitored Domains")
                    }
                }
            }
            .navigationTitle("SSL Checker")
            .refreshable {
                await refreshAll()
            }
            .sheet(item: $selectedDomain) { domain in
                DomainDetailSheet(domain: domain)
            }
        }
    }

    private func addDomain() {
        let host = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        
        let newDomain = SSLDomain(host: host)
        modelContext.insert(newDomain)
        
        Task {
            await refreshDomain(newDomain)
        }
        
        newHost = ""
    }

    private func deleteDomains(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(domains[index])
            }
        }
    }
    
    private func refreshAll() async {
        isRefreshing = true
        for domain in domains {
            await refreshDomain(domain)
        }
        isRefreshing = false
    }
    
    private func refreshDomain(_ domain: SSLDomain) async {
        do {
            let info = try await SSLService.shared.fetchSSLInfo(for: domain.host)
            if let expiry = info.expiryDate {
                domain.expiryDate = expiry
            }
            domain.ipAddress = info.ipAddress
            domain.lastChecked = Date()
        } catch {
            print("Error refreshing \(domain.host): \(error)")
            domain.lastChecked = Date()
        }
    }
    
    private func expiryDateColor(for date: Date) -> Color {
        let days = daysRemaining(to: date)
        if days < 7 { return .red }
        if days < 30 { return .orange }
        return .green
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SSLDomain.self, inMemory: true)
}
