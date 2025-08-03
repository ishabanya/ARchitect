import Foundation
import UIKit
import MetricKit
import OSLog
import Combine

// MARK: - Enhanced Crash Reporting System
@MainActor
public class EnhancedCrashReportingSystem: ObservableObject {
    public static let shared = EnhancedCrashReportingSystem()
    
    @Published public var recentCrashes: [EnhancedCrashReport] = []
    @Published public var crashTrends: CrashTrends?
    @Published public var isProcessingCrash = false
    
    private let crashReporter = CrashReporter.shared
    private let analyticsManager = AnalyticsManager.shared
    private let feedbackManager = FeedbackManager.shared
    private let storageManager = CrashReportStorageManager()
    
    private var cancellables = Set<AnyCancellable>()
    private var metricKit: MXMetricManager?
    
    private init() {
        setupEnhancedReporting()
        setupMetricKit()
        loadRecentCrashes()
    }
    
    // MARK: - Public Methods
    
    public func reportCrashWithContext(
        error: Error,
        context: CrashContext,
        userActions: [UserAction] = [],
        environmentData: EnvironmentData? = nil
    ) async {
        isProcessingCrash = true
        defer { isProcessingCrash = false }
        
        let enhancedReport = await createEnhancedCrashReport(
            error: error,
            context: context,
            userActions: userActions,
            environmentData: environmentData
        )
        
        // Store the report
        await storageManager.store(enhancedReport)
        recentCrashes.insert(enhancedReport, at: 0)
        
        // Analyze crash patterns
        updateCrashTrends()
        
        // Auto-create feedback if critical
        if enhancedReport.severity == .critical {
            await createAutomaticFeedback(for: enhancedReport)
        }
        
        // Send to analytics
        trackCrashAnalytics(enhancedReport)
        
        // Report to crash reporting service
        await submitToRemoteService(enhancedReport)
    }
    
    public func getCrashReports(
        severity: CrashSeverity? = nil,
        timeRange: TimeRange? = nil,
        category: CrashCategory? = nil
    ) -> [EnhancedCrashReport] {
        return recentCrashes.filter { report in
            if let severity = severity, report.severity != severity { return false }
            if let category = category, report.category != category { return false }
            if let timeRange = timeRange {
                switch timeRange {
                case .lastHour:
                    return report.timestamp > Date().addingTimeInterval(-3600)
                case .lastDay:
                    return report.timestamp > Date().addingTimeInterval(-86400)
                case .lastWeek:
                    return report.timestamp > Date().addingTimeInterval(-604800)
                case .lastMonth:
                    return report.timestamp > Date().addingTimeInterval(-2592000)
                }
            }
            return true
        }
    }
    
    public func analyzeCrashPatterns() -> CrashPatternAnalysis {
        let analysis = CrashPatternAnalysis()
        
        // Analyze recent crashes
        let recentCrashes = getCrashReports(timeRange: .lastWeek)
        
        // Group by category
        let categoryGroups = Dictionary(grouping: recentCrashes) { $0.category }
        analysis.crashesByCategory = categoryGroups.mapValues { $0.count }
        
        // Group by severity
        let severityGroups = Dictionary(grouping: recentCrashes) { $0.severity }
        analysis.crashesBySeverity = severityGroups.mapValues { $0.count }
        
        // Identify frequent crash locations
        let locationGroups = Dictionary(grouping: recentCrashes) { report in
            report.stackTrace.first ?? "Unknown"
        }
        analysis.frequentCrashLocations = locationGroups
            .sorted { $0.value.count > $1.value.count }
            .prefix(10)
            .map { (location: $0.key, count: $0.value.count) }
        
        // Calculate crash rate
        let totalSessions = analyticsManager.getTotalSessions(in: .lastWeek)
        analysis.crashRate = totalSessions > 0 ? Double(recentCrashes.count) / Double(totalSessions) : 0
        
        // Identify problematic app versions
        let versionGroups = Dictionary(grouping: recentCrashes) { $0.appVersion }
        analysis.crashesByVersion = versionGroups.mapValues { $0.count }
        
        return analysis
    }
    
    public func generateCrashReport(for crashId: UUID) -> String {
        guard let crash = recentCrashes.first(where: { $0.id == crashId }) else {
            return "Crash report not found"
        }
        
        return CrashReportFormatter.format(crash)
    }
    
