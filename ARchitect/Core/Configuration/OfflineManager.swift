import Foundation
import Network
import Combine

// MARK: - Offline Configuration
struct OfflineConfiguration {
    let enableOfflineMode: Bool
    let localDataRetentionDays: Int
    let maxLocalStorageMB: Int
    let syncOnReconnect: Bool
    let backgroundSyncEnabled: Bool
    let conflictResolutionStrategy: ConflictResolutionStrategy
    let localModelPath: String
    let fallbackFeatures: [OfflineFeature]
    
    enum ConflictResolutionStrategy {
        case clientWins
        case serverWins
        case manualResolve
        case mostRecent
    }
    
    enum OfflineFeature {
        case basicARScanning
        case localObjectRecognition
        case offlineLayoutSuggestions
        case localDataStorage
        case cachedModels
        case basicErrorLogging
    }
    
    static func forEnvironment(_ environment: AppEnvironment) -> OfflineConfiguration {
        switch environment {
        case .development:
            return OfflineConfiguration(
                enableOfflineMode: true,
                localDataRetentionDays: 30,
                maxLocalStorageMB: 500,
                syncOnReconnect: true,
                backgroundSyncEnabled: true,
                conflictResolutionStrategy: .mostRecent,
                localModelPath: "Models/Local",
                fallbackFeatures: [.basicARScanning, .localObjectRecognition, .localDataStorage, .basicErrorLogging]
            )
        case .staging:
            return OfflineConfiguration(
                enableOfflineMode: true,
                localDataRetentionDays: 14,
                maxLocalStorageMB: 300,
                syncOnReconnect: true,
                backgroundSyncEnabled: false,
                conflictResolutionStrategy: .serverWins,
                localModelPath: "Models/Local",
                fallbackFeatures: [.basicARScanning, .localDataStorage, .basicErrorLogging]
            )
        case .production:
            return OfflineConfiguration(
                enableOfflineMode: false,
                localDataRetentionDays: 7,
                maxLocalStorageMB: 100,
                syncOnReconnect: true,
                backgroundSyncEnabled: false,
                conflictResolutionStrategy: .serverWins,
                localModelPath: "Models/Local",
                fallbackFeatures: [.basicARScanning, .basicErrorLogging]
            )
        }
    }
}

// MARK: - Network Status
enum NetworkStatus {
    case connected(ConnectionType)
    case disconnected
    case unknown
    
    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case other
    }
    
    var isConnected: Bool {
        switch self {
        case .connected:
            return true
        case .disconnected, .unknown:
            return false
        }
    }
}

// MARK: - Offline Manager
class OfflineManager: ObservableObject {
    static let shared = OfflineManager()
    
    @Published private(set) var networkStatus: NetworkStatus = .unknown
    @Published private(set) var isOfflineMode = false
    @Published private(set) var pendingSyncItems: [SyncItem] = []
    @Published private(set) var lastSyncTime: Date?
    @Published private(set) var offlineDataSize: Int = 0
    
    private let configuration: OfflineConfiguration
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    private let errorManager = ErrorManager.shared
    private let localDataManager = LocalDataManager()
    private var cancellables = Set<AnyCancellable>()
    
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 300 // 5 minutes
    
    struct SyncItem {
        let id: UUID
        let type: SyncItemType
        let data: Data
        let timestamp: Date
        let priority: SyncPriority
        let retryCount: Int
        
        enum SyncItemType {
            case userData
            case sessionData
            case errorLog
            case analyticsEvent
            case modelUpdate
        }
        
        enum SyncPriority {
            case low
            case medium
            case high
            case critical
        }
    }
    
    private init() {
        self.configuration = OfflineConfiguration.forEnvironment(AppEnvironment.current)
        
        setupNetworkMonitoring()
        setupOfflineSupport()
        startPeriodicSync()
    }
    
