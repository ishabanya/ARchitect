import SwiftUI
import ARKit
import RealityKit
import Combine
import MetricKit

// MARK: - AR Performance Monitor

@MainActor
public class ARPerformanceMonitor: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var currentFPS: Double = 60.0
    @Published public var averageFPS: Double = 60.0
    @Published public var trackingQuality: TrackingQuality = .normal
    @Published public var worldMappingStatus: ARFrame.WorldMappingStatus = .notAvailable
    @Published public var lightEstimate: Float = 1000.0
    
    // Memory and performance
    @Published public var memoryUsage: Int64 = 0
    @Published public var thermalState: ProcessInfo.ThermalState = .nominal
    @Published public var batteryLevel: Float = 1.0
    @Published public var deviceTemperature: Float = 0.0
    
    // AR-specific metrics
    @Published public var anchorsCount: Int = 0
    @Published public var entitiesCount: Int = 0
    @Published public var triangleCount: Int = 0
    @Published public var drawCalls: Int = 0
    @Published public var renderTime: TimeInterval = 0.0
    
    // Visual indicators
    @Published public var shouldShowIndicators = false
    @Published public var performanceLevel: PerformanceLevel = .good
    @Published public var warningMessage: String?
    @Published public var isThrottling = false
    
    // Configuration
    @Published public var showDetailedMetrics = false
    @Published public var enablePerformanceLogs = true
    @Published public var autoAdjustQuality = true
    
    // Internal state
    private var fpsHistory: [Double] = []
    private var frameTimestamps: [TimeInterval] = []
    private var lastFrameTime: TimeInterval = 0
    private var isMonitoring = false
    
    // Timers and monitoring
    private var performanceTimer: Timer?
    private var memoryTimer: Timer?
    private var thermalTimer: Timer?
    
    // Performance thresholds
    private let goodFPSThreshold: Double = 55.0
    private let acceptableFPSThreshold: Double = 45.0
    private let poorFPSThreshold: Double = 30.0
    private let criticalMemoryThreshold: Int64 = 800 * 1024 * 1024 // 800MB
    private let warningMemoryThreshold: Int64 = 600 * 1024 * 1024 // 600MB
    
    private let accessibilityManager = AccessibilityManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        setupObservers()
        
        logDebug("AR performance monitor initialized", category: .general)
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Monitor FPS changes
        $currentFPS
            .sink { [weak self] fps in
                self?.updatePerformanceLevel(fps: fps)
                self?.checkForPerformanceIssues()
            }
            .store(in: &cancellables)
        
        // Monitor thermal state
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateThermalState()
            }
            .store(in: &cancellables)
        
        // Monitor battery level
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateBatteryLevel()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Monitoring Control
    
    public func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        
        // Start performance monitoring timer
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePerformanceMetrics()
            }
        }
        
        // Start memory monitoring timer
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMemoryUsage()
            }
        }
        
        // Start thermal monitoring timer
        thermalTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateThermalState()
                self?.updateBatteryLevel()
            }
        }
        
        // Initial state
        updateThermalState()
        updateBatteryLevel()
        
        logInfo("Performance monitoring started", category: .general)
    }
    
    public func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        
        performanceTimer?.invalidate()
        memoryTimer?.invalidate()
        thermalTimer?.invalidate()
        
        performanceTimer = nil
        memoryTimer = nil
        thermalTimer = nil
        
        logInfo("Performance monitoring stopped", category: .general)
    }
    
    // MARK: - Performance Updates
    
    private func updatePerformanceMetrics() {
        updateFPS()
        updateRenderMetrics()
    }
    
    private func updateFPS() {
        let currentTime = CACurrentMediaTime()
        
        if lastFrameTime > 0 {
            let frameDelta = currentTime - lastFrameTime
            let fps = frameDelta > 0 ? 1.0 / frameDelta : 60.0
            
            currentFPS = min(fps, 60.0) // Cap at 60 FPS
            
            // Update FPS history
            fpsHistory.append(currentFPS)
            if fpsHistory.count > 30 { // Keep last 30 samples (15 seconds at 0.5s intervals)
                fpsHistory.removeFirst()
            }
            
            // Calculate average FPS
            averageFPS = fpsHistory.reduce(0, +) / Double(fpsHistory.count)
        }
        
        lastFrameTime = currentTime
    }
    
    private func updateRenderMetrics() {
        // These would be obtained from the AR session and RealityKit
        // For now, using placeholder values that would come from actual AR metrics
        
        // Simulate realistic values based on FPS
        renderTime = 1.0 / max(currentFPS, 1.0) // Frame time in seconds
        drawCalls = Int.random(in: 50...200) // Typical range for AR apps
        triangleCount = Int.random(in: 10000...100000) // Polygon count
    }
    
    private func updateMemoryUsage() {
        // Get actual memory usage
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
            memoryUsage = Int64(info.resident_size)
        }
        
        // Log memory warnings
        if memoryUsage > criticalMemoryThreshold {
            logWarning("Critical memory usage detected", category: .general, context: LogContext(customData: [
                "memory_usage_mb": memoryUsage / (1024 * 1024)
            ]))
            
            if autoAdjustQuality {
                requestQualityReduction()
            }
        }
    }
    
    private func updateThermalState() {
        thermalState = ProcessInfo.processInfo.thermalState
        
        // Simulate device temperature (this would come from actual thermal sensors in production)
        deviceTemperature = switch thermalState {
        case .nominal: Float.random(in: 25...35)
        case .fair: Float.random(in: 35...45)
        case .serious: Float.random(in: 45...55)
        case .critical: Float.random(in: 55...65)
        @unknown default: 30.0
        }
        
        // Handle thermal throttling
        handleThermalStateChange()
    }
    
    private func updateBatteryLevel() {
        batteryLevel = UIDevice.current.batteryLevel
        
        if batteryLevel < 0.15 && batteryLevel > 0 { // Below 15% but not unknown (-1)
            logWarning("Low battery detected", category: .general, context: LogContext(customData: [
                "battery_level": batteryLevel * 100
            ]))
            
            if autoAdjustQuality {
                requestPowerOptimization()
            }
        }
    }
    
    // MARK: - AR Session Integration
    
    public func updateFromARFrame(_ frame: ARFrame) {
        // Update tracking quality
        trackingQuality = TrackingQuality(from: frame.camera.trackingState)
        
        // Update world mapping status
        worldMappingStatus = frame.worldMappingStatus
        
        // Update light estimate
        if let lightEstimate = frame.lightEstimate {
            self.lightEstimate = lightEstimate.ambientIntensity
        }
        
        // Update anchor count
        anchorsCount = frame.anchors.count
        
        // Update frame timestamps for FPS calculation
        frameTimestamps.append(frame.timestamp)
        if frameTimestamps.count > 60 { // Keep last 60 frames
            frameTimestamps.removeFirst()
        }
        
        // Calculate FPS from frame timestamps
        if frameTimestamps.count >= 2 {
            let timeDelta = frameTimestamps.last! - frameTimestamps.first!
            if timeDelta > 0 {
                currentFPS = Double(frameTimestamps.count - 1) / timeDelta
            }
        }
    }
    
    // MARK: - Performance Analysis
    
    private func updatePerformanceLevel(fps: Double) {
        let newLevel: PerformanceLevel
        
        if fps >= goodFPSThreshold {
            newLevel = .good
        } else if fps >= acceptableFPSThreshold {
            newLevel = .acceptable
        } else if fps >= poorFPSThreshold {
            newLevel = .poor
        } else {
            newLevel = .critical
        }
        
        if newLevel != performanceLevel {
            performanceLevel = newLevel
            handlePerformanceLevelChange(newLevel)
        }
    }
    
    private func handlePerformanceLevelChange(_ level: PerformanceLevel) {
        switch level {
        case .good:
            shouldShowIndicators = false
            warningMessage = nil
            isThrottling = false
            
        case .acceptable:
            shouldShowIndicators = true
            warningMessage = nil
            isThrottling = false
            
        case .poor:
            shouldShowIndicators = true
            warningMessage = "Performance may be affected"
            isThrottling = false
            
        case .critical:
            shouldShowIndicators = true
            warningMessage = "Poor performance detected"
            isThrottling = true
            
            if autoAdjustQuality {
                requestPerformanceOptimization()
            }
        }
        
        logDebug("Performance level changed", category: .general, context: LogContext(customData: [
            "level": level.rawValue,
            "fps": currentFPS,
            "memory_mb": memoryUsage / (1024 * 1024)
        ]))
    }
    
    private func checkForPerformanceIssues() {
        var issues: [String] = []
        
        if currentFPS < poorFPSThreshold {
            issues.append("Low frame rate")
        }
        
        if memoryUsage > warningMemoryThreshold {
            issues.append("High memory usage")
        }
        
        if thermalState == .serious || thermalState == .critical {
            issues.append("Device overheating")
        }
        
        if trackingQuality == .poor {
            issues.append("Poor tracking quality")
        }
        
        if !issues.isEmpty && enablePerformanceLogs {
            logWarning("Performance issues detected", category: .general, context: LogContext(customData: [
                "issues": issues.joined(separator: ", ")
            ]))
        }
    }
    
    // MARK: - Thermal Management
    
    private func handleThermalStateChange() {
        switch thermalState {
        case .nominal:
            isThrottling = false
            
        case .fair:
            isThrottling = false
            warningMessage = "Device warming up"
            
        case .serious:
            isThrottling = true
            warningMessage = "Device is hot - reducing performance"
            
            if autoAdjustQuality {
                requestThermalOptimization()
            }
            
        case .critical:
            isThrottling = true
            warningMessage = "Device overheating - limiting functionality"
            
            accessibilityManager.announceError("Device overheating detected")
            
            if autoAdjustQuality {
                requestEmergencyOptimization()
            }
            
        @unknown default:
            break
        }
        
        logDebug("Thermal state changed", category: .general, context: LogContext(customData: [
            "thermal_state": thermalState.rawValue,
            "device_temperature": deviceTemperature
        ]))
    }
    
    // MARK: - Quality Adjustment Requests
    
    private func requestQualityReduction() {
        // Request quality reduction from the AR system
        logInfo("Requesting quality reduction due to memory pressure", category: .general)
    }
    
    private func requestPowerOptimization() {
        // Request power optimizations
        logInfo("Requesting power optimization due to low battery", category: .general)
    }
    
    private func requestPerformanceOptimization() {
        // Request performance optimizations
        logInfo("Requesting performance optimization due to poor FPS", category: .general)
    }
    
    private func requestThermalOptimization() {
        // Request thermal optimizations
        logInfo("Requesting thermal optimization due to device heat", category: .general)
    }
    
    private func requestEmergencyOptimization() {
        // Request emergency optimizations
        logWarning("Requesting emergency optimization due to critical thermal state", category: .general)
    }
    
    // MARK: - Color Coding
    
    public var fpsColor: Color {
        switch currentFPS {
        case goodFPSThreshold...: return .green
        case acceptableFPSThreshold..<goodFPSThreshold: return .yellow
        case poorFPSThreshold..<acceptableFPSThreshold: return .orange
        default: return .red
        }
    }
    
    public var trackingColor: Color {
        switch trackingQuality {
        case .normal: return .green
        case .limited: return .yellow
        case .poor: return .red
        }
    }
    
    public var memoryColor: Color {
        switch memoryUsage {
        case 0..<warningMemoryThreshold: return .green
        case warningMemoryThreshold..<criticalMemoryThreshold: return .yellow
        default: return .red
        }
    }
    
    public var thermalColor: Color {
        switch thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }
    
    // MARK: - Statistics
    
    public func getPerformanceStatistics() -> PerformanceStatistics {
        return PerformanceStatistics(
            currentFPS: currentFPS,
            averageFPS: averageFPS,
            trackingQuality: trackingQuality,
            memoryUsage: memoryUsage,
            thermalState: thermalState,
            batteryLevel: batteryLevel,
            anchorsCount: anchorsCount,
            entitiesCount: entitiesCount,
            triangleCount: triangleCount,
            drawCalls: drawCalls,
            renderTime: renderTime,
            performanceLevel: performanceLevel
        )
    }
}