    public func exportCrashData(timeRange: TimeRange) -> Data? {
        let crashes = getCrashReports(timeRange: timeRange)
        let exportData = CrashExportData(
            crashes: crashes,
            generatedAt: Date(),
            timeRange: timeRange,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        )
        
        return try? JSONEncoder().encode(exportData)
    }
    
    // MARK: - Private Methods
    
    private func setupEnhancedReporting() {
        // Listen for crash reports from the basic crash reporter
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBasicCrashReport),
            name: Notification.Name("CrashReported"),
            object: nil
        )
        
        // Setup memory warning monitoring
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.recordMemoryWarning()
            }
            .store(in: &cancellables)
        
        // Setup app state monitoring
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.recordAppStateChange(.background)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.recordAppStateChange(.foreground)
            }
            .store(in: &cancellables)
    }
    
    private func setupMetricKit() {
        if #available(iOS 13.0, *) {
            metricKit = MXMetricManager.shared
            metricKit?.add(self)
        }
    }
    
    @objc private func handleBasicCrashReport(_ notification: Notification) {
        if let crashReport = notification.object as? CrashReport {
            Task {
                await convertAndEnhanceCrashReport(crashReport)
            }
        }
    }
    
    private func convertAndEnhanceCrashReport(_ basicReport: CrashReport) async {
        let context = CrashContext(
            feature: detectCurrentFeature(),
            userFlow: getCurrentUserFlow(),
            screenName: getCurrentScreenName(),
            networkState: getNetworkState(),
            memoryPressure: getMemoryPressure()
        )
        
        let environmentData = EnvironmentData(
            thermalState: ProcessInfo.processInfo.thermalState,
            batteryState: UIDevice.current.batteryState,
            batteryLevel: UIDevice.current.batteryLevel,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            availableStorage: getAvailableStorage(),
            networkType: getNetworkType()
        )
        
        let enhancedReport = EnhancedCrashReport(
            id: basicReport.id,
            timestamp: basicReport.timestamp,
            severity: determineSeverity(from: basicReport),
            category: categorizeError(basicReport),
            title: generateCrashTitle(basicReport),
            description: basicReport.exceptionReason ?? "Unknown crash",
            stackTrace: basicReport.stackTrace,
            context: context,
            environmentData: environmentData,
            userActions: getUserActionHistory(),
            reproductionSteps: generateReproductionSteps(),
            appVersion: basicReport.appInfo.version,
            buildNumber: basicReport.appInfo.build,
            deviceInfo: convertDeviceInfo(basicReport.deviceInfo),
            symbolicated: false,
            attachments: [],
            tags: generateTags(basicReport),
            relatedCrashes: findRelatedCrashes(basicReport),
            userImpact: assessUserImpact(basicReport),
            priority: calculatePriority(basicReport),
            assignee: nil,
            status: .new,
            resolution: nil
        )
        
        await storageManager.store(enhancedReport)
        recentCrashes.insert(enhancedReport, at: 0)
        updateCrashTrends()
    }
    
    private func createEnhancedCrashReport(
        error: Error,
        context: CrashContext,
        userActions: [UserAction],
        environmentData: EnvironmentData?
    ) async -> EnhancedCrashReport {
        
        let severity = determineSeverityFromError(error)
        let category = categorizeError(error)
        
        return EnhancedCrashReport(
            id: UUID(),
            timestamp: Date(),
            severity: severity,
            category: category,
            title: generateTitleFromError(error),
            description: error.localizedDescription,
            stackTrace: Thread.callStackSymbols,
            context: context,
            environmentData: environmentData ?? EnvironmentData.current(),
            userActions: userActions,
            reproductionSteps: generateReproductionStepsFromActions(userActions),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown",
            deviceInfo: DeviceInfo.current(),
            symbolicated: false,
            attachments: [],
            tags: generateTagsFromError(error),
            relatedCrashes: [],
            userImpact: assessUserImpactFromError(error),
            priority: calculatePriorityFromError(error),
            assignee: nil,
            status: .new,
            resolution: nil
        )
    }
    
    private func createAutomaticFeedback(for crashReport: EnhancedCrashReport) async {
        let feedback = FeedbackItem(
            type: .crash,
            priority: .critical,
            title: "Automatic Crash Report: \(crashReport.title)",
            description: """
            The app experienced a critical crash. Here are the details:
            
            Error: \(crashReport.description)
            Feature: \(crashReport.context.feature ?? "Unknown")
            Screen: \(crashReport.context.screenName ?? "Unknown")
            
            This feedback was automatically generated to help improve the app.
            """,
            steps: crashReport.reproductionSteps,
            crashReportId: crashReport.id.uuidString,
            tags: crashReport.tags + ["auto-generated", "critical-crash"],
            severity: 5
        )
        
        do {
            _ = try await feedbackManager.submitFeedback(feedback)
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "auto_feedback_creation",
                "crash_id": crashReport.id.uuidString
            ])
        }
    }
    
    private func trackCrashAnalytics(_ report: EnhancedCrashReport) {
        analyticsManager.trackCustomEvent(
            name: "enhanced_crash_reported",
            parameters: [
                "crash_id": report.id.uuidString,
                "severity": report.severity.rawValue,
                "category": report.category.rawValue,
                "feature": report.context.feature ?? "unknown",
                "screen": report.context.screenName ?? "unknown",
                "user_impact": report.userImpact.rawValue,
                "has_reproduction_steps": !report.reproductionSteps.isEmpty,
                "user_actions_count": report.userActions.count
            ],
            severity: .high
        )
    }
    
    private func submitToRemoteService(_ report: EnhancedCrashReport) async {
        // This would integrate with a crash reporting service like Firebase Crashlytics, Bugsnag, etc.
        // For now, just log it
        print("Submitting enhanced crash report to remote service: \(report.id)")
    }
    
    private func loadRecentCrashes() {
        Task {
            recentCrashes = await storageManager.loadRecent(limit: 100)
            updateCrashTrends()
        }
    }
    
    private func updateCrashTrends() {
        let analysis = analyzeCrashPatterns()
        crashTrends = CrashTrends(
            totalCrashes: recentCrashes.count,
            crashRate: analysis.crashRate,
            topCrashCategories: analysis.crashesByCategory.sorted { $0.value > $1.value }.prefix(5).map { $0 },
            mostProblematicVersion: analysis.crashesByVersion.max { $0.value < $1.value }?.key,
            trendDirection: calculateTrendDirection()
        )
    }
    
    private func calculateTrendDirection() -> TrendDirection {
        let thisWeek = getCrashReports(timeRange: .lastWeek).count
        let lastWeek = getCrashReports().filter { crash in
            let weekAgo = Date().addingTimeInterval(-604800)
            let twoWeeksAgo = Date().addingTimeInterval(-1209600)
            return crash.timestamp >= twoWeeksAgo && crash.timestamp < weekAgo
        }.count
        
        if thisWeek > lastWeek {
            return .increasing
        } else if thisWeek < lastWeek {
            return .decreasing
        } else {
            return .stable
        }
    }
    
    private func recordMemoryWarning() {
        // Record memory warning as a potential crash precursor
        let context = CrashContext(
            feature: detectCurrentFeature(),
            userFlow: getCurrentUserFlow(),
            screenName: getCurrentScreenName(),
            networkState: getNetworkState(),
            memoryPressure: .high
        )
        
        // This would be stored as a warning event
        analyticsManager.trackCustomEvent(
            name: "memory_warning_recorded",
            parameters: [
                "feature": context.feature ?? "unknown",
                "screen": context.screenName ?? "unknown",
                "memory_usage": getMemoryUsage()
            ],
            severity: .high
        )
    }
    
    private func recordAppStateChange(_ state: AppState) {
        // Record app state changes for crash context
        let context = [
            "new_state": state.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        analyticsManager.trackCustomEvent(
            name: "app_state_changed",
            parameters: context,
            severity: .low
        )
    }
    
    // MARK: - Helper Methods
    
    private func detectCurrentFeature() -> String? {
        // This would analyze the current view controller stack or SwiftUI view hierarchy
        return "AR_View"
    }
    
    private func getCurrentUserFlow() -> String? {
        // This would track the current user journey
        return "Room_Scanning"
    }
    
    private func getCurrentScreenName() -> String? {
        // This would get the current screen name
        return "RoomScanningView"
    }
    
    private func getNetworkState() -> NetworkState {
        // This would check actual network connectivity
        return .wifi
    }
    
    private func getMemoryPressure() -> MemoryPressure {
        let memoryMB = Float(getMemoryUsage()) / 1024 / 1024
        
        if memoryMB > 500 {
            return .high
        } else if memoryMB > 200 {
            return .medium
        } else {
            return .low
        }
    }
    
    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
    
    private func getAvailableStorage() -> Int64 {
        do {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            return Int64(values.volumeAvailableCapacity ?? 0)
        } catch {
            return 0
        }
    }
    
    private func getNetworkType() -> String {
        // This would use Network framework for actual detection
        return "wifi"
    }
    
    private func getUserActionHistory() -> [UserAction] {
        // This would retrieve recent user actions from analytics
        return []
    }
    
    private func generateReproductionSteps() -> [String] {
        // This would generate steps based on user actions
        return []
    }
    
    private func generateReproductionStepsFromActions(_ actions: [UserAction]) -> [String] {
        return actions.map { "User \($0.type.rawValue): \($0.target ?? "unknown")" }
    }
    
    private func determineSeverity(from report: CrashReport) -> CrashSeverity {
        switch report.crashType {
        case .exception:
            return .high
        case .signal:
            return .critical
        case .memoryPressure:
            return .medium
        case .watchdog:
            return .high
        case .manualReport:
            return .low
        }
    }
    
    private func determineSeverityFromError(_ error: Error) -> CrashSeverity {
        let nsError = error as NSError
        
        switch nsError.domain {
        case NSCocoaErrorDomain:
            return .medium
        case "ARErrorDomain":
            return .high
        default:
            return .medium
        }
    }
    
    private func categorizeError(_ report: CrashReport) -> CrashCategory {
        // Analyze crash report to determine category
        if let exceptionName = report.exceptionName {
            if exceptionName.contains("Memory") {
                return .memory
            } else if exceptionName.contains("Network") {
                return .network
            } else if exceptionName.contains("UI") {
                return .ui
            }
        }
        
        return .runtime
    }
    
    private func categorizeError(_ error: Error) -> CrashCategory {
        let nsError = error as NSError
        
        switch nsError.domain {
        case NSURLErrorDomain:
            return .network
        case "ARErrorDomain":
            return .ar
        case NSCocoaErrorDomain:
            return .runtime
        default:
            return .unknown
        }
    }
    
    private func generateCrashTitle(_ report: CrashReport) -> String {
        if let exceptionName = report.exceptionName {
            return "Crash: \(exceptionName)"
        } else if let signal = report.signal {
            return "Signal \(signal) Crash"
        } else {
            return "Unknown Crash"
        }
    }
    
    private func generateTitleFromError(_ error: Error) -> String {
        return "Error: \(type(of: error))"
    }
    
    private func generateTags(_ report: CrashReport) -> [String] {
        var tags: [String] = []
        
        tags.append(report.crashType.rawValue)
        
        if let exceptionName = report.exceptionName {
            tags.append(exceptionName.lowercased())
        }
        
        return tags
    }
    
    private func generateTagsFromError(_ error: Error) -> [String] {
        let nsError = error as NSError
        return [nsError.domain.lowercased(), "error_code_\(nsError.code)"]
    }
    
    private func findRelatedCrashes(_ report: CrashReport) -> [UUID] {
        // Find crashes with similar stack traces or error types
        return []
    }
    
    private func assessUserImpact(_ report: CrashReport) -> UserImpact {
        switch report.crashType {
        case .signal, .exception:
            return .high
        case .memoryPressure:
            return .medium
        case .watchdog:
            return .high
        case .manualReport:
            return .low
        }
    }
    
    private func assessUserImpactFromError(_ error: Error) -> UserImpact {
        let nsError = error as NSError
        
        if nsError.domain == "ARErrorDomain" {
            return .high
        } else if nsError.domain == NSURLErrorDomain {
            return .medium
        } else {
            return .low
        }
    }
    
    private func calculatePriority(_ report: CrashReport) -> CrashPriority {
        let severity = determineSeverity(from: report)
        let impact = assessUserImpact(report)
        
        switch (severity, impact) {
        case (.critical, _), (_, .high):
            return .p1
        case (.high, .medium):
            return .p2
        case (.medium, .medium):
            return .p3
        default:
            return .p4
        }
    }
    
    private func calculatePriorityFromError(_ error: Error) -> CrashPriority {
        let severity = determineSeverityFromError(error)
        let impact = assessUserImpactFromError(error)
        
        switch (severity, impact) {
        case (.critical, _), (_, .high):
            return .p1
        case (.high, .medium):
            return .p2
        case (.medium, .medium):
            return .p3
        default:
            return .p4
        }
    }
    
    private func convertDeviceInfo(_ crashDeviceInfo: CrashReport.DeviceInfo) -> DeviceInfo {
        return DeviceInfo(
            model: crashDeviceInfo.model,
            systemName: crashDeviceInfo.systemName,
            systemVersion: crashDeviceInfo.systemVersion,
            architecture: crashDeviceInfo.architecture,
            screenSize: "unknown",
            screenScale: 1.0,
            orientation: "unknown",
            batteryLevel: crashDeviceInfo.batteryLevel,
            batteryState: crashDeviceInfo.batteryState,
            isJailbroken: crashDeviceInfo.isJailbroken,
            availableStorage: Int64(crashDeviceInfo.diskSpace),
            totalMemory: Int64(crashDeviceInfo.totalMemory),
            processorType: crashDeviceInfo.architecture,
            isSimulator: false,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )
    }
}

