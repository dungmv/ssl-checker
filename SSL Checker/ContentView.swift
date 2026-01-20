//
//  ContentView.swift
//  SSL Checker
//
//  Created by Mai Dũng on 20/1/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SSLDomain.host) private var domains: [SSLDomain]
    
    @State private var newHost = ""
    @State private var isRefreshing = false

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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(domain.host)
                                .font(.headline)
                            
                            HStack {
                                if let expiry = domain.expiryDate {
                                    Text("Expires: \(expiry, format: .dateTime.day().month().year())")
                                        .font(.subheadline)
                                        .foregroundStyle(expiryDateColor(for: expiry))
                                } else {
                                    Text("No expiry info")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Text("Last checked: \(domain.lastChecked, format: .dateTime.hour().minute())")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
            if let expiry = try await SSLService.shared.fetchExpiryDate(for: domain.host) {
                domain.expiryDate = expiry
                domain.lastChecked = Date()
            }
        } catch {
            print("Error refreshing \(domain.host): \(error)")
            domain.lastChecked = Date()
        }
    }
    
    private func expiryDateColor(for date: Date) -> Color {
        let daysUntilExpiry = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if daysUntilExpiry < 7 {
            return .red
        } else if daysUntilExpiry < 30 {
            return .orange
        } else {
            return .green
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SSLDomain.self, inMemory: true)
}
