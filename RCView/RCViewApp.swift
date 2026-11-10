import SwiftUI

@main
struct RCViewApp: App {
    var body: some Scene {
        WindowGroup {
            ViewerScreen()
                .preferredColorScheme(.light)
        }
    }
}
