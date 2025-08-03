import Foundation
import os.signpost
import MetricKit
import Combine

// MARK: - Instruments Profiling Integration

@MainActor
public class InstrumentsProfiler: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var isProfilingEnabled: Bool = false
    @Published public var activeProfiles: [ProfileSession] = []
    @Published public var performanceMetrics: PerformanceMetrics = PerformanceMetrics()
    @Published public var profilerWarnings: [ProfilerWarning] = []
    
    // MARK: - Signpost System
    private let subsystem = "com.architectar.app"
    private let category = "Performance"
    
    // Create dedicated signpost logs for different systems
    private lazy var arSessionLog = OSLog(subsystem: subsystem, category: "ARSession")
    private lazy var renderingLog = OSLog(subsystem: subsystem, category: "Rendering")
    private lazy var modelLoadingLog = OSLog(subsystem: subsystem, category: "ModelLoading")
    private lazy var physicsLog = OSLog(subsystem: subsystem, category: "Physics")
    private lazy var memoryLog = OSLog(subsystem: subsystem, category: "Memory")
    private lazy var networkingLog = OSLog(subsystem: subsystem, category: "Networking")
    
    // Signpost IDs
    private lazy var arFrameProcessingID = OSSignpostID(log: arSessionLog)
    private lazy var renderingFrameID = OSSignpostID(log: renderingLog)
    private lazy var modelLoadingID = OSSignpostID(log: modelLoadingLog)
    private lazy var physicsSimulationID = OSSignpostID(log: physicsLog)
    
    // MARK: - MetricKit Integration
    private var metricManager: MXMetricManager?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Performance Tracking
    private var frameTimeTracker = FrameTimeTracker()
    private var memoryTracker = MemoryTracker()
    private var thermalTracker = ThermalTracker()
    private var batteryTracker = BatteryTracker()
    
    public init() {
        setupMetricKit()
        setupPerformanceMonitoring()
        
        logDebug("Instruments profiler initialized", category: .performance)
    }
    
    // MARK: - Setup
    
    private func setupMetricKit() {
        guard #available(iOS 13.0, *) else { return }
        
        metricManager = MXMetricManager.shared
        metricManager?.add(self)
        
        logInfo("MetricKit integration enabled", category: .performance)
    }
    
    private func setupPerformanceMonitoring() {
        // Monitor thermal state changes
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.handleThermalStateChange()
            }
            .store(in: &cancellables)
        
        // Monitor memory warnings
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
        
        // Start periodic monitoring
        startPeriodicMonitoring()
    }
    
    // MARK: - Signpost Operations
    
    public func beginARFrameProcessing() {
        guard isProfilingEnabled else { return }
        
        os_signpost(.begin, log: arSessionLog, name: "AR Frame Processing", signpostID: arFrameProcessingID,
                   "Starting AR frame processing")
    }
    
    public func endARFrameProcessing(anchorsCount: Int, planesCount: Int) {
        guard isProfilingEnabled else { return }
        
        os_signpost(.end, log: arSessionLog, name: "AR Frame Processing", signpostID: arFrameProcessingID,
                   "Completed AR frame processing - Anchors: %d, Planes: %d", anchorsCount, planesCount)
    }
    
    public func beginRendering(objectCount: Int) {
        guard isProfilingEnabled else { return }
        
        os_signpost(.begin, log: renderingLog, name: "Scene Rendering", signpostID: renderingFrameID,
                   "Starting scene rendering - Objects: %d", objectCount)
    }
    
    public func endRendering(drawCalls: Int, triangles: Int) {
        guard isProfilingEnabled else { return }
        
        os_signpost(.end, log: renderingLog, name: "Scene Rendering", signpostID: renderingFrameID,
                   "Completed scene rendering - Draw calls: %d, Triangles: %d", drawCalls, triangles)
    }
    
    public func beginModelLoading(modelName: String, fileSize: Int64) {
        guard isProfilingEnabled else { return }
        
        os_signpost(.begin, log: modelLoadingLog, name: "Model Loading", signpostID: modelLoadingID,
                   "Loading model: %{public}s, Size: %lld bytes", modelName, fileSize)
    }
    
    public func endModelLoading(modelName: String, success: Bool, loadTime: TimeInterval) {
        guard isProfilingEnabled else { return }
        
        let status = success ? "Success" : "Failed"
        os_signpost(.end, log: modelLoadingLog, name: "Model Loading", signpostID: modelLoadingID,
                   "Model %{public}s loading %{public}s - Time: %.3f seconds", modelName, status, loadTime)
    }
    
    public func beginPhysicsSimulation(objectCount: Int) {
        guard isProfilingEnabled else { return }
        
        os_signpost(.begin, log: physicsLog, name: "Physics Simulation", signpostID: physicsSimulationID,
                   "Starting physics simulation - Objects: %d", objectCount)
    }
    
    public func endPhysicsSimulation(collisionCount: Int, simulationTime: TimeInterval) {
        guard isProfilingEnabled else { return }
        
        os_signpost(.end, log: physicsLog, name: "Physics Simulation", signpostID: physicsSimulationID,
                   "Physics simulation completed - Collisions: %d, Time: %.3f ms", collisionCount, simulationTime * 1000)
    }
    
    // MARK: - Memory Profiling
    
    public func logMemoryUsage(context: String, additionalInfo: [String: Any] = [:]) {
        guard isProfilingEnabled else { return }
        
        let memoryInfo = getMemoryInfo()
        
        os_signpost(.event, log: memoryLog, name: "Memory Usage",
                   "Context: %{public}s, Used: %.1f MB, Available: %.1f MB", 
                   context, memoryInfo.usedMemory, memoryInfo.availableMemory)
        
        // Track memory usage over time
        memoryTracker.recordMemoryUsage(
            used: memoryInfo.usedMemory,
            available: memoryInfo.availableMemory,
            context: context
        )
        
        // Check for memory warnings
        if memoryInfo.usedMemory > 800 { // 800 MB threshold
            addProfilerWarning(.highMemoryUsage(memoryInfo.usedMemory))
        }
    }
    
    // MARK: - Performance Point Tracking
    
    public func recordPerformancePoint(_ point: PerformancePoint) {
        guard isProfilingEnabled else { return }
        
        // Log to Instruments
        os_signpost(.event, log: renderingLog, name: "Performance Point",
                   "Metric: %{public}s, Value: %.3f, Threshold: %.3f",
                   point.metric, point.value, point.threshold ?? 0)
        
        // Track internally
        performanceMetrics.addDataPoint(point)
        
        // Check for performance issues
        if let threshold = point.threshold, point.value > threshold {
            addProfilerWarning(.performanceThresholdExceeded(point))
        }
    }
    
    // MARK: - Frame Time Tracking
    
    public func recordFrameTime(_ frameTime: TimeInterval) {
        frameTimeTracker.recordFrame(frameTime)
        
        let fps = 1.0 / frameTime
        performanceMetrics.updateFPS(fps)
        
        // Log significant frame drops
        if frameTime > 0.033 { // > 30 FPS
            os_signpost(.event, log: renderingLog, name: "Frame Drop",
                       "Frame time: %.3f ms (%.1f FPS)", frameTime * 1000, fps)
        }
    }
    
    // MARK: - Custom Profiling Sessions
    
    public func startProfilingSession(name: String, configuration: ProfileConfiguration = .default) -> UUID {
        let sessionID = UUID()
        let session = ProfileSession(
            id: sessionID,
            name: name,
            configuration: configuration,
            startTime: Date()
        )
        
        activeProfiles.append(session)
        
        os_signpost(.begin, log: OSLog(subsystem: subsystem, category: "CustomProfile"), 
                   name: "Custom Profile Session",
                   "Starting profile session: %{public}s", name)
        
        logInfo("Started profiling session", category: .performance, context: LogContext(customData: [
            "session_name": name,
            "session_id": sessionID.uuidString
        ]))
        
        return sessionID
    }
    
    public func endProfilingSession(_ sessionID: UUID) -> ProfileSessionResult? {
        guard let sessionIndex = activeProfiles.firstIndex(where: { $0.id == sessionID }) else {
            return nil
        }
        
        var session = activeProfiles.remove(at: sessionIndex)
        session.endTime = Date()
        
        let duration = session.endTime!.timeIntervalSince(session.startTime)
        
        os_signpost(.end, log: OSLog(subsystem: subsystem, category: "CustomProfile"),
                   name: "Custom Profile Session",
                   "Completed profile session: %{public}s, Duration: %.3f seconds", 
                   session.name, duration)
        
        let result = ProfileSessionResult(
            session: session,
            duration: duration,
            performanceData: collectPerformanceData(for: session)
        )
        
        logInfo("Completed profiling session", category: .performance, context: LogContext(customData: [
            "session_name": session.name,
            "duration": duration
        ]))
        
        return result
    }
    
    // MARK: - Thermal and Battery Monitoring
    
    private func handleThermalStateChange() {
        let thermalState = ProcessInfo.processInfo.thermalState
        
        os_signpost(.event, log: OSLog(subsystem: subsystem, category: "Thermal"),
                   name: "Thermal State Change",
                   "New thermal state: %{public}s", thermalStateDescription(thermalState))
        
        thermalTracker.recordThermalState(thermalState)
        
        if thermalState == .critical || thermalState == .serious {
            addProfilerWarning(.thermalThrottling(thermalState))
        }
    }
    
    private func handleMemoryWarning() {
        os_signpost(.event, log: memoryLog, name: "Memory Warning", "System memory warning received")
        
        addProfilerWarning(.memoryWarning)
        
        // Log current memory state
        logMemoryUsage(context: "Memory Warning")
    }
    
    // MARK: - Periodic Monitoring
    
    private func startPeriodicMonitoring() {
        Timer.publish(every: 5.0, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.performPeriodicCheck()
            }
            .store(in: &cancellables)
    }
    
    private func performPeriodicCheck() {
        guard isProfilingEnabled else { return }
        
        // Update performance metrics
        updatePerformanceMetrics()
        
        // Check for performance degradation
        checkPerformanceHealth()
    }
    
    private func updatePerformanceMetrics() {
        let memoryInfo = getMemoryInfo()
        performanceMetrics.updateMemoryUsage(memoryInfo.usedMemory)
        
        let thermalState = ProcessInfo.processInfo.thermalState
        performanceMetrics.updateThermalState(thermalState)
        
        // Update battery level if available
        if UIDevice.current.isBatteryMonitoringEnabled {
            performanceMetrics.updateBatteryLevel(UIDevice.current.batteryLevel)
        }
    }
    
    private func checkPerformanceHealth() {
        // Check frame rate health
        let avgFPS = frameTimeTracker.getAverageFPS()
        if avgFPS < 20 {
            addProfilerWarning(.lowFrameRate(avgFPS))
        }
        
        // Check memory health
        let memoryInfo = getMemoryInfo()
        if memoryInfo.usedMemory > 1000 { // 1GB threshold
            addProfilerWarning(.highMemoryUsage(memoryInfo.usedMemory))
        }
    }
    
    // MARK: - Data Collection
    
    private func collectPerformanceData(for session: ProfileSession) -> PerformanceData {
        return PerformanceData(
            averageFPS: frameTimeTracker.getAverageFPS(),
            frameTimeMetrics: frameTimeTracker.getMetrics(),
            memoryMetrics: memoryTracker.getMetrics(),
            thermalEvents: thermalTracker.getEvents(),
            batteryMetrics: batteryTracker.getMetrics()
        )
    }
    
    // MARK: - Utility Methods
    
    private func getMemoryInfo() -> (usedMemory: Double, availableMemory: Double) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMemory = Double(info.resident_size) / (1024 * 1024) // Convert to MB
            let availableMemory = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024) - usedMemory
            return (usedMemory, availableMemory)
        }
        
        return (0, 0)
    }
    
    private func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
    
    private func addProfilerWarning(_ warning: ProfilerWarning) {
        profilerWarnings.append(warning)
        
        // Keep only recent warnings
        if profilerWarnings.count > 50 {
            profilerWarnings.removeFirst(profilerWarnings.count - 50)
        }
        
        logWarning("Profiler warning", category: .performance, context: LogContext(customData: [
            "warning_type": warning.type
        ]))
    }
    
    // MARK: - Public Interface
    
    public func enableProfiling(_ enabled: Bool) {
        isProfilingEnabled = enabled
        
        if enabled {
            logInfo("Profiling enabled", category: .performance)
        } else {
            logInfo("Profiling disabled", category: .performance)
        }
    }
    
    public func exportProfilingData() -> ProfilingDataExport {
        return ProfilingDataExport(
            sessions: activeProfiles,
            performanceMetrics: performanceMetrics,
            warnings: profilerWarnings,
            frameTimeData: frameTimeTracker.getAllData(),
            memoryData: memoryTracker.getAllData(),
            exportDate: Date()
        )
    }
    
    public func clearProfilingData() {
        activeProfiles.removeAll()
        profilerWarnings.removeAll()
        frameTimeTracker.clearData()
        memoryTracker.clearData()
        thermalTracker.clearData()
        batteryTracker.clearData()
        
        logInfo("Profiling data cleared", category: .performance)
    }
}