// MARK: - Performance Indicators View

public struct PerformanceIndicators: View {
    @EnvironmentObject private var performanceMonitor: ARPerformanceMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 8) {
            if performanceMonitor.shouldShowIndicators {
                // FPS Indicator
                PerformanceMetric(
                    value: String(format: "%.0f", performanceMonitor.currentFPS),
                    unit: "FPS",
                    color: performanceMonitor.fpsColor,
                    isGood: performanceMonitor.currentFPS >= 55
                )
                
                // Tracking Quality
                PerformanceMetric(
                    value: performanceMonitor.trackingQuality.shortName,
                    unit: "",
                    color: performanceMonitor.trackingColor,
                    isGood: performanceMonitor.trackingQuality == .normal
                )
                
                // Memory Usage (when concerning)
                if performanceMonitor.memoryUsage > performanceMonitor.warningMemoryThreshold {
                    PerformanceMetric(
                        value: String(format: "%.0f", Double(performanceMonitor.memoryUsage) / (1024.0 * 1024.0)),
                        unit: "MB",
                        color: performanceMonitor.memoryColor,
                        isGood: false
                    )
                }
                
                // Thermal State (when concerning)
                if performanceMonitor.thermalState != .nominal {
                    PerformanceMetric(
                        value: performanceMonitor.thermalState.shortName,
                        unit: "",
                        color: performanceMonitor.thermalColor,
                        isGood: false
                    )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .scaleEffect(performanceMonitor.isThrottling && !reduceMotion ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: performanceMonitor.isThrottling)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(getAccessibilityLabel())
    }
    
    private func getAccessibilityLabel() -> String {
        var components: [String] = []
        
        components.append("Performance: \(Int(performanceMonitor.currentFPS)) FPS")
        components.append("\(performanceMonitor.trackingQuality.rawValue) tracking")
        
        if performanceMonitor.memoryUsage > performanceMonitor.warningMemoryThreshold {
            components.append("High memory usage: \(Int(performanceMonitor.memoryUsage / (1024 * 1024))) MB")
        }
        
        if performanceMonitor.thermalState != .nominal {
            components.append("Thermal state: \(performanceMonitor.thermalState.rawValue)")
        }
        
        return components.joined(separator: ", ")
    }
}

// MARK: - Performance Metric

private struct PerformanceMetric: View {
    let value: String
    let unit: String
    let color: Color
    let isGood: Bool
    
    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            Text(value)
                .font(.caption2)
                .fontWeight(.semibold)
                .monospacedDigit()
            
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
        }
        .foregroundColor(.primary)
    }
}

