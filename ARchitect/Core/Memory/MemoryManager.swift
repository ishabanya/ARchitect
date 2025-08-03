import Foundation
import Combine

/// Centralized memory management utility
@MainActor
final class MemoryManager: ObservableObject {
    static let shared = MemoryManager()
    
    // MARK: - Published Properties
    @Published private(set) var currentMemoryUsage: Int = 0
    @Published private(set) var peakMemoryUsage: Int = 0
    @Published private(set) var memoryWarnings: [MemoryWarning] = []
    @Published private(set) var isMemoryPressureHigh = false
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var memoryMonitoringTimer: Timer?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private weak var applicationDelegate: NSObject?
    
    // Memory thresholds (in bytes)
    private let warningThreshold: Int = 200 * 1024 * 1024 // 200MB
    private let criticalThreshold: Int = 400 * 1024 * 1024 // 400MB
    
    private init() {
        setupMemoryMonitoring()
        setupMemoryPressureMonitoring()
        setupApplicationLifecycleObservers()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring memory usage
    func startMonitoring() {
        guard memoryMonitoringTimer == nil else { return }
        
        memoryMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMemoryUsage()
            }
        }
        
        logInfo("Memory monitoring started", category: .performance)
    }
    
    /// Stop monitoring memory usage
    func stopMonitoring() {
        memoryMonitoringTimer?.invalidate()
        memoryMonitoringTimer = nil
        
        logInfo("Memory monitoring stopped", category: .performance)
    }
    
    /// Force memory cleanup
    func performMemoryCleanup() {
        // Clear memory warnings older than 5 minutes
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        memoryWarnings.removeAll { $0.timestamp < fiveMinutesAgo }
        
        // Notify other components to clean up
        NotificationCenter.default.post(name: .memoryCleanupRequested, object: nil)
        
        // Force garbage collection
        Task {
            await performGarbageCollection()
        }
        
        logInfo("Memory cleanup performed", category: .performance, context: LogContext(customData: [
            "current_usage_mb": currentMemoryUsage / 1024 / 1024,
            "warnings_cleared": memoryWarnings.count
        ]))
    }
    
    /// Get current memory statistics
    func getMemoryStatistics() -> MemoryStatistics {
        return MemoryStatistics(
            currentUsage: currentMemoryUsage,
            peakUsage: peakMemoryUsage,
            warningsCount: memoryWarnings.count,
            isHighPressure: isMemoryPressureHigh,
            lastUpdated: Date()
        )
    }
    
    // MARK: - Private Methods
    
    private func setupMemoryMonitoring() {
        startMonitoring()
    }
    
    private func setupMemoryPressureMonitoring() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .main)
        
        memoryPressureSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            let event = self.memoryPressureSource?.mask
            
            if event?.contains(.warning) == true {
                self.handleMemoryPressure(.warning)
            } else if event?.contains(.urgent) == true {
                self.handleMemoryPressure(.urgent)
            } else if event?.contains(.critical) == true {
                self.handleMemoryPressure(.critical)
            }
        }
        
        memoryPressureSource?.resume()
    }
    
    private func setupApplicationLifecycleObservers() {
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
        
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
    
    private func updateMemoryUsage() {
        let usage = getCurrentMemoryUsage()
        currentMemoryUsage = usage
        
        if usage > peakMemoryUsage {
            peakMemoryUsage = usage
        }
        
        // Check for memory warnings
        checkMemoryThresholds(usage: usage)
    }
    
    private func getCurrentMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
    
    private func checkMemoryThresholds(usage: Int) {
        if usage > criticalThreshold {
            addMemoryWarning(.critical, usage: usage)
        } else if usage > warningThreshold {
            addMemoryWarning(.warning, usage: usage)
        }
    }
    
    private func addMemoryWarning(_ level: MemoryWarningLevel, usage: Int) {
        let warning = MemoryWarning(
            level: level,
            usage: usage,
            timestamp: Date()
        )
        
        memoryWarnings.append(warning)
        
        // Keep only recent warnings
        let oneHourAgo = Date().addingTimeInterval(-3600)
        memoryWarnings.removeAll { $0.timestamp < oneHourAgo }
        
        logWarning("Memory warning: \(level.rawValue)", category: .performance, context: LogContext(customData: [
            "usage_mb": usage / 1024 / 1024,
            "threshold_mb": (level == .critical ? criticalThreshold : warningThreshold) / 1024 / 1024
        ]))
        
        // Auto-cleanup on critical warnings
        if level == .critical {
            performMemoryCleanup()
        }
    }
    
    private func handleMemoryPressure(_ level: MemoryPressureLevel) {
        isMemoryPressureHigh = level != .normal
        
        logWarning("Memory pressure detected: \(level.rawValue)", category: .performance, context: LogContext(customData: [
            "current_usage_mb": currentMemoryUsage / 1024 / 1024,
            "pressure_level": level.rawValue
        ]))
        
        switch level {
        case .normal:
            break
        case .warning:
            // Mild cleanup
            NotificationCenter.default.post(name: .memoryPressureWarning, object: level)
        case .urgent, .critical:
            // Aggressive cleanup
            performMemoryCleanup()
            NotificationCenter.default.post(name: .memoryPressureCritical, object: level)
        }
    }
    
    private func handleMemoryWarning() {
        addMemoryWarning(.system, usage: currentMemoryUsage)
        performMemoryCleanup()
        
        logWarning("System memory warning received", category: .performance, context: LogContext(customData: [
            "current_usage_mb": currentMemoryUsage / 1024 / 1024
        ]))
    }
    
    private func handleAppDidEnterBackground() {
        // Perform cleanup when app enters background
        performMemoryCleanup()
        stopMonitoring()
        
        logInfo("App entered background, memory monitoring paused", category: .performance)
    }
    
    private func handleAppWillEnterForeground() {
        // Resume monitoring when app returns to foreground
        startMonitoring()
        updateMemoryUsage()
        
        logInfo("App will enter foreground, memory monitoring resumed", category: .performance)
    }
    
    private func performGarbageCollection() async {
        // Simulate garbage collection delay
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // In a real implementation, this might involve:
        // - Clearing caches
        // - Releasing unused objects
        // - Compacting memory pools
        
        await MainActor.run {
            updateMemoryUsage()
        }
    }
    
    private func cleanup() {
        stopMonitoring()
        memoryPressureSource?.cancel()
        cancellables.removeAll()
    }
}