// MARK: - MetricKit Delegate

@available(iOS 13.0, *)
extension InstrumentsProfiler: MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            processMetricPayload(payload)
        }
    }
    
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            processDiagnosticPayload(payload)
        }
    }
    
    private func processMetricPayload(_ payload: MXMetricPayload) {
        // Process CPU metrics
        if let cpuMetrics = payload.cpuMetrics {
            performanceMetrics.updateCPUUsage(cpuMetrics.cumulativeCPUTime.doubleValue)
        }
        
        // Process memory metrics
        if let memoryMetrics = payload.memoryMetrics {
            performanceMetrics.updatePeakMemoryUsage(memoryMetrics.peakMemoryUsage?.doubleValue ?? 0)
        }
        
        // Process display metrics
        if let displayMetrics = payload.displayMetrics {
            performanceMetrics.updateAveragePixelLuminance(displayMetrics.averagePixelLuminance?.doubleValue ?? 0)
        }
        
        logInfo("Received MetricKit payload", category: .performance, context: LogContext(customData: [
            "payload_timestamp": payload.timeStampEnd.timeIntervalSince1970
        ]))
    }
    
    private func processDiagnosticPayload(_ payload: MXDiagnosticPayload) {
        // Process crash diagnostics
        if let crashDiagnostics = payload.crashDiagnostics {
            for crash in crashDiagnostics {
                addProfilerWarning(.crashDetected(crash.callStackTree.jsonRepresentation()))
            }
        }
        
        // Process hang diagnostics
        if let hangDiagnostics = payload.hangDiagnostics {
            for hang in hangDiagnostics {
                addProfilerWarning(.hangDetected(hang.callStackTree.jsonRepresentation()))
            }
        }
        
        logWarning("Received diagnostic payload", category: .performance, context: LogContext(customData: [
            "crash_count": payload.crashDiagnostics?.count ?? 0,
            "hang_count": payload.hangDiagnostics?.count ?? 0
        ]))
    }
}

