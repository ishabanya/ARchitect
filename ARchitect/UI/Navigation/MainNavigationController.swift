import SwiftUI
import UIKit
import Combine

// MARK: - Main Navigation Controller

@MainActor
public class MainNavigationController: ObservableObject {
    
    // MARK: - Properties
    @Published public var selectedTab: NavigationTab = .discover
    @Published public var isARViewActive = false
    @Published public var showingSheet = false
    @Published public var currentSheet: NavigationSheet?
    @Published public var navigationPath = NavigationPath()
    
    // Navigation state
    @Published public var canGoBack = false
    @Published public var canGoForward = false
    @Published public var currentTitle = ""
    
    // Orientation support
    @Published public var orientation: UIDeviceOrientation = .portrait
    @Published public var isLandscape = false
    
    // Animation control
    @Published public var transitionInProgress = false
    
    private var cancellables = Set<AnyCancellable>()
    private let hapticFeedback = HapticFeedbackManager.shared
    
    public init() {
        setupObservers()
        setupOrientationObserver()
        
        logInfo("Main navigation controller initialized", category: .general)
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Monitor navigation path changes
        $navigationPath
            .sink { [weak self] path in
                self?.updateNavigationState(path: path)
            }
            .store(in: &cancellables)
        
        // Monitor tab changes
        $selectedTab
            .sink { [weak self] tab in
                self?.handleTabChange(tab)
            }
            .store(in: &cancellables)
    }
    
    private func setupOrientationObserver() {
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateOrientation()
            }
            .store(in: &cancellables)
        
