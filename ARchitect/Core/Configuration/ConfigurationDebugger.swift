import Foundation
import SwiftUI
import Combine

// MARK: - Debug Information
struct ConfigurationDebugInfo {
    let timestamp: Date
    let environment: AppEnvironment
    let configurationHealth: ConfigurationHealth
    let activeFeatureFlags: [String: Bool]
    let performanceMetrics: PerformanceDebugInfo
    let networkStatus: NetworkDebugInfo
    let storageInfo: StorageDebugInfo
    let validationResults: ValidationResult?
    let syncStatus: SyncDebugInfo
    let errorCounts: [String: Int]
    
    struct ConfigurationHealth {
        let isValid: Bool
        let healthScore: Double
        let criticalIssues: Int
        let warnings: Int
        let lastValidatedAt: Date?
    }
    
    struct PerformanceDebugInfo {
        let memoryUsageMB: Double
        let cpuUsagePercent: Double
        let frameRate: Double
        let activeOptimizations: [String]
        let isThrottled: Bool
    }
    
    struct NetworkDebugInfo {
        let isConnected: Bool
        let connectionType: String
        let lastSyncTime: Date?
        let pendingRequests: Int
    }
    
    struct StorageDebugInfo {
        let offlineDataSizeMB: Double
        let cachedItemsCount: Int
        let lastCleanupTime: Date?
        let storageQuotaUsedPercent: Double
    }
    
    struct SyncDebugInfo {
        let status: String
        let lastSyncTime: Date?
        let pendingUpdates: Int
        let appliedUpdates: Int
        let failedSyncs: Int
    }
}

// MARK: - Configuration Debugger
class ConfigurationDebugger: ObservableObject {
    static let shared = ConfigurationDebugger()
    
    @Published private(set) var debugInfo: ConfigurationDebugInfo?
    @Published private(set) var isDebuggingEnabled = false
    @Published private(set) var debugLogs: [DebugLogEntry] = []
    @Published private(set) var configurationTrace: [ConfigurationTraceEntry] = []
    
    private let configurationManager = ConfigurationManager.shared
    private let validator = ConfigurationValidator.shared
    private let syncManager = ConfigurationSyncManager.shared
    private let performanceManager = PerformanceManager.shared
    private let offlineManager = OfflineManager.shared
    private let featureFlags = FeatureFlagManager.shared
    private let errorManager = ErrorManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    private let maxDebugLogs = 500
    private let maxTraceEntries = 100
    
    struct DebugLogEntry {
        let id = UUID()
        let timestamp: Date
        let level: LogLevel
        let category: String
        let message: String
        let context: [String: Any]
        
        enum LogLevel: String, CaseIterable {
            case verbose = "VERBOSE"
            case debug = "DEBUG"
            case info = "INFO"
            case warning = "WARNING"
            case error = "ERROR"
        }
    }
    
    struct ConfigurationTraceEntry {
        let id = UUID()
        let timestamp: Date
        let action: TraceAction
        let component: String
        let details: String
        let duration: TimeInterval?
        
        enum TraceAction {
            case load
            case validate
            case update
            case sync
            case error
            case rollback
        }
    }
    
    private init() {
        setupDebugMonitoring()
        
        // Enable debugging in development
        if AppEnvironment.current == .development {
            enableDebugging()
        }
    }
    
    // MARK: - Public Methods
    
    func enableDebugging() {
        isDebuggingEnabled = true
        startDebugDataCollection()
        logDebug("Configuration debugging enabled", category: "Debugger")
    }
    
    func disableDebugging() {
        isDebuggingEnabled = false
        stopDebugDataCollection()
        logDebug("Configuration debugging disabled", category: "Debugger")
    }
    
    func refreshDebugInfo() async {
        guard isDebuggingEnabled else { return }
        
        let startTime = Date()
        
        let health = await getConfigurationHealth()
        let performance = getPerformanceDebugInfo()
        let network = getNetworkDebugInfo()
        let storage = getStorageDebugInfo()
        let sync = getSyncDebugInfo()
        let errorCounts = getErrorCounts()
        
        let info = ConfigurationDebugInfo(
            timestamp: Date(),
            environment: AppEnvironment.current,
            configurationHealth: health,
            activeFeatureFlags: featureFlags.flags,
            performanceMetrics: performance,
            networkStatus: network,
            storageInfo: storage,
            validationResults: validator.lastValidationResult,
            syncStatus: sync,
            errorCounts: errorCounts
        )
        
        await MainActor.run {
            self.debugInfo = info
        }
        
        let duration = Date().timeIntervalSince(startTime)
        addTraceEntry(.load, component: "DebugInfo", details: "Refreshed debug information", duration: duration)
    }
    
