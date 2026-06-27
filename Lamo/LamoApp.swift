import SwiftUI
import SwiftData

@main
struct LamoApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                MainView()
            }
        }
        .modelContainer(for: [Conversation.self, Message.self])
    }
}
