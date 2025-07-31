import Foundation
import Combine
import Network

// MARK: - Configuration Update Info
struct ConfigurationUpdate {
    let id: UUID
    let version: String
    let timestamp: Date
    let environment: AppEnvironment
    let updateType: UpdateType
    let changes: [ConfigurationChange]
    let signature: String? // For security verification
    let rolloutPercentage: Double
    let minimumAppVersion: String?
    let expirationDate: Date?
    
    enum UpdateType {
        case full
        case partial
        case hotfix
        case rollback
    }
}

// MARK: - Configuration Change
struct ConfigurationChange {
    let path: String
    let oldValue: Any?
    let newValue: Any
    let changeType: ChangeType
    let priority: Priority
    let requiresRestart: Bool
    
    enum ChangeType {
        case add
        case update
        case delete
    }
    
    enum Priority {
        case low
        case medium
        case high
        case critical
    }
}

// MARK: - Sync Status
enum SyncStatus {
    case idle
    case syncing
    case success(Date)
    case failed(Error, Date)
    case noConnection
}

// MARK: - Configuration Sync Manager
class ConfigurationSyncManager: ObservableObject {
    static let shared = ConfigurationSyncManager()
    
    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published private(set) var lastSyncTime: Date?
    @Published private(set) var pendingUpdates: [ConfigurationUpdate] = []
    @Published private(set) var appliedUpdates: [ConfigurationUpdate] = []
    @Published private(set) var isAutoSyncEnabled = true
    