// MARK: - Detailed Performance View

public struct DetailedPerformanceView: View {
    @EnvironmentObject private var performanceMonitor: ARPerformanceMonitor
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Details")
                .font(.headline)
                .fontWeight(.semibold)
            
            // FPS Section
            PerformanceSection(title: "Frame Rate") {
                MetricRow(label: "Current FPS", value: String(format: "%.1f", performanceMonitor.currentFPS), color: performanceMonitor.fpsColor)
                MetricRow(label: "Average FPS", value: String(format: "%.1f", performanceMonitor.averageFPS), color: performanceMonitor.fpsColor)
                MetricRow(label: "Render Time", value: String(format: "%.1f ms", performanceMonitor.renderTime * 1000), color: .primary)
            }
            
            // Tracking Section
            PerformanceSection(title: "AR Tracking") {
                MetricRow(label: "Quality", value: performanceMonitor.trackingQuality.rawValue, color: performanceMonitor.trackingColor)
                MetricRow(label: "World Mapping", value: performanceMonitor.worldMappingStatus.description, color: .primary)
                MetricRow(label: "Anchors", value: "\(performanceMonitor.anchorsCount)", color: .primary)
                MetricRow(label: "Light Estimate", value: String(format: "%.0f lm", performanceMonitor.lightEstimate), color: .primary)
            }
            