// MARK: - Supporting Data Structures

public struct ProfileSession {
    public let id: UUID
    public let name: String
    public let configuration: ProfileConfiguration
    public let startTime: Date
    public var endTime: Date?
}

public struct ProfileConfiguration {
    public let enableFrameTimeTracking: Bool
    public let enableMemoryTracking: Bool
    public let enableThermalTracking: Bool
    public let enableNetworkTracking: Bool
    public let samplingInterval: TimeInterval
    
    public static let `default` = ProfileConfiguration(
        enableFrameTimeTracking: true,
        enableMemoryTracking: true,
        enableThermalTracking: true,
        enableNetworkTracking: false,
        samplingInterval: 1.0
    )
}

public struct ProfileSessionResult {
    public let session: ProfileSession
    public let duration: TimeInterval
    public let performanceData: PerformanceData
}

public struct PerformanceData {
    public let averageFPS: Double
    public let frameTimeMetrics: FrameTimeMetrics
    public let memoryMetrics: MemoryMetrics
    public let thermalEvents: [ThermalEvent]
    public let batteryMetrics: BatteryMetrics
}

public struct PerformancePoint {
    public let metric: String
    public let value: Double
    public let threshold: Double?
    public let timestamp: Date
    
    public init(metric: String, value: Double, threshold: Double? = nil) {
        self.metric = metric
        self.value = value
        self.threshold = threshold
        self.timestamp = Date()
    }
}