// MARK: - MetricKit Delegate
@available(iOS 13.0, *)
extension EnhancedCrashReportingSystem: MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            if let crashDiagnostics = payload.crashDiagnostics {
                for diagnostic in crashDiagnostics {
                    Task {
                        await processMXCrashDiagnostic(diagnostic)
                    }
                }
            }
        }
    }
    
    private func processMXCrashDiagnostic(_ diagnostic: MXCrashDiagnostic) async {
        let context = CrashContext(
            feature: nil,
            userFlow: nil,
            screenName: nil,
            networkState: .unknown,
            memoryPressure: .unknown
        )
        
        let enhancedReport = EnhancedCrashReport(
            id: UUID(),
            timestamp: diagnostic.metaData.osVersion != nil ? Date() : Date(),
            severity: .high,
            category: .runtime,
            title: "MetricKit Crash: \(diagnostic.callStackTree.callStacks.first?.callStackPerThread.keys.first ?? "Unknown")",
            description: "Crash detected by MetricKit",
            stackTrace: extractStackTrace(from: diagnostic),
            context: context,
            environmentData: EnvironmentData.current(),
            userActions: [],
            reproductionSteps: [],
            appVersion: diagnostic.metaData.applicationBuildVersion ?? "Unknown",
            buildNumber: diagnostic.metaData.applicationBuildVersion ?? "Unknown",
            deviceInfo: DeviceInfo.current(),
            symbolicated: true,
            attachments: [],
            tags: ["metrickit", "crash"],
            relatedCrashes: [],
            userImpact: .medium,
            priority: .p2,
            assignee: nil,
            status: .new,
            resolution: nil
        )
        
        await storageManager.store(enhancedReport)
        recentCrashes.insert(enhancedReport, at: 0)
        updateCrashTrends()
    }
    
    private func extractStackTrace(from diagnostic: MXCrashDiagnostic) -> [String] {
        // Extract stack trace from MXCrashDiagnostic
        var stackTrace: [String] = []
        
        for callStackPerThread in diagnostic.callStackTree.callStacks {
            for (thread, callStack) in callStackPerThread.callStackPerThread {
                stackTrace.append("Thread \(thread):")
                for frame in callStack {
                    stackTrace.append("  \(frame.binaryName ?? "Unknown") + \(frame.offsetIntoBinaryTextSegment)")
                }
            }
        }
        
        return stackTrace
    }
}

