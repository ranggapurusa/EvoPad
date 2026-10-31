import SwiftUI

@main
struct EvoPadMacApp: App {
    @StateObject private var server = MacServer()

    var body: some Scene {
        WindowGroup {
            MacContentView(server: server)
        }
        .windowResizability(.contentSize)
    }
}
