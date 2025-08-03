import Foundation
import UIKit
import os.log

// MARK: - Memory Warning Manager
@MainActor
public class MemoryWarningManager: ObservableObject {
    public static let shared = MemoryWarningManager()
    
    @Published public var currentMemoryUsage: Int64 = 0 // bytes
    @Published public var memoryPressureLevel: MemoryPressureLevel = .normal
    @Published public var isAutomaticCleanupEnabled: Bool = true
    @Published public var lastCleanupTime: Date?
    @Published public var cleanupStatistics = CleanupStatistics()
    
    // MARK: - Configuration
    private let warningThresholdMB: Int64 = 300    // 300MB
    private let criticalThresholdMB: Int64 = 450   // 450MB
    private let monitoringInterval: TimeInterval = 2.0
    private let cleanupCooldownInterval: TimeInterval = 30.0
    
    // MARK: - Private Properties
    private var memoryMonitorTimer: Timer?
    private var cleanupHandlers: [CleanupPriority: [CleanupHandler]] = [:]
    private var isCleaningUp = false
    private let logger = Logger(subsystem: "ARchitect", category: "MemoryWarning")
    private var lastWarningTime: Date?
    
    // MARK: - Cleanup Statistics
    public struct CleanupStatistics {
        var totalCleanups: Int = 0
        var automaticCleanups: Int = 0
        var manualCleanups: Int = 0
        var totalMemoryFreed: Int64 = 0 // bytes
        var averageCleanupTime: TimeInterval = 0
        var lastCleanupResult: CleanupResult?
        
        mutating func recordCleanup(result: CleanupResult, duration: TimeInterval, isAutomatic: Bool) {
            totalCleanups += 1
            if isAutomatic {
                automaticCleanups += 1
            } else {
                manualCleanups += 1
            }
            totalMemoryFreed += result.memoryFreed
            averageCleanupTime = ((averageCleanupTime * Double(totalCleanups - 1)) + duration) / Double(totalCleanups)
            lastCleanupResult = result
        }
    }
    
    private init() {
        setupMemoryMonitoring()
        registerDefaultCleanupHandlers()
        logInfo("Memory Warning Manager initialized", category: .system)
    }
    
    deinit {
        stopMemoryMonitoring()
    }
    
    // MARK: - Public Methods
    
