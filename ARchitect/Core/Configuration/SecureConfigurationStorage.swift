import Foundation
import Security

// MARK: - Secure Configuration Storage
class SecureConfigurationStorage {
    static let shared = SecureConfigurationStorage()
    
    private let serviceName = "com.architect.ARchitect.config"
    private let accessGroup: String? = nil // Set if using shared keychain
    
    private init() {}
    
    // MARK: - Public Methods
    
    func storeAPIKey(_ key: String, for environment: AppEnvironment) throws {
        let keyName = "api_key_\(environment.rawValue)"
        try storeSecureString(key, forKey: keyName)
    }
    
    func retrieveAPIKey(for environment: AppEnvironment) throws -> String? {
        let keyName = "api_key_\(environment.rawValue)"
        return try retrieveSecureString(forKey: keyName)
    }
    
    func storeAPIEndpoint(_ endpoint: String, for environment: AppEnvironment) throws {
        let keyName = "api_endpoint_\(environment.rawValue)"
        try storeSecureString(endpoint, forKey: keyName)
    }
    
    func retrieveAPIEndpoint(for environment: AppEnvironment) throws -> String? {
        let keyName = "api_endpoint_\(environment.rawValue)"
        return try retrieveSecureString(forKey: keyName)
    }
    
    func storeAuthToken(_ token: String) throws {
        try storeSecureString(token, forKey: "auth_token")
    }
    
    func retrieveAuthToken() throws -> String? {
        return try retrieveSecureString(forKey: "auth_token")
    }
    
    func storeRefreshToken(_ token: String) throws {
        try storeSecureString(token, forKey: "refresh_token")
    }
    
    func retrieveRefreshToken() throws -> String? {
        return try retrieveSecureString(forKey: "refresh_token")
    }
    
    func storeEncryptionKey(_ key: Data) throws {
        try storeSecureData(key, forKey: "encryption_key")
    }
    
    func retrieveEncryptionKey() throws -> Data? {
        return try retrieveSecureData(forKey: "encryption_key")
    }
    
    func clearAllSecureData() throws {
        let keys = [
            "api_key_dev", "api_key_staging", "api_key_prod",
            "api_endpoint_dev", "api_endpoint_staging", "api_endpoint_prod",
            "auth_token", "refresh_token", "encryption_key"
        ]
        
        for key in keys {
            try? deleteSecureItem(forKey: key)
        }
    }
    
    func clearAuthenticationData() throws {
        try? deleteSecureItem(forKey: "auth_token")
        try? deleteSecureItem(forKey: "refresh_token")
    }
    
    // MARK: - Private Methods
    
    private func storeSecureString(_ string: String, forKey key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw SecureStorageError.encodingError
        }
        try storeSecureData(data, forKey: key)
    }
    
    private func retrieveSecureString(forKey key: String) throws -> String? {
        guard let data = try retrieveSecureData(forKey: key) else {
            return nil
        }
        
        guard let string = String(data: data, encoding: .utf8) else {
            throw SecureStorageError.decodingError
        }
        
        return string
    }
    
    private func storeSecureData(_ data: Data, forKey key: String) throws {
        // Delete existing item first
        try? deleteSecureItem(forKey: key)
        
        var query = baseQuery(forKey: key)
        query[kSecValueData] = data
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw SecureStorageError.storageError(status)
        }
    }
    
    private func retrieveSecureData(forKey key: String) throws -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw SecureStorageError.retrievalError(status)
        }
        
        guard let data = result as? Data else {
            throw SecureStorageError.decodingError
        }
        
        return data
    }
    
    private func deleteSecureItem(forKey key: String) throws {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.deletionError(status)
        }
    }
    
    private func baseQuery(forKey key: String) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        
        return query
    }
}

// MARK: - Secure Storage Errors
enum SecureStorageError: Error, AppErrorProtocol {
    case encodingError
    case decodingError
    case storageError(OSStatus)
    case retrievalError(OSStatus)
    case deletionError(OSStatus)
    
    var errorCode: String {
        switch self {
        case .encodingError:
            return "SECURE_STORAGE_ENCODING_ERROR"
        case .decodingError:
            return "SECURE_STORAGE_DECODING_ERROR"
        case .storageError(let status):
            return "SECURE_STORAGE_STORE_ERROR_\(status)"
        case .retrievalError(let status):
            return "SECURE_STORAGE_RETRIEVE_ERROR_\(status)"
        case .deletionError(let status):
            return "SECURE_STORAGE_DELETE_ERROR_\(status)"
        }
    }
    
