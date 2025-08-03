import Foundation
import SwiftUI
import Combine
import Charts

// MARK: - Performance Monitoring Dashboard

@MainActor
public class PerformanceMonitoringDashboard: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var isVisible: Bool = false
    @Published public var dashboardData: DashboardData = DashboardData()
    @Published public var selectedMetric: MetricType = .frameRate
    @Published public var timeRange: TimeRange = .last5Minutes
    @Published public var alertsEnabled: Bool = true
    @Published public var currentAlerts: [PerformanceAlert] = []
    
    // MARK: - Dashboard Configuration
    public enum MetricType: String, CaseIterable {
        case frameRate = "Frame Rate"
        case memoryUsage = "Memory Usage"
        case cpuUsage = "CPU Usage"
        case gpuUsage = "GPU Usage"
        case batteryLevel = "Battery Level"
        case thermalState = "Thermal State"
        case networkActivity = "Network Activity"
        case renderingStats = "Rendering Stats"
        case cullingStats = "Culling Stats"
        case textureStats = "Texture Stats"
        case poolingStats = "Object Pooling"
        
        var unit: String {
            switch self {
            case .frameRate: return "FPS"
            case .memoryUsage: return "MB"
            case .cpuUsage: return "%"
            case .gpuUsage: return "%"
            case .batteryLevel: return "%"
            case .thermalState: return ""
            case .networkActivity: return "KB/s"
            case .renderingStats: return "ms"
            case .cullingStats: return "objects"
            case .textureStats: return "MB"
            case .poolingStats: return "objects"
            }
        }
        
        var color: Color {
            switch self {
            case .frameRate: return .green
            case .memoryUsage: return .blue
            case .cpuUsage: return .orange
            case .gpuUsage: return .purple
            case .batteryLevel: return .yellow
            case .thermalState: return .red
            case .networkActivity: return .cyan
            case .renderingStats: return .pink
            case .cullingStats: return .indigo
            case .textureStats: return .mint
            case .poolingStats: return .teal
            }
        }
    }
    
    public enum TimeRange: String, CaseIterable {
        case last1Minute = "1m"
        case last5Minutes = "5m"
        case last15Minutes = "15m"
        case last1Hour = "1h"
        case last6Hours = "6h"
        case last24Hours = "24h"
        
        var seconds: TimeInterval {
            switch self {
            case .last1Minute: return 60
            case .last5Minutes: return 300
            case .last15Minutes: return 900
            case .last1Hour: return 3600
            case .last6Hours: return 21600
            case .last24Hours: return 86400
            }
        }
        
        var sampleInterval: TimeInterval {
            switch self {
            case .last1Minute: return 1
            case .last5Minutes: return 5
            case .last15Minutes: return 15
            case .last1Hour: return 60
            case .last6Hours: return 300
            case .last24Hours: return 600
            }
        }
    }
    
    // MARK: - Private Properties
    private var performanceProfiler: InstrumentsProfiler
    private var dynamicQualityManager: DynamicQualityManager
    private var batteryOptimizer: BatteryOptimizationSystem
    private var textureOptimizer: TextureOptimizationSystem
    private var frustumCuller: FrustumCullingSystem
    private var objectPooling: ObjectPoolingSystem
    
    // Data collection
    private var dataCollector: PerformanceDataCollector
    private var alertManager: PerformanceAlertManager
    private var exportManager: DashboardExportManager
    
    // Real-time monitoring
    private var monitoringTimer: Timer?
    private var dataUpdateTimer: Timer?
    
    private var cancellables = Set<AnyCancellable>()
    
    public init(
        performanceProfiler: InstrumentsProfiler,
        dynamicQualityManager: DynamicQualityManager,
        batteryOptimizer: BatteryOptimizationSystem,
        textureOptimizer: TextureOptimizationSystem,
        frustumCuller: FrustumCullingSystem,
        objectPooling: ObjectPoolingSystem
    ) {
        self.performanceProfiler = performanceProfiler
        self.dynamicQualityManager = dynamicQualityManager
        self.batteryOptimizer = batteryOptimizer
        self.textureOptimizer = textureOptimizer
        self.frustumCuller = frustumCuller
        self.objectPooling = objectPooling
        
        self.dataCollector = PerformanceDataCollector()
        self.alertManager = PerformanceAlertManager()
        self.exportManager = DashboardExportManager()
        
        setupDashboard()
        
        logDebug("Performance monitoring dashboard initialized", category: .performance)
    }
    
    // MARK: - Setup
    
    private func setupDashboard() {
        setupDataCollection()
        setupAlertMonitoring()
        setupObservers()
        
        // Start with dashboard hidden
        isVisible = false
    }
    
    private func setupDataCollection() {
        // Start periodic data collection
        dataUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.collectPerformanceData()
        }
    }
    
    private func setupAlertMonitoring() {
        // Monitor for performance alerts
        alertManager.$currentAlerts
            .sink { [weak self] alerts in
                self?.currentAlerts = alerts
            }
            .store(in: &cancellables)
    }
    
    private func setupObservers() {
        // Monitor visibility changes
        $isVisible
            .sink { [weak self] visible in
                if visible {
                    self?.startRealTimeMonitoring()
                } else {
                    self?.stopRealTimeMonitoring()
                }
            }
            .store(in: &cancellables)
        
        // Monitor time range changes
        $timeRange
            .sink { [weak self] _ in
                self?.refreshDashboardData()
            }
            .store(in: &cancellables)
        
        // Monitor selected metric changes
        $selectedMetric
            .sink { [weak self] _ in
                self?.refreshDashboardData()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Collection
    
    private func collectPerformanceData() {
        let dataPoint = createCurrentDataPoint()
        dataCollector.addDataPoint(dataPoint)
        
        // Check for performance alerts
        if alertsEnabled {
            alertManager.checkForAlerts(dataPoint)
        }
        
        // Update dashboard data if visible
        if isVisible {
            updateDashboardData()
        }
    }
    
    private func createCurrentDataPoint() -> PerformanceDataPoint {
        return PerformanceDataPoint(
            timestamp: Date(),
            frameRate: getCurrentFrameRate(),
            memoryUsage: getCurrentMemoryUsage(),
            cpuUsage: getCurrentCPUUsage(),
            gpuUsage: getCurrentGPUUsage(),
            batteryLevel: batteryOptimizer.batteryLevel,
            thermalState: ProcessInfo.processInfo.thermalState,
            networkActivity: getCurrentNetworkActivity(),
            renderingStats: getRenderingStats(),
            cullingStats: getCullingStats(),
            textureStats: getTextureStats(),
            poolingStats: getPoolingStats()
        )
    }
    
    // MARK: - Data Sources
    
    private func getCurrentFrameRate() -> Double {
        return dynamicQualityManager.performanceMetrics.currentFPS
    }
    
    private func getCurrentMemoryUsage() -> Double {
        return dynamicQualityManager.performanceMetrics.memoryUsage
    }
    
    private func getCurrentCPUUsage() -> Double {
        return dynamicQualityManager.performanceMetrics.cpuUsage
    }
    
    private func getCurrentGPUUsage() -> Double {
        // GPU usage would need platform-specific implementation
        return 0.0
    }
    
    private func getCurrentNetworkActivity() -> Double {
        // Network activity would need implementation
        return 0.0
    }
    
    private func getRenderingStats() -> RenderingStats {
        return RenderingStats(
            drawCalls: 0,
            triangles: 0,
            renderTime: 0.0,
            shaderSwitches: 0
        )
    }
    
    private func getCullingStats() -> CullingStats {
        return CullingStats(
            totalObjects: frustumCuller.processedObjects,
            visibleObjects: frustumCuller.visibleObjects,
            culledObjects: frustumCuller.processedObjects - frustumCuller.visibleObjects,
            cullingTime: 0.0
        )
    }
    
    private func getTextureStats() -> TextureStats {
        let stats = textureOptimizer.getTextureStatistics()
        return TextureStats(
            loadedTextures: stats["loaded_textures"] as? Int ?? 0,
            memoryUsage: stats["memory_usage_mb"] as? Double ?? 0.0,
            cacheHitRate: stats["hit_rate"] as? Double ?? 0.0,
            averageLoadTime: stats["average_load_time"] as? Double ?? 0.0
        )
    }
    
    private func getPoolingStats() -> PoolingStats {
        let stats = objectPooling.getPoolingStatistics()
        return PoolingStats(
            totalPools: stats["scenekit_pools"] as? Int ?? 0 + stats["realitykit_pools"] as? Int ?? 0,
            totalObjects: stats["total_objects"] as? Int ?? 0,
            memoryUsage: stats["memory_usage_mb"] as? Double ?? 0.0,
            hitRate: Double(stats["returns"] as? Int ?? 0) / Double(max(1, stats["checkouts"] as? Int ?? 1))
        )
    }
    
    // MARK: - Real-Time Monitoring
    
    private func startRealTimeMonitoring() {
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateRealTimeMetrics()
        }
        
        logInfo("Started real-time performance monitoring", category: .performance)
    }
    
    private func stopRealTimeMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        logInfo("Stopped real-time performance monitoring", category: .performance)
    }
    
    private func updateRealTimeMetrics() {
        let currentData = createCurrentDataPoint()
        
        // Update current values in dashboard data
        dashboardData.currentValues = currentData
        
        // Update real-time chart data
        dashboardData.addRealTimeDataPoint(currentData)
    }
    
    // MARK: - Dashboard Data Management
    
    private func updateDashboardData() {
        let timeRangeData = dataCollector.getDataForTimeRange(timeRange)
        
        dashboardData = DashboardData(
            currentValues: createCurrentDataPoint(),
            historicalData: timeRangeData,
            selectedMetric: selectedMetric,
            timeRange: timeRange,
            summary: calculateSummaryStats(timeRangeData),
            alerts: currentAlerts
        )
    }
    
    private func refreshDashboardData() {
        updateDashboardData()
    }
    
    private func calculateSummaryStats(_ data: [PerformanceDataPoint]) -> SummaryStats {
        guard !data.isEmpty else {
            return SummaryStats(
                average: 0,
                minimum: 0,
                maximum: 0,
                standardDeviation: 0,
                dataPoints: 0
            )
        }
        
        let values = data.map { getMetricValue($0, for: selectedMetric) }
        let average = values.reduce(0, +) / Double(values.count)
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        
        let variance = values.map { pow($0 - average, 2) }.reduce(0, +) / Double(values.count)
        let standardDeviation = sqrt(variance)
        
        return SummaryStats(
            average: average,
            minimum: minimum,
            maximum: maximum,
            standardDeviation: standardDeviation,
            dataPoints: values.count
        )
    }
    
    private func getMetricValue(_ dataPoint: PerformanceDataPoint, for metric: MetricType) -> Double {
        switch metric {
        case .frameRate: return dataPoint.frameRate
        case .memoryUsage: return dataPoint.memoryUsage
        case .cpuUsage: return dataPoint.cpuUsage
        case .gpuUsage: return dataPoint.gpuUsage
        case .batteryLevel: return Double(dataPoint.batteryLevel * 100)
        case .thermalState: return Double(dataPoint.thermalState.rawValue)
        case .networkActivity: return dataPoint.networkActivity
        case .renderingStats: return dataPoint.renderingStats.renderTime
        case .cullingStats: return Double(dataPoint.cullingStats.culledObjects)
        case .textureStats: return dataPoint.textureStats.memoryUsage
        case .poolingStats: return Double(dataPoint.poolingStats.totalObjects)
        }
    }
    
    // MARK: - Public Interface
    
    public func showDashboard() {
        isVisible = true
        refreshDashboardData()
    }
    
    public func hideDashboard() {
        isVisible = false
    }
    
    public func toggleDashboard() {
        isVisible.toggle()
    }
    
    public func setMetric(_ metric: MetricType) {
        selectedMetric = metric
    }
    
    public func setTimeRange(_ range: TimeRange) {
        timeRange = range
    }
    
    public func enableAlerts(_ enabled: Bool) {
        alertsEnabled = enabled
        alertManager.setEnabled(enabled)
    }
    
    public func clearAlerts() {
        alertManager.clearAlerts()
    }
    
    public func exportData() -> DashboardExportData {
        return exportManager.exportData(
            historicalData: dataCollector.getAllData(),
            currentData: dashboardData,
            alerts: currentAlerts
        )
    }
    
    public func resetData() {
        dataCollector.clearData()
        dashboardData = DashboardData()
        currentAlerts.removeAll()
        
        logInfo("Performance dashboard data reset", category: .performance)
    }
    
    public func getDashboardView() -> some View {
        PerformanceDashboardView(dashboard: self)
    }
    
    deinit {
        monitoringTimer?.invalidate()
        dataUpdateTimer?.invalidate()
        
        logDebug("Performance monitoring dashboard deinitialized", category: .performance)
    }
}

