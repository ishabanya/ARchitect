import Foundation
import Combine

// MARK: - Validation Result
struct ValidationResult {
    let isValid: Bool
    let errors: [ValidationError]
    let warnings: [ValidationWarning]
    let validatedAt: Date
    
    var hasErrors: Bool { !errors.isEmpty }
    var hasWarnings: Bool { !warnings.isEmpty }
    var isHealthy: Bool { !hasErrors && warnings.count < 3 }
}

// MARK: - Validation Error
struct ValidationError {
    let code: String
    let message: String
    let severity: Severity
    let component: ConfigurationComponent
    let suggestedFix: String?
    let relatedKeys: [String]
    
    enum Severity {
        case critical
        case high
        case medium
        case low
    }
    
    enum ConfigurationComponent {
        case environment
        case api
        case storage
        case performance
        case featureFlags
        case offline
        case security
        case analytics
    }
}

// MARK: - Validation Warning
struct ValidationWarning {
    let code: String
    let message: String
    let component: ValidationError.ConfigurationComponent
    let recommendation: String
    let impact: ImpactLevel
    
    enum ImpactLevel {
        case performance
        case usability
        case maintenance
        case security
    }
}

// MARK: - Configuration Validator
class ConfigurationValidator: ObservableObject {
    static let shared = ConfigurationValidator()
    
    @Published private(set) var lastValidationResult: ValidationResult?
    @Published private(set) var isValidating = false
    @Published private(set) var validationHistory: [ValidationResult] = []
    
