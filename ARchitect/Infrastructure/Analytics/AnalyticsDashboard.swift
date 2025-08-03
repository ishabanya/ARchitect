import SwiftUI
import Charts
import Combine

// MARK: - Dashboard Data Models
struct DashboardMetrics {
    let sessionMetrics: SessionMetrics
    let engagementMetrics: EngagementMetrics
    let performanceMetrics: PerformanceMetrics
    let featureUsageMetrics: FeatureUsageMetrics
    let errorMetrics: ErrorMetrics
    let abTestMetrics: ABTestMetrics
}

struct SessionMetrics {
    let activeUsers: Int
    let totalSessions: Int
    let averageSessionDuration: TimeInterval
    let sessionsByHour: [HourlyData]
    let topScreens: [ScreenData]
    let retentionRate: Double
}

struct EngagementMetrics {
    let dailyActiveUsers: Int
    let weeklyActiveUsers: Int
    let monthlyActiveUsers: Int
    let userInteractions: [InteractionData]
    let screenViews: [ScreenViewData]
    let engagementScore: Double
}

struct PerformanceMetrics {
    let averageFPS: Double
    let memoryUsage: Double
    let batteryImpact: Double
    let crashRate: Double
    let errorRate: Double
    let loadTimes: [LoadTimeData]
    let thermalEvents: [ThermalData]
}

struct FeatureUsageMetrics {
    let arUsage: FeatureUsage
    let scanningUsage: FeatureUsage
    let placementUsage: FeatureUsage
    let collaborationUsage: FeatureUsage
    let aiOptimizationUsage: FeatureUsage
    let topFeatures: [FeatureData]
}

struct ErrorMetrics {
    let totalErrors: Int
    let criticalErrors: Int
    let errorsByCategory: [ErrorCategoryData]
    let errorTrends: [ErrorTrendData]
    let topErrors: [ErrorData]
}

struct ABTestMetrics {
    let activeTests: [ABTestData]
    let conversionRates: [ConversionData]
    let significantResults: [ABTestResult]
}

// Supporting data structures
struct HourlyData: Identifiable {
    let id = UUID()
    let hour: Int
    let count: Int
}

struct ScreenData: Identifiable {
    let id = UUID()
    let screenName: String
    let viewCount: Int
    let averageTime: TimeInterval
}

struct InteractionData: Identifiable {
    let id = UUID()
    let timestamp: Date
    let interactionType: String
    let count: Int
}

struct ScreenViewData: Identifiable {
    let id = UUID()
    let screenName: String
    let viewCount: Int
    let averageTime: TimeInterval
    let bounceRate: Double
}

struct LoadTimeData: Identifiable {
    let id = UUID()
    let feature: String
    let averageLoadTime: Double
    let p95LoadTime: Double
}

struct ThermalData: Identifiable {
    let id = UUID()
    let timestamp: Date
    let thermalState: String
    let duration: TimeInterval
}

struct FeatureUsage: Identifiable {
    let id = UUID()
    let featureName: String
    let usageCount: Int
    let uniqueUsers: Int
    let averageUsageTime: TimeInterval
    let completionRate: Double
}

struct FeatureData: Identifiable {
    let id = UUID()
    let featureName: String
    let usageCount: Int
    let trend: Double // positive for growth, negative for decline
}

struct ErrorCategoryData: Identifiable {
    let id = UUID()
    let category: String
    let count: Int
    let severity: String
}

struct ErrorTrendData: Identifiable {
    let id = UUID()
    let timestamp: Date
    let errorCount: Int
}

struct ErrorData: Identifiable {
    let id = UUID()
    let errorCode: String
    let count: Int
    let lastOccurrence: Date
    let severity: String
}

struct ABTestData: Identifiable {
    let id = UUID()
    let testName: String
    let variants: [String]
    let participants: Int
    let status: String
}

struct ConversionData: Identifiable {
    let id = UUID()
    let testName: String
    let variant: String
    let conversionRate: Double
    let confidence: Double
}

struct ABTestResult: Identifiable {
    let id = UUID()
    let testName: String
    let winningVariant: String
    let improvement: Double
    let significance: Double
}