// MARK: - Dashboard Data Structures

public struct DashboardData {
    public var currentValues: PerformanceDataPoint
    public var historicalData: [PerformanceDataPoint]
    public var selectedMetric: PerformanceMonitoringDashboard.MetricType
    public var timeRange: PerformanceMonitoringDashboard.TimeRange
    public var summary: SummaryStats
    public var alerts: [PerformanceAlert]
    public var realTimeData: [PerformanceDataPoint]
    
    public init() {
        self.currentValues = PerformanceDataPoint()
        self.historicalData = []
        self.selectedMetric = .frameRate
        self.timeRange = .last5Minutes
        self.summary = SummaryStats(average: 0, minimum: 0, maximum: 0, standardDeviation: 0, dataPoints: 0)
        self.alerts = []
        self.realTimeData = []
    }
    
    public init(
        currentValues: PerformanceDataPoint,
        historicalData: [PerformanceDataPoint],
        selectedMetric: PerformanceMonitoringDashboard.MetricType,
        timeRange: PerformanceMonitoringDashboard.TimeRange,
        summary: SummaryStats,
        alerts: [PerformanceAlert]
    ) {
        self.currentValues = currentValues
        self.historicalData = historicalData
        self.selectedMetric = selectedMetric
        self.timeRange = timeRange
        self.summary = summary
        self.alerts = alerts
        self.realTimeData = []
    }
    