    var errorCategory: ErrorCategory {
        return .storage
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .encodingError, .decodingError:
            return .high
        case .storageError, .retrievalError, .deletionError:
            return .critical
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .encodingError, .decodingError:
            return false
        case .storageError, .retrievalError, .deletionError:
            return true
        }
    }
    
    var userMessage: String {
        switch self {
        case .encodingError, .decodingError:
            return "Failed to process secure configuration data"
        case .storageError:
            return "Failed to save secure configuration"
        case .retrievalError:
            return "Failed to retrieve secure configuration"
        case .deletionError:
            return "Failed to remove secure configuration"
        }
    }
    
    var recoveryAction: RecoveryAction? {
        switch self {
        case .encodingError, .decodingError:
            return .none
        case .storageError, .retrievalError, .deletionError:
            return .retry
        }
    }
    
    var errorDescription: String? {
        return userMessage
    }
}

// MARK: - Configuration Manager
class ConfigurationManager: ObservableObject {
    static let shared = ConfigurationManager()
    
    @Published private(set) var currentConfiguration: EnvironmentConfiguration
    @Published private(set) var isConfigurationValid = false
    
    private let secureStorage = SecureConfigurationStorage.shared
    private let errorManager = ErrorManager.shared
    private let environment: AppEnvironment
    
    private init() {
        self.environment = AppEnvironment.current
        self.currentConfiguration = Self.createConfiguration(for: environment)
        
        Task {
            await loadSecureConfiguration()
            await validateConfiguration()
        }
    }
    
    // MARK: - Public Methods
    
    func reloadConfiguration() async {
        await loadSecureConfiguration()
        await validateConfiguration()
    }
    
    func updateAPIKey(_ key: String, for environment: AppEnvironment? = nil) async {
        let targetEnvironment = environment ?? self.environment
        
        do {
            try secureStorage.storeAPIKey(key, for: targetEnvironment)
            await reloadConfiguration()
        } catch {
            if let secureError = error as? SecureStorageError {
                errorManager.reportError(secureError)
            } else {
                errorManager.reportError(StorageError.writeFailure)
            }
        }
    }
    
    func updateAPIEndpoint(_ endpoint: String, for environment: AppEnvironment? = nil) async {
        let targetEnvironment = environment ?? self.environment
        
        do {
            try secureStorage.storeAPIEndpoint(endpoint, for: targetEnvironment)
            await reloadConfiguration()
        } catch {
            if let secureError = error as? SecureStorageError {
                errorManager.reportError(secureError)
            } else {
                errorManager.reportError(StorageError.writeFailure)
            }
        }
    }
    
    func storeAuthToken(_ token: String) async {
        do {
            try secureStorage.storeAuthToken(token)
        } catch {
            if let secureError = error as? SecureStorageError {
                errorManager.reportError(secureError)
            } else {
                errorManager.reportError(StorageError.writeFailure)
            }
        }
    }
    
    func retrieveAuthToken() async -> String? {
        do {
            return try secureStorage.retrieveAuthToken()
        } catch {
            if let secureError = error as? SecureStorageError {
                errorManager.reportError(secureError)
            } else {
                errorManager.reportError(StorageError.readFailure)
            }
            return nil
        }
    }
    
    func clearAuthenticationData() async {
        do {
            try secureStorage.clearAuthenticationData()
        } catch {
            if let secureError = error as? SecureStorageError {
                errorManager.reportError(secureError)
            } else {
                errorManager.reportError(StorageError.writeFailure)
            }
        }
    }
    
    func resetConfiguration() async {
        do {
            try secureStorage.clearAllSecureData()
            currentConfiguration = Self.createConfiguration(for: environment)
            await validateConfiguration()
        } catch {
            errorManager.reportError(StorageError.writeFailure)
        }
    }
    
    // MARK: - Private Methods
    
    private func loadSecureConfiguration() async {
        do {
            // Load API key if available
            if let apiKey = try secureStorage.retrieveAPIKey(for: environment) {
                // Update configuration with secure API key
                updateConfigurationWithSecureData(apiKey: apiKey)
            }
            
            // Load custom API endpoint if available
            if let apiEndpoint = try secureStorage.retrieveAPIEndpoint(for: environment),
               let url = URL(string: apiEndpoint) {
                updateConfigurationWithSecureData(apiEndpoint: url)
            }
        } catch {
            if let secureError = error as? SecureStorageError {
                errorManager.reportError(secureError)
            } else {
                errorManager.reportError(StorageError.readFailure)
            }
        }
    }
    
    private func validateConfiguration() async {
        let validationErrors = validateCurrentConfiguration()
        
        if validationErrors.isEmpty {
            await MainActor.run {
                isConfigurationValid = true
            }
        } else {
            await MainActor.run {
                isConfigurationValid = false
            }
            
            // Report validation errors
            for error in validationErrors {
                errorManager.reportError(error)
            }
        }
    }
    