// MARK: - Dashboard ViewModel
@MainActor
class AnalyticsDashboardViewModel: ObservableObject {
    @Published var metrics: DashboardMetrics?
    @Published var isLoading = true
    @Published var selectedTimeRange = TimeRange.last24Hours
    @Published var refreshInterval: TimeInterval = 30.0
    @Published var autoRefreshEnabled = true
    
    private let analyticsManager = AnalyticsManager.shared
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    enum TimeRange: CaseIterable {
        case last1Hour
        case last24Hours
        case last7Days
        case last30Days
        
        var displayName: String {
            switch self {
            case .last1Hour: return "Last Hour"
            case .last24Hours: return "Last 24 Hours"
            case .last7Days: return "Last 7 Days"
            case .last30Days: return "Last 30 Days"
            }
        }
        
        var timeInterval: TimeInterval {
            switch self {
            case .last1Hour: return 3600
            case .last24Hours: return 86400
            case .last7Days: return 604800
            case .last30Days: return 2592000
            }
        }
    }
    
    init() {
        startAutoRefresh()
        loadMetrics()
    }
    
    deinit {
        stopAutoRefresh()
    }
    
    func loadMetrics() {
        isLoading = true
        
        Task {
            do {
                let dashboardMetrics = try await generateDashboardMetrics()
                await MainActor.run {
                    self.metrics = dashboardMetrics
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
                print("Failed to load dashboard metrics: \(error)")
            }
        }
    }
    
    func refreshMetrics() {
        loadMetrics()
    }
    
    func startAutoRefresh() {
        guard autoRefreshEnabled else { return }
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.loadMetrics()
        }
    }
    
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    func updateTimeRange(_ timeRange: TimeRange) {
        selectedTimeRange = timeRange
        loadMetrics()
    }
    
    func toggleAutoRefresh() {
        autoRefreshEnabled.toggle()
        
        if autoRefreshEnabled {
            startAutoRefresh()
        } else {
            stopAutoRefresh()
        }
    }
    
    func exportDashboardData() -> Data? {
        guard let metrics = metrics else { return nil }
        
        let exportData: [String: Any] = [
            "export_timestamp": Date().timeIntervalSince1970,
            "time_range": selectedTimeRange.displayName,
            "session_metrics": [
                "active_users": metrics.sessionMetrics.activeUsers,
                "total_sessions": metrics.sessionMetrics.totalSessions,
                "average_session_duration": metrics.sessionMetrics.averageSessionDuration,
                "retention_rate": metrics.sessionMetrics.retentionRate
            ],
            "engagement_metrics": [
                "daily_active_users": metrics.engagementMetrics.dailyActiveUsers,
                "weekly_active_users": metrics.engagementMetrics.weeklyActiveUsers,
                "monthly_active_users": metrics.engagementMetrics.monthlyActiveUsers,
                "engagement_score": metrics.engagementMetrics.engagementScore
            ],
            "performance_metrics": [
                "average_fps": metrics.performanceMetrics.averageFPS,
                "memory_usage": metrics.performanceMetrics.memoryUsage,
                "battery_impact": metrics.performanceMetrics.batteryImpact,
                "crash_rate": metrics.performanceMetrics.crashRate,
                "error_rate": metrics.performanceMetrics.errorRate
            ],
            "error_metrics": [
                "total_errors": metrics.errorMetrics.totalErrors,
                "critical_errors": metrics.errorMetrics.criticalErrors
            ]
        ]
        
        return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }
    