    public mutating func addRealTimeDataPoint(_ dataPoint: PerformanceDataPoint) {
        realTimeData.append(dataPoint)
        
        // Keep only recent real-time data (last 60 seconds)
        let cutoffTime = Date().addingTimeInterval(-60)
        realTimeData = realTimeData.filter { $0.timestamp > cutoffTime }
    }
}

public struct PerformanceDataPoint {
    public let timestamp: Date
    public let frameRate: Double
    public let memoryUsage: Double
    public let cpuUsage: Double
    public let gpuUsage: Double
    public let batteryLevel: Float
    public let thermalState: ProcessInfo.ThermalState
    public let networkActivity: Double
    public let renderingStats: RenderingStats
    public let cullingStats: CullingStats
    public let textureStats: TextureStats
    public let poolingStats: PoolingStats
    
    public init() {
        self.timestamp = Date()
        self.frameRate = 60.0
        self.memoryUsage = 0.0
        self.cpuUsage = 0.0
        self.gpuUsage = 0.0
        self.batteryLevel = 1.0
        self.thermalState = .nominal
        self.networkActivity = 0.0
        self.renderingStats = RenderingStats(drawCalls: 0, triangles: 0, renderTime: 0.0, shaderSwitches: 0)
        self.cullingStats = CullingStats(totalObjects: 0, visibleObjects: 0, culledObjects: 0, cullingTime: 0.0)
        self.textureStats = TextureStats(loadedTextures: 0, memoryUsage: 0.0, cacheHitRate: 0.0, averageLoadTime: 0.0)
        self.poolingStats = PoolingStats(totalPools: 0, totalObjects: 0, memoryUsage: 0.0, hitRate: 0.0)
    }
    