    deinit {
        networkMonitor.cancel()
        syncTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func enableOfflineMode() {
        guard configuration.enableOfflineMode else {
            errorManager.reportError(OfflineError.offlineModeDisabled)
            return
        }
        
        isOfflineMode = true
        prepareOfflineResources()
    }
    
    func disableOfflineMode() {
        isOfflineMode = false
        syncPendingData()
    }
    
    func addToSyncQueue(_ item: SyncItem) {
        pendingSyncItems.append(item)
        
        // Try immediate sync if connected
        if networkStatus.isConnected {
            Task {
                await syncPendingData()
            }
        }
    }
    
    func forceSyncNow() async {
        await syncPendingData()
    }
    
    func clearOfflineData() {
        localDataManager.clearAllData()
        pendingSyncItems.removeAll()
        offlineDataSize = 0
    }
    
    func getOfflineCapabilities() -> [OfflineConfiguration.OfflineFeature] {
        return configuration.fallbackFeatures
    }
    
    func isFeatureAvailableOffline(_ feature: OfflineConfiguration.OfflineFeature) -> Bool {
        return configuration.fallbackFeatures.contains(feature)
    }
    
    func getCachedData<T: Codable>(for key: String, type: T.Type) -> T? {
        return localDataManager.getData(for: key, type: type)
    }
    
    func setCachedData<T: Codable>(_ data: T, for key: String) {
        localDataManager.setData(data, for: key)
        updateOfflineDataSize()
    }
    
    // MARK: - Private Methods
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.handleNetworkPathUpdate(path)
            }
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    private func setupOfflineSupport() {
        // Prepare offline resources
        if configuration.enableOfflineMode {
            prepareOfflineResources()
        }
        
        // Monitor app state changes
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.handleAppDidEnterBackground()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.handleAppWillEnterForeground()
            }
            .store(in: &cancellables)
    }
    
    private func handleNetworkPathUpdate(_ path: NWPath) {
        let previousStatus = networkStatus
        
        if path.status == .satisfied {
            let connectionType: NetworkStatus.ConnectionType
            
            if path.usesInterfaceType(.wifi) {
                connectionType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                connectionType = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                connectionType = .ethernet
            } else {
                connectionType = .other
            }
            
            networkStatus = .connected(connectionType)
        } else {
            networkStatus = .disconnected
        }
        
        // Handle network status changes
        if previousStatus != networkStatus {
            handleNetworkStatusChange(from: previousStatus, to: networkStatus)
        }
    }
    
    private func handleNetworkStatusChange(from previous: NetworkStatus, to current: NetworkStatus) {
        switch (previous, current) {
        case (.disconnected, .connected), (.unknown, .connected):
            // Network became available
            handleNetworkReconnected()
            
        case (.connected, .disconnected):
            // Network became unavailable
            handleNetworkDisconnected()
            
        default:
            break
        }
    }
    
    private func handleNetworkReconnected() {
        // Sync pending data if enabled
        if configuration.syncOnReconnect {
            Task {
                await syncPendingData()
            }
        }
        
        // Disable offline mode if it was automatically enabled
        if isOfflineMode && configuration.enableOfflineMode {
            // Check if we should stay in offline mode or return to online
            evaluateOfflineModeStatus()
        }
    }
    
    private func handleNetworkDisconnected() {
        // Enable offline mode if supported
        if configuration.enableOfflineMode && !isOfflineMode {
            enableOfflineMode()
        }
        
        // Report network error
        errorManager.reportError(NetworkError.noConnection, context: [
            "offline_mode_enabled": isOfflineMode,
            "pending_sync_items": pendingSyncItems.count
        ])
    }
    
    private func evaluateOfflineModeStatus() {
        // Logic to determine if we should stay offline or go online
        // This could be based on user preference, data usage, etc.
        
        if networkStatus.isConnected {
            // For now, automatically go online when network is available
            disableOfflineMode()
        }
    }
    
    private func prepareOfflineResources() {
        // Download essential models and data for offline use
        Task {
            await downloadOfflineResources()
        }
        
        // Ensure local storage is set up
        localDataManager.setupOfflineStorage()
        
        // Update offline data size
        updateOfflineDataSize()
    }
    
    private func downloadOfflineResources() async {
        // Download local AI models if feature is enabled
        if configuration.fallbackFeatures.contains(.localObjectRecognition) {
            await downloadLocalObjectRecognitionModel()
        }
        
        if configuration.fallbackFeatures.contains(.offlineLayoutSuggestions) {
            await downloadLocalLayoutModel()
        }
        
        // Cache essential app data
        await cacheEssentialData()
    }
    
    private func downloadLocalObjectRecognitionModel() async {
        // Download and cache local object recognition model
        // This would typically download from a CDN or app bundle
        let modelPath = configuration.localModelPath + "/ObjectRecognition.mlmodel"
        
        do {
            // Simulate model download
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            
            // Store model path for offline use
            localDataManager.setData(modelPath, for: "local_object_model_path")
            
        } catch {
            errorManager.reportError(OfflineError.resourceDownloadFailed("ObjectRecognition"))
        }
    }
    
    private func downloadLocalLayoutModel() async {
        // Download and cache local layout suggestion model
        let modelPath = configuration.localModelPath + "/LayoutSuggestions.mlmodel"
        
        do {
            // Simulate model download
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            
            // Store model path for offline use
            localDataManager.setData(modelPath, for: "local_layout_model_path")
            
        } catch {
            errorManager.reportError(OfflineError.resourceDownloadFailed("LayoutSuggestions"))
        }
    }
    
    private func cacheEssentialData() async {
        // Cache frequently used data for offline access
        let essentialData = [
            "user_preferences": getUserPreferences(),
            "app_settings": getAppSettings(),
            "recent_projects": getRecentProjects()
        ]
        
        for (key, data) in essentialData {
            localDataManager.setData(data, for: key)
        }
    }
    
    private func startPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            if self?.networkStatus.isConnected == true {
                Task {
                    await self?.syncPendingData()
                }
            }
        }
    }
    
    private func syncPendingData() async {
        guard networkStatus.isConnected else { return }
        guard !pendingSyncItems.isEmpty else { return }
        
        let sortedItems = pendingSyncItems.sorted { item1, item2 in
            // Sort by priority first, then by timestamp
            if item1.priority != item2.priority {
                return item1.priority.rawValue > item2.priority.rawValue
            }
            return item1.timestamp < item2.timestamp
        }
        
        var successfulSyncs: [UUID] = []
        var failedSyncs: [(UUID, Error)] = []
        
        for item in sortedItems {
            do {
                try await syncItem(item)
                successfulSyncs.append(item.id)
            } catch {
                failedSyncs.append((item.id, error))
                
                // Increment retry count and re-queue if under limit
                let maxRetries = 3
                if item.retryCount < maxRetries {
                    let updatedItem = SyncItem(
                        id: item.id,
                        type: item.type,
                        data: item.data,
                        timestamp: item.timestamp,
                        priority: item.priority,
                        retryCount: item.retryCount + 1
                    )
                    
                    // Re-add to queue with updated retry count
                    if let index = pendingSyncItems.firstIndex(where: { $0.id == item.id }) {
                        pendingSyncItems[index] = updatedItem
                    }
                } else {
                    // Max retries reached, report error
                    errorManager.reportError(OfflineError.syncFailed(item.type))
                }
            }
        }
        
        // Remove successfully synced items
        pendingSyncItems.removeAll { item in
            successfulSyncs.contains(item.id)
        }
        
        // Update last sync time
        if !successfulSyncs.isEmpty {
            lastSyncTime = Date()
        }
    }
    
    private func syncItem(_ item: SyncItem) async throws {
        // Simulate network sync operation
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
        
        switch item.type {
        case .userData:
            try await syncUserData(item.data)
        case .sessionData:
            try await syncSessionData(item.data)
        case .errorLog:
            try await syncErrorLog(item.data)
        case .analyticsEvent:
            try await syncAnalyticsEvent(item.data)
        case .modelUpdate:
            try await syncModelUpdate(item.data)
        }
    }
    
    private func syncUserData(_ data: Data) async throws {
        // Sync user data to server
        // Implementation would depend on your API
    }
    
    private func syncSessionData(_ data: Data) async throws {
        // Sync session data to server
        // Implementation would depend on your API
    }
    
    private func syncErrorLog(_ data: Data) async throws {
        // Sync error logs to server
        // Implementation would depend on your API
    }
    
    private func syncAnalyticsEvent(_ data: Data) async throws {
        // Sync analytics events to server
        // Implementation would depend on your API
    }
    
    private func syncModelUpdate(_ data: Data) async throws {
        // Sync model updates to server
        // Implementation would depend on your API
    }
    
    private func handleAppDidEnterBackground() {
        // Save current state
        localDataManager.persistPendingData()
        
        // Schedule background sync if enabled
        if configuration.backgroundSyncEnabled && networkStatus.isConnected {
            scheduleBackgroundSync()
        }
    }
    
    private func handleAppWillEnterForeground() {
        // Check network status
        networkMonitor.start(queue: networkQueue)
        
        // Sync if needed
        if networkStatus.isConnected && !pendingSyncItems.isEmpty {
            Task {
                await syncPendingData()
            }
        }
    }
    
    private func scheduleBackgroundSync() {
        // Schedule background task for sync
        // This would use BGTaskScheduler in a real app
    }
    
    private func updateOfflineDataSize() {
        offlineDataSize = localDataManager.getTotalDataSize()
        
        // Check if we're approaching storage limits
        let maxSizeMB = configuration.maxLocalStorageMB
        let currentSizeMB = offlineDataSize / (1024 * 1024)
        
        if currentSizeMB > maxSizeMB {
            cleanupOldData()
        }
    }
    
    private func cleanupOldData() {
        let retentionDays = configuration.localDataRetentionDays
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(retentionDays * 24 * 3600))
        
        localDataManager.cleanupDataBefore(cutoffDate)
        updateOfflineDataSize()
    }
    
    // MARK: - Helper Methods
    
    private func getUserPreferences() -> [String: Any] {
        // Return user preferences for caching
        return [:]
    }
    
    private func getAppSettings() -> [String: Any] {
        // Return app settings for caching
        return [:]
    }
    
    private func getRecentProjects() -> [String: Any] {
        // Return recent projects for caching
        return [:]
    }
}