    func exportDebugReport() -> Data? {
        guard let debugInfo = debugInfo else { return nil }
        
        let report: [String: Any] = [
            "exportTime": ISO8601DateFormatter().string(from: Date()),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "Unknown",
            "environment": debugInfo.environment.rawValue,
            "debugInfo": [
                "configurationHealth": [
                    "isValid": debugInfo.configurationHealth.isValid,
                    "healthScore": debugInfo.configurationHealth.healthScore,
                    "criticalIssues": debugInfo.configurationHealth.criticalIssues,
                    "warnings": debugInfo.configurationHealth.warnings
                ],
                "activeFeatureFlags": debugInfo.activeFeatureFlags,
                "performanceMetrics": [
                    "memoryUsageMB": debugInfo.performanceMetrics.memoryUsageMB,
                    "cpuUsagePercent": debugInfo.performanceMetrics.cpuUsagePercent,
                    "frameRate": debugInfo.performanceMetrics.frameRate,
                    "isThrottled": debugInfo.performanceMetrics.isThrottled
                ],
                "networkStatus": [
                    "isConnected": debugInfo.networkStatus.isConnected,
                    "connectionType": debugInfo.networkStatus.connectionType
                ],
                "syncStatus": [
                    "status": debugInfo.syncStatus.status,
                    "pendingUpdates": debugInfo.syncStatus.pendingUpdates,
                    "appliedUpdates": debugInfo.syncStatus.appliedUpdates
                ]
            ],
            "recentLogs": debugLogs.suffix(50).map { log in
                [
                    "timestamp": ISO8601DateFormatter().string(from: log.timestamp),
                    "level": log.level.rawValue,
                    "category": log.category,
                    "message": log.message
                ]
            },
            "configurationTrace": configurationTrace.suffix(20).map { trace in
                [
                    "timestamp": ISO8601DateFormatter().string(from: trace.timestamp),
                    "action": "\(trace.action)",
                    "component": trace.component,
                    "details": trace.details,
                    "duration": trace.duration ?? 0
                ]
            }
        ]
        
        return try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted)
    }
    
    func clearDebugData() {
        debugLogs.removeAll()
        configurationTrace.removeAll()
        logDebug("Debug data cleared", category: "Debugger")
    }
    
    func testConfiguration() async -> [ConfigurationTestResult] {
        var results: [ConfigurationTestResult] = []
        
        // Test API connectivity
        results.append(await testAPIConnectivity())
        
        // Test secure storage
        results.append(testSecureStorage())
        
        // Test feature flags
        results.append(testFeatureFlags())
        
        // Test performance thresholds
        results.append(testPerformanceThresholds())
        
        // Test validation system
        results.append(await testValidationSystem())
        
        return results
    }
    
    func simulateConfigurationScenarios() async {
        guard isDebuggingEnabled else { return }
        
        logDebug("Starting configuration scenario simulation", category: "Testing")
        
        // Simulate network disconnection
        await simulateNetworkDisconnection()
        
        // Simulate memory pressure
        await simulateMemoryPressure()
        
        // Simulate configuration update
        await simulateConfigurationUpdate()
        
        // Simulate validation failure
        await simulateValidationFailure()
        
        logDebug("Configuration scenario simulation completed", category: "Testing")
    }
    
    struct ConfigurationTestResult {
        let testName: String
        let passed: Bool
        let message: String
        let duration: TimeInterval
        let details: [String: Any]
    }
    
    // MARK: - Private Methods
    
    private func setupDebugMonitoring() {
        // Monitor configuration changes
        configurationManager.$currentConfiguration
            .sink { [weak self] _ in
                self?.addTraceEntry(.update, component: "Configuration", details: "Configuration updated")
            }
            .store(in: &cancellables)
        
        // Monitor validation results
        validator.$lastValidationResult
            .sink { [weak self] result in
                if let result = result {
                    let message = result.isValid ? "Validation passed" : "Validation failed with \(result.errors.count) errors"
                    self?.addTraceEntry(.validate, component: "Validator", details: message)
                }
            }
            .store(in: &cancellables)
        
        // Monitor sync status
        syncManager.$syncStatus
            .sink { [weak self] status in
                let details = "Sync status: \(status)"
                self?.addTraceEntry(.sync, component: "SyncManager", details: details)
            }
            .store(in: &cancellables)
        
        // Monitor errors
        NotificationCenter.default.publisher(for: .errorOccurred)
            .sink { [weak self] notification in
                if let error = notification.object as? AppErrorProtocol {
                    self?.addTraceEntry(.error, component: "ErrorManager", details: "Error: \(error.errorCode)")
                }
            }
            .store(in: &cancellables)
    }
    
    private func startDebugDataCollection() {
        // Start periodic debug info refresh
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshDebugInfo()
            }
        }
    }
    
    private func stopDebugDataCollection() {
        // Stop timers and clear data if needed
    }
    
    private func getConfigurationHealth() async -> ConfigurationDebugInfo.ConfigurationHealth {
        let validationResult = await validator.validateAll()
        
        return ConfigurationDebugInfo.ConfigurationHealth(
            isValid: validationResult.isValid,
            healthScore: validationResult.healthScore,
            criticalIssues: validationResult.errors.filter { $0.severity == .critical }.count,
            warnings: validationResult.warnings.count,
            lastValidatedAt: validationResult.validatedAt
        )
    }
    
    private func getPerformanceDebugInfo() -> ConfigurationDebugInfo.PerformanceDebugInfo {
        let metrics = performanceManager.currentMetrics
        
        return ConfigurationDebugInfo.PerformanceDebugInfo(
            memoryUsageMB: metrics.memoryUsageMB,
            cpuUsagePercent: metrics.cpuUsagePercent,
            frameRate: metrics.frameRate,
            activeOptimizations: performanceManager.activeOptimizations.map { "\($0)" },
            isThrottled: performanceManager.isThrottled
        )
    }
    
    private func getNetworkDebugInfo() -> ConfigurationDebugInfo.NetworkDebugInfo {
        let networkStatus = offlineManager.networkStatus
        
        let connectionType: String
        switch networkStatus {
        case .connected(let type):
            connectionType = "\(type)"
        case .disconnected:
            connectionType = "disconnected"
        case .unknown:
            connectionType = "unknown"
        }
        
        return ConfigurationDebugInfo.NetworkDebugInfo(
            isConnected: networkStatus.isConnected,
            connectionType: connectionType,
            lastSyncTime: syncManager.lastSyncTime,
            pendingRequests: 0 // This would be tracked by a network manager
        )
    }
    
    private func getStorageDebugInfo() -> ConfigurationDebugInfo.StorageDebugInfo {
        let offlineDataSize = Double(offlineManager.offlineDataSize) / (1024 * 1024) // Convert to MB
        
        return ConfigurationDebugInfo.StorageDebugInfo(
            offlineDataSizeMB: offlineDataSize,
            cachedItemsCount: 0, // This would be tracked by a cache manager
            lastCleanupTime: nil,
            storageQuotaUsedPercent: min(100.0, offlineDataSize / 100.0 * 100) // Assuming 100MB quota
        )
    }
    
    private func getSyncDebugInfo() -> ConfigurationDebugInfo.SyncDebugInfo {
        let status: String
        switch syncManager.syncStatus {
        case .idle:
            status = "idle"
        case .syncing:
            status = "syncing"
        case .success:
            status = "success"
        case .failed:
            status = "failed"
        case .noConnection:
            status = "no_connection"
        }
        
        return ConfigurationDebugInfo.SyncDebugInfo(
            status: status,
            lastSyncTime: syncManager.lastSyncTime,
            pendingUpdates: syncManager.pendingUpdates.count,
            appliedUpdates: syncManager.appliedUpdates.count,
            failedSyncs: 0 // This would be tracked
        )
    }
    
    private func getErrorCounts() -> [String: Int] {
        // This would track error counts by category
        return [
            "network": 0,
            "ar": 0,
            "storage": 0,
            "configuration": 0
        ]
    }
    
    private func logDebug(_ message: String, category: String, level: DebugLogEntry.LogLevel = .debug, context: [String: Any] = [:]) {
        guard isDebuggingEnabled else { return }
        
        let entry = DebugLogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            context: context
        )
        
        debugLogs.append(entry)
        
        // Maintain size limit
        if debugLogs.count > maxDebugLogs {
            debugLogs.removeFirst(debugLogs.count - maxDebugLogs)
        }
    }
    
    private func addTraceEntry(_ action: ConfigurationTraceEntry.TraceAction, component: String, details: String, duration: TimeInterval? = nil) {
        guard isDebuggingEnabled else { return }
        
        let entry = ConfigurationTraceEntry(
            timestamp: Date(),
            action: action,
            component: component,
            details: details,
            duration: duration
        )
        
        configurationTrace.append(entry)
        
        // Maintain size limit
        if configurationTrace.count > maxTraceEntries {
            configurationTrace.removeFirst(configurationTrace.count - maxTraceEntries)
        }
    }
    
    // MARK: - Test Methods
    
    private func testAPIConnectivity() async -> ConfigurationTestResult {
        let startTime = Date()
        let config = configurationManager.currentConfiguration
        
        do {
            let (_, response) = try await URLSession.shared.data(from: config.apiConfiguration.baseURL)
            let duration = Date().timeIntervalSince(startTime)
            
            if let httpResponse = response as? HTTPURLResponse {
                let passed = httpResponse.statusCode < 500
                return ConfigurationTestResult(
                    testName: "API Connectivity",
                    passed: passed,
                    message: passed ? "API is reachable" : "API returned error status \(httpResponse.statusCode)",
                    duration: duration,
                    details: ["statusCode": httpResponse.statusCode, "url": config.apiConfiguration.baseURL.absoluteString]
                )
            } else {
                return ConfigurationTestResult(
                    testName: "API Connectivity",
                    passed: false,
                    message: "Invalid response type",
                    duration: duration,
                    details: ["url": config.apiConfiguration.baseURL.absoluteString]
                )
            }
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return ConfigurationTestResult(
                testName: "API Connectivity",
                passed: false,
                message: "Connection failed: \(error.localizedDescription)",
                duration: duration,
                details: ["error": error.localizedDescription, "url": config.apiConfiguration.baseURL.absoluteString]
            )
        }
    }
    
    private func testSecureStorage() -> ConfigurationTestResult {
        let startTime = Date()
        let testKey = "debug_test_key"
        let testValue = "debug_test_value_\(UUID().uuidString)"
        
        do {
            let secureStorage = SecureConfigurationStorage.shared
            
            // Test write
            try secureStorage.storeAPIKey(testValue, for: .development)
            
            // Test read
            let retrievedValue = try secureStorage.retrieveAPIKey(for: .development)
            
            // Cleanup
            try? secureStorage.clearAuthenticationData()
            
            let duration = Date().timeIntervalSince(startTime)
            let passed = retrievedValue == testValue
            
            return ConfigurationTestResult(
                testName: "Secure Storage",
                passed: passed,
                message: passed ? "Secure storage working correctly" : "Read/write mismatch",
                duration: duration,
                details: ["expected": testValue, "actual": retrievedValue ?? "nil"]
            )
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return ConfigurationTestResult(
                testName: "Secure Storage",
                passed: false,
                message: "Secure storage failed: \(error.localizedDescription)",
                duration: duration,
                details: ["error": error.localizedDescription]
            )
        }
    }
    
    private func testFeatureFlags() -> ConfigurationTestResult {
        let startTime = Date()
        
        // Test flag operations
        let testFlag = FeatureFlagKey.newOnboardingFlow
        let originalValue = featureFlags.isEnabled(testFlag)
        
        // Toggle flag
        featureFlags.enableFlag(testFlag, temporarily: true)
        let enabledValue = featureFlags.isEnabled(testFlag)
        
        featureFlags.disableFlag(testFlag, temporarily: true)
        let disabledValue = featureFlags.isEnabled(testFlag)
        
        // Restore original value
        if originalValue {
            featureFlags.enableFlag(testFlag, temporarily: true)
        } else {
            featureFlags.disableFlag(testFlag, temporarily: true)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let passed = enabledValue == true && disabledValue == false
        
        return ConfigurationTestResult(
            testName: "Feature Flags",
            passed: passed,
            message: passed ? "Feature flag operations working correctly" : "Feature flag toggle failed",
            duration: duration,
            details: [
                "testFlag": testFlag.rawValue,
                "originalValue": originalValue,
                "enabledValue": enabledValue,
                "disabledValue": disabledValue
            ]
        )
    }
    
    private func testPerformanceThresholds() -> ConfigurationTestResult {
        let startTime = Date()
        let metrics = performanceManager.currentMetrics
        let thresholds = PerformanceThresholds.forEnvironment(AppEnvironment.current)
        
        var issues: [String] = []
        
        if metrics.memoryUsageMB > thresholds.memoryCriticalMB {
            issues.append("Memory usage critical")
        }
        
        if metrics.cpuUsagePercent > thresholds.cpuCriticalPercent {
            issues.append("CPU usage critical")
        }
        
        if metrics.frameRate < thresholds.frameRateCritical {
            issues.append("Frame rate critical")
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let passed = issues.isEmpty
        
        return ConfigurationTestResult(
            testName: "Performance Thresholds",
            passed: passed,
            message: passed ? "Performance within acceptable thresholds" : "Performance issues: \(issues.joined(separator: ", "))",
            duration: duration,
            details: [
                "memoryUsageMB": metrics.memoryUsageMB,
                "cpuUsagePercent": metrics.cpuUsagePercent,
                "frameRate": metrics.frameRate,
                "issues": issues
            ]
        )
    }
    
    private func testValidationSystem() async -> ConfigurationTestResult {
        let startTime = Date()
        
        let validationResult = await validator.validateAll()
        let duration = Date().timeIntervalSince(startTime)
        
        let criticalErrors = validationResult.errors.filter { $0.severity == .critical }.count
        let passed = criticalErrors == 0
        
        return ConfigurationTestResult(
            testName: "Configuration Validation",
            passed: passed,
            message: passed ? "All configurations valid" : "\(criticalErrors) critical validation errors",
            duration: duration,
            details: [
                "isValid": validationResult.isValid,
                "errorCount": validationResult.errors.count,
                "warningCount": validationResult.warnings.count,
                "healthScore": validationResult.healthScore
            ]
        )
    }
    
    // MARK: - Simulation Methods
    
    private func simulateNetworkDisconnection() async {
        logDebug("Simulating network disconnection", category: "Simulation")
        
        // This would simulate network disconnection scenarios
        // In a real implementation, you might use network conditioning tools
        
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        logDebug("Network disconnection simulation completed", category: "Simulation")
    }
    
    private func simulateMemoryPressure() async {
        logDebug("Simulating memory pressure", category: "Simulation")
        
        // This would simulate memory pressure scenarios
        performanceManager.triggerMemoryCleanup()
        
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        logDebug("Memory pressure simulation completed", category: "Simulation")
    }
    
    private func simulateConfigurationUpdate() async {
        logDebug("Simulating configuration update", category: "Simulation")
        
        // This would simulate a configuration update scenario
        await configurationManager.reloadConfiguration()
        
        logDebug("Configuration update simulation completed", category: "Simulation")
    }
    
    private func simulateValidationFailure() async {
        logDebug("Simulating validation failure", category: "Simulation")
        
        // This would simulate validation failure scenarios
        // In practice, you might temporarily corrupt a configuration value
        
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        logDebug("Validation failure simulation completed", category: "Simulation")
    }
}

// MARK: - Debug View (SwiftUI)
struct ConfigurationDebugView: View {
    @ObservedObject private var debugger = ConfigurationDebugger.shared
    @State private var selectedTab = 0
    @State private var showingExportSheet = false
    @State private var exportData: Data?
    
    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                OverviewTab()
                    .tabItem {
                        Image(systemName: "info.circle")
                        Text("Overview")
                    }
                    .tag(0)
                
                LogsTab()
                    .tabItem {
                        Image(systemName: "doc.text")
                        Text("Logs")
                    }
                    .tag(1)
                
                TestsTab()
                    .tabItem {
                        Image(systemName: "checkmark.circle")
                        Text("Tests")
                    }
                    .tag(2)
                
                TraceTab()
                    .tabItem {
                        Image(systemName: "timeline.selection")
                        Text("Trace")
                    }
                    .tag(3)
            }
            .navigationTitle("Configuration Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("Export") {
                        exportDebugReport()
                    }
                    
                    Button("Clear") {
                        debugger.clearDebugData()
                    }
                }
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            if let data = exportData {
                ActivityViewController(activityItems: [data])
            }
        }
        .onAppear {
            Task {
                await debugger.refreshDebugInfo()
            }
        }
    }
    
    private func exportDebugReport() {
        exportData = debugger.exportDebugReport()
        showingExportSheet = true
    }
}