    public init(
        timestamp: Date,
        frameRate: Double,
        memoryUsage: Double,
        cpuUsage: Double,
        gpuUsage: Double,
        batteryLevel: Float,
        thermalState: ProcessInfo.ThermalState,
        networkActivity: Double,
        renderingStats: RenderingStats,
        cullingStats: CullingStats,
        textureStats: TextureStats,
        poolingStats: PoolingStats
    ) {
        self.timestamp = timestamp
        self.frameRate = frameRate
        self.memoryUsage = memoryUsage
        self.cpuUsage = cpuUsage
        self.gpuUsage = gpuUsage
        self.batteryLevel = batteryLevel
        self.thermalState = thermalState
        self.networkActivity = networkActivity
        self.renderingStats = renderingStats
        self.cullingStats = cullingStats
        self.textureStats = textureStats
        self.poolingStats = poolingStats
    }
}

public struct RenderingStats {
    public let drawCalls: Int
    public let triangles: Int
    public let renderTime: Double
    public let shaderSwitches: Int
}

public struct CullingStats {
    public let totalObjects: Int
    public let visibleObjects: Int
    public let culledObjects: Int
    public let cullingTime: Double
}

public struct TextureStats {
    public let loadedTextures: Int
    public let memoryUsage: Double
    public let cacheHitRate: Double
    public let averageLoadTime: Double
}