// MARK: - Enhanced Crash Report Models
public struct EnhancedCrashReport: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let severity: CrashSeverity
    public let category: CrashCategory
    public let title: String
    public let description: String
    public let stackTrace: [String]
    public let context: CrashContext
    public let environmentData: EnvironmentData
    public let userActions: [UserAction]
    public let reproductionSteps: [String]
    public let appVersion: String
    public let buildNumber: String
    public let deviceInfo: DeviceInfo
    public let symbolicated: Bool
    public let attachments: [CrashAttachment]
    public let tags: [String]
    public let relatedCrashes: [UUID]
    public let userImpact: UserImpact
    public let priority: CrashPriority
    public let assignee: String?
    public let status: CrashStatus
    public let resolution: CrashResolution?
}

public struct CrashContext: Codable {
    public let feature: String?
    public let userFlow: String?
    public let screenName: String?
    public let networkState: NetworkState
    public let memoryPressure: MemoryPressure
}

public struct EnvironmentData: Codable {
    public let thermalState: ProcessInfo.ThermalState
    public let batteryState: UIDevice.BatteryState
    public let batteryLevel: Float?
    public let lowPowerMode: Bool
    public let availableStorage: Int64
    public let networkType: String
    
    public static func current() -> EnvironmentData {
        return EnvironmentData(
            thermalState: ProcessInfo.processInfo.thermalState,
            batteryState: UIDevice.current.batteryState,
            batteryLevel: UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel : nil,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            availableStorage: getAvailableStorage(),
            networkType: "wifi"
        )
    }
    
