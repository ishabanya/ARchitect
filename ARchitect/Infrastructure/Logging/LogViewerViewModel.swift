import Foundation
import Combine

// MARK: - Log Viewer ViewModel
public class LogViewerViewModel: ObservableObject {
    @Published var displayedLogs: [LogEntry] = []
    @Published var statistics: LogStatistics?
    @Published var analysis: LogAnalysis?
    @Published var selectedLog: LogEntry?
    @Published var isLoading = false
    
    // Filter properties
    @Published var filterLevel: LogLevel? = nil
    @Published var filterCategory: LogCategory? = nil
    @Published var filterSince: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @Published var searchQuery: String = ""
    
    private let logManager = LogManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var currentFilter = LogFilter()
    
    init() {
        setupObservers()
        refreshLogs()
        refreshStats()
        refreshAnalysis()
    }
    
    // MARK: - Public Methods
    
    func refreshLogs() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let logs = self.logManager.getLogs(filter: self.currentFilter)
            
            DispatchQueue.main.async {
                self.displayedLogs = logs
                self.isLoading = false
            }
        }
    }
    
    func refreshStats() {
        DispatchQueue.global(qos: .userInitiated).async {
            let stats = self.logManager.getLogStatistics(since: self.filterSince)
            
            DispatchQueue.main.async {
                self.statistics = stats
            }
        }
    }
    
    func refreshAnalysis() {
        DispatchQueue.global(qos: .userInitiated).async {
            let analysis = self.logManager.analyzeLogPatterns(since: self.filterSince)
            
            DispatchQueue.main.async {
                self.analysis = analysis
            }
        }
    }
    
    func searchLogs(query: String) {
        searchQuery = query
        
        if query.isEmpty {
            refreshLogs()
            return
        }
        
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let searchResults = self.logManager.searchLogs(query: query, filter: self.currentFilter)
            
            DispatchQueue.main.async {
                self.displayedLogs = searchResults
                self.isLoading = false
            }
        }
    }
    
    func applyFilters() {
        currentFilter = LogFilter(
            category: filterCategory,
            level: filterLevel,
            since: filterSince,
            limit: 1000 // Reasonable limit for UI
        )
        
        refreshLogs()
        refreshStats()
        refreshAnalysis()
    }
    
    func resetFilters() {
        filterLevel = nil
        filterCategory = nil
        filterSince = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        searchQuery = ""
        currentFilter = LogFilter()
        
        refreshLogs()
        refreshStats()
        refreshAnalysis()
    }
    
    func clearAllLogs() {
        logManager.clearLogs()
        refreshLogs()
        refreshStats()
        refreshAnalysis()
    }
    
    func exportLogs(format: LogExportFormat) -> Data? {
        return logManager.exportLogs(filter: currentFilter, format: format)
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // Observe filter changes
        Publishers.CombineLatest3($filterLevel, $filterCategory, $filterSince)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _, _, _ in
                // Auto-apply filters when they change (with debounce)
                self?.applyFilters()
            }
            .store(in: &cancellables)
        
        // Observe search query changes
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query in
                self?.searchLogs(query: query)
            }
            .store(in: &cancellables)
    }
}

// MARK: - Log Performance Monitor
public class LogPerformanceMonitor: ObservableObject {
    @Published var currentMemoryUsage: Int = 0
    @Published var logThroughput: Double = 0 // logs per second
    @Published var averageLogSize: Int = 0
    @Published var storageInfo: LogStorageInfo?
    @Published var performanceMetrics: LogPerformanceMetrics?
    
    private let logManager = LogManager.shared
    private var logCountTimer: Timer?
    private var lastLogCount = 0
    private var lastUpdateTime = Date()
    
    struct LogPerformanceMetrics {
        let logsPerSecond: Double
        let averageProcessingTime: TimeInterval
        let memoryUsage: Int
        let diskUsage: Int64
        let queueSize: Int
        let droppedLogs: Int
    }
    
