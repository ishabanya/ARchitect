import SwiftUI
import Combine
import Charts

// MARK: - Monitoring Dashboard View
struct MonitoringDashboard: View {
    @StateObject private var viewModel = MonitoringDashboardViewModel()
    @State private var selectedTimeRange: TimeRange = .lastHour
    @State private var selectedMetricCategory: MetricCategory = .performance
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Time Range Selector
                timeRangeSelector
                
                // Metric Category Selector
                metricCategorySelector
                
                // Dashboard Content
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Real-time Status Card
                        realTimeStatusCard
                        
                        // Key Metrics Cards
                        keyMetricsGrid
                        
                        // Charts Section
                        chartsSection
                        
                        // Alerts Section
                        alertsSection
                        
                        // Recent Events
                        recentEventsSection
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Monitoring Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                viewModel.loadDashboardData(timeRange: selectedTimeRange)
            }
            .onChange(of: selectedTimeRange) { range in
                viewModel.loadDashboardData(timeRange: range)
            }
            .onChange(of: selectedMetricCategory) { category in
                viewModel.updateMetricCategory(category)
            }
        }
    }
    
    private var timeRangeSelector: some View {
        Picker("Time Range", selection: $selectedTimeRange) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Text(range.displayName).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
    
    private var metricCategorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(MetricCategory.allCases, id: \.self) { category in
                    Button(action: {
                        selectedMetricCategory = category
                    }) {
                        Text(category.displayName)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(selectedMetricCategory == category ? Color.blue : Color.gray.opacity(0.2))
                            )
                            .foregroundColor(selectedMetricCategory == category ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var realTimeStatusCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundColor(.green)
                    Text("Real-time Status")
                        .font(.headline)
                    Spacer()
                    Text("Live")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .rounded()
                }
                
                HStack(spacing: 20) {
                    StatusIndicator(
                        title: "Active Users",
                        value: "\(viewModel.realTimeMetrics.activeUsers)",
                        trend: .stable
                    )
                    
                    StatusIndicator(
                        title: "AR Sessions",
                        value: "\(viewModel.realTimeMetrics.activeSessions)",
                        trend: .up
                    )
                    
                    StatusIndicator(
                        title: "Avg FPS",
                        value: String(format: "%.1f", viewModel.realTimeMetrics.averageFPS),
                        trend: viewModel.realTimeMetrics.averageFPS > 45 ? .up : .down
                    )
                }
            }
        }
    }
    
    private var keyMetricsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
            ForEach(viewModel.keyMetrics, id: \.id) { metric in
                MetricCard(metric: metric)
            }
        }
    }
    
    private var chartsSection: some View {
        VStack(spacing: 16) {
            // Performance Chart
            if selectedMetricCategory == .performance {
                performanceChart
            }
            
            // User Engagement Chart
            if selectedMetricCategory == .engagement {
                engagementChart
            }
            
            // Error Rate Chart
            if selectedMetricCategory == .errors {
                errorChart
            }
        }
    }
    
    private var performanceChart: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Performance Metrics")
                    .font(.headline)
                
                if #available(iOS 16.0, *) {
                    Chart(viewModel.performanceData) { data in
                        LineMark(
                            x: .value("Time", data.timestamp),
                            y: .value("FPS", data.fps)
                        )
                        .foregroundStyle(.blue)
                        
                        LineMark(
                            x: .value("Time", data.timestamp),
                            y: .value("Memory", data.memoryUsageMB)
                        )
                        .foregroundStyle(.red)
                    }
                    .frame(height: 200)
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                }
            }
        }
    }
    
    private var engagementChart: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("User Engagement")
                    .font(.headline)
                
                if #available(iOS 16.0, *) {
                    Chart(viewModel.engagementData) { data in
                        BarMark(
                            x: .value("Hour", data.hour),
                            y: .value("Sessions", data.sessionCount)
                        )
                        .foregroundStyle(.green)
                    }
                    .frame(height: 200)
                }
            }
        }
    }
    
    private var errorChart: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Error Rate")
                    .font(.headline)
                
                if #available(iOS 16.0, *) {
                    Chart(viewModel.errorData) { data in
                        LineMark(
                            x: .value("Time", data.timestamp),
                            y: .value("Error Rate", data.errorRate)
                        )
                        .foregroundStyle(.red)
                    }
                    .frame(height: 200)
                }
            }
        }
    }
    
    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.activeAlerts.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Active Alerts (\(viewModel.activeAlerts.count))")
                                .font(.headline)
                        }
                        
                        ForEach(viewModel.activeAlerts, id: \.id) { alert in
                            AlertRow(alert: alert)
                        }
                    }
                }
            }
        }
    }
    
    private var recentEventsSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Events")
                    .font(.headline)
                
                ForEach(viewModel.recentEvents.prefix(5), id: \.id) { event in
                    EventRow(event: event)
                }
                
                if viewModel.recentEvents.count > 5 {
                    Button("View All Events") {
                        // Navigate to full events view
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }
}