    private func generateDashboardMetrics() async throws -> DashboardMetrics {
        let since = Date().addingTimeInterval(-selectedTimeRange.timeInterval)
        
        // This would typically fetch from analytics storage
        // For now, generating sample data
        
        let sessionMetrics = SessionMetrics(
            activeUsers: Int.random(in: 50...500),
            totalSessions: Int.random(in: 100...1000),
            averageSessionDuration: TimeInterval.random(in: 120...600),
            sessionsByHour: generateHourlyData(),
            topScreens: generateTopScreens(),
            retentionRate: Double.random(in: 0.6...0.9)
        )
        
        let engagementMetrics = EngagementMetrics(
            dailyActiveUsers: Int.random(in: 100...800),
            weeklyActiveUsers: Int.random(in: 500...2000),
            monthlyActiveUsers: Int.random(in: 1000...5000),
            userInteractions: generateInteractionData(),
            screenViews: generateScreenViewData(),
            engagementScore: Double.random(in: 0.7...0.95)
        )
        
        let performanceMetrics = PerformanceMetrics(
            averageFPS: Double.random(in: 45...60),
            memoryUsage: Double.random(in: 200...800),
            batteryImpact: Double.random(in: 0.1...0.3),
            crashRate: Double.random(in: 0.001...0.01),
            errorRate: Double.random(in: 0.01...0.05),
            loadTimes: generateLoadTimeData(),
            thermalEvents: generateThermalData()
        )
        
        let featureUsageMetrics = FeatureUsageMetrics(
            arUsage: generateFeatureUsage("AR Session"),
            scanningUsage: generateFeatureUsage("Room Scanning"),
            placementUsage: generateFeatureUsage("Furniture Placement"),
            collaborationUsage: generateFeatureUsage("Collaboration"),
            aiOptimizationUsage: generateFeatureUsage("AI Optimization"),
            topFeatures: generateTopFeatures()
        )
        
        let errorMetrics = ErrorMetrics(
            totalErrors: Int.random(in: 10...100),
            criticalErrors: Int.random(in: 0...5),
            errorsByCategory: generateErrorCategoryData(),
            errorTrends: generateErrorTrendData(),
            topErrors: generateTopErrors()
        )
        
        let abTestMetrics = ABTestMetrics(
            activeTests: generateABTestData(),
            conversionRates: generateConversionData(),
            significantResults: generateABTestResults()
        )
        
        return DashboardMetrics(
            sessionMetrics: sessionMetrics,
            engagementMetrics: engagementMetrics,
            performanceMetrics: performanceMetrics,
            featureUsageMetrics: featureUsageMetrics,
            errorMetrics: errorMetrics,
            abTestMetrics: abTestMetrics
        )
    }
    
    // Sample data generation methods
    private func generateHourlyData() -> [HourlyData] {
        (0..<24).map { hour in
            HourlyData(hour: hour, count: Int.random(in: 5...50))
        }
    }
    
    private func generateTopScreens() -> [ScreenData] {
        let screens = ["AR View", "Room Scanning", "Furniture Catalog", "Settings", "Measurements"]
        return screens.map { screen in
            ScreenData(
                screenName: screen,
                viewCount: Int.random(in: 10...200),
                averageTime: TimeInterval.random(in: 30...300)
            )
        }
    }
    
    private func generateInteractionData() -> [InteractionData] {
        let interactions = ["tap", "swipe", "pinch", "rotation", "long_press"]
        return interactions.map { interaction in
            InteractionData(
                timestamp: Date().addingTimeInterval(-TimeInterval.random(in: 0...86400)),
                interactionType: interaction,
                count: Int.random(in: 10...100)
            )
        }
    }
    
    private func generateScreenViewData() -> [ScreenViewData] {
        let screens = ["AR View", "Room Scanning", "Furniture Catalog", "Settings", "Profile"]
        return screens.map { screen in
            ScreenViewData(
                screenName: screen,
                viewCount: Int.random(in: 20...300),
                averageTime: TimeInterval.random(in: 60...400),
                bounceRate: Double.random(in: 0.1...0.4)
            )
        }
    }
    
    private func generateLoadTimeData() -> [LoadTimeData] {
        let features = ["AR Initialization", "Model Loading", "Scan Processing", "Collaboration Sync"]
        return features.map { feature in
            LoadTimeData(
                feature: feature,
                averageLoadTime: Double.random(in: 0.5...3.0),
                p95LoadTime: Double.random(in: 2.0...8.0)
            )
        }
    }
    
    private func generateThermalData() -> [ThermalData] {
        let states = ["nominal", "fair", "serious", "critical"]
        return states.map { state in
            ThermalData(
                timestamp: Date().addingTimeInterval(-TimeInterval.random(in: 0...86400)),
                thermalState: state,
                duration: TimeInterval.random(in: 60...1800)
            )
        }
    }
    
    private func generateFeatureUsage(_ featureName: String) -> FeatureUsage {
        FeatureUsage(
            featureName: featureName,
            usageCount: Int.random(in: 50...500),
            uniqueUsers: Int.random(in: 20...200),
            averageUsageTime: TimeInterval.random(in: 120...900),
            completionRate: Double.random(in: 0.6...0.95)
        )
    }
    
