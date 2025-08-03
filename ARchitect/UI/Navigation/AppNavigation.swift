import SwiftUI

// MARK: - App Navigation

public enum AppDestination {
    case roomScanning
    case measurementTools
    case furnitureCatalog
    case arStatus
    case logViewer
}

// MARK: - Navigation Extensions

extension View {
    public func navigate(to destination: AppDestination, isPresented: Binding<Bool>) -> some View {
        switch destination {
        case .roomScanning:
            return self.fullScreenCover(isPresented: isPresented) {
                // RoomScanningView would be presented here
                Text("Room Scanning")
            }
        case .measurementTools:
            return self.fullScreenCover(isPresented: isPresented) {
                // MeasurementToolsView would be presented here
                Text("Measurement Tools")
            }
        case .furnitureCatalog:
            return self.fullScreenCover(isPresented: isPresented) {
                FurnitureCatalogView()
            }
        case .arStatus:
            return self.sheet(isPresented: isPresented) {
                // ARSessionStatusView would be presented here
                Text("AR Status")
            }
        case .logViewer:
            return self.sheet(isPresented: isPresented) {
                // LogViewer would be presented here
                Text("Log Viewer")
            }
        }
    }
}

// MARK: - Navigation Coordinator

@MainActor
public class NavigationCoordinator: ObservableObject {
    @Published public var currentDestination: AppDestination?
    @Published public var isPresenting = false
    
    public init() {}
    
    public func navigate(to destination: AppDestination) {
        currentDestination = destination
        isPresenting = true
    }
    
    public func dismiss() {
        isPresenting = false
        currentDestination = nil
    }
}

// MARK: - Tab Navigation

public enum MainTab: String, CaseIterable {
    case home = "home"
    case scan = "scan"
    case catalog = "catalog"
    case measurements = "measurements"
    case settings = "settings"
    
    public var title: String {
        switch self {
        case .home: return "Home"
        case .scan: return "Scan"
        case .catalog: return "Catalog"
        case .measurements: return "Measure"
        case .settings: return "Settings"
        }
    }
    
    public var icon: String {
        switch self {
        case .home: return "house"
        case .scan: return "viewfinder"
        case .catalog: return "chair.fill"
        case .measurements: return "ruler"
        case .settings: return "gear"
        }
    }
    
    public var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .scan: return "viewfinder"
        case .catalog: return "chair.fill"
        case .measurements: return "ruler.fill"
        case .settings: return "gear.fill"
        }
    }
}

// MARK: - Tabbed App View

public struct TabbedAppView: View {
    @State private var selectedTab: MainTab = .home
    @StateObject private var arSessionManager = ARSessionManager()
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            // Home Tab
            ContentView()
                .tabItem {
                    Image(systemName: selectedTab == .home ? MainTab.home.selectedIcon : MainTab.home.icon)
                    Text(MainTab.home.title)
                }
                .tag(MainTab.home)
            
            // Scan Tab - Room Scanning
            RoomScanningView(sessionManager: arSessionManager)
                .tabItem {
                    Image(systemName: selectedTab == .scan ? MainTab.scan.selectedIcon : MainTab.scan.icon)
                    Text(MainTab.scan.title)
                }
                .tag(MainTab.scan)
            
            // Catalog Tab - Furniture Catalog
            FurnitureCatalogView()
                .tabItem {
                    Image(systemName: selectedTab == .catalog ? MainTab.catalog.selectedIcon : MainTab.catalog.icon)
                    Text(MainTab.catalog.title)
                }
                .tag(MainTab.catalog)
            
            // Measurements Tab
            MeasurementToolsView(sessionManager: arSessionManager)
                .tabItem {
                    Image(systemName: selectedTab == .measurements ? MainTab.measurements.selectedIcon : MainTab.measurements.icon)
                    Text(MainTab.measurements.title)
                }
                .tag(MainTab.measurements)
            
            // Settings Tab (placeholder)
            SettingsView()
                .tabItem {
                    Image(systemName: selectedTab == .settings ? MainTab.settings.selectedIcon : MainTab.settings.icon)
                    Text(MainTab.settings.title)
                }
                .tag(MainTab.settings)
        }
        .tint(.accentColor)
    }
}

// MARK: - Settings View Placeholder

private struct SettingsView: View {
    var body: some View {
        NavigationView {
            List {
                Section("App") {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("About ARchitect")
                    }
                    
                    HStack {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.green)
                        Text("Help & Support")
                    }
                }
                
                Section("AR Settings") {
                    HStack {
                        Image(systemName: "camera.viewfinder")
                            .foregroundColor(.orange)
                        Text("AR Preferences")
                    }
                    
                    HStack {
                        Image(systemName: "cube.transparent")
                            .foregroundColor(.purple)
                        Text("Model Quality")
                    }
                }
                
                Section("Data") {
                    HStack {
                        Image(systemName: "icloud")
                            .foregroundColor(.blue)
                        Text("Cloud Sync")
                    }
                    
                    HStack {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                        Text("Clear Cache")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    TabbedAppView()
}