// MARK: - Supporting Views
struct Card<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct StatusIndicator: View {
    let title: String
    let value: String
    let trend: Trend
    
    enum Trend {
        case up, down, stable
        
        var color: Color {
            switch self {
            case .up: return .green
            case .down: return .red
            case .stable: return .gray
            }
        }
        
        var icon: String {
            switch self {
            case .up: return "arrow.up"
            case .down: return "arrow.down"
            case .stable: return "minus"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Image(systemName: trend.icon)
                    .font(.caption)
                    .foregroundColor(trend.color)
            }
        }
    }
}

struct MetricCard: View {
    let metric: KeyMetric
    
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: metric.icon)
                        .foregroundColor(metric.color)
                    Text(metric.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                Text(metric.value)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                HStack {
                    Text(metric.subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(metric.changePercentage)
                        .font(.caption2)
                        .foregroundColor(metric.changeColor)
                }
            }
        }
    }
}

struct AlertRow: View {
    let alert: MonitoringAlert
    
    var body: some View {
        HStack {
            Image(systemName: alert.severity.icon)
                .foregroundColor(alert.severity.color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(alert.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(alert.timestamp.formatted(.relative(presentation: .abbreviated)))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct EventRow: View {
    let event: MonitoringEvent
    
    var body: some View {
        HStack {
            Circle()
                .fill(event.severity.color)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(.subheadline)
                
                Text(event.type)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(event.timestamp.formatted(.relative(presentation: .abbreviated)))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - View Model
@MainActor
class MonitoringDashboardViewModel: ObservableObject {
    @Published var realTimeMetrics = RealTimeMetrics()
    @Published var keyMetrics: [KeyMetric] = []
    @Published var performanceData: [PerformanceDataPoint] = []
    @Published var engagementData: [EngagementDataPoint] = []
    @Published var errorData: [ErrorDataPoint] = []
    @Published var activeAlerts: [MonitoringAlert] = []
    @Published var recentEvents: [MonitoringEvent] = []
    
    private let analyticsManager = AnalyticsManager.shared
    private var updateTimer: Timer?
    
    init() {
        startRealTimeUpdates()
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    func loadDashboardData(timeRange: TimeRange) {
        Task {
            await loadMetrics(for: timeRange)
            await loadChartData(for: timeRange)
            await loadAlerts()
            await loadRecentEvents()
        }
    }
    
    func updateMetricCategory(_ category: MetricCategory) {
        // Filter metrics based on category
        Task {
            await loadMetrics(for: .lastHour, category: category)
        }
    }
    
    private func startRealTimeUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateRealTimeMetrics()
            }
        }
    }
    
    private func updateRealTimeMetrics() async {
        let metrics = analyticsManager.getRealtimeMetrics()
        
        realTimeMetrics = RealTimeMetrics(
            activeUsers: metrics["active_users"] as? Int ?? 0,
            activeSessions: metrics["active_sessions"] as? Int ?? 0,
            averageFPS: metrics["average_fps"] as? Double ?? 0.0
        )
    }
    
    private func loadMetrics(for timeRange: TimeRange, category: MetricCategory = .performance) async {
        // Generate sample key metrics based on category
        keyMetrics = generateKeyMetrics(for: category)
    }
    
    private func loadChartData(for timeRange: TimeRange) async {
        // Generate sample chart data
        performanceData = generatePerformanceData(for: timeRange)
        engagementData = generateEngagementData(for: timeRange)
        errorData = generateErrorData(for: timeRange)
    }
    
    private func loadAlerts() async {
        // Load active alerts
        activeAlerts = generateSampleAlerts()
    }
    
    private func loadRecentEvents() async {
        // Load recent events from analytics
        let analyticsEvents = analyticsManager.getRealtimeMetrics()["recent_events"] as? [[String: Any]] ?? []
        
        recentEvents = analyticsEvents.compactMap { eventData in
            guard let name = eventData["name"] as? String,
                  let type = eventData["type"] as? String,
                  let timestamp = eventData["timestamp"] as? TimeInterval,
                  let severityString = eventData["severity"] as? String else {
                return nil
            }
            
            let severity = EventSeverity(rawValue: severityString) ?? .medium
            
            return MonitoringEvent(
                id: UUID(),
                name: name,
                type: type,
                timestamp: Date(timeIntervalSince1970: timestamp),
                severity: severity
            )
        }
    }
    
    private func generateKeyMetrics(for category: MetricCategory) -> [KeyMetric] {
        switch category {
        case .performance:
            return [
                KeyMetric(
                    id: UUID(),
                    title: "Avg FPS",
                    value: "58.2",
                    subtitle: "Rendering Performance",
                    icon: "speedometer",
                    color: .green,
                    changePercentage: "+2.1%",
                    changeColor: .green
                ),
                KeyMetric(
                    id: UUID(),
                    title: "Memory Usage",
                    value: "234MB",
                    subtitle: "Peak Usage",
                    icon: "memorychip",
                    color: .orange,
                    changePercentage: "+5.2%",
                    changeColor: .orange
                ),
                KeyMetric(
                    id: UUID(),
                    title: "Crash Rate",
                    value: "0.03%",
                    subtitle: "Last 24 hours",
                    icon: "exclamationmark.triangle",
                    color: .red,
                    changePercentage: "-0.01%",
                    changeColor: .green
                ),
                KeyMetric(
                    id: UUID(),
                    title: "Load Time",
                    value: "1.2s",
                    subtitle: "App Launch",
                    icon: "timer",
                    color: .blue,
                    changePercentage: "-0.3s",
                    changeColor: .green
                )
            ]
        case .engagement:
            return [
                KeyMetric(
                    id: UUID(),
                    title: "Active Users",
                    value: "1,234",
                    subtitle: "Last 24 hours",
                    icon: "person.2",
                    color: .blue,
                    changePercentage: "+12%",
                    changeColor: .green
                ),
                KeyMetric(
                    id: UUID(),
                    title: "Session Duration",
                    value: "8.5m",
                    subtitle: "Average",
                    icon: "clock",
                    color: .green,
                    changePercentage: "+1.2m",
                    changeColor: .green
                ),
                KeyMetric(
                    id: UUID(),
                    title: "Feature Usage",
                    value: "76%",
                    subtitle: "AR Scanning",
                    icon: "viewfinder",
                    color: .purple,
                    changePercentage: "+3%",
                    changeColor: .green
                ),
                KeyMetric(
                    id: UUID(),
                    title: "Retention",
                    value: "68%",
                    subtitle: "Day 7",
                    icon: "repeat",
                    color: .indigo,
                    changePercentage: "+2%",
                    changeColor: .green
                )
            ]
        case .errors:
            return [
                KeyMetric(
                    id: UUID(),
                    title: "Error Rate",
                    value: "0.8%",
                    subtitle: "Last hour",
                    icon: "exclamationmark.circle",
                    color: .red,
                    changePercentage: "+0.1%",
                    changeColor: .red
                ),
                KeyMetric(
                    id: UUID(),
                    title: "API Errors",
                    value: "23",
                    subtitle: "5xx responses",
                    icon: "network",
                    color: .orange,
                    changePercentage: "-5",
                    changeColor: .green
                ),
                KeyMetric(
                    id: UUID(),
                    title: "AR Failures",
                    value: "12",
                    subtitle: "Tracking lost",
                    icon: "viewfinder",
                    color: .yellow,
                    changePercentage: "+2",
                    changeColor: .red
                ),
                KeyMetric(
                    id: UUID(),
                    title: "Recovery Rate",
                    value: "94%",
                    subtitle: "Auto-recovery",
                    icon: "arrow.clockwise",
                    color: .green,
                    changePercentage: "+1%",
                    changeColor: .green
                )
            ]
        }
    }
    
    private func generatePerformanceData(for timeRange: TimeRange) -> [PerformanceDataPoint] {
        let count = timeRange.dataPointCount
        let now = Date()
        var data: [PerformanceDataPoint] = []
        
        for i in 0..<count {
            let timestamp = now.addingTimeInterval(-Double(count - i) * timeRange.interval)
            let fps = 55.0 + Double.random(in: -10...10)
            let memory = 200.0 + Double.random(in: -50...50)
            
            data.append(PerformanceDataPoint(
                timestamp: timestamp,
                fps: fps,
                memoryUsageMB: memory
            ))
        }
        
        return data
    }
    
    private func generateEngagementData(for timeRange: TimeRange) -> [EngagementDataPoint] {
        var data: [EngagementDataPoint] = []
        
        for hour in 0..<24 {
            let sessionCount = Int.random(in: 10...100)
            data.append(EngagementDataPoint(
                hour: hour,
                sessionCount: sessionCount
            ))
        }
        
        return data
    }
    
    private func generateErrorData(for timeRange: TimeRange) -> [ErrorDataPoint] {
        let count = timeRange.dataPointCount
        let now = Date()
        var data: [ErrorDataPoint] = []
        
        for i in 0..<count {
            let timestamp = now.addingTimeInterval(-Double(count - i) * timeRange.interval)
            let errorRate = Double.random(in: 0...2.0)
            
            data.append(ErrorDataPoint(
                timestamp: timestamp,
                errorRate: errorRate
            ))
        }
        
        return data
    }
    
    private func generateSampleAlerts() -> [MonitoringAlert] {
        return [
            MonitoringAlert(
                id: UUID(),
                title: "High Memory Usage",
                message: "Memory usage exceeded 80% for 10+ minutes",
                severity: .high,
                timestamp: Date().addingTimeInterval(-300)
            ),
            MonitoringAlert(
                id: UUID(),
                title: "AR Tracking Issues",
                message: "Increased tracking failures on iPhone 12",
                severity: .medium,
                timestamp: Date().addingTimeInterval(-600)
            )
        ]
    }
}

// MARK: - Data Models
struct RealTimeMetrics {
    var activeUsers: Int = 0
    var activeSessions: Int = 0
    var averageFPS: Double = 0.0
}

struct KeyMetric: Identifiable {
    let id: UUID
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    let changePercentage: String
    let changeColor: Color
}

struct PerformanceDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let fps: Double
    let memoryUsageMB: Double
}

struct EngagementDataPoint: Identifiable {
    let id = UUID()
    let hour: Int
    let sessionCount: Int
}

struct ErrorDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let errorRate: Double
}

struct MonitoringAlert: Identifiable {
    let id: UUID
    let title: String
    let message: String
    let severity: AlertSeverity
    let timestamp: Date
    
    enum AlertSeverity {
        case low, medium, high, critical
        
        var color: Color {
            switch self {
            case .low: return .blue
            case .medium: return .yellow
            case .high: return .orange
            case .critical: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .low: return "info.circle"
            case .medium: return "exclamationmark.triangle"
            case .high: return "exclamationmark.triangle.fill"
            case .critical: return "exclamationmark.octagon.fill"
            }
        }
    }
}

struct MonitoringEvent: Identifiable {
    let id: UUID
    let name: String
    let type: String
    let timestamp: Date
    let severity: EventSeverity
}

extension EventSeverity {
    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .blue
        case .high: return .orange
        case .critical: return .red
        }
    }
}

enum TimeRange: String, CaseIterable {
    case lastHour = "1h"
    case last6Hours = "6h"
    case last24Hours = "24h"
    case last7Days = "7d"
    case last30Days = "30d"
    
    var displayName: String {
        switch self {
        case .lastHour: return "1H"
        case .last6Hours: return "6H"
        case .last24Hours: return "24H"
        case .last7Days: return "7D"
        case .last30Days: return "30D"
        }
    }
    
    var dataPointCount: Int {
        switch self {
        case .lastHour: return 12
        case .last6Hours: return 24
        case .last24Hours: return 48
        case .last7Days: return 168
        case .last30Days: return 720
        }
    }
    
    var interval: TimeInterval {
        switch self {
        case .lastHour: return 300 // 5 minutes
        case .last6Hours: return 900 // 15 minutes
        case .last24Hours: return 1800 // 30 minutes
        case .last7Days: return 3600 // 1 hour
        case .last30Days: return 3600 // 1 hour
        }
    }
}

enum MetricCategory: String, CaseIterable {
    case performance = "performance"
    case engagement = "engagement"
    case errors = "errors"
    
    var displayName: String {
        switch self {
        case .performance: return "Performance"
        case .engagement: return "Engagement"
        case .errors: return "Errors"
        }
    }
}

extension View {
    func rounded() -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: 8))
    }
}