    private func validateCurrentConfiguration() -> [ConfigurationError] {
        var errors: [ConfigurationError] = []
        
        // Validate API configuration
        if currentConfiguration.apiConfiguration.baseURL.absoluteString.isEmpty {
            errors.append(.invalidAPIEndpoint)
        }
        
        if currentConfiguration.apiConfiguration.timeout <= 0 {
            errors.append(.invalidTimeout)
        }
        
        // Validate performance thresholds
        if currentConfiguration.performanceConfiguration.maxMemoryUsageMB <= 0 {
            errors.append(.invalidMemoryLimit)
        }
        
        if currentConfiguration.performanceConfiguration.targetFrameRate <= 0 {
            errors.append(.invalidFrameRate)
        }
        
        // Validate AR configuration
        if currentConfiguration.arConfiguration.maxAnchorsPerSession <= 0 {
            errors.append(.invalidARSettings)
        }
        
        return errors
    }
    
    private func updateConfigurationWithSecureData(apiKey: String? = nil, apiEndpoint: URL? = nil) {
        var apiConfig = currentConfiguration.apiConfiguration
        
        if let endpoint = apiEndpoint {
            apiConfig = APIConfiguration(
                baseURL: endpoint,
                timeout: apiConfig.timeout,
                maxRetries: apiConfig.maxRetries,
                rateLimitPerMinute: apiConfig.rateLimitPerMinute,
                authEndpoint: apiConfig.authEndpoint,
                modelEndpoint: apiConfig.modelEndpoint,
                analyticsEndpoint: apiConfig.analyticsEndpoint
            )
        }
        
        currentConfiguration = EnvironmentConfiguration(
            environment: currentConfiguration.environment,
            apiConfiguration: apiConfig,
            analyticsConfiguration: currentConfiguration.analyticsConfiguration,
            arConfiguration: currentConfiguration.arConfiguration,
            aiConfiguration: currentConfiguration.aiConfiguration,
            debugConfiguration: currentConfiguration.debugConfiguration,
            performanceConfiguration: currentConfiguration.performanceConfiguration,
            networkConfiguration: currentConfiguration.networkConfiguration
        )
    }
    
    private static func createConfiguration(for environment: AppEnvironment) -> EnvironmentConfiguration {
        return EnvironmentConfiguration(
            environment: environment,
            apiConfiguration: APIConfiguration.forEnvironment(environment),
            analyticsConfiguration: AnalyticsConfiguration.forEnvironment(environment),
            arConfiguration: ARConfiguration.forEnvironment(environment),
            aiConfiguration: AIConfiguration.forEnvironment(environment),
            debugConfiguration: DebugConfiguration.forEnvironment(environment),
            performanceConfiguration: PerformanceConfiguration.forEnvironment(environment),
            networkConfiguration: NetworkConfiguration.forEnvironment(environment)
        )
    }
}

// MARK: - Configuration Errors
enum ConfigurationError: Error, AppErrorProtocol {
    case invalidAPIEndpoint
    case invalidTimeout
    case invalidMemoryLimit
    case invalidFrameRate
    case invalidARSettings
    case configurationLoadFailed
    case configurationValidationFailed
    
    var errorCode: String {
        switch self {
        case .invalidAPIEndpoint:
            return "CONFIG_INVALID_API_ENDPOINT"
        case .invalidTimeout:
            return "CONFIG_INVALID_TIMEOUT"
        case .invalidMemoryLimit:
            return "CONFIG_INVALID_MEMORY_LIMIT"
        case .invalidFrameRate:
            return "CONFIG_INVALID_FRAME_RATE"
        case .invalidARSettings:
            return "CONFIG_INVALID_AR_SETTINGS"
        case .configurationLoadFailed:
            return "CONFIG_LOAD_FAILED"
        case .configurationValidationFailed:
            return "CONFIG_VALIDATION_FAILED"
        }
    }
    
    var errorCategory: ErrorCategory {
        return .system
    }
    
    var severity: ErrorSeverity {
        return .high
    }
    
    var isRetryable: Bool {
        switch self {
        case .configurationLoadFailed:
            return true
        default:
            return false
        }
    }
    
    var userMessage: String {
        switch self {
        case .invalidAPIEndpoint:
            return "Invalid API endpoint configuration"
        case .invalidTimeout:
            return "Invalid timeout configuration"
        case .invalidMemoryLimit:
            return "Invalid memory limit configuration"
        case .invalidFrameRate:
            return "Invalid frame rate configuration"
        case .invalidARSettings:
            return "Invalid AR configuration settings"
        case .configurationLoadFailed:
            return "Failed to load app configuration"
        case .configurationValidationFailed:
            return "App configuration validation failed"
        }
    }
    
    var recoveryAction: RecoveryAction? {
        switch self {
        case .configurationLoadFailed:
            return .retry
        default:
            return .contactSupport
        }
    }
    
    var errorDescription: String? {
        return userMessage
    }
}