public class PerformanceMetrics: ObservableObject {
    @Published public var currentFPS: Double = 60.0
    @Published public var memoryUsage: Double = 0.0
    @Published public var cpuUsage: Double = 0.0
    @Published public var thermalState: ProcessInfo.ThermalState = .nominal
    @Published public var batteryLevel: Float = 1.0
    
    private var dataPoints: [PerformancePoint] = []
    
    public func updateFPS(_ fps: Double) {
        currentFPS = fps
    }
    
    public func updateMemoryUsage(_ memory: Double) {
        memoryUsage = memory
    }
    
    public func updateCPUUsage(_ cpu: Double) {
        cpuUsage = cpu
    }
    
    public func updateThermalState(_ state: ProcessInfo.ThermalState) {
        thermalState = state
    }
    
    public func updateBatteryLevel(_ level: Float) {
        batteryLevel = level
    }
    
    public func updatePeakMemoryUsage(_ peak: Double) {
        // Implementation for peak memory tracking
    }
    
    public func updateAveragePixelLuminance(_ luminance: Double) {
        // Implementation for display metrics
    }
    
    public func addDataPoint(_ point: PerformancePoint) {
        dataPoints.append(point)
        
        // Keep only recent data points
        if dataPoints.count > 1000 {
            dataPoints.removeFirst(dataPoints.count - 1000)
        }
    }
}

