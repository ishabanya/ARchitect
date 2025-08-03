import SwiftUI

// MARK: - Main Tab View

public struct MainTabView: View {
    @StateObject private var navigationController = MainNavigationController()
    @StateObject private var hapticFeedback = HapticFeedbackManager.shared
    
    // Environment values for accessibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Main content
            TabView(selection: $navigationController.selectedTab) {
                ForEach(NavigationTab.allCases, id: \.self) { tab in
                    NavigationStack(path: $navigationController.navigationPath) {
                        tabContent(for: tab)
                            .trackScreenView(tab.rawValue)
                            .navigationDestination(for: NavigationDestination.self) { destination in
                                destinationView(for: destination)
                                    .trackScreenView(String(describing: destination))
                            }
                    }
                    .tabItem {
                        TabItemView(tab: tab, isSelected: navigationController.selectedTab == tab)
                    }
                    .tag(tab)
                }
            }
            .tabViewStyle(.automatic)
            .accentColor(.primary)
            .onChange(of: navigationController.selectedTab) { oldValue, newValue in
                handleTabChange(from: oldValue, to: newValue)
                
                // Track tab change
                AnalyticsManager.shared.trackUserEngagement(.screenView, parameters: [
                    "previous_tab": oldValue?.rawValue ?? "none",
                    "new_tab": newValue.rawValue,
                    "navigation_method": "tab_bar"
                ])
            }
            
            // Transition overlay
            if navigationController.transitionInProgress && !reduceMotion {
                TransitionOverlay()
                    .allowsHitTesting(false)
            }
        }
        .environmentObject(navigationController)
        .sheet(isPresented: $navigationController.showingSheet) {
            sheetContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            handleOrientationChange()
        }
    }
    
    // MARK: - Tab Content
    
    @ViewBuilder
    private func tabContent(for tab: NavigationTab) -> some View {
        switch tab {
        case .discover:
            DiscoverView()
            
        case .ar:
            ARViewContainer()
            
        case .rooms:
            RoomsView()
            
        case .favorites:
            FavoritesView()
            
        case .profile:
            ProfileView()
        }
    }
    
    // MARK: - Navigation Destinations
    
    @ViewBuilder
    private func destinationView(for destination: NavigationDestination) -> some View {
        switch destination {
        case .furnitureDetail(let item):
            FurnitureDetailView(item: item)
            
        case .roomDetail(let room):
            RoomDetailView(room: room)
            
        case .categoryView(let category):
            CategoryView(category: category)
            
        case .searchResults(let query):
            SearchResultsView(query: query)
            
        case .userProfile(let userID):
            UserProfileView(userID: userID)
            
        case .settings:
            SettingsView()
            
        case .about:
            AboutView()
        }
    }
    
    // MARK: - Sheet Content
    
    @ViewBuilder
    private func sheetContent() -> some View {
        if let sheet = navigationController.currentSheet {
            NavigationStack {
                switch sheet {
                case .furnitureCatalog:
                    FurnitureCatalogSheet()
                    
                case .furnitureDetail:
                    EmptyView() // Handled via navigation
                    
                case .roomSettings:
                    RoomSettingsSheet()
                    
                case .shareRoom:
                    ShareRoomSheet()
                    
                case .settings:
                    SettingsSheet()
                    
                case .profile:
                    ProfileSheet()
                    
                case .search:
                    SearchSheet()
                    
                case .filters:
                    FiltersSheet()
                }
            }
            .presentationDragIndicator(.visible)
            .presentationDetents([.medium, .large])
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleTabChange(from oldTab: NavigationTab, to newTab: NavigationTab) {
        // Haptic feedback
        hapticFeedback.selectionChanged()
        
        // Announce tab change for accessibility
        navigationController.announceNavigationChange("Switched to \(newTab.title)")
        
        // Analytics tracking
        logDebug("Tab changed", category: .general, context: LogContext(customData: [
            "from_tab": oldTab.rawValue,
            "to_tab": newTab.rawValue
        ]))
    }
    
    private func handleOrientationChange() {
        // Handle any orientation-specific logic
        withAnimation(.easeInOut(duration: 0.3)) {
            // Force view refresh if needed
        }
    }
}

// MARK: - Tab Item View

private struct TabItemView: View {
    let tab: NavigationTab
    let isSelected: Bool
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                .scaleEffect(isSelected && !reduceMotion ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
            
            Text(tab.title)
                .font(.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
        }
        .foregroundColor(isSelected ? .accentColor : .secondary)
        .accessibilityLabel(tab.accessibilityLabel)
        .accessibilityHint(tab.accessibilityHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Transition Overlay

private struct TransitionOverlay: View {
    @State private var opacity: Double = 0
    
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.15)) {
                    opacity = 1
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        opacity = 0
                    }
                }
            }
    }
}