            // System Section
            PerformanceSection(title: "System") {
                MetricRow(label: "Memory Usage", value: String(format: "%.0f MB", Double(performanceMonitor.memoryUsage) / (1024.0 * 1024.0)), color: performanceMonitor.memoryColor)
                MetricRow(label: "Thermal State", value: performanceMonitor.thermalState.rawValue, color: performanceMonitor.thermalColor)
                MetricRow(label: "Battery Level", value: String(format: "%.0f%%", performanceMonitor.batteryLevel * 100), color: .primary)
                MetricRow(label: "Temperature", value: String(format: "%.1f°C", performanceMonitor.deviceTemperature), color: .primary)
            }
            
            // Rendering Section
            PerformanceSection(title: "Rendering") {
                MetricRow(label: "Entities", value: "\(performanceMonitor.entitiesCount)", color: .primary)
                MetricRow(label: "Triangles", value: "\(performanceMonitor.triangleCount)", color: .primary)
                MetricRow(label: "Draw Calls", value: "\(performanceMonitor.drawCalls)", color: .primary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Performance Section

private struct PerformanceSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                content
            }
        }
    }
}

// MARK: - Metric Row

private struct MetricRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
                .monospacedDigit()
        }
    }
}

// MARK: - Supporting Types

public enum TrackingQuality: String, CaseIterable {
    case normal = "Normal"
    case limited = "Limited"
    case poor = "Poor"
    
