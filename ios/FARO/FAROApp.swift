import SwiftUI
import SwiftData

@main
struct FAROApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Place.self, PlaceSnapshot.self])
    }
}