// MARK: - Offline Errors
enum OfflineError: Error, AppErrorProtocol {
    case offlineModeDisabled
    case resourceDownloadFailed(String)
    case syncFailed(OfflineManager.SyncItem.SyncItemType)
    case storageQuotaExceeded
    case dataCorrupted
    
    var errorCode: String {
        switch self {
        case .offlineModeDisabled:
            return "OFFLINE_MODE_DISABLED"
        case .resourceDownloadFailed(let resource):
            return "OFFLINE_RESOURCE_DOWNLOAD_FAILED_\(resource.uppercased())"
        case .syncFailed(let type):
            return "OFFLINE_SYNC_FAILED_\(type)".uppercased()
        case .storageQuotaExceeded:
            return "OFFLINE_STORAGE_QUOTA_EXCEEDED"
        case .dataCorrupted:
            return "OFFLINE_DATA_CORRUPTED"
        }
    }
    
    var errorCategory: ErrorCategory {
        return .network
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .offlineModeDisabled:
            return .medium
        case .resourceDownloadFailed:
            return .high
        case .syncFailed:
            return .medium
        case .storageQuotaExceeded:
            return .high
        case .dataCorrupted:
            return .critical
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .offlineModeDisabled, .storageQuotaExceeded:
            return false
        case .resourceDownloadFailed, .syncFailed, .dataCorrupted:
            return true
        }
    }
    
    var userMessage: String {
        switch self {
        case .offlineModeDisabled:
            return "Offline mode is not available in this version"
        case .resourceDownloadFailed(let resource):
            return "Failed to download \(resource) for offline use"
        case .syncFailed:
            return "Failed to sync data when connection was restored"
        case .storageQuotaExceeded:
            return "Offline storage limit exceeded. Please clear some data."
        case .dataCorrupted:
            return "Offline data appears to be corrupted"
        }
    }
    
    var recoveryAction: RecoveryAction? {
        switch self {
        case .offlineModeDisabled:
            return .none
        case .resourceDownloadFailed, .syncFailed:
            return .retry
        case .storageQuotaExceeded:
            return .contactSupport
        case .dataCorrupted:
            return .restartSession
        }
    }
    
    var errorDescription: String? {
        return userMessage
    }
}