    private static func getAvailableStorage() -> Int64 {
        do {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            return Int64(values.volumeAvailableCapacity ?? 0)
        } catch {
            return 0
        }
    }
}

public struct UserAction: Codable {
    public let id: UUID
    public let timestamp: Date
    public let type: ActionType
    public let target: String?
    public let parameters: [String: String]
    
    public enum ActionType: String, Codable {
        case tap = "tap"
        case swipe = "swipe"
        case pinch = "pinch"
        case navigate = "navigate"
        case input = "input"
        case gesture = "gesture"
    }
}

public struct CrashAttachment: Identifiable, Codable {
    public let id: UUID
    public let filename: String
    public let mimeType: String
    public let size: Int64
    public let localPath: String
    public let uploadUrl: String?
}

// MARK: - Enums
public enum CrashSeverity: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

public enum CrashCategory: String, CaseIterable, Codable {
    case runtime = "runtime"
    case memory = "memory"
    case network = "network"
    case ui = "ui"
    case ar = "ar"
    case data = "data"
    case permission = "permission"
    case unknown = "unknown"
}

public enum NetworkState: String, Codable {
    case wifi = "wifi"
    case cellular = "cellular"
    case offline = "offline"
    case unknown = "unknown"
}

public enum MemoryPressure: String, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case unknown = "unknown"
}