    private let errorManager = ErrorManager.shared
    private let maxHistorySize = 50
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupValidationTriggers()
    }
    
    // MARK: - Public Methods
    
    func validateAll() async -> ValidationResult {
        await MainActor.run { isValidating = true }
        
        let configManager = ConfigurationManager.shared
        let configuration = configManager.currentConfiguration
        
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        // Validate each configuration component
        errors.append(contentsOf: await validateEnvironmentConfiguration(configuration))
        errors.append(contentsOf: await validateAPIConfiguration(configuration.apiConfiguration))
        errors.append(contentsOf: await validatePerformanceConfiguration(configuration.performanceConfiguration))
        errors.append(contentsOf: await validateARConfiguration(configuration.arConfiguration))
        errors.append(contentsOf: await validateAnalyticsConfiguration(configuration.analyticsConfiguration))
        errors.append(contentsOf: await validateNetworkConfiguration(configuration.networkConfiguration))
        
        // Generate warnings
        warnings.append(contentsOf: await generateWarnings(configuration))
        
        // Validate feature flags
        errors.append(contentsOf: await validateFeatureFlags())
        
        // Validate offline configuration
        errors.append(contentsOf: await validateOfflineConfiguration())
        
        // Validate secure storage
        errors.append(contentsOf: await validateSecureStorage())
        
        let result = ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            validatedAt: Date()
        )
        
        await MainActor.run {
            self.isValidating = false
            self.lastValidationResult = result
            self.addToHistory(result)
        }
        
        // Report critical validation failures
        if !result.isValid {
            reportValidationFailures(result)
        }
        
        return result
    }
    
    func validateComponent(_ component: ValidationError.ConfigurationComponent) async -> ValidationResult {
        await MainActor.run { isValidating = true }
        
        let configManager = ConfigurationManager.shared
        let configuration = configManager.currentConfiguration
        
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        switch component {
        case .environment:
            errors.append(contentsOf: await validateEnvironmentConfiguration(configuration))
        case .api:
            errors.append(contentsOf: await validateAPIConfiguration(configuration.apiConfiguration))
        case .performance:
            errors.append(contentsOf: await validatePerformanceConfiguration(configuration.performanceConfiguration))
        case .featureFlags:
            errors.append(contentsOf: await validateFeatureFlags())
        case .offline:
            errors.append(contentsOf: await validateOfflineConfiguration())
        case .security:
            errors.append(contentsOf: await validateSecureStorage())
        case .analytics:
            errors.append(contentsOf: await validateAnalyticsConfiguration(configuration.analyticsConfiguration))
        case .storage:
            errors.append(contentsOf: await validateSecureStorage())
        }
        
        let result = ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            validatedAt: Date()
        )
        
        await MainActor.run {
            self.isValidating = false
            self.lastValidationResult = result
        }
        
        return result
    }
    
    func getValidationHistory(last count: Int = 10) -> [ValidationResult] {
        return Array(validationHistory.suffix(count))
    }
    
    func clearValidationHistory() {
        validationHistory.removeAll()
    }
    
    // MARK: - Private Validation Methods
    
    private func validateEnvironmentConfiguration(_ config: EnvironmentConfiguration) async -> [ValidationError] {
        var errors: [ValidationError] = []
        
        // Validate environment consistency
        let currentEnv = AppEnvironment.current
        if config.environment != currentEnv {
            errors.append(ValidationError(
                code: "ENV_MISMATCH",
                message: "Configuration environment (\(config.environment.rawValue)) doesn't match current environment (\(currentEnv.rawValue))",
                severity: .critical,
                component: .environment,
                suggestedFix: "Reload configuration for current environment",
                relatedKeys: ["environment"]
            ))
        }
        
        return errors
    }
    
    private func validateAPIConfiguration(_ config: APIConfiguration) async -> [ValidationError] {
        var errors: [ValidationError] = []
        
        // Validate base URL
        if config.baseURL.absoluteString.isEmpty {
            errors.append(ValidationError(
                code: "API_EMPTY_URL",
                message: "API base URL is empty",
                severity: .critical,
                component: .api,
                suggestedFix: "Set a valid API base URL",
                relatedKeys: ["baseURL"]
            ))
        }
        
        // Validate URL scheme
        if let scheme = config.baseURL.scheme, !["https", "http"].contains(scheme) {
            errors.append(ValidationError(
                code: "API_INVALID_SCHEME",
                message: "API URL scheme '\(scheme)' is not supported",
                severity: .high,
                component: .api,
                suggestedFix: "Use https:// or http:// scheme",
                relatedKeys: ["baseURL"]
            ))
        }
        
        // Validate HTTPS in production
        if AppEnvironment.current == .production && config.baseURL.scheme != "https" {
            errors.append(ValidationError(
                code: "API_INSECURE_PRODUCTION",
                message: "Production environment must use HTTPS",
                severity: .critical,
                component: .api,
                suggestedFix: "Change API URL to use HTTPS",
                relatedKeys: ["baseURL"]
            ))
        }
        
        // Validate timeout values
        if config.timeout <= 0 {
            errors.append(ValidationError(
                code: "API_INVALID_TIMEOUT",
                message: "API timeout must be greater than 0",
                severity: .high,
                component: .api,
                suggestedFix: "Set timeout to a positive value (recommended: 10-30 seconds)",
                relatedKeys: ["timeout"]
            ))
        }
        
        if config.timeout > 60 {
            errors.append(ValidationError(
                code: "API_EXCESSIVE_TIMEOUT",
                message: "API timeout is excessively high (\(config.timeout)s)",
                severity: .medium,
                component: .api,
                suggestedFix: "Consider reducing timeout to improve user experience",
                relatedKeys: ["timeout"]
            ))
        }
        
        // Validate retry count
        if config.maxRetries < 0 {
            errors.append(ValidationError(
                code: "API_INVALID_RETRIES",
                message: "Max retries cannot be negative",
                severity: .medium,
                component: .api,
                suggestedFix: "Set maxRetries to 0 or positive value",
                relatedKeys: ["maxRetries"]
            ))
        }
        
        // Validate rate limiting
        if config.rateLimitPerMinute <= 0 {
            errors.append(ValidationError(
                code: "API_INVALID_RATE_LIMIT",
                message: "Rate limit must be greater than 0",
                severity: .medium,
                component: .api,
                suggestedFix: "Set a reasonable rate limit (e.g., 60 requests per minute)",
                relatedKeys: ["rateLimitPerMinute"]
            ))
        }
        
        // Test API connectivity
        await testAPIConnectivity(config.baseURL, errors: &errors)
        
        return errors
    }
    
    private func validatePerformanceConfiguration(_ config: PerformanceConfiguration) async -> [ValidationError] {
        var errors: [ValidationError] = []
        
        // Validate memory limits
        if config.maxMemoryUsageMB <= 0 {
            errors.append(ValidationError(
                code: "PERF_INVALID_MEMORY_LIMIT",
                message: "Memory limit must be greater than 0",
                severity: .high,
                component: .performance,
                suggestedFix: "Set a reasonable memory limit (e.g., 512MB)",
                relatedKeys: ["maxMemoryUsageMB"]
            ))
        }
        
        if config.maxMemoryUsageMB > 2048 {
            errors.append(ValidationError(
                code: "PERF_EXCESSIVE_MEMORY_LIMIT",
                message: "Memory limit is very high (\(config.maxMemoryUsageMB)MB)",
                severity: .medium,
                component: .performance,
                suggestedFix: "Consider reducing memory limit to improve device compatibility",
                relatedKeys: ["maxMemoryUsageMB"]
            ))
        }
        
        // Validate frame rate
        if config.targetFrameRate <= 0 {
            errors.append(ValidationError(
                code: "PERF_INVALID_FRAME_RATE",
                message: "Target frame rate must be greater than 0",
                severity: .high,
                component: .performance,
                suggestedFix: "Set target frame rate to 30 or 60 FPS",
                relatedKeys: ["targetFrameRate"]
            ))
        }
        
        if config.targetFrameRate > 120 {
            errors.append(ValidationError(
                code: "PERF_EXCESSIVE_FRAME_RATE",
                message: "Target frame rate is very high (\(config.targetFrameRate) FPS)",
                severity: .medium,
                component: .performance,
                suggestedFix: "Most devices can't sustain frame rates above 60 FPS",
                relatedKeys: ["targetFrameRate"]
            ))
        }
        
        // Validate cache settings
        if config.maxCacheSize <= 0 {
            errors.append(ValidationError(
                code: "PERF_INVALID_CACHE_SIZE",
                message: "Cache size must be greater than 0",
                severity: .medium,
                component: .performance,
                suggestedFix: "Set a reasonable cache size (e.g., 50MB)",
                relatedKeys: ["maxCacheSize"]
            ))
        }
        
        return errors
    }
    
    private func validateARConfiguration(_ config: ARConfiguration) async -> [ValidationError] {
        var errors: [ValidationError] = []
        
        // Validate tracking loss time
        if config.maxTrackingLossTime <= 0 {
            errors.append(ValidationError(
                code: "AR_INVALID_TRACKING_TIME",
                message: "Max tracking loss time must be greater than 0",
                severity: .medium,
                component: .performance,
                suggestedFix: "Set tracking loss time to 5-10 seconds",
                relatedKeys: ["maxTrackingLossTime"]
            ))
        }
        
        // Validate anchor limits
        if config.maxAnchorsPerSession <= 0 {
            errors.append(ValidationError(
                code: "AR_INVALID_ANCHOR_LIMIT",
                message: "Max anchors per session must be greater than 0",
                severity: .medium,
                component: .performance,
                suggestedFix: "Set a reasonable anchor limit (e.g., 50-100)",
                relatedKeys: ["maxAnchorsPerSession"]
            ))
        }
        
        if config.maxAnchorsPerSession > 1000 {
            errors.append(ValidationError(
                code: "AR_EXCESSIVE_ANCHOR_LIMIT",
                message: "Anchor limit is very high (\(config.maxAnchorsPerSession))",
                severity: .medium,
                component: .performance,
                suggestedFix: "High anchor counts can impact performance",
                relatedKeys: ["maxAnchorsPerSession"]
            ))
        }
        
        return errors
    }
    
    private func validateAnalyticsConfiguration(_ config: AnalyticsConfiguration) async -> [ValidationError] {
        var errors: [ValidationError] = []
        
        // Validate sampling rate
        if config.samplingRate < 0 || config.samplingRate > 1 {
            errors.append(ValidationError(
                code: "ANALYTICS_INVALID_SAMPLING_RATE",
                message: "Sampling rate must be between 0 and 1",
                severity: .medium,
                component: .analytics,
                suggestedFix: "Set sampling rate to a value between 0.0 and 1.0",
                relatedKeys: ["samplingRate"]
            ))
        }
        
        // Validate batch size
        if config.batchSize <= 0 {
            errors.append(ValidationError(
                code: "ANALYTICS_INVALID_BATCH_SIZE",
                message: "Batch size must be greater than 0",
                severity: .medium,
                component: .analytics,
                suggestedFix: "Set batch size to a reasonable value (e.g., 10-50)",
                relatedKeys: ["batchSize"]
            ))
        }
        
        // Validate flush interval
        if config.flushInterval <= 0 {
            errors.append(ValidationError(
                code: "ANALYTICS_INVALID_FLUSH_INTERVAL",
                message: "Flush interval must be greater than 0",
                severity: .medium,
                component: .analytics,
                suggestedFix: "Set flush interval to a reasonable value (e.g., 60-300 seconds)",
                relatedKeys: ["flushInterval"]
            ))
        }
        
        return errors
    }
    
    private func validateNetworkConfiguration(_ config: NetworkConfiguration) async -> [ValidationError] {
        var errors: [ValidationError] = []
        
        // Validate timeouts
        if config.connectionTimeout <= 0 {
            errors.append(ValidationError(
                code: "NET_INVALID_CONNECTION_TIMEOUT",
                message: "Connection timeout must be greater than 0",
                severity: .medium,
                component: .api,
                suggestedFix: "Set connection timeout to a positive value",
                relatedKeys: ["connectionTimeout"]
            ))
        }
        
        if config.readTimeout <= 0 {
            errors.append(ValidationError(
                code: "NET_INVALID_READ_TIMEOUT",
                message: "Read timeout must be greater than 0",
                severity: .medium,
                component: .api,
                suggestedFix: "Set read timeout to a positive value",
                relatedKeys: ["readTimeout"]
            ))
        }
        
        // Validate concurrent connections
        if config.maxConcurrentConnections <= 0 {
            errors.append(ValidationError(
                code: "NET_INVALID_CONCURRENT_CONNECTIONS",
                message: "Max concurrent connections must be greater than 0",
                severity: .medium,
                component: .api,
                suggestedFix: "Set max concurrent connections to a reasonable value (e.g., 4-8)",
                relatedKeys: ["maxConcurrentConnections"]
            ))
        }
        
        return errors
    }
    
    private func validateFeatureFlags() async -> [ValidationError] {
        var errors: [ValidationError] = []
        let featureFlags = FeatureFlagManager.shared
        
        // Check for dependency violations
        for flag in FeatureFlagKey.allCases {
            if featureFlags.isEnabled(flag) {
                if let flagInfo = featureFlags.getFlagInfo(flag) {
                    for dependency in flagInfo.dependencies {
                        if let depFlag = FeatureFlagKey(rawValue: dependency),
                           !featureFlags.isEnabled(depFlag) {
                            errors.append(ValidationError(
                                code: "FF_DEPENDENCY_VIOLATION",
                                message: "Feature flag '\(flag.rawValue)' is enabled but dependency '\(dependency)' is disabled",
                                severity: .high,
                                component: .featureFlags,
                                suggestedFix: "Enable dependency '\(dependency)' or disable '\(flag.rawValue)'",
                                relatedKeys: [flag.rawValue, dependency]
                            ))
                        }
                    }
                }
            }
        }
        
        return errors
    }
    
    private func validateOfflineConfiguration() async -> [ValidationError] {
        var errors: [ValidationError] = []
        let offlineManager = OfflineManager.shared
        
        // Check offline data size limits
        let currentSize = offlineManager.offlineDataSize
        let maxSize = 100 * 1024 * 1024 // 100MB limit for validation
        
        if currentSize > maxSize {
            errors.append(ValidationError(
                code: "OFFLINE_EXCESSIVE_DATA_SIZE",
                message: "Offline data size (\(currentSize / (1024*1024))MB) exceeds recommended limit",
                severity: .medium,
                component: .offline,
                suggestedFix: "Clear old offline data or increase storage limit",
                relatedKeys: ["offlineDataSize"]
            ))
        }
        
        return errors
    }
    
    private func validateSecureStorage() async -> [ValidationError] {
        var errors: [ValidationError] = []
        let secureStorage = SecureConfigurationStorage.shared
        
        // Test keychain accessibility
        do {
            try secureStorage.storeAPIKey("test", for: .development)
            let retrieved = try secureStorage.retrieveAPIKey(for: .development)
            if retrieved != "test" {
                errors.append(ValidationError(
                    code: "SECURE_STORAGE_READ_WRITE_MISMATCH",
                    message: "Secure storage read/write test failed",
                    severity: .critical,
                    component: .security,
                    suggestedFix: "Check keychain permissions and device lock status",
                    relatedKeys: ["secureStorage"]
                ))
            }
            // Clean up test data
            try? secureStorage.clearAuthenticationData()
        } catch {
            errors.append(ValidationError(
                code: "SECURE_STORAGE_ACCESS_FAILED",
                message: "Cannot access secure storage: \(error.localizedDescription)",
                severity: .critical,
                component: .security,
                suggestedFix: "Check device lock status and keychain permissions",
                relatedKeys: ["secureStorage"]
            ))
        }
        
        return errors
    }
    
    private func generateWarnings(_ config: EnvironmentConfiguration) async -> [ValidationWarning] {
        var warnings: [ValidationWarning] = []
        
        // Performance warnings
        if config.performanceConfiguration.maxMemoryUsageMB > 1024 {
            warnings.append(ValidationWarning(
                code: "PERF_HIGH_MEMORY_LIMIT",
                message: "High memory limit may cause issues on older devices",
                component: .performance,
                recommendation: "Consider device-specific memory limits",
                impact: .performance
            ))
        }
        
        // Debug warnings for production
        if config.environment == .production && config.debugConfiguration.loggingEnabled {
            warnings.append(ValidationWarning(
                code: "DEBUG_LOGGING_IN_PRODUCTION",
                message: "Debug logging is enabled in production",
                component: .environment,
                recommendation: "Disable debug logging in production for performance and privacy",
                impact: .performance
            ))
        }
        
        // Analytics warnings
        if config.analyticsConfiguration.samplingRate == 1.0 && config.environment == .production {
            warnings.append(ValidationWarning(
                code: "ANALYTICS_FULL_SAMPLING_PRODUCTION",
                message: "100% analytics sampling in production may impact performance",
                component: .analytics,
                recommendation: "Consider reducing sampling rate in production",
                impact: .performance
            ))
        }
        
        return warnings
    }
    
    private func testAPIConnectivity(_ baseURL: URL, errors: inout [ValidationError]) async {
        // Test basic connectivity to API
        do {
            let (_, response) = try await URLSession.shared.data(from: baseURL)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode >= 500 {
                    errors.append(ValidationError(
                        code: "API_SERVER_ERROR",
                        message: "API server returned error status: \(httpResponse.statusCode)",
                        severity: .high,
                        component: .api,
                        suggestedFix: "Check API server status",
                        relatedKeys: ["baseURL"]
                    ))
                }
            }
        } catch {
            errors.append(ValidationError(
                code: "API_CONNECTIVITY_FAILED",
                message: "Cannot connect to API: \(error.localizedDescription)",
                severity: .high,
                component: .api,
                suggestedFix: "Check network connection and API URL",
                relatedKeys: ["baseURL"]
            ))
        }
    }
    
    private func setupValidationTriggers() {
        // Validate when configuration changes
        ConfigurationManager.shared.$currentConfiguration
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.validateAll()
                }
            }
            .store(in: &cancellables)
        
        // Validate when feature flags change
        FeatureFlagManager.shared.$flags
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.validateComponent(.featureFlags)
                }
            }
            .store(in: &cancellables)
    }
    
    private func addToHistory(_ result: ValidationResult) {
        validationHistory.append(result)
        
        if validationHistory.count > maxHistorySize {
            validationHistory.removeFirst()
        }
    }
    
    private func reportValidationFailures(_ result: ValidationResult) {
        let criticalErrors = result.errors.filter { $0.severity == .critical }
        
        for error in criticalErrors {
            let configError = ConfigurationError.configurationValidationFailed
            errorManager.reportError(configError, context: [
                "validation_error_code": error.code,
                "validation_error_message": error.message,
                "component": "\(error.component)",
                "suggested_fix": error.suggestedFix ?? "None"
            ])
        }
    }
}

// MARK: - Validation Extensions
extension ValidationError: Identifiable {
    var id: String { "\(component)_\(code)" }
}

extension ValidationWarning: Identifiable {
    var id: String { "\(component)_\(code)" }
}

extension ValidationResult {
    var summary: String {
        if isValid {
            return hasWarnings ? "Valid with \(warnings.count) warnings" : "All configurations valid"
        } else {
            let criticalCount = errors.filter { $0.severity == .critical }.count
            let errorSummary = criticalCount > 0 ? "\(criticalCount) critical, " : ""
            return "Invalid: \(errorSummary)\(errors.count) total errors"
        }
    }
    
    var healthScore: Double {
        if !isValid {
            let criticalErrors = errors.filter { $0.severity == .critical }.count
            if criticalErrors > 0 {
                return 0.0
            }
            return max(0.0, 1.0 - Double(errors.count) * 0.2)
        }
        
        return max(0.0, 1.0 - Double(warnings.count) * 0.1)
    }
}