//
//  SSL_CheckerApp.swift
//  SSL Checker
//
//  Created by Mai Dũng on 20/1/26.
//

import SwiftUI
import SwiftData

@main
struct SSL_CheckerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SSLDomain.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