public enum ProfilerWarning {
    case highMemoryUsage(Double)
    case lowFrameRate(Double)
    case thermalThrottling(ProcessInfo.ThermalState)
    case memoryWarning
    case performanceThresholdExceeded(PerformancePoint)
    case crashDetected(String)
    case hangDetected(String)
    
    var type: String {
        switch self {
        case .highMemoryUsage: return "high_memory_usage"
        case .lowFrameRate: return "low_frame_rate"
        case .thermalThrottling: return "thermal_throttling"
        case .memoryWarning: return "memory_warning"
        case .performanceThresholdExceeded: return "performance_threshold"
        case .crashDetected: return "crash_detected"
        case .hangDetected: return "hang_detected"
        }
    }
}

public struct ProfilingDataExport {
    public let sessions: [ProfileSession]
    public let performanceMetrics: PerformanceMetrics
    public let warnings: [ProfilerWarning]
    public let frameTimeData: [FrameTimeData]
    public let memoryData: [MemoryData]
    public let exportDate: Date
}

// MARK: - Tracking Classes

class FrameTimeTracker {
    private var frameTimes: [TimeInterval] = []
    private let maxSamples = 300 // Keep 5 seconds at 60 FPS
    
    func recordFrame(_ frameTime: TimeInterval) {
        frameTimes.append(frameTime)
        
        if frameTimes.count > maxSamples {
            frameTimes.removeFirst(frameTimes.count - maxSamples)
        }
    }
    
    func getAverageFPS() -> Double {
        guard !frameTimes.isEmpty else { return 0 }
        
        let avgFrameTime = frameTimes.reduce(0, +) / Double(frameTimes.count)
        return 1.0 / avgFrameTime
    }
    
    func getMetrics() -> FrameTimeMetrics {
        guard !frameTimes.isEmpty else {
            return FrameTimeMetrics(average: 0, min: 0, max: 0, standardDeviation: 0)
        }
        
        let avg = frameTimes.reduce(0, +) / Double(frameTimes.count)
        let min = frameTimes.min() ?? 0
        let max = frameTimes.max() ?? 0
        
        let variance = frameTimes.map { pow($0 - avg, 2) }.reduce(0, +) / Double(frameTimes.count)
        let stdDev = sqrt(variance)
        
        return FrameTimeMetrics(average: avg, min: min, max: max, standardDeviation: stdDev)
    }
    