    init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    private func startMonitoring() {
        logCountTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMetrics()
        }
    }
    
    private func stopMonitoring() {
        logCountTimer?.invalidate()
        logCountTimer = nil
    }
    
    private func updateMetrics() {
        // Update storage info
        storageInfo = logManager.getStorageInfo()
        
        // Calculate throughput
        let currentLogCount = storageInfo?.totalEntries ?? 0
        let currentTime = Date()
        let timeDelta = currentTime.timeIntervalSince(lastUpdateTime)
        
        if timeDelta > 0 {
            let logDelta = currentLogCount - lastLogCount
            logThroughput = Double(logDelta) / timeDelta
        }
        
        lastLogCount = currentLogCount
        lastUpdateTime = currentTime
        
        // Update memory usage (simplified)
        currentMemoryUsage = getCurrentMemoryUsage()
        
        // Calculate average log size
        if let storageInfo = storageInfo, storageInfo.totalEntries > 0 {
            averageLogSize = Int(storageInfo.totalSize) / storageInfo.totalEntries
        }
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
}

// MARK: - Log Health Monitor
public class LogHealthMonitor: ObservableObject {
    @Published var healthStatus: HealthStatus = .unknown
    @Published var healthScore: Double = 0.0
    @Published var healthIssues: [HealthIssue] = []
    @Published var recommendations: [String] = []
    
    private let logManager = LogManager.shared
    private var healthCheckTimer: Timer?
    
    enum HealthStatus {
        case healthy
        case warning
        case critical
        case unknown
        
        var color: String {
            switch self {
            case .healthy: return "green"
            case .warning: return "orange"
            case .critical: return "red"
            case .unknown: return "gray"
            }
        }
        
        var description: String {
            switch self {
            case .healthy: return "All systems operational"
            case .warning: return "Some issues detected"
            case .critical: return "Critical issues require attention"
            case .unknown: return "Status unknown"
            }
        }
    }
    
    struct HealthIssue {
        let id = UUID()
        let severity: Severity
        let category: String
        let description: String
        let recommendation: String?
        
        enum Severity {
            case info
            case warning
            case critical
        }
    }
    
    init() {
        startHealthMonitoring()
    }
    
    deinit {
        stopHealthMonitoring()
    }
    