// MARK: - Supporting Types

struct MemoryStatistics {
    let currentUsage: Int
    let peakUsage: Int
    let warningsCount: Int
    let isHighPressure: Bool
    let lastUpdated: Date
    
    var currentUsageMB: Double {
        return Double(currentUsage) / 1024.0 / 1024.0
    }
    
    var peakUsageMB: Double {
        return Double(peakUsage) / 1024.0 / 1024.0
    }
}

struct MemoryWarning {
    let level: MemoryWarningLevel
    let usage: Int
    let timestamp: Date
    
    var usageMB: Double {
        return Double(usage) / 1024.0 / 1024.0
    }
}

enum MemoryWarningLevel: String, CaseIterable {
    case warning = "warning"
    case critical = "critical"
    case system = "system"
}

enum MemoryPressureLevel: String, CaseIterable {
    case normal = "normal"
    case warning = "warning"
    case urgent = "urgent"
    case critical = "critical"
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let memoryCleanupRequested = Notification.Name("memoryCleanupRequested")
    static let memoryPressureWarning = Notification.Name("memoryPressureWarning")
    static let memoryPressureCritical = Notification.Name("memoryPressureCritical")
}

// MARK: - Memory-Aware Protocol

/// Protocol for objects that can respond to memory pressure
protocol MemoryAware: AnyObject {
    func didReceiveMemoryWarning()
    func performMemoryCleanup()
}

// MARK: - Weak Reference Holder

/// Utility class for holding weak references to prevent retain cycles
final class WeakRef<T: AnyObject> {
    weak var value: T?
    
    init(_ value: T) {
        self.value = value
    }
}

// MARK: - Memory-Safe Collection

/// A collection that automatically removes nil weak references
struct WeakCollection<T: AnyObject> {
    private var items: [WeakRef<T>] = []
    
    mutating func add(_ item: T) {
        items.append(WeakRef(item))
    }
    
    mutating func remove(_ item: T) {
        items.removeAll { $0.value === item }
    }
    
    var allObjects: [T] {
        cleanupNilReferences()
        return items.compactMap { $0.value }
    }
    
    private mutating func cleanupNilReferences() {
        items.removeAll { $0.value == nil }
    }
}