public struct PoolingStats {
    public let totalPools: Int
    public let totalObjects: Int
    public let memoryUsage: Double
    public let hitRate: Double
}

public struct SummaryStats {
    public let average: Double
    public let minimum: Double
    public let maximum: Double
    public let standardDeviation: Double
    public let dataPoints: Int
}

public struct PerformanceAlert {
    public let id: UUID
    public let type: AlertType
    public let severity: AlertSeverity
    public let message: String
    public let timestamp: Date
    public let metric: PerformanceMonitoringDashboard.MetricType
    public let value: Double
    public let threshold: Double
    public let isAcknowledged: Bool
    
    public enum AlertType: String, CaseIterable {
        case lowFrameRate = "Low Frame Rate"
        case highMemoryUsage = "High Memory Usage"
        case highCPUUsage = "High CPU Usage"
        case lowBattery = "Low Battery"
        case thermalThrottling = "Thermal Throttling"
        case networkIssue = "Network Issue"
        case renderingIssue = "Rendering Issue"
    }
    
    public enum AlertSeverity: String, CaseIterable {
        case info = "Info"
        case warning = "Warning"
        case critical = "Critical"
        
        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .critical: return .red
            }
        }
    }
    
    public init(
        type: AlertType,
        severity: AlertSeverity,
        message: String,
        metric: PerformanceMonitoringDashboard.MetricType,
        value: Double,
        threshold: Double
    ) {
        self.id = UUID()
        self.type = type
        self.severity = severity
        self.message = message
        self.timestamp = Date()
        self.metric = metric
        self.value = value
        self.threshold = threshold
        self.isAcknowledged = false
    }
}

// MARK: - Supporting Classes

class PerformanceDataCollector {
    private var dataPoints: [PerformanceDataPoint] = []
    private let maxDataPoints = 24 * 60 * 60 // 24 hours of data at 1 second intervals
    
    func addDataPoint(_ dataPoint: PerformanceDataPoint) {
        dataPoints.append(dataPoint)
        
        // Keep only recent data
        if dataPoints.count > maxDataPoints {
            dataPoints.removeFirst(dataPoints.count - maxDataPoints)
        }
    }
    
    func getDataForTimeRange(_ timeRange: PerformanceMonitoringDashboard.TimeRange) -> [PerformanceDataPoint] {
        let cutoffTime = Date().addingTimeInterval(-timeRange.seconds)
        return dataPoints.filter { $0.timestamp > cutoffTime }
    }
    
    func getAllData() -> [PerformanceDataPoint] {
        return dataPoints
    }
    
    func clearData() {
        dataPoints.removeAll()
    }
}

class PerformanceAlertManager: ObservableObject {
    @Published var currentAlerts: [PerformanceAlert] = []
    