    private func startHealthMonitoring() {
        // Initial health check
        performHealthCheck()
        
        // Schedule periodic health checks
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.performHealthCheck()
        }
    }
    
    private func stopHealthMonitoring() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }
    
    func performHealthCheck() {
        DispatchQueue.global(qos: .utility).async {
            let issues = self.analyzeLogHealth()
            let score = self.calculateHealthScore(issues: issues)
            let status = self.determineHealthStatus(score: score, issues: issues)
            let recs = self.generateHealthRecommendations(issues: issues)
            
            DispatchQueue.main.async {
                self.healthIssues = issues
                self.healthScore = score
                self.healthStatus = status
                self.recommendations = recs
            }
        }
    }
    
    private func analyzeLogHealth() -> [HealthIssue] {
        var issues: [HealthIssue] = []
        
        // Get recent logs for analysis
        let recentLogs = logManager.getLogs(filter: LogFilter(
            since: Date().addingTimeInterval(-3600), // Last hour
            limit: 1000
        ))
        
        // Check error rate
        let errorLogs = recentLogs.filter { $0.level >= .error }
        let errorRate = Double(errorLogs.count) / Double(max(recentLogs.count, 1))
        
        if errorRate > 0.1 { // More than 10% errors
            issues.append(HealthIssue(
                severity: .critical,
                category: "Error Rate",
                description: "High error rate detected: \(Int(errorRate * 100))%",
                recommendation: "Review error patterns and implement fixes"
            ))
        } else if errorRate > 0.05 { // More than 5% errors
            issues.append(HealthIssue(
                severity: .warning,
                category: "Error Rate",
                description: "Elevated error rate: \(Int(errorRate * 100))%",
                recommendation: "Monitor error trends and investigate common issues"
            ))
        }
        
        // Check storage health
        if let storageInfo = logManager.getStorageInfo() {
            let storageMB = storageInfo.totalSizeMB
            
            if storageMB > 100 { // More than 100MB
                issues.append(HealthIssue(
                    severity: .warning,
                    category: "Storage",
                    description: "Log storage usage is high: \(Int(storageMB))MB",
                    recommendation: "Consider adjusting log retention policies"
                ))
            }
            
            if storageInfo.totalFiles > 50 {
                issues.append(HealthIssue(
                    severity: .info,
                    category: "Storage",
                    description: "Many log files present: \(storageInfo.totalFiles)",
                    recommendation: "Log rotation is working, but consider more frequent cleanup"
                ))
            }
        }
        
        // Check for memory-related logs
        let memoryLogs = recentLogs.filter { $0.message.lowercased().contains("memory") }
        if memoryLogs.count > 5 {
            issues.append(HealthIssue(
                severity: .warning,
                category: "Memory",
                description: "\(memoryLogs.count) memory-related log entries",
                recommendation: "Monitor memory usage and optimize if necessary"
            ))
        }
        
        // Check for crash reports
        let crashReports = CrashReporter.shared.getCrashReports()
        let recentCrashes = crashReports.filter { 
            $0.timestamp > Date().addingTimeInterval(-24 * 3600) // Last 24 hours
        }
        
        if !recentCrashes.isEmpty {
            issues.append(HealthIssue(
                severity: .critical,
                category: "Crashes",
                description: "\(recentCrashes.count) crash(es) in the last 24 hours",
                recommendation: "Review and address crash reports immediately"
            ))
        }
        
        // Check log volume trends
        if recentLogs.count > 500 { // High volume
            issues.append(HealthIssue(
                severity: .info,
                category: "Volume",
                description: "High log volume: \(recentLogs.count) logs in the last hour",
                recommendation: "Consider implementing log sampling for non-critical categories"
            ))
        }
        
        return issues
    }
    
    private func calculateHealthScore(issues: [HealthIssue]) -> Double {
        var score = 100.0
        
        for issue in issues {
            switch issue.severity {
            case .critical:
                score -= 25.0
            case .warning:
                score -= 10.0
            case .info:
                score -= 2.0
            }
        }
        
        return max(0.0, min(100.0, score))
    }
    
    private func determineHealthStatus(score: Double, issues: [HealthIssue]) -> HealthStatus {
        let hasCriticalIssues = issues.contains { $0.severity == .critical }
        
        if hasCriticalIssues || score < 50 {
            return .critical
        } else if score < 80 {
            return .warning
        } else {
            return .healthy
        }
    }
    
    private func generateHealthRecommendations(issues: [HealthIssue]) -> [String] {
        var recommendations: [String] = []
        
        // Add specific recommendations based on issues
        for issue in issues {
            if let recommendation = issue.recommendation {
                recommendations.append(recommendation)
            }
        }
        
        // Add general recommendations
        if issues.isEmpty {
            recommendations.append("Logging system is healthy. Continue monitoring.")
        } else {
            recommendations.append("Address the identified issues to improve system health.")
            recommendations.append("Regular monitoring helps prevent issues from becoming critical.")
        }
        
        return Array(Set(recommendations)) // Remove duplicates
    }
}

// MARK: - Real-time Log Observer
public class RealTimeLogObserver: ObservableObject, LogObserver {
    @Published var recentLogs: [LogEntry] = []
    @Published var isEnabled = false
    
    private let maxRecentLogs = 100
    private let logManager = LogManager.shared
    
    init() {
        logManager.addObserver(self)
    }
    
    deinit {
        logManager.removeObserver(self)
    }
    
    func enable() {
        isEnabled = true
    }
    
    func disable() {
        isEnabled = false
        recentLogs.removeAll()
    }
    
    func clearRecentLogs() {
        recentLogs.removeAll()
    }
    
    // MARK: - LogObserver
    
    public func logEvent(_ event: LogEvent) {
        guard isEnabled else { return }
        
        DispatchQueue.main.async {
            switch event {
            case .logAdded(let logEntry):
                self.recentLogs.append(logEntry)
                
                // Maintain size limit
                if self.recentLogs.count > self.maxRecentLogs {
                    self.recentLogs.removeFirst(self.recentLogs.count - self.maxRecentLogs)
                }
                
            case .logsCleared:
                self.recentLogs.removeAll()
                
            default:
                break
            }
        }
    }
}