    private func generateTopFeatures() -> [FeatureData] {
        let features = ["AR Session", "Room Scanning", "Furniture Placement", "Measurements", "Share"]
        return features.map { feature in
            FeatureData(
                featureName: feature,
                usageCount: Int.random(in: 20...200),
                trend: Double.random(in: -0.2...0.3)
            )
        }
    }
    
    private func generateErrorCategoryData() -> [ErrorCategoryData] {
        let categories = ["AR", "Network", "Storage", "UI", "System"]
        let severities = ["low", "medium", "high", "critical"]
        return categories.map { category in
            ErrorCategoryData(
                category: category,
                count: Int.random(in: 1...20),
                severity: severities.randomElement()!
            )
        }
    }
    
    private func generateErrorTrendData() -> [ErrorTrendData] {
        let now = Date()
        return (0..<24).map { hour in
            ErrorTrendData(
                timestamp: now.addingTimeInterval(-TimeInterval(hour * 3600)),
                errorCount: Int.random(in: 0...10)
            )
        }
    }
    
    private func generateTopErrors() -> [ErrorData] {
        let errors = ["AR_INIT_FAILED", "MODEL_LOAD_ERROR", "NETWORK_TIMEOUT", "STORAGE_FULL", "PERMISSION_DENIED"]
        let severities = ["medium", "high", "critical"]
        return errors.map { error in
            ErrorData(
                errorCode: error,
                count: Int.random(in: 1...15),
                lastOccurrence: Date().addingTimeInterval(-TimeInterval.random(in: 0...86400)),
                severity: severities.randomElement()!
            )
        }
    }
    
    private func generateABTestData() -> [ABTestData] {
        let tests = ["New Onboarding Flow", "AR Controls Layout", "Furniture Catalog Design", "Tutorial Sequence"]
        return tests.map { test in
            ABTestData(
                testName: test,
                variants: ["A", "B"],
                participants: Int.random(in: 100...1000),
                status: ["running", "completed", "paused"].randomElement()!
            )
        }
    }
    
    private func generateConversionData() -> [ConversionData] {
        let tests = ["New Onboarding Flow", "AR Controls Layout"]
        var data: [ConversionData] = []
        
        for test in tests {
            for variant in ["A", "B"] {
                data.append(ConversionData(
                    testName: test,
                    variant: variant,
                    conversionRate: Double.random(in: 0.1...0.4),
                    confidence: Double.random(in: 0.8...0.99)
                ))
            }
        }
        
        return data
    }
    
    private func generateABTestResults() -> [ABTestResult] {
        [
            ABTestResult(
                testName: "New Onboarding Flow",
                winningVariant: "B",
                improvement: 0.15,
                significance: 0.95
            ),
            ABTestResult(
                testName: "AR Controls Layout",
                winningVariant: "A",
                improvement: 0.08,
                significance: 0.92
            )
        ]
    }
}

