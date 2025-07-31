import Foundation

struct AppConfiguration {
    static let shared = AppConfiguration()
    
    // MARK: - App Settings
    let bundleIdentifier = "com.architect.ARchitect"
    let appVersion = "1.0.0"
    
    // MARK: - AR Settings
    let maxFurnitureItems = 50
    let roomScanningTimeout: TimeInterval = 30.0
    let aiOptimizationEnabled = true
    
    // MARK: - Collaboration Settings
    let maxCollaborators = 4
    let sessionTimeout: TimeInterval = 3600 // 1 hour
    
    private init() {}
}