// MARK: - Placeholder Views

private struct DiscoverView: View {
    var body: some View {
        Text("Discover View")
            .navigationTitle("Discover")
    }
}

private struct ARViewContainer: View {
    var body: some View {
        Text("AR View Container")
            .navigationTitle("AR View")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RoomsView: View {
    var body: some View {
        Text("Rooms View")
            .navigationTitle("My Rooms")
    }
}

private struct FavoritesView: View {
    var body: some View {
        Text("Favorites View")
            .navigationTitle("Favorites")
    }
}

private struct ProfileView: View {
    var body: some View {
        Text("Profile View")
            .navigationTitle("Profile")
    }
}

private struct FurnitureDetailView: View {
    let item: FurnitureItem
    
    var body: some View {
        Text("Furniture Detail: \(item.name)")
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.large)
    }
}

private struct RoomDetailView: View {
    let room: RoomDesign
    
    var body: some View {
        Text("Room Detail: \(room.name)")
            .navigationTitle(room.name)
    }
}

private struct CategoryView: View {
    let category: FurnitureCategory
    
    var body: some View {
        Text("Category: \(category.displayName)")
            .navigationTitle(category.displayName)
    }
}

private struct SearchResultsView: View {
    let query: String
    
    var body: some View {
        Text("Search Results for: \(query)")
            .navigationTitle("Search Results")
    }
}

private struct UserProfileView: View {
    let userID: String
    
    var body: some View {
        Text("User Profile: \(userID)")
            .navigationTitle("Profile")
    }
}

private struct SettingsView: View {
    var body: some View {
        Text("Settings")
            .navigationTitle("Settings")
    }
}

private struct AboutView: View {
    var body: some View {
        Text("About ARchitect")
            .navigationTitle("About")
    }
}

// MARK: - Sheet Views

private struct FurnitureCatalogSheet: View {
    @EnvironmentObject private var navigationController: MainNavigationController
    
    var body: some View {
        Text("Furniture Catalog Sheet")
            .navigationTitle("Furniture Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        navigationController.dismissSheet()
                    }
                }
            }
    }
}

private struct RoomSettingsSheet: View {
    @EnvironmentObject private var navigationController: MainNavigationController
    
    var body: some View {
        Text("Room Settings Sheet")
            .navigationTitle("Room Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        navigationController.dismissSheet()
                    }
                }
            }
    }
}

private struct ShareRoomSheet: View {
    @EnvironmentObject private var navigationController: MainNavigationController
    
    var body: some View {
        Text("Share Room Sheet")
            .navigationTitle("Share Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        navigationController.dismissSheet()
                    }
                }
            }
    }
}

private struct SettingsSheet: View {
    @EnvironmentObject private var navigationController: MainNavigationController
    
    var body: some View {
        Text("Settings Sheet")
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        navigationController.dismissSheet()
                    }
                }
            }
    }
}

private struct ProfileSheet: View {
    @EnvironmentObject private var navigationController: MainNavigationController
    
    var body: some View {
        Text("Profile Sheet")
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        navigationController.dismissSheet()
                    }
                }
            }
    }
}

private struct SearchSheet: View {
    @EnvironmentObject private var navigationController: MainNavigationController
    
    var body: some View {
        Text("Search Sheet")
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        navigationController.dismissSheet()
                    }
                }
            }
    }
}

private struct FiltersSheet: View {
    @EnvironmentObject private var navigationController: MainNavigationController
    
    var body: some View {
        Text("Filters Sheet")
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        navigationController.dismissSheet()
                    }
                }
            }
    }
}