public enum UserImpact: String, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
}

public enum CrashPriority: String, CaseIterable, Codable {
    case p1 = "p1"
    case p2 = "p2"
    case p3 = "p3"
    case p4 = "p4"
}

public enum CrashStatus: String, CaseIterable, Codable {
    case new = "new"
    case triaged = "triaged"
    case assigned = "assigned"
    case inProgress = "in_progress"
    case resolved = "resolved"
    case closed = "closed"
    case rejected = "rejected"
}

public enum CrashResolution: String, CaseIterable, Codable {
    case fixed = "fixed"
    case wontFix = "wont_fix"
    case duplicate = "duplicate"
    case cannotReproduce = "cannot_reproduce"
    case workingAsDesigned = "working_as_designed"
}

public enum TimeRange: String, CaseIterable {
    case lastHour = "last_hour"
    case lastDay = "last_day"
    case lastWeek = "last_week"
    case lastMonth = "last_month"
}

public enum AppState: String {
    case foreground = "foreground"
    case background = "background"
}

public enum TrendDirection: String {
    case increasing = "increasing"
    case decreasing = "decreasing"
    case stable = "stable"
}

// MARK: - Analysis Models
public struct CrashPatternAnalysis {
    public var crashesByCategory: [CrashCategory: Int] = [:]
    public var crashesBySeverity: [CrashSeverity: Int] = [:]
    public var frequentCrashLocations: [(location: String, count: Int)] = []
    public var crashRate: Double = 0
    public var crashesByVersion: [String: Int] = [:]
}

public struct CrashTrends {
    public let totalCrashes: Int
    public let crashRate: Double
    public let topCrashCategories: [(key: CrashCategory, value: Int)]
    public let mostProblematicVersion: String?
    public let trendDirection: TrendDirection
}

public struct CrashExportData: Codable {
    public let crashes: [EnhancedCrashReport]
    public let generatedAt: Date
    public let timeRange: TimeRange
    public let appVersion: String
}

// MARK: - Storage Manager
public class CrashReportStorageManager {
    private let fileManager = FileManager.default
    private let crashesDirectory: URL
    