    public var shortName: String {
        switch self {
        case .normal: return "OK"
        case .limited: return "LTD"
        case .poor: return "BAD"
        }
    }
    
    public init(from trackingState: ARCamera.TrackingState) {
        switch trackingState {
        case .normal:
            self = .normal
        case .limited:
            self = .limited
        case .notAvailable:
            self = .poor
        }
    }
}

public enum PerformanceLevel: String, CaseIterable {
    case good = "good"
    case acceptable = "acceptable"
    case poor = "poor"
    case critical = "critical"
}

public struct PerformanceStatistics {
    public let currentFPS: Double
    public let averageFPS: Double
    public let trackingQuality: TrackingQuality
    public let memoryUsage: Int64
    public let thermalState: ProcessInfo.ThermalState
    public let batteryLevel: Float
    public let anchorsCount: Int
    public let entitiesCount: Int
    public let triangleCount: Int
    public let drawCalls: Int
    public let renderTime: TimeInterval
    public let performanceLevel: PerformanceLevel
    
    public init(currentFPS: Double, averageFPS: Double, trackingQuality: TrackingQuality, memoryUsage: Int64, thermalState: ProcessInfo.ThermalState, batteryLevel: Float, anchorsCount: Int, entitiesCount: Int, triangleCount: Int, drawCalls: Int, renderTime: TimeInterval, performanceLevel: PerformanceLevel) {
        self.currentFPS = currentFPS
        self.averageFPS = averageFPS
        self.trackingQuality = trackingQuality
        self.memoryUsage = memoryUsage
        self.thermalState = thermalState
        self.batteryLevel = batteryLevel
        self.anchorsCount = anchorsCount
        self.entitiesCount = entitiesCount
        self.triangleCount = triangleCount
        self.drawCalls = drawCalls
        self.renderTime = renderTime
        self.performanceLevel = performanceLevel
    }
}

// MARK: - Extensions

extension ProcessInfo.ThermalState {
    var shortName: String {
        switch self {
        case .nominal: return "OK"
        case .fair: return "FAIR"
        case .serious: return "HOT"
        case .critical: return "CRIT"
        @unknown default: return "UNK"
        }
    }
}

extension ARFrame.WorldMappingStatus {
    var description: String {
        switch self {
        case .notAvailable: return "Not Available"
        case .limited: return "Limited"
        case .extending: return "Extending"
        case .mapped: return "Mapped"
        @unknown default: return "Unknown"
        }
    }
}