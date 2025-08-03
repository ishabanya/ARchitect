import SwiftUI
import Combine
import Foundation

/// ViewModel for the main content view following MVVM pattern
@MainActor
final class ContentViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var showingLogViewer = false
    @Published var showingARStatus = false
    @Published var showingRoomScanner = false
    @Published var showingMeasurementTools = false
    @Published var showingFurnitureCatalog = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var sessionState: ARSessionState = .unknown
    @Published var trackingQuality: ARTrackingQuality = .unknown
    @Published var detectedPlanesCount = 0
    
    // MARK: - Dependencies
    private let arSessionManager: ARSessionManagerProtocol
    private let analyticsManager: AnalyticsManagerProtocol
    private let errorManager: ErrorManagerProtocol
    private let loggingSystem: LoggingSystemProtocol
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Lifecycle
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Initialization
    init(
        arSessionManager: ARSessionManagerProtocol = ARSessionManager(),
        analyticsManager: AnalyticsManagerProtocol = AnalyticsManager.shared,
        errorManager: ErrorManagerProtocol = ErrorManager.shared,
        loggingSystem: LoggingSystemProtocol = LoggingSystem.shared
    ) {
        self.arSessionManager = arSessionManager
        self.analyticsManager = analyticsManager
        self.errorManager = errorManager
        self.loggingSystem = loggingSystem
        
        setupBindings()
    }
    
    // MARK: - Public Methods
    func onAppear() {
        Task {
            await initializeApp()
        }
    }
    
    func startRoomScanner() {
        showingRoomScanner = true
        analyticsManager.trackUserEngagement(.featureUsed, parameters: ["feature": "room_scanner"])
    }
    
    func startMeasurementTools() {
        showingMeasurementTools = true
        analyticsManager.trackUserEngagement(.featureUsed, parameters: ["feature": "measurement_tools"])
    }
    
    func showFurnitureCatalog() {
        showingFurnitureCatalog = true
        analyticsManager.trackUserEngagement(.featureUsed, parameters: ["feature": "furniture_catalog"])
    }
    
    func showARStatus() {
        showingARStatus = true
        analyticsManager.trackUserEngagement(.featureUsed, parameters: ["feature": "ar_status"])
    }
    
    func showLogViewer() {
        showingLogViewer = true
        analyticsManager.trackUserEngagement(.featureUsed, parameters: ["feature": "log_viewer"])
    }
    
    func triggerNetworkError() {
        errorManager.reportError(NetworkError.noConnection)
        loggingSystem.logError("Demo network error triggered", category: .network)
    }
    
    func triggerARError() {
        errorManager.reportError(ARError.trackingLost)
        loggingSystem.logError("Demo AR error triggered", category: .ar)
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Bind AR session state changes
        arSessionManager.sessionStatePublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.sessionState, on: self)
            .store(in: &cancellables)
        
        arSessionManager.trackingQualityPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.trackingQuality, on: self)
            .store(in: &cancellables)
        
        arSessionManager.detectedPlanesPublisher
            .receive(on: DispatchQueue.main)
            .map { $0.count }
            .assign(to: \.detectedPlanesCount, on: self)
            .store(in: &cancellables)
        
        // Bind error state
        errorManager.errorPublisher
            .receive(on: DispatchQueue.main)
            .compactMap { $0?.localizedDescription }
            .assign(to: \.errorMessage, on: self)
            .store(in: &cancellables)
    }
    
    private func initializeApp() async {
        isLoading = true
        
        do {
            // Initialize logging system
            try await loggingSystem.initialize()
            
            // Start AR session
            try await arSessionManager.startSession()
            
            // Log app launch
            loggingSystem.logInfo("App launched successfully", category: .general, context: LogContext(customData: [
                "launch_time": Date().timeIntervalSince1970,
                "environment": AppEnvironment.current.rawValue,
                "is_first_launch": !UserDefaults.standard.bool(forKey: "has_launched_before")
            ]))
            
            // Mark first launch
            UserDefaults.standard.set(true, forKey: "has_launched_before")
            
            analyticsManager.trackScreenView("ContentView")
            
        } catch {
            errorManager.reportError(error)
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

// MARK: - Supporting Types
enum ARSessionState {
    case unknown
    case initializing
    case running
    case paused
    case interrupted
    case failed
    
    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .initializing: return "Initializing"
        case .running: return "Running"
        case .paused: return "Paused"
        case .interrupted: return "Interrupted"
        case .failed: return "Failed"
        }
    }
}

enum ARTrackingQuality {
    case unknown
    case poor
    case fair
    case good
    case excellent
    
    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .poor: return "Poor"
        case .fair: return "Fair"
        case .good: return "Good"
        case .excellent: return "Excellent"
        }
    }
}