// MARK: - Tab Views
struct OverviewTab: View {
    @ObservedObject private var debugger = ConfigurationDebugger.shared
    
    var body: some View {
        List {
            if let debugInfo = debugger.debugInfo {
                Section("Configuration Health") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(debugInfo.configurationHealth.isValid ? "Valid" : "Invalid")
                            .foregroundColor(debugInfo.configurationHealth.isValid ? .green : .red)
                    }
                    
                    HStack {
                        Text("Health Score")
                        Spacer()
                        Text("\(Int(debugInfo.configurationHealth.healthScore * 100))%")
                    }
                    
                    HStack {
                        Text("Critical Issues")
                        Spacer()
                        Text("\(debugInfo.configurationHealth.criticalIssues)")
                            .foregroundColor(debugInfo.configurationHealth.criticalIssues > 0 ? .red : .green)
                    }
                }
                
                Section("Performance") {
                    HStack {
                        Text("Memory Usage")
                        Spacer()
                        Text("\(Int(debugInfo.performanceMetrics.memoryUsageMB)) MB")
                    }
                    
                    HStack {
                        Text("Frame Rate")
                        Spacer()
                        Text("\(Int(debugInfo.performanceMetrics.frameRate)) FPS")
                    }
                    
                    HStack {
                        Text("Is Throttled")
                        Spacer()
                        Text(debugInfo.performanceMetrics.isThrottled ? "Yes" : "No")
                            .foregroundColor(debugInfo.performanceMetrics.isThrottled ? .orange : .green)
                    }
                }
                
                Section("Network & Sync") {
                    HStack {
                        Text("Connection")
                        Spacer()
                        Text(debugInfo.networkStatus.isConnected ? "Connected" : "Disconnected")
                            .foregroundColor(debugInfo.networkStatus.isConnected ? .green : .red)
                    }
                    
                    HStack {
                        Text("Sync Status")
                        Spacer()
                        Text(debugInfo.syncStatus.status.capitalized)
                    }
                    
                    HStack {
                        Text("Pending Updates")
                        Spacer()
                        Text("\(debugInfo.syncStatus.pendingUpdates)")
                    }
                }
            } else {
                Text("Loading debug information...")
                    .foregroundColor(.secondary)
            }
        }
        .refreshable {
            await debugger.refreshDebugInfo()
        }
    }
}