    public func startMonitoring() {
        guard memoryMonitorTimer == nil else { return }
        
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: monitoringInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkMemoryUsage()
            }
        }
        
        logInfo("Memory monitoring started", category: .system)
    }
    
    public func stopMemoryMonitoring() {
        memoryMonitorTimer?.invalidate()
        memoryMonitorTimer = nil
        logInfo("Memory monitoring stopped", category: .system)
    }
    
    public func registerCleanupHandler(
        priority: CleanupPriority,
        name: String,
        handler: @escaping () async -> CleanupResult
    ) {
        let cleanupHandler = CleanupHandler(name: name, priority: priority, cleanup: handler)
        
        if cleanupHandlers[priority] == nil {
            cleanupHandlers[priority] = []
        }
        cleanupHandlers[priority]?.append(cleanupHandler)
        
        logDebug("Cleanup handler registered", category: .system, context: LogContext(customData: [
            "handler_name": name,
            "priority": priority.rawValue
        ]))
    }
    
    public func unregisterCleanupHandler(name: String) {
        for priority in CleanupPriority.allCases {
            cleanupHandlers[priority]?.removeAll { $0.name == name }
        }
        
        logDebug("Cleanup handler unregistered", category: .system, context: LogContext(customData: [
            "handler_name": name
        ]))
    }
    
    public func performManualCleanup() async -> CleanupResult {
        return await performCleanup(isAutomatic: false)
    }
    
    public func getMemoryUsageReport() -> MemoryUsageReport {
        let usage = getCurrentMemoryUsage()
        let availableMemory = getAvailableMemory()
        let totalMemory = getTotalMemory()
        
        return MemoryUsageReport(
            currentUsageMB: usage / 1024 / 1024,
            availableMemoryMB: availableMemory / 1024 / 1024,
            totalMemoryMB: totalMemory / 1024 / 1024,
            pressureLevel: memoryPressureLevel,
            warningThresholdMB: warningThresholdMB,
            criticalThresholdMB: criticalThresholdMB,
            cleanupStatistics: cleanupStatistics
        )
    }
    
    // MARK: - Private Methods
    
    private func setupMemoryMonitoring() {
        // Listen for system memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        // Start monitoring
        startMonitoring()
        
        // Initial memory check
        checkMemoryUsage()
    }
    
    @objc private func didReceiveMemoryWarning() {
        logger.warning("System memory warning received")
        
        Task { @MainActor in
            memoryPressureLevel = .critical
            
            if isAutomaticCleanupEnabled {
                await performCleanup(isAutomatic: true)
            }
            
            // Track memory warning
            AnalyticsManager.shared.trackSystemEvent(.memoryWarning, parameters: [
                "memory_usage_mb": currentMemoryUsage / 1024 / 1024,
                "pressure_level": memoryPressureLevel.rawValue,
                "automatic_cleanup": isAutomaticCleanupEnabled
            ])
        }
    }
    
    private func checkMemoryUsage() {
        let usage = getCurrentMemoryUsage()
        currentMemoryUsage = usage
        
        let usageMB = usage / 1024 / 1024
        let previousPressureLevel = memoryPressureLevel
        
        // Determine pressure level
        if usageMB >= criticalThresholdMB {
            memoryPressureLevel = .critical
        } else if usageMB >= warningThresholdMB {
            memoryPressureLevel = .warning
        } else {
            memoryPressureLevel = .normal
        }
        
        // Handle pressure level changes
        if memoryPressureLevel != previousPressureLevel {
            handlePressureLevelChange(from: previousPressureLevel, to: memoryPressureLevel)
        }
        
        // Automatic cleanup if needed
        if shouldPerformAutomaticCleanup() {
            Task {
                await performCleanup(isAutomatic: true)
            }
        }
    }
    
    private func handlePressureLevelChange(from: MemoryPressureLevel, to: MemoryPressureLevel) {
        logInfo("Memory pressure level changed", category: .system, context: LogContext(customData: [
            "from": from.rawValue,
            "to": to.rawValue,
            "memory_usage_mb": currentMemoryUsage / 1024 / 1024
        ]))
        
        // Notify other components about pressure change
        NotificationCenter.default.post(
            name: .memoryPressureLevelChanged,
            object: to,
            userInfo: [
                "previous_level": from,
                "current_usage": currentMemoryUsage
            ]
        )
        
        // Show user warning for critical memory
        if to == .critical && from != .critical {
            showMemoryWarningToUser()
        }
    }
    
    private func shouldPerformAutomaticCleanup() -> Bool {
        guard isAutomaticCleanupEnabled && !isCleaningUp else { return false }
        
        // Don't cleanup too frequently
        if let lastCleanup = lastCleanupTime,
           Date().timeIntervalSince(lastCleanup) < cleanupCooldownInterval {
            return false
        }
        
        // Cleanup on warning or critical pressure
        return memoryPressureLevel == .warning || memoryPressureLevel == .critical
    }
    
    private func performCleanup(isAutomatic: Bool) async -> CleanupResult {
        guard !isCleaningUp else {
            return CleanupResult(memoryFreed: 0, handlersExecuted: 0, success: false, error: "Cleanup already in progress")
        }
        
        isCleaningUp = true
        let startTime = Date()
        let initialMemory = getCurrentMemoryUsage()
        
        logInfo("Starting memory cleanup", category: .system, context: LogContext(customData: [
            "is_automatic": isAutomatic,
            "initial_memory_mb": initialMemory / 1024 / 1024,
            "pressure_level": memoryPressureLevel.rawValue
        ]))
        
        var totalMemoryFreed: Int64 = 0
        var handlersExecuted = 0
        var errors: [String] = []
        
        // Execute cleanup handlers by priority
        for priority in CleanupPriority.allCases.sorted(by: { $0.order < $1.order }) {
            guard let handlers = cleanupHandlers[priority], !handlers.isEmpty else { continue }
            
            // For critical memory pressure, execute all handlers
            // For warning, skip low priority handlers
            if memoryPressureLevel == .warning && priority == .low {
                continue
            }
            
            logDebug("Executing cleanup handlers", category: .system, context: LogContext(customData: [
                "priority": priority.rawValue,
                "handler_count": handlers.count
            ]))
            
            for handler in handlers {
                do {
                    let handlerStartTime = Date()
                    let result = await handler.cleanup()
                    let handlerDuration = Date().timeIntervalSince(handlerStartTime)
                    
                    totalMemoryFreed += result.memoryFreed
                    handlersExecuted += 1
                    
                    logDebug("Cleanup handler executed", category: .system, context: LogContext(customData: [
                        "handler_name": handler.name,
                        "memory_freed_mb": result.memoryFreed / 1024 / 1024,
                        "duration": handlerDuration,
                        "success": result.success
                    ]))
                    
                    if !result.success, let error = result.error {
                        errors.append("\(handler.name): \(error)")
                    }
                    
                } catch {
                    errors.append("\(handler.name): \(error.localizedDescription)")
                    logError("Cleanup handler failed", category: .system, context: LogContext(customData: [
                        "handler_name": handler.name
                    ]), error: error)
                }
            }
        }
        
        isCleaningUp = false
        lastCleanupTime = Date()
        let duration = Date().timeIntervalSince(startTime)
        let finalMemory = getCurrentMemoryUsage()
        let actualMemoryFreed = max(0, initialMemory - finalMemory)
        
        let result = CleanupResult(
            memoryFreed: actualMemoryFreed,
            handlersExecuted: handlersExecuted,
            success: errors.isEmpty,
            error: errors.isEmpty ? nil : errors.joined(separator: "; "),
            duration: duration
        )
        
        // Update statistics
        cleanupStatistics.recordCleanup(result: result, duration: duration, isAutomatic: isAutomatic)
        
        logInfo("Memory cleanup completed", category: .system, context: LogContext(customData: [
            "memory_freed_mb": actualMemoryFreed / 1024 / 1024,
            "handlers_executed": handlersExecuted,
            "duration": duration,
            "success": result.success,
            "final_memory_mb": finalMemory / 1024 / 1024
        ]))
        
        // Track cleanup completion
        AnalyticsManager.shared.trackSystemEvent(.memoryCleanup, parameters: [
            "memory_freed_mb": actualMemoryFreed / 1024 / 1024,
            "handlers_executed": handlersExecuted,
            "duration": duration,
            "is_automatic": isAutomatic,
            "success": result.success
        ])
        
        return result
    }
    
    private func registerDefaultCleanupHandlers() {
        // High priority: Critical AR resources
        registerCleanupHandler(priority: .high, name: "ar_session_cleanup") {
            await self.cleanupARResources()
        }
        
        // High priority: 3D models and textures
        registerCleanupHandler(priority: .high, name: "model_cache_cleanup") {
            await self.cleanupModelCache()
        }
        
        // Medium priority: Image caches
        registerCleanupHandler(priority: .medium, name: "image_cache_cleanup") {
            await self.cleanupImageCache()
        }
        
        // Medium priority: Analytics data
        registerCleanupHandler(priority: .medium, name: "analytics_cleanup") {
            await self.cleanupAnalyticsData()
        }
        
        // Low priority: UI caches
        registerCleanupHandler(priority: .low, name: "ui_cache_cleanup") {
            await self.cleanupUICache()
        }
        
        // Low priority: Temporary files
        registerCleanupHandler(priority: .low, name: "temp_files_cleanup") {
            await self.cleanupTemporaryFiles()
        }
    }
    
    // MARK: - Cleanup Implementations
    
    private func cleanupARResources() async -> CleanupResult {
        let initialMemory = getCurrentMemoryUsage()
        
        // Notify AR session to cleanup
        NotificationCenter.default.post(name: .cleanupARResources, object: nil)
        
        // Allow time for cleanup to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        let finalMemory = getCurrentMemoryUsage()
        let memoryFreed = max(0, initialMemory - finalMemory)
        
        return CleanupResult(
            memoryFreed: memoryFreed,
            handlersExecuted: 1,
            success: true
        )
    }
    
    private func cleanupModelCache() async -> CleanupResult {
        let initialMemory = getCurrentMemoryUsage()
        
        // Notify model manager to cleanup
        NotificationCenter.default.post(name: .cleanupModelCache, object: nil)
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        let finalMemory = getCurrentMemoryUsage()
        let memoryFreed = max(0, initialMemory - finalMemory)
        
        return CleanupResult(
            memoryFreed: memoryFreed,
            handlersExecuted: 1,
            success: true
        )
    }
    
    private func cleanupImageCache() async -> CleanupResult {
        let initialMemory = getCurrentMemoryUsage()
        
        // Clear URLSession cache
        URLCache.shared.removeAllCachedResponses()
        
        // Notify image loading systems to cleanup
        NotificationCenter.default.post(name: .cleanupImageCache, object: nil)
        
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        let finalMemory = getCurrentMemoryUsage()
        let memoryFreed = max(0, initialMemory - finalMemory)
        
        return CleanupResult(
            memoryFreed: memoryFreed,
            handlersExecuted: 1,
            success: true
        )
    }
    
    private func cleanupAnalyticsData() async -> CleanupResult {
        let initialMemory = getCurrentMemoryUsage()
        
        // Notify analytics manager to flush and cleanup
        NotificationCenter.default.post(name: .cleanupAnalyticsData, object: nil)
        
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        let finalMemory = getCurrentMemoryUsage()
        let memoryFreed = max(0, initialMemory - finalMemory)
        
        return CleanupResult(
            memoryFreed: memoryFreed,
            handlersExecuted: 1,
            success: true
        )
    }
    
    private func cleanupUICache() async -> CleanupResult {
        let initialMemory = getCurrentMemoryUsage()
        
        // Notify UI components to cleanup
        NotificationCenter.default.post(name: .cleanupUICache, object: nil)
        
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        let finalMemory = getCurrentMemoryUsage()
        let memoryFreed = max(0, initialMemory - finalMemory)
        
        return CleanupResult(
            memoryFreed: memoryFreed,
            handlersExecuted: 1,
            success: true
        )
    }
    
    private func cleanupTemporaryFiles() async -> CleanupResult {
        let initialMemory = getCurrentMemoryUsage()
        var filesDeleted = 0
        
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.creationDateKey])
            
            let cutoffDate = Date().addingTimeInterval(-3600) // 1 hour old
            
            for fileURL in contents {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey])
                    if let creationDate = resourceValues.creationDate, creationDate < cutoffDate {
                        try FileManager.default.removeItem(at: fileURL)
                        filesDeleted += 1
                    }
                } catch {
                    // Continue with other files
                }
            }
        } catch {
            return CleanupResult(
                memoryFreed: 0,
                handlersExecuted: 1,
                success: false,
                error: error.localizedDescription
            )
        }
        
        let finalMemory = getCurrentMemoryUsage()
        let memoryFreed = max(0, initialMemory - finalMemory)
        
        return CleanupResult(
            memoryFreed: memoryFreed,
            handlersExecuted: 1,
            success: true,
            metadata: ["files_deleted": filesDeleted]
        )
    }
    
    private func showMemoryWarningToUser() {
        let now = Date()
        
        // Don't show warnings too frequently
        if let lastWarning = lastWarningTime,
           now.timeIntervalSince(lastWarning) < 60.0 { // 1 minute
            return
        }
        
        lastWarningTime = now
        
        // Notify UI to show memory warning
        NotificationCenter.default.post(
            name: .showMemoryWarning,
            object: nil,
            userInfo: [
                "memory_usage_mb": currentMemoryUsage / 1024 / 1024,
                "message": "Low memory available. Some features may be limited."
            ]
        )
    }
    
    // MARK: - Memory Utilities
    
    private func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
    
    private func getAvailableMemory() -> Int64 {
        let host = mach_host_self()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var hostInfo = vm_statistics64_data_t()
        
        let result = withUnsafeMutablePointer(to: &hostInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &size)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0 }
        
        let pageSize = Int64(vm_kernel_page_size)
        let freePages = Int64(hostInfo.free_count)
        
        return freePages * pageSize
    }
    
    private func getTotalMemory() -> Int64 {
        return Int64(ProcessInfo.processInfo.physicalMemory)
    }
}