// MARK: - Local Data Manager
class LocalDataManager {
    private let fileManager = FileManager.default
    private let offlineDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init() {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        offlineDirectory = documentsDirectory.appendingPathComponent("OfflineData")
        
        setupOfflineStorage()
    }
    
    func setupOfflineStorage() {
        try? fileManager.createDirectory(at: offlineDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    func setData<T: Codable>(_ data: T, for key: String) {
        let fileURL = offlineDirectory.appendingPathComponent("\(key).json")
        
        do {
            let encodedData = try encoder.encode(data)
            try encodedData.write(to: fileURL)
        } catch {
            print("Failed to save offline data for key \(key): \(error)")
        }
    }
    
    func getData<T: Codable>(for key: String, type: T.Type) -> T? {
        let fileURL = offlineDirectory.appendingPathComponent("\(key).json")
        
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        return try? decoder.decode(type, from: data)
    }
    
    func removeData(for key: String) {
        let fileURL = offlineDirectory.appendingPathComponent("\(key).json")
        try? fileManager.removeItem(at: fileURL)
    }
    
    func clearAllData() {
        try? fileManager.removeItem(at: offlineDirectory)
        setupOfflineStorage()
    }
    
    func getTotalDataSize() -> Int {
        guard let files = try? fileManager.contentsOfDirectory(at: offlineDirectory, includingPropertiesForKeys: [.fileSizeKey], options: []) else {
            return 0
        }
        
        return files.compactMap { url in
            try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        }.reduce(0, +)
    }
    
    func cleanupDataBefore(_ date: Date) {
        guard let files = try? fileManager.contentsOfDirectory(at: offlineDirectory, includingPropertiesForKeys: [.creationDateKey], options: []) else {
            return
        }
        
        for file in files {
            if let resourceValues = try? file.resourceValues(forKeys: [.creationDateKey]),
               let creationDate = resourceValues.creationDate,
               creationDate < date {
                try? fileManager.removeItem(at: file)
            }
        }
    }
    
    func persistPendingData() {
        // Save any pending data to persistent storage
        // This would be called when the app goes to background
    }
}

// MARK: - Extensions
extension OfflineConfiguration.OfflineFeature: Equatable {}

extension OfflineManager.SyncItem.SyncPriority {
    var rawValue: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .critical: return 3
        }
    }
}