// MARK: - Dashboard Views
struct AnalyticsDashboardView: View {
    @StateObject private var viewModel = AnalyticsDashboardViewModel()
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack {
                // Header with controls
                HStack {
                    Picker("Time Range", selection: $viewModel.selectedTimeRange) {
                        ForEach(AnalyticsDashboardViewModel.TimeRange.allCases, id: \.self) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    Spacer()
                    
                    Button(action: viewModel.refreshMetrics) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                    
                    Button(action: viewModel.toggleAutoRefresh) {
                        Image(systemName: viewModel.autoRefreshEnabled ? "pause.circle" : "play.circle")
                    }
                }
                .padding()
                
                if viewModel.isLoading {
                    ProgressView("Loading Analytics...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let metrics = viewModel.metrics {
                    TabView(selection: $selectedTab) {
                        OverviewTab(metrics: metrics)
                            .tabItem {
                                Image(systemName: "chart.bar")
                                Text("Overview")
                            }
                            .tag(0)
                        
                        UserEngagementTab(metrics: metrics.engagementMetrics)
                            .tabItem {
                                Image(systemName: "person.2")
                                Text("Engagement")
                            }
                            .tag(1)
                        
                        PerformanceTab(metrics: metrics.performanceMetrics)
                            .tabItem {
                                Image(systemName: "speedometer")
                                Text("Performance")
                            }
                            .tag(2)
                        
                        FeatureUsageTab(metrics: metrics.featureUsageMetrics)
                            .tabItem {
                                Image(systemName: "app.gift")
                                Text("Features")
                            }
                            .tag(3)
                        
                        ErrorsTab(metrics: metrics.errorMetrics)
                            .tabItem {
                                Image(systemName: "exclamationmark.triangle")
                                Text("Errors")
                            }
                            .tag(4)
                        
                        ABTestingTab(metrics: metrics.abTestMetrics)
                            .tabItem {
                                Image(systemName: "flask")
                                Text("A/B Tests")
                            }
                            .tag(5)
                    }
                } else {
                    Text("No data available")
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Analytics Dashboard")
            .onChange(of: viewModel.selectedTimeRange) { newRange in
                viewModel.updateTimeRange(newRange)
            }
        }
    }
}

// MARK: - Tab Views
struct OverviewTab: View {
    let metrics: DashboardMetrics
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                MetricCard(
                    title: "Active Users",
                    value: "\(metrics.sessionMetrics.activeUsers)",
                    trend: nil,
                    color: .blue
                )
                
                MetricCard(
                    title: "Total Sessions",
                    value: "\(metrics.sessionMetrics.totalSessions)",
                    trend: nil,
                    color: .green
                )
                
                MetricCard(
                    title: "Avg Session Duration",
                    value: formatDuration(metrics.sessionMetrics.averageSessionDuration),
                    trend: nil,
                    color: .orange
                )
                
                MetricCard(
                    title: "Retention Rate",
                    value: "\(Int(metrics.sessionMetrics.retentionRate * 100))%",
                    trend: nil,
                    color: .purple
                )
                
                MetricCard(
                    title: "Error Rate",
                    value: String(format: "%.2f%%", metrics.performanceMetrics.errorRate * 100),
                    trend: nil,
                    color: metrics.performanceMetrics.errorRate > 0.03 ? .red : .green
                )
                
                MetricCard(
                    title: "Average FPS",
                    value: String(format: "%.1f", metrics.performanceMetrics.averageFPS),
                    trend: nil,
                    color: metrics.performanceMetrics.averageFPS < 45 ? .red : .green
                )
            }
            .padding()
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(seconds)s"
    }
}

struct UserEngagementTab: View {
    let metrics: EngagementMetrics
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    MetricCard(
                        title: "DAU",
                        value: "\(metrics.dailyActiveUsers)",
                        trend: nil,
                        color: .blue
                    )
                    
                    MetricCard(
                        title: "WAU",
                        value: "\(metrics.weeklyActiveUsers)",
                        trend: nil,
                        color: .green
                    )
                    
                    MetricCard(
                        title: "MAU",
                        value: "\(metrics.monthlyActiveUsers)",
                        trend: nil,
                        color: .orange
                    )
                }
                
                VStack(alignment: .leading) {
                    Text("Top Screens")
                        .font(.headline)
                        .padding(.leading)
                    
                    ForEach(metrics.screenViews.prefix(5)) { screen in
                        HStack {
                            Text(screen.screenName)
                            Spacer()
                            Text("\(screen.viewCount) views")
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 2)
            }
            .padding()
        }
    }
}

struct PerformanceTab: View {
    let metrics: PerformanceMetrics
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    MetricCard(
                        title: "Average FPS",
                        value: String(format: "%.1f", metrics.averageFPS),
                        trend: nil,
                        color: metrics.averageFPS < 45 ? .red : .green
                    )
                    
                    MetricCard(
                        title: "Memory Usage",
                        value: "\(Int(metrics.memoryUsage))MB",
                        trend: nil,
                        color: metrics.memoryUsage > 500 ? .red : .green
                    )
                    
                    MetricCard(
                        title: "Crash Rate",
                        value: String(format: "%.3f%%", metrics.crashRate * 100),
                        trend: nil,
                        color: metrics.crashRate > 0.005 ? .red : .green
                    )
                    
                    MetricCard(
                        title: "Battery Impact",
                        value: String(format: "%.1f%%", metrics.batteryImpact * 100),
                        trend: nil,
                        color: metrics.batteryImpact > 0.2 ? .orange : .green
                    )
                }
                
                VStack(alignment: .leading) {
                    Text("Load Times")
                        .font(.headline)
                        .padding(.leading)
                    
                    ForEach(metrics.loadTimes) { loadTime in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(loadTime.feature)
                                Spacer()
                                Text(String(format: "%.2fs avg", loadTime.averageLoadTime))
                                    .foregroundColor(.secondary)
                            }
                            
                            ProgressView(value: loadTime.averageLoadTime, total: 5.0)
                                .tint(loadTime.averageLoadTime > 3.0 ? .red : .green)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 2)
            }
            .padding()
        }
    }
}