// MARK: - Supporting Types

public enum MemoryPressureLevel: String, CaseIterable {
    case normal = "normal"
    case warning = "warning"
    case critical = "critical"
    
    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
    
    var color: UIColor {
        switch self {
        case .normal: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }
}

public enum CleanupPriority: String, CaseIterable {
    case high = "high"
    case medium = "medium"
    case low = "low"
    
    var order: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

public struct CleanupHandler {
    let name: String
    let priority: CleanupPriority
    let cleanup: () async -> CleanupResult
}

public struct CleanupResult {
    let memoryFreed: Int64
    let handlersExecuted: Int
    let success: Bool
    let error: String?
    let duration: TimeInterval?
    let metadata: [String: Any]?
    
    init(
        memoryFreed: Int64,
        handlersExecuted: Int,
        success: Bool,
        error: String? = nil,
        duration: TimeInterval? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.memoryFreed = memoryFreed
        self.handlersExecuted = handlersExecuted
        self.success = success
        self.error = error
        self.duration = duration
        self.metadata = metadata
    }
}

public struct MemoryUsageReport {
    let currentUsageMB: Int64
    let availableMemoryMB: Int64
    let totalMemoryMB: Int64
    let pressureLevel: MemoryPressureLevel
    let warningThresholdMB: Int64
    let criticalThresholdMB: Int64
    let cleanupStatistics: MemoryWarningManager.CleanupStatistics
    
    var usagePercentage: Double {
        return Double(currentUsageMB) / Double(totalMemoryMB) * 100.0
    }
    
    var formattedCurrentUsage: String {
        return formatBytes(currentUsageMB * 1024 * 1024)
    }
    
    var formattedAvailableMemory: String {
        return formatBytes(availableMemoryMB * 1024 * 1024)
    }
    
    var formattedTotalMemory: String {
        return formatBytes(totalMemoryMB * 1024 * 1024)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let memoryPressureLevelChanged = Notification.Name("memoryPressureLevelChanged")
    static let showMemoryWarning = Notification.Name("showMemoryWarning")
    static let cleanupARResources = Notification.Name("cleanupARResources")
    static let cleanupModelCache = Notification.Name("cleanupModelCache")
    static let cleanupImageCache = Notification.Name("cleanupImageCache")
    static let cleanupAnalyticsData = Notification.Name("cleanupAnalyticsData")
    static let cleanupUICache = Notification.Name("cleanupUICache")
}