    private let configurationManager = ConfigurationManager.shared
    private let validator = ConfigurationValidator.shared
    private let errorManager = ErrorManager.shared
    private let secureStorage = SecureConfigurationStorage.shared
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "ConfigSyncNetwork")
    
    private var syncTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private let syncInterval: TimeInterval = 300 // 5 minutes
    private let maxRetries = 3
    private let syncEndpoint = "/config/sync"
    
    private init() {
        setupNetworkMonitoring()
        setupAutoSync()
        loadAppliedUpdates()
    }
    
    deinit {
        networkMonitor.cancel()
        syncTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func syncNow() async {
        await performSync(force: true)
    }
    
    func enableAutoSync() {
        isAutoSyncEnabled = true
        startAutoSync()
    }
    
    func disableAutoSync() {
        isAutoSyncEnabled = false
        stopAutoSync()
    }
    
    func applyUpdate(_ update: ConfigurationUpdate) async -> Bool {
        guard validateUpdate(update) else {
            errorManager.reportError(ConfigurationSyncError.invalidUpdate(update.id))
            return false
        }
        
        // Check if update is already applied
        if appliedUpdates.contains(where: { $0.id == update.id }) {
            return true
        }
        
        // Backup current configuration
        let backupId = UUID()
        await backupCurrentConfiguration(backupId: backupId)
        
        do {
            // Apply changes
            try await applyChanges(update.changes)
            
            // Validate configuration after changes
            let validationResult = await validator.validateAll()
            
            if !validationResult.isValid {
                // Rollback on validation failure
                await rollbackToBackup(backupId: backupId)
                errorManager.reportError(ConfigurationSyncError.validationFailedAfterUpdate(update.id))
                return false
            }
            
            // Mark as applied
            appliedUpdates.append(update)
            saveAppliedUpdates()
            
            // Remove from pending
            pendingUpdates.removeAll { $0.id == update.id }
            
            return true
            
        } catch {
            // Rollback on error
            await rollbackToBackup(backupId: backupId)
            errorManager.reportError(ConfigurationSyncError.updateApplicationFailed(update.id, error))
            return false
        }
    }
    
    func rollbackUpdate(_ updateId: UUID) async -> Bool {
        guard let update = appliedUpdates.first(where: { $0.id == updateId }) else {
            errorManager.reportError(ConfigurationSyncError.updateNotFound(updateId))
            return false
        }
        
        do {
            // Create rollback changes (reverse the original changes)
            let rollbackChanges = createRollbackChanges(from: update.changes)
            
            // Apply rollback changes
            try await applyChanges(rollbackChanges)
            
            // Validate configuration after rollback
            let validationResult = await validator.validateAll()
            
            if !validationResult.isValid {
                errorManager.reportError(ConfigurationSyncError.rollbackValidationFailed(updateId))
                return false
            }
            
            // Remove from applied updates
            appliedUpdates.removeAll { $0.id == updateId }
            saveAppliedUpdates()
            
            return true
            
        } catch {
            errorManager.reportError(ConfigurationSyncError.rollbackFailed(updateId, error))
            return false
        }
    }
    
    func getUpdateHistory(limit: Int = 50) -> [ConfigurationUpdate] {
        return Array(appliedUpdates.suffix(limit))
    }
    
    func clearUpdateHistory() {
        appliedUpdates.removeAll()
        saveAppliedUpdates()
    }
    
    func exportConfiguration() -> Data? {
        let configuration = configurationManager.currentConfiguration
        let exportData: [String: Any] = [
            "environment": configuration.environment.rawValue,
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "Unknown",
            "appliedUpdates": appliedUpdates.map { update in
                [
                    "id": update.id.uuidString,
                    "version": update.version,
                    "timestamp": ISO8601DateFormatter().string(from: update.timestamp),
                    "updateType": "\(update.updateType)"
                ]
            }
        ]
        
        return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }
    
    // MARK: - Private Methods
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                if path.status == .satisfied && self?.isAutoSyncEnabled == true {
                    Task {
                        await self?.performSync()
                    }
                }
            }
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    private func setupAutoSync() {
        // Monitor configuration changes to trigger sync
        configurationManager.$currentConfiguration
            .debounce(for: .seconds(30), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                if self?.isAutoSyncEnabled == true {
                    Task {
                        await self?.performSync()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func startAutoSync() {
        stopAutoSync() // Ensure no duplicate timers
        
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.performSync()
            }
        }
    }
    
    private func stopAutoSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    private func performSync(force: Bool = false) async {
        guard isAutoSyncEnabled || force else { return }
        
        await MainActor.run {
            syncStatus = .syncing
        }
        
        do {
            // Fetch updates from server
            let updates = try await fetchConfigurationUpdates()
            
            await MainActor.run {
                self.pendingUpdates = updates
            }
            
            // Apply applicable updates
            for update in updates {
                if shouldApplyUpdate(update) {
                    let success = await applyUpdate(update)
                    if !success {
                        // Log but continue with other updates
                        continue
                    }
                }
            }
            
            await MainActor.run {
                self.syncStatus = .success(Date())
                self.lastSyncTime = Date()
            }
            
        } catch {
            await MainActor.run {
                self.syncStatus = .failed(error, Date())
            }
            
            errorManager.reportError(ConfigurationSyncError.syncFailed(error))
        }
    }
    
    private func fetchConfigurationUpdates() async throws -> [ConfigurationUpdate] {
        let currentConfig = configurationManager.currentConfiguration
        let endpoint = currentConfig.apiConfiguration.baseURL.appendingPathComponent(syncEndpoint)
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Include current configuration version and applied updates in request
        let requestBody: [String: Any] = [
            "environment": currentConfig.environment.rawValue,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "1.0.0",
            "appliedUpdates": appliedUpdates.map { $0.id.uuidString },
            "lastSyncTime": lastSyncTime?.timeIntervalSince1970 ?? 0
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Add authentication if available
        if let authToken = try? secureStorage.retrieveAuthToken() {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConfigurationSyncError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ConfigurationSyncError.serverError(httpResponse.statusCode)
        }
        
        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let updatesArray = json?["updates"] as? [[String: Any]] else {
            return [] // No updates available
        }
        
        // Convert to ConfigurationUpdate objects
        return try parseConfigurationUpdates(from: updatesArray)
    }
    
    private func parseConfigurationUpdates(from array: [[String: Any]]) throws -> [ConfigurationUpdate] {
        var updates: [ConfigurationUpdate] = []
        
        for updateDict in array {
            guard let idString = updateDict["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let version = updateDict["version"] as? String,
                  let timestampInterval = updateDict["timestamp"] as? TimeInterval,
                  let environmentString = updateDict["environment"] as? String,
                  let environment = AppEnvironment(rawValue: environmentString),
                  let updateTypeString = updateDict["updateType"] as? String,
                  let changesArray = updateDict["changes"] as? [[String: Any]] else {
                continue
            }
            
            let timestamp = Date(timeIntervalSince1970: timestampInterval)
            let updateType = parseUpdateType(updateTypeString)
            let changes = try parseConfigurationChanges(from: changesArray)
            
            let update = ConfigurationUpdate(
                id: id,
                version: version,
                timestamp: timestamp,
                environment: environment,
                updateType: updateType,
                changes: changes,
                signature: updateDict["signature"] as? String,
                rolloutPercentage: updateDict["rolloutPercentage"] as? Double ?? 1.0,
                minimumAppVersion: updateDict["minimumAppVersion"] as? String,
                expirationDate: (updateDict["expirationDate"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
            )
            
            updates.append(update)
        }
        
        return updates
    }
    
    private func parseUpdateType(_ string: String) -> ConfigurationUpdate.UpdateType {
        switch string.lowercased() {
        case "full":
            return .full
        case "partial":
            return .partial
        case "hotfix":
            return .hotfix
        case "rollback":
            return .rollback
        default:
            return .partial
        }
    }
    
    private func parseConfigurationChanges(from array: [[String: Any]]) throws -> [ConfigurationChange] {
        var changes: [ConfigurationChange] = []
        
        for changeDict in array {
            guard let path = changeDict["path"] as? String,
                  let newValue = changeDict["newValue"],
                  let changeTypeString = changeDict["changeType"] as? String else {
                continue
            }
            
            let oldValue = changeDict["oldValue"]
            let changeType = parseChangeType(changeTypeString)
            let priority = parsePriority(changeDict["priority"] as? String ?? "medium")
            let requiresRestart = changeDict["requiresRestart"] as? Bool ?? false
            
            let change = ConfigurationChange(
                path: path,
                oldValue: oldValue,
                newValue: newValue,
                changeType: changeType,
                priority: priority,
                requiresRestart: requiresRestart
            )
            
            changes.append(change)
        }
        
        return changes
    }
    
    private func parseChangeType(_ string: String) -> ConfigurationChange.ChangeType {
        switch string.lowercased() {
        case "add":
            return .add
        case "update":
            return .update
        case "delete":
            return .delete
        default:
            return .update
        }
    }
    
    private func parsePriority(_ string: String) -> ConfigurationChange.Priority {
        switch string.lowercased() {
        case "low":
            return .low
        case "medium":
            return .medium
        case "high":
            return .high
        case "critical":
            return .critical
        default:
            return .medium
        }
    }
    
    private func shouldApplyUpdate(_ update: ConfigurationUpdate) -> Bool {
        // Check environment match
        guard update.environment == configurationManager.currentConfiguration.environment else {
            return false
        }
        
        // Check app version requirements
        if let minVersion = update.minimumAppVersion {
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
            if currentVersion.compare(minVersion, options: .numeric) == .orderedAscending {
                return false
            }
        }
        
        // Check expiration
        if let expirationDate = update.expirationDate, Date() > expirationDate {
            return false
        }
        
        // Check rollout percentage
        if update.rolloutPercentage < 1.0 {
            let userHash = getUserHash()
            let threshold = UInt32(update.rolloutPercentage * Double(UInt32.max))
            if userHash >= threshold {
                return false
            }
        }
        
        return true
    }
    
    private func validateUpdate(_ update: ConfigurationUpdate) -> Bool {
        // Verify signature if present
        if let signature = update.signature {
            return verifyUpdateSignature(update, signature: signature)
        }
        
        // Basic validation
        return !update.changes.isEmpty && !update.version.isEmpty
    }
    
    private func verifyUpdateSignature(_ update: ConfigurationUpdate, signature: String) -> Bool {
        // In a real implementation, you would verify the signature using a public key
        // For now, we'll just check if signature exists
        return !signature.isEmpty
    }
    
    private func applyChanges(_ changes: [ConfigurationChange]) async throws {
        for change in changes {
            try await applyChange(change)
        }
        
        // Reload configuration after applying changes
        await configurationManager.reloadConfiguration()
    }
    
    private func applyChange(_ change: ConfigurationChange) async throws {
        // Apply configuration changes based on path
        // This is a simplified implementation - in practice, you'd have a more
        // sophisticated system for applying configuration changes
        
        switch change.path {
        case "api.timeout":
            if let timeout = change.newValue as? TimeInterval {
                // Update API timeout - this would require a more sophisticated
                // configuration update mechanism in practice
            }
        case "performance.maxMemoryUsageMB":
            if let memoryLimit = change.newValue as? Int {
                // Update memory limit
            }
        case "features.*":
            // Update feature flags
            if let flagKey = extractFeatureFlagKey(from: change.path),
               let enabled = change.newValue as? Bool {
                let featureFlags = FeatureFlagManager.shared
                if enabled {
                    featureFlags.enableFlag(flagKey, temporarily: false)
                } else {
                    featureFlags.disableFlag(flagKey, temporarily: false)
                }
            }
        default:
            // Handle other configuration paths
            break
        }
    }
    
    private func extractFeatureFlagKey(from path: String) -> FeatureFlagKey? {
        let components = path.components(separatedBy: ".")
        guard components.count >= 2, components[0] == "features" else {
            return nil
        }
        
        let flagKey = components[1]
        return FeatureFlagKey(rawValue: flagKey)
    }
    
    private func createRollbackChanges(from changes: [ConfigurationChange]) -> [ConfigurationChange] {
        return changes.map { change in
            ConfigurationChange(
                path: change.path,
                oldValue: change.newValue,
                newValue: change.oldValue ?? getDefaultValue(for: change.path),
                changeType: change.changeType,
                priority: change.priority,
                requiresRestart: change.requiresRestart
            )
        }
    }
    
    private func getDefaultValue(for path: String) -> Any {
        // Return default values for configuration paths
        switch path {
        case "api.timeout":
            return 30.0
        case "performance.maxMemoryUsageMB":
            return 512
        default:
            return ""
        }
    }
    
    private func backupCurrentConfiguration(backupId: UUID) async {
        let configuration = configurationManager.currentConfiguration
        
        // Store backup in local storage
        let backupData: [String: Any] = [
            "id": backupId.uuidString,
            "timestamp": Date().timeIntervalSince1970,
            "environment": configuration.environment.rawValue
            // Add other configuration data as needed
        ]
        
        UserDefaults.standard.set(backupData, forKey: "config_backup_\(backupId.uuidString)")
    }
    
    private func rollbackToBackup(backupId: UUID) async {
        guard let backupData = UserDefaults.standard.dictionary(forKey: "config_backup_\(backupId.uuidString)") else {
            return
        }
        
        // Restore configuration from backup
        // This would require a more sophisticated implementation in practice
        
        // Clean up backup
        UserDefaults.standard.removeObject(forKey: "config_backup_\(backupId.uuidString)")
    }
    
    private func getUserHash() -> UInt32 {
        let userID = UIDevice.current.identifierForVendor?.uuidString ?? "anonymous"
        return userID.hash.magnitude
    }
    
    private func loadAppliedUpdates() {
        if let data = UserDefaults.standard.data(forKey: "applied_config_updates"),
           let updates = try? JSONDecoder().decode([ConfigurationUpdate].self, from: data) {
            appliedUpdates = updates
        }
    }
    
    private func saveAppliedUpdates() {
        if let data = try? JSONEncoder().encode(appliedUpdates) {
            UserDefaults.standard.set(data, forKey: "applied_config_updates")
        }
    }
}

// MARK: - Configuration Sync Errors
enum ConfigurationSyncError: Error, AppErrorProtocol {
    case syncFailed(Error)
    case invalidUpdate(UUID)
    case updateNotFound(UUID)
    case updateApplicationFailed(UUID, Error)
    case validationFailedAfterUpdate(UUID)
    case rollbackFailed(UUID, Error)
    case rollbackValidationFailed(UUID)
    case invalidResponse
    case serverError(Int)
    case networkUnavailable
    
    var errorCode: String {
        switch self {
        case .syncFailed:
            return "CONFIG_SYNC_FAILED"
        case .invalidUpdate(let id):
            return "CONFIG_INVALID_UPDATE_\(id.uuidString.prefix(8))"
        case .updateNotFound(let id):
            return "CONFIG_UPDATE_NOT_FOUND_\(id.uuidString.prefix(8))"
        case .updateApplicationFailed(let id, _):
            return "CONFIG_UPDATE_APPLICATION_FAILED_\(id.uuidString.prefix(8))"
        case .validationFailedAfterUpdate(let id):
            return "CONFIG_VALIDATION_FAILED_AFTER_UPDATE_\(id.uuidString.prefix(8))"
        case .rollbackFailed(let id, _):
            return "CONFIG_ROLLBACK_FAILED_\(id.uuidString.prefix(8))"
        case .rollbackValidationFailed(let id):
            return "CONFIG_ROLLBACK_VALIDATION_FAILED_\(id.uuidString.prefix(8))"
        case .invalidResponse:
            return "CONFIG_INVALID_RESPONSE"
        case .serverError(let code):
            return "CONFIG_SERVER_ERROR_\(code)"
        case .networkUnavailable:
            return "CONFIG_NETWORK_UNAVAILABLE"
        }
    }
    
    var errorCategory: ErrorCategory {
        return .network
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .syncFailed, .networkUnavailable:
            return .medium
        case .invalidUpdate, .updateNotFound:
            return .low
        case .updateApplicationFailed, .validationFailedAfterUpdate:
            return .high
        case .rollbackFailed, .rollbackValidationFailed:
            return .critical
        case .invalidResponse, .serverError:
            return .high
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .syncFailed, .networkUnavailable, .serverError:
            return true
        case .invalidUpdate, .updateNotFound, .validationFailedAfterUpdate, .rollbackValidationFailed:
            return false
        case .updateApplicationFailed, .rollbackFailed:
            return true
        case .invalidResponse:
            return false
        }
    }
    
    var userMessage: String {
        switch self {
        case .syncFailed:
            return "Failed to sync configuration updates"
        case .invalidUpdate:
            return "Invalid configuration update received"
        case .updateNotFound:
            return "Configuration update not found"
        case .updateApplicationFailed:
            return "Failed to apply configuration update"
        case .validationFailedAfterUpdate:
            return "Configuration became invalid after update"
        case .rollbackFailed:
            return "Failed to rollback configuration change"
        case .rollbackValidationFailed:
            return "Configuration remained invalid after rollback"
        case .invalidResponse:
            return "Invalid response from configuration server"
        case .serverError(let code):
            return "Configuration server error (\(code))"
        case .networkUnavailable:
            return "Network unavailable for configuration sync"
        }
    }
    
    var recoveryAction: RecoveryAction? {
        switch self {
        case .syncFailed, .networkUnavailable, .serverError:
            return .retryWithDelay(5.0)
        case .updateApplicationFailed, .rollbackFailed:
            return .retry
        case .validationFailedAfterUpdate, .rollbackValidationFailed:
            return .restartSession
        default:
            return .none
        }
    }
    
    var errorDescription: String? {
        return userMessage
    }
}

// MARK: - Codable Extensions
extension ConfigurationUpdate: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, version, timestamp, environment, updateType, changes
        case signature, rolloutPercentage, minimumAppVersion, expirationDate
    }
}

extension ConfigurationChange: Codable {
    private enum CodingKeys: String, CodingKey {
        case path, oldValue, newValue, changeType, priority, requiresRestart
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        oldValue = try container.decodeIfPresent(AnyCodable.self, forKey: .oldValue)?.value
        newValue = try container.decode(AnyCodable.self, forKey: .newValue).value
        
        let changeTypeString = try container.decode(String.self, forKey: .changeType)
        changeType = ConfigurationSyncManager().parseChangeType(changeTypeString)
        
        let priorityString = try container.decode(String.self, forKey: .priority)
        priority = ConfigurationSyncManager().parsePriority(priorityString)
        
        requiresRestart = try container.decode(Bool.self, forKey: .requiresRestart)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(AnyCodable(oldValue), forKey: .oldValue)
        try container.encode(AnyCodable(newValue), forKey: .newValue)
        try container.encode("\(changeType)", forKey: .changeType)
        try container.encode("\(priority)", forKey: .priority)
        try container.encode(requiresRestart, forKey: .requiresRestart)
    }
}

// MARK: - Helper Types
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else {
            value = ""
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else {
            try container.encode("")
        }
    }
}