    private var isEnabled: Bool = true
    private var alertThresholds: [PerformanceMonitoringDashboard.MetricType: (min: Double?, max: Double?)] = [
        .frameRate: (min: 20, max: nil),
        .memoryUsage: (min: nil, max: 800),
        .cpuUsage: (min: nil, max: 80),
        .batteryLevel: (min: 20, max: nil)
    ]
    
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            clearAlerts()
        }
    }
    
    func checkForAlerts(_ dataPoint: PerformanceDataPoint) {
        guard isEnabled else { return }
        
        checkFrameRateAlert(dataPoint)
        checkMemoryAlert(dataPoint)
        checkCPUAlert(dataPoint)
        checkBatteryAlert(dataPoint)
        checkThermalAlert(dataPoint)
    }
    
    private func checkFrameRateAlert(_ dataPoint: PerformanceDataPoint) {
        if let minThreshold = alertThresholds[.frameRate]?.min,
           dataPoint.frameRate < minThreshold {
            
            let alert = PerformanceAlert(
                type: .lowFrameRate,
                severity: dataPoint.frameRate < 15 ? .critical : .warning,
                message: "Frame rate dropped to \(Int(dataPoint.frameRate)) FPS",
                metric: .frameRate,
                value: dataPoint.frameRate,
                threshold: minThreshold
            )
            
            addAlert(alert)
        }
    }
    
    private func checkMemoryAlert(_ dataPoint: PerformanceDataPoint) {
        if let maxThreshold = alertThresholds[.memoryUsage]?.max,
           dataPoint.memoryUsage > maxThreshold {
            
            let alert = PerformanceAlert(
                type: .highMemoryUsage,
                severity: dataPoint.memoryUsage > 1000 ? .critical : .warning,
                message: "Memory usage is \(Int(dataPoint.memoryUsage)) MB",
                metric: .memoryUsage,
                value: dataPoint.memoryUsage,
                threshold: maxThreshold
            )
            
            addAlert(alert)
        }
    }
    
    private func checkCPUAlert(_ dataPoint: PerformanceDataPoint) {
        if let maxThreshold = alertThresholds[.cpuUsage]?.max,
           dataPoint.cpuUsage > maxThreshold {
            
            let alert = PerformanceAlert(
                type: .highCPUUsage,
                severity: dataPoint.cpuUsage > 90 ? .critical : .warning,
                message: "CPU usage is \(Int(dataPoint.cpuUsage))%",
                metric: .cpuUsage,
                value: dataPoint.cpuUsage,
                threshold: maxThreshold
            )
            
            addAlert(alert)
        }
    }
    
    private func checkBatteryAlert(_ dataPoint: PerformanceDataPoint) {
        let batteryPercentage = Double(dataPoint.batteryLevel * 100)
        
        if let minThreshold = alertThresholds[.batteryLevel]?.min,
           batteryPercentage < minThreshold {
            
            let alert = PerformanceAlert(
                type: .lowBattery,
                severity: batteryPercentage < 10 ? .critical : .warning,
                message: "Battery level is \(Int(batteryPercentage))%",
                metric: .batteryLevel,
                value: batteryPercentage,
                threshold: minThreshold
            )
            
            addAlert(alert)
        }
    }
    
    private func checkThermalAlert(_ dataPoint: PerformanceDataPoint) {
        if dataPoint.thermalState == .serious || dataPoint.thermalState == .critical {
            let alert = PerformanceAlert(
                type: .thermalThrottling,
                severity: dataPoint.thermalState == .critical ? .critical : .warning,
                message: "Device thermal state: \(String(describing: dataPoint.thermalState))",
                metric: .thermalState,
                value: Double(dataPoint.thermalState.rawValue),
                threshold: Double(ProcessInfo.ThermalState.fair.rawValue)
            )
            
            addAlert(alert)
        }
    }
    
    private func addAlert(_ alert: PerformanceAlert) {
        // Check if similar alert already exists
        let existingAlert = currentAlerts.first { 
            $0.type == alert.type && !$0.isAcknowledged &&
            Date().timeIntervalSince($0.timestamp) < 60 // Within last minute
        }
        
        if existingAlert == nil {
            currentAlerts.append(alert)
            
            // Keep only recent alerts
            let cutoffTime = Date().addingTimeInterval(-3600) // Last hour
            currentAlerts = currentAlerts.filter { $0.timestamp > cutoffTime }
        }
    }
    
    func clearAlerts() {
        currentAlerts.removeAll()
    }
    
    func acknowledgeAlert(_ alertId: UUID) {
        if let index = currentAlerts.firstIndex(where: { $0.id == alertId }) {
            // Create new alert with acknowledged status
            let acknowledgedAlert = PerformanceAlert(
                type: currentAlerts[index].type,
                severity: currentAlerts[index].severity,
                message: currentAlerts[index].message,
                metric: currentAlerts[index].metric,
                value: currentAlerts[index].value,
                threshold: currentAlerts[index].threshold
            )
            
            currentAlerts[index] = acknowledgedAlert
        }
    }
}

class DashboardExportManager {
    func exportData(
        historicalData: [PerformanceDataPoint],
        currentData: DashboardData,
        alerts: [PerformanceAlert]
    ) -> DashboardExportData {
        return DashboardExportData(
            exportDate: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            deviceInfo: getDeviceInfo(),
            timeRange: currentData.timeRange,
            selectedMetric: currentData.selectedMetric,
            historicalData: historicalData,
            summary: currentData.summary,
            alerts: alerts,
            systemInfo: getSystemInfo()
        )
    }
    
    private func getDeviceInfo() -> [String: Any] {
        let device = UIDevice.current
        return [
            "model": device.model,
            "name": device.name,
            "systemName": device.systemName,
            "systemVersion": device.systemVersion,
            "batteryLevel": device.batteryLevel,
            "batteryState": device.batteryState.description
        ]
    }
    