struct LogsTab: View {
    @ObservedObject private var debugger = ConfigurationDebugger.shared
    
    var body: some View {
        List(debugger.debugLogs.reversed(), id: \.id) { log in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(log.level.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(colorForLogLevel(log.level))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    
                    Text(log.category)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(formatTime(log.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(log.message)
                    .font(.body)
            }
            .padding(.vertical, 2)
        }
    }
    
    private func colorForLogLevel(_ level: ConfigurationDebugger.DebugLogEntry.LogLevel) -> Color {
        switch level {
        case .verbose:
            return .gray
        case .debug:
            return .blue
        case .info:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct TestsTab: View {
    @State private var testResults: [ConfigurationDebugger.ConfigurationTestResult] = []
    @State private var isRunningTests = false
    
    var body: some View {
        VStack {
            Button("Run Configuration Tests") {
                runTests()
            }
            .disabled(isRunningTests)
            .padding()
            
            List(testResults, id: \.testName) { result in
                HStack {
                    Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.passed ? .green : .red)
                    
                    VStack(alignment: .leading) {
                        Text(result.testName)
                            .font(.headline)
                        
                        Text(result.message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Duration: \(String(format: "%.3f", result.duration))s")
                            .font(.caption2)
                            .foregroundColor(.tertiary)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }
    
    private func runTests() {
        isRunningTests = true
        
        Task {
            let results = await ConfigurationDebugger.shared.testConfiguration()
            
            await MainActor.run {
                self.testResults = results
                self.isRunningTests = false
            }
        }
    }
}

struct TraceTab: View {
    @ObservedObject private var debugger = ConfigurationDebugger.shared
    
    var body: some View {
        List(debugger.configurationTrace.reversed(), id: \.id) { trace in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(trace.action)".capitalized)
                            .font(.headline)
                        
                        Text(trace.component)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    Text(trace.details)
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text(formatTime(trace.timestamp))
                            .font(.caption2)
                            .foregroundColor(.tertiary)
                        
                        if let duration = trace.duration {
                            Text("(\(String(format: "%.3f", duration))s)")
                                .font(.caption2)
                                .foregroundColor(.tertiary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 2)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Helper Views
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}