struct FeatureUsageTab: View {
    let metrics: FeatureUsageMetrics
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Feature Usage")
                        .font(.headline)
                        .padding(.leading)
                    
                    ForEach([
                        metrics.arUsage,
                        metrics.scanningUsage,
                        metrics.placementUsage,
                        metrics.collaborationUsage,
                        metrics.aiOptimizationUsage
                    ]) { feature in
                        FeatureUsageRow(feature: feature)
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 2)
                
                VStack(alignment: .leading) {
                    Text("Trending Features")
                        .font(.headline)
                        .padding(.leading)
                    
                    ForEach(metrics.topFeatures) { feature in
                        HStack {
                            Text(feature.featureName)
                            Spacer()
                            HStack {
                                Text("\(feature.usageCount)")
                                    .foregroundColor(.secondary)
                                Image(systemName: feature.trend > 0 ? "arrow.up" : "arrow.down")
                                    .foregroundColor(feature.trend > 0 ? .green : .red)
                                Text(String(format: "%.1f%%", abs(feature.trend * 100)))
                                    .font(.caption)
                                    .foregroundColor(feature.trend > 0 ? .green : .red)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 2)
            }
            .padding()
        }
    }
}

struct ErrorsTab: View {
    let metrics: ErrorMetrics
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    MetricCard(
                        title: "Total Errors",
                        value: "\(metrics.totalErrors)",
                        trend: nil,
                        color: .orange
                    )
                    
                    MetricCard(
                        title: "Critical Errors",
                        value: "\(metrics.criticalErrors)",
                        trend: nil,
                        color: .red
                    )
                }
                
                VStack(alignment: .leading) {
                    Text("Top Errors")
                        .font(.headline)
                        .padding(.leading)
                    
                    ForEach(metrics.topErrors.prefix(10)) { error in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(error.errorCode)
                                    .font(.subheadline)
                                Text("Last: \(formatDate(error.lastOccurrence))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(error.count)")
                                    .font(.headline)
                                Text(error.severity.uppercased())
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(severityColor(error.severity))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 2)
            }
            .padding()
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "critical": return .red
        case "high": return .orange
        case "medium": return .yellow
        default: return .blue
        }
    }
}

struct ABTestingTab: View {
    let metrics: ABTestMetrics
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Active Tests")
                        .font(.headline)
                        .padding(.leading)
                    
                    ForEach(metrics.activeTests) { test in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(test.testName)
                                    .font(.subheadline)
                                Spacer()
                                Text(test.status.uppercased())
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(statusColor(test.status))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                            
                            Text("\(test.participants) participants")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Variants: \(test.variants.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 2)
                
                VStack(alignment: .leading) {
                    Text("Significant Results")
                        .font(.headline)
                        .padding(.leading)
                    
                    ForEach(metrics.significantResults) { result in
                        VStack(alignment: .leading) {
                            Text(result.testName)
                                .font(.subheadline)
                            HStack {
                                Text("Winner: \(result.winningVariant)")
                                    .foregroundColor(.green)
                                Spacer()
                                Text("+\(Int(result.improvement * 100))%")
                                    .foregroundColor(.green)
                                    .font(.headline)
                            }
                            Text("\(Int(result.significance * 100))% confidence")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 2)
            }
            .padding()
        }
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "running": return .green
        case "completed": return .blue
        case "paused": return .orange
        default: return .gray
        }
    }
}

// MARK: - Supporting Views
struct MetricCard: View {
    let title: String
    let value: String
    let trend: Double?
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                
                if let trend = trend {
                    Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                        .foregroundColor(trend > 0 ? .green : .red)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct FeatureUsageRow: View {
    let feature: FeatureUsage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(feature.featureName)
                    .font(.subheadline)
                Spacer()
                Text("\(feature.usageCount) uses")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("\(feature.uniqueUsers) users")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(feature.completionRate * 100))% completion")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: feature.completionRate)
                .tint(.blue)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}