    private func getSystemInfo() -> [String: Any] {
        let processInfo = ProcessInfo.processInfo
        return [
            "physicalMemory": processInfo.physicalMemory,
            "thermalState": String(describing: processInfo.thermalState),
            "lowPowerModeEnabled": processInfo.isLowPowerModeEnabled,
            "processorCount": processInfo.processorCount,
            "activeProcessorCount": processInfo.activeProcessorCount
        ]
    }
}

public struct DashboardExportData: Codable {
    public let exportDate: Date
    public let appVersion: String
    public let deviceInfo: [String: String]
    public let timeRange: String
    public let selectedMetric: String
    public let historicalData: [ExportDataPoint]
    public let summary: ExportSummaryStats
    public let alerts: [ExportAlert]
    public let systemInfo: [String: String]
    
    public init(
        exportDate: Date,
        appVersion: String,
        deviceInfo: [String: Any],
        timeRange: PerformanceMonitoringDashboard.TimeRange,
        selectedMetric: PerformanceMonitoringDashboard.MetricType,
        historicalData: [PerformanceDataPoint],
        summary: SummaryStats,
        alerts: [PerformanceAlert],
        systemInfo: [String: Any]
    ) {
        self.exportDate = exportDate
        self.appVersion = appVersion
        self.deviceInfo = deviceInfo.compactMapValues { "\($0)" }
        self.timeRange = timeRange.rawValue
        self.selectedMetric = selectedMetric.rawValue
        self.historicalData = historicalData.map { ExportDataPoint(from: $0) }
        self.summary = ExportSummaryStats(
            average: summary.average,
            minimum: summary.minimum,
            maximum: summary.maximum,
            standardDeviation: summary.standardDeviation,
            dataPoints: summary.dataPoints
        )
        self.alerts = alerts.map { ExportAlert(from: $0) }
        self.systemInfo = systemInfo.compactMapValues { "\($0)" }
    }
}

public struct ExportDataPoint: Codable {
    public let timestamp: Date
    public let frameRate: Double
    public let memoryUsage: Double
    public let cpuUsage: Double
    public let batteryLevel: Double
    public let thermalState: String
    
    public init(from dataPoint: PerformanceDataPoint) {
        self.timestamp = dataPoint.timestamp
        self.frameRate = dataPoint.frameRate
        self.memoryUsage = dataPoint.memoryUsage
        self.cpuUsage = dataPoint.cpuUsage
        self.batteryLevel = Double(dataPoint.batteryLevel)
        self.thermalState = String(describing: dataPoint.thermalState)
    }
}

public struct ExportSummaryStats: Codable {
    public let average: Double
    public let minimum: Double
    public let maximum: Double
    public let standardDeviation: Double
    public let dataPoints: Int
}

public struct ExportAlert: Codable {
    public let timestamp: Date
    public let type: String
    public let severity: String
    public let message: String
    public let metric: String
    public let value: Double
    public let threshold: Double
    
    public init(from alert: PerformanceAlert) {
        self.timestamp = alert.timestamp
        self.type = alert.type.rawValue
        self.severity = alert.severity.rawValue
        self.message = alert.message
        self.metric = alert.metric.rawValue
        self.value = alert.value
        self.threshold = alert.threshold
    }
}

// MARK: - SwiftUI Dashboard View

public struct PerformanceDashboardView: View {
    @ObservedObject var dashboard: PerformanceMonitoringDashboard
    @State private var selectedTab: Int = 0
    
    public var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                // Real-time metrics tab
                RealTimeMetricsView(dashboard: dashboard)
                    .tabItem {
                        Image(systemName: "gauge")
                        Text("Real-time")
                    }
                    .tag(0)
                
                // Historical data tab
                HistoricalDataView(dashboard: dashboard)
                    .tabItem {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                        Text("History")
                    }
                    .tag(1)
                
                // Alerts tab
                AlertsView(dashboard: dashboard)
                    .tabItem {
                        Image(systemName: "exclamationmark.triangle")
                        Text("Alerts")
                    }
                    .tag(2)
                    .badge(dashboard.currentAlerts.count)
                
