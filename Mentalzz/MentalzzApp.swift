//
//  MentalzzApp.swift
//  Mentalzz
//
//  Created by I Made Debrio Amarta on 20/08/26.
//

import SwiftUI
import SwiftData

@main
struct MentalzzApp: App {

    let container: ModelContainer = {
        let schema = Schema([Client.self, Handler.self, ChatMessage.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // If the on-disk store can't be opened, fall back to memory so the
            // app still launches instead of crashing on the owner's iPad.
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [memory])
        }
    }()

    init() {
        // Restore the owner's weekday preference before anything schedules.
        SchedulingService.weekdaysOnly =
            UserDefaults.standard.object(forKey: "weekdaysOnly") as? Bool ?? true
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
