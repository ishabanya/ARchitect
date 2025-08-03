import SwiftUI

@main
struct ARchitectApp: App {
    init() {
        // Initialize analytics on app launch
        // _ = AnalyticsManager.shared
        
        // Track app launch
        // AnalyticsManager.shared.trackUserEngagement(.sessionStart, parameters: [
        //     "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "Unknown",
        //     "build_number": Bundle.main.infoDictionary?["CFBundleVersion"] ?? "Unknown"
        // ])
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // AnalyticsManager.shared.trackScreenView("ContentView")
                }
        }
    }
}