    func getAllData() -> [FrameTimeData] {
        return frameTimes.enumerated().map {
            FrameTimeData(timestamp: Date().addingTimeInterval(-Double($0.offset)), frameTime: $0.element)
        }
    }
    
    func clearData() {
        frameTimes.removeAll()
    }
}

class MemoryTracker {
    private var memoryUsages: [(timestamp: Date, used: Double, available: Double, context: String)] = []
    private let maxSamples = 1000
    
    func recordMemoryUsage(used: Double, available: Double, context: String) {
        memoryUsages.append((Date(), used, available, context))
        
        if memoryUsages.count > maxSamples {
            memoryUsages.removeFirst(memoryUsages.count - maxSamples)
        }
    }
    
    func getMetrics() -> MemoryMetrics {
        guard !memoryUsages.isEmpty else {
            return MemoryMetrics(averageUsed: 0, peakUsed: 0, averageAvailable: 0)
        }
        
        let avgUsed = memoryUsages.map { $0.used }.reduce(0, +) / Double(memoryUsages.count)
        let peakUsed = memoryUsages.map { $0.used }.max() ?? 0
        let avgAvailable = memoryUsages.map { $0.available }.reduce(0, +) / Double(memoryUsages.count)
        
        return MemoryMetrics(averageUsed: avgUsed, peakUsed: peakUsed, averageAvailable: avgAvailable)
    }
    
    func getAllData() -> [MemoryData] {
        return memoryUsages.map {
            MemoryData(timestamp: $0.timestamp, used: $0.used, available: $0.available, context: $0.context)
        }
    }
    
    func clearData() {
        memoryUsages.removeAll()
    }
}

class ThermalTracker {
    private var thermalEvents: [ThermalEvent] = []
    
    func recordThermalState(_ state: ProcessInfo.ThermalState) {
        thermalEvents.append(ThermalEvent(timestamp: Date(), state: state))
    }
    
    func getEvents() -> [ThermalEvent] {
        return thermalEvents
    }
    
    func clearData() {
        thermalEvents.removeAll()
    }
}

class BatteryTracker {
    private var batteryLevels: [(timestamp: Date, level: Float)] = []
    
    func recordBatteryLevel(_ level: Float) {
        batteryLevels.append((Date(), level))
    }
    
    func getMetrics() -> BatteryMetrics {
        guard !batteryLevels.isEmpty else {
            return BatteryMetrics(averageLevel: 1.0, minimumLevel: 1.0, drainRate: 0.0)
        }
        
        let avgLevel = batteryLevels.map { $0.level }.reduce(0, +) / Float(batteryLevels.count)
        let minLevel = batteryLevels.map { $0.level }.min() ?? 1.0
        
        // Calculate drain rate (very basic implementation)
        var drainRate: Float = 0.0
        if batteryLevels.count >= 2 {
            let firstLevel = batteryLevels.first!.level
            let lastLevel = batteryLevels.last!.level
            let timeInterval = batteryLevels.last!.timestamp.timeIntervalSince(batteryLevels.first!.timestamp)
            drainRate = (firstLevel - lastLevel) / Float(timeInterval) * 3600 // Per hour
        }
        
        return BatteryMetrics(averageLevel: avgLevel, minimumLevel: minLevel, drainRate: drainRate)
    }
    
    func clearData() {
        batteryLevels.removeAll()
    }
}

// MARK: - Metric Data Structures

public struct FrameTimeMetrics {
    public let average: TimeInterval
    public let min: TimeInterval
    public let max: TimeInterval
    public let standardDeviation: TimeInterval
}

public struct MemoryMetrics {
    public let averageUsed: Double
    public let peakUsed: Double
    public let averageAvailable: Double
}

public struct BatteryMetrics {
    public let averageLevel: Float
    public let minimumLevel: Float
    public let drainRate: Float // Per hour
}

public struct ThermalEvent {
    public let timestamp: Date
    public let state: ProcessInfo.ThermalState
}

public struct FrameTimeData {
    public let timestamp: Date
    public let frameTime: TimeInterval
}

public struct MemoryData {
    public let timestamp: Date
    public let used: Double
    public let available: Double
    public let context: String
}