        updateOrientation()
    }
    
    private func updateOrientation() {
        let currentOrientation = UIDevice.current.orientation
        
        if currentOrientation != .unknown && currentOrientation != .faceUp && currentOrientation != .faceDown {
            orientation = currentOrientation
            isLandscape = currentOrientation.isLandscape
            
            logDebug("Orientation changed", category: .general, context: LogContext(customData: [
                "orientation": currentOrientation.rawValue,
                "is_landscape": isLandscape
            ]))
        }
    }
    
    // MARK: - Tab Navigation
    
    public func selectTab(_ tab: NavigationTab) {
        guard tab != selectedTab else { return }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            transitionInProgress = true
        }
        
        hapticFeedback.selectionChanged()
        selectedTab = tab
        
        // Clear navigation path when switching tabs
        navigationPath = NavigationPath()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation {
                self.transitionInProgress = false
            }
        }
        
        logDebug("Tab selected", category: .general, context: LogContext(customData: [
            "tab": tab.rawValue
        ]))
    }
    
    private func handleTabChange(_ tab: NavigationTab) {
        currentTitle = tab.title
        
        // Handle special tab behaviors
        switch tab {
        case .ar:
            isARViewActive = true
        default:
            isARViewActive = false
        }
    }
    
    // MARK: - Navigation Actions
    
    public func navigateTo<T: Hashable>(_ destination: T) {
        withAnimation(.easeInOut(duration: 0.25)) {
            navigationPath.append(destination)
        }
        
        hapticFeedback.impact(.light)
        
        logDebug("Navigated to destination", category: .general, context: LogContext(customData: [
            "destination": String(describing: destination)
        ]))
    }
    
    public func goBack() {
        guard canGoBack else { return }
        
        withAnimation(.easeInOut(duration: 0.25)) {
            navigationPath.removeLast()
        }
        
        hapticFeedback.impact(.light)
        
        logDebug("Navigated back", category: .general)
    }
    
    public func popToRoot() {
        guard !navigationPath.isEmpty else { return }
        
        withAnimation(.easeInOut(duration: 0.4)) {
            navigationPath = NavigationPath()
        }
        
        hapticFeedback.impact(.medium)
        
        logDebug("Popped to root", category: .general)
    }
    
    private func updateNavigationState(path: NavigationPath) {
        canGoBack = !path.isEmpty
        canGoForward = false // SwiftUI NavigationPath doesn't support forward navigation
    }
    
    // MARK: - Sheet Presentation
    
    public func presentSheet(_ sheet: NavigationSheet) {
        currentSheet = sheet
        showingSheet = true
        
        hapticFeedback.impact(.light)
        
        logDebug("Presented sheet", category: .general, context: LogContext(customData: [
            "sheet": sheet.rawValue
        ]))
    }
    
    public func dismissSheet() {
        withAnimation {
            showingSheet = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.currentSheet = nil
        }
        
        hapticFeedback.impact(.light)
        
        logDebug("Dismissed sheet", category: .general)
    }
    
    // MARK: - AR Navigation
    
    public func enterARMode() {
        selectTab(.ar)
        
        logInfo("Entered AR mode", category: .general)
    }
    
    public func exitARMode() {
        selectTab(.discover)
        
        logInfo("Exited AR mode", category: .general)
    }
    
    // MARK: - Quick Actions
    
    public func performQuickAction(_ action: QuickAction) {
        hapticFeedback.impact(.medium)
        
        switch action {
        case .scanRoom:
            enterARMode()
            // Additional scan room logic would go here
            
        case .addFurniture:
            presentSheet(.furnitureCatalog)
            
        case .saveRoom:
            // Save room logic would go here
            break
            
        case .shareRoom:
            presentSheet(.shareRoom)
            
        case .settings:
            presentSheet(.settings)
        }
        
        logDebug("Performed quick action", category: .general, context: LogContext(customData: [
            "action": action.rawValue
        ]))
    }
    
    // MARK: - Accessibility
    
    public func announceNavigationChange(_ message: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            UIAccessibility.post(notification: .screenChanged, argument: message)
        }
    }
    
    public func announceImportantAction(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

// MARK: - Navigation Types

public enum NavigationTab: String, CaseIterable {
    case discover = "discover"
    case ar = "ar"
    case rooms = "rooms"
    case favorites = "favorites"
    case profile = "profile"
    
    public var title: String {
        switch self {
        case .discover: return "Discover"
        case .ar: return "AR View"
        case .rooms: return "My Rooms"
        case .favorites: return "Favorites"
        case .profile: return "Profile"
        }
    }
    
    public var systemImage: String {
        switch self {
        case .discover: return "square.grid.2x2"
        case .ar: return "viewfinder"
        case .rooms: return "house"
        case .favorites: return "heart"
        case .profile: return "person"
        }
    }
    
    public var accessibilityLabel: String {
        return "\(title) tab"
    }
    
    public var accessibilityHint: String {
        switch self {
        case .discover: return "Browse furniture catalog"
        case .ar: return "View and place furniture in augmented reality"
        case .rooms: return "View your saved room designs"
        case .favorites: return "View your favorite furniture items"
        case .profile: return "View and edit your profile"
        }
    }
}

public enum NavigationSheet: String {
    case furnitureCatalog = "furniture_catalog"
    case furnitureDetail = "furniture_detail"
    case roomSettings = "room_settings"
    case shareRoom = "share_room"
    case settings = "settings"
    case profile = "profile"
    case search = "search"
    case filters = "filters"
    
    public var title: String {
        switch self {
        case .furnitureCatalog: return "Furniture Catalog"
        case .furnitureDetail: return "Furniture Details"
        case .roomSettings: return "Room Settings"
        case .shareRoom: return "Share Room"
        case .settings: return "Settings"
        case .profile: return "Profile"
        case .search: return "Search"
        case .filters: return "Filters"
        }
    }
}

public enum QuickAction: String, CaseIterable {
    case scanRoom = "scan_room"
    case addFurniture = "add_furniture"
    case saveRoom = "save_room"
    case shareRoom = "share_room"
    case settings = "settings"
    
    public var title: String {
        switch self {
        case .scanRoom: return "Scan Room"
        case .addFurniture: return "Add Furniture"
        case .saveRoom: return "Save Room"
        case .shareRoom: return "Share Room"
        case .settings: return "Settings"
        }
    }
    
    public var systemImage: String {
        switch self {
        case .scanRoom: return "viewfinder.circle"
        case .addFurniture: return "plus.circle"
        case .saveRoom: return "square.and.arrow.down"
        case .shareRoom: return "square.and.arrow.up"
        case .settings: return "gear"
        }
    }
}

// MARK: - Navigation Destination

public enum NavigationDestination: Hashable {
    case furnitureDetail(FurnitureItem)
    case roomDetail(RoomDesign)
    case categoryView(FurnitureCategory)
    case searchResults(String)
    case userProfile(String)
    case settings
    case about
    
    public var title: String {
        switch self {
        case .furnitureDetail: return "Furniture Details"
        case .roomDetail: return "Room Details"
        case .categoryView(let category): return category.displayName
        case .searchResults: return "Search Results"
        case .userProfile: return "Profile"
        case .settings: return "Settings"
        case .about: return "About"
        }
    }
}