                // Settings tab
                DashboardSettingsView(dashboard: dashboard)
                    .tabItem {
                        Image(systemName: "gear")
                        Text("Settings")
                    }
                    .tag(3)
            }
            .navigationTitle("Performance Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dashboard.hideDashboard()
                    }
                }
            }
        }
    }
}

struct RealTimeMetricsView: View {
    @ObservedObject var dashboard: PerformanceMonitoringDashboard
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 20) {
                MetricCardView(
                    title: "Frame Rate",
                    value: "\(Int(dashboard.dashboardData.currentValues.frameRate))",
                    unit: "FPS",
                    color: .green
                )
                
                MetricCardView(
                    title: "Memory",
                    value: "\(Int(dashboard.dashboardData.currentValues.memoryUsage))",
                    unit: "MB",
                    color: .blue
                )
                
                MetricCardView(
                    title: "CPU",
                    value: "\(Int(dashboard.dashboardData.currentValues.cpuUsage))",
                    unit: "%",
                    color: .orange
                )
                
                MetricCardView(
                    title: "Battery",
                    value: "\(Int(dashboard.dashboardData.currentValues.batteryLevel * 100))",
                    unit: "%",
                    color: .yellow
                )
            }
            .padding()
        }
    }
}

struct MetricCardView: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct HistoricalDataView: View {
    @ObservedObject var dashboard: PerformanceMonitoringDashboard
    
    var body: some View {
        VStack {
            // Metric selector
            Picker("Metric", selection: $dashboard.selectedMetric) {
                ForEach(PerformanceMonitoringDashboard.MetricType.allCases, id: \.self) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            // Time range selector
            Picker("Time Range", selection: $dashboard.timeRange) {
                ForEach(PerformanceMonitoringDashboard.TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            // Chart placeholder
            VStack {
                Text("Chart for \(dashboard.selectedMetric.rawValue)")
                    .font(.headline)
                
                Text("Time Range: \(dashboard.timeRange.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Summary statistics
                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary")
                        .font(.headline)
                    
                    HStack {
                        Text("Average:")
                        Spacer()
                        Text("\(dashboard.dashboardData.summary.average, specifier: "%.1f") \(dashboard.selectedMetric.unit)")
                    }
                    
                    HStack {
                        Text("Min/Max:")
                        Spacer()
                        Text("\(dashboard.dashboardData.summary.minimum, specifier: "%.1f") / \(dashboard.dashboardData.summary.maximum, specifier: "%.1f") \(dashboard.selectedMetric.unit)")
                    }
                    
                    HStack {
                        Text("Data Points:")
                        Spacer()
                        Text("\(dashboard.dashboardData.summary.dataPoints)")
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
            }
            .padding()
            
            Spacer()
        }
    }
}

struct AlertsView: View {
    @ObservedObject var dashboard: PerformanceMonitoringDashboard
    
    var body: some View {
        VStack {
            if dashboard.currentAlerts.isEmpty {
                VStack {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                    
                    Text("No Active Alerts")
                        .font(.headline)
                        .padding(.top)
                    
                    Text("System performance is within normal parameters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List {
                    ForEach(dashboard.currentAlerts, id: \.id) { alert in
                        AlertRowView(alert: alert)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Clear All") {
                    dashboard.clearAlerts()
                }
                .disabled(dashboard.currentAlerts.isEmpty)
            }
        }
    }
}

struct AlertRowView: View {
    let alert: PerformanceAlert
    
    var body: some View {
        HStack {
            Circle()
                .fill(alert.severity.color)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.message)
                    .font(.body)
                
                Text(alert.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(alert.severity.rawValue)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(alert.severity.color.opacity(0.2))
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
    }
}

struct DashboardSettingsView: View {
    @ObservedObject var dashboard: PerformanceMonitoringDashboard
    
    var body: some View {
        Form {
            Section("Monitoring") {
                Toggle("Enable Alerts", isOn: $dashboard.alertsEnabled)
                
                Button("Reset Data") {
                    dashboard.resetData()
                }
                .foregroundColor(.red)
            }
            
            Section("Export") {
                Button("Export Performance Data") {
                    let exportData = dashboard.exportData()
                    // Handle export data
                }
            }
            
            Section("System Information") {
                HStack {
                    Text("Device")
                    Spacer()
                    Text(UIDevice.current.model)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("iOS Version")
                    Spacer()
                    Text(UIDevice.current.systemVersion)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Memory")
                    Spacer()
                    Text("\(Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))) GB")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}