    public init() {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        crashesDirectory = documentsDirectory.appendingPathComponent("EnhancedCrashes")
        
        try? fileManager.createDirectory(at: crashesDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    public func store(_ report: EnhancedCrashReport) async {
        let filename = "\(report.timestamp.timeIntervalSince1970)_\(report.id.uuidString).json"
        let url = crashesDirectory.appendingPathComponent(filename)
        
        do {
            let data = try JSONEncoder().encode(report)
            try data.write(to: url)
        } catch {
            print("Failed to store enhanced crash report: \(error)")
        }
    }
    
    public func loadRecent(limit: Int) async -> [EnhancedCrashReport] {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: crashesDirectory, 
                                                              includingPropertiesForKeys: [.creationDateKey],
                                                              options: [])
            
            let sortedURLs = fileURLs
                .filter { $0.pathExtension == "json" }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return date1 > date2
                }
                .prefix(limit)
            
            var reports: [EnhancedCrashReport] = []
            for url in sortedURLs {
                if let data = try? Data(contentsOf: url),
                   let report = try? JSONDecoder().decode(EnhancedCrashReport.self, from: data) {
                    reports.append(report)
                }
            }
            
            return reports
            
        } catch {
            return []
        }
    }
}

// MARK: - Report Formatter
public struct CrashReportFormatter {
    public static func format(_ report: EnhancedCrashReport) -> String {
        var formatted = """
        ENHANCED CRASH REPORT
        =====================
        
        ID: \(report.id.uuidString)
        Timestamp: \(report.timestamp)
        Severity: \(report.severity.rawValue.uppercased())
        Category: \(report.category.rawValue.uppercased())
        Priority: \(report.priority.rawValue.uppercased())
        
        SUMMARY
        -------
        Title: \(report.title)
        Description: \(report.description)
        
        APP INFO
        --------
        Version: \(report.appVersion)
        Build: \(report.buildNumber)
        
        DEVICE INFO
        -----------
        Model: \(report.deviceInfo.model)
        OS: \(report.deviceInfo.systemName) \(report.deviceInfo.systemVersion)
        Architecture: \(report.deviceInfo.architecture)
        
        CONTEXT
        -------
        Feature: \(report.context.feature ?? "Unknown")
        Screen: \(report.context.screenName ?? "Unknown")
        User Flow: \(report.context.userFlow ?? "Unknown")
        Network: \(report.context.networkState.rawValue)
        Memory Pressure: \(report.context.memoryPressure.rawValue)
        
        ENVIRONMENT
        -----------
        Thermal State: \(report.environmentData.thermalState.description)
        Battery: \(report.environmentData.batteryLevel.map { "\($0 * 100)%" } ?? "Unknown") (\(report.environmentData.batteryState.description))
        Low Power Mode: \(report.environmentData.lowPowerMode ? "Yes" : "No")
        
        """
        
        if !report.reproductionSteps.isEmpty {
            formatted += """
            
            REPRODUCTION STEPS
            ------------------
            \(report.reproductionSteps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
            
            """
        }
        
        if !report.userActions.isEmpty {
            formatted += """
            
            USER ACTIONS (Last \(report.userActions.count))
            \(String(repeating: "-", count: 20 + "\(report.userActions.count)".count))
            \(report.userActions.map { "\($0.timestamp): \($0.type.rawValue) - \($0.target ?? "unknown")" }.joined(separator: "\n"))
            
            """
        }
        
        formatted += """
        
        STACK TRACE
        -----------
        \(report.stackTrace.joined(separator: "\n"))
        
        TAGS: \(report.tags.joined(separator: ", "))
        
        """
        
        return formatted
    }
}

// MARK: - Extensions
extension ProcessInfo.ThermalState: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        
        switch rawValue {
        case 0: self = .nominal
        case 1: self = .fair
        case 2: self = .serious
        case 3: self = .critical
        default: self = .nominal
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let rawValue: Int
        
        switch self {
        case .nominal: rawValue = 0
        case .fair: rawValue = 1
        case .serious: rawValue = 2
        case .critical: rawValue = 3
        @unknown default: rawValue = 0
        }
        
        try container.encode(rawValue)
    }
}

extension UIDevice.BatteryState: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        
        switch rawValue {
        case 0: self = .unknown
        case 1: self = .unplugged
        case 2: self = .charging
        case 3: self = .full
        default: self = .unknown
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}