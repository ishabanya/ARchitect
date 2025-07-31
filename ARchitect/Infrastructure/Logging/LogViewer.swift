import SwiftUI
import UniformTypeIdentifiers

// MARK: - Log Viewer
public struct LogViewer: View {
    @StateObject private var viewModel = LogViewerViewModel()
    @State private var selectedTab = 0
    @State private var showingExporter = false
    @State private var showingFilter = false
    
    public var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                LogListTab(viewModel: viewModel)
                    .tabItem {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Logs")
                    }
                    .tag(0)
                
                LogStatsTab(viewModel: viewModel)
                    .tabItem {
                        Image(systemName: "chart.bar")
                        Text("Statistics")
                    }
                    .tag(1)
                
                LogAnalysisTab(viewModel: viewModel)
                    .tabItem {
                        Image(systemName: "brain")
                        Text("Analysis")
                    }
                    .tag(2)
                
                CrashReportsTab()
                    .tabItem {
                        Image(systemName: "exclamationmark.triangle")
                        Text("Crashes")
                    }
                    .tag(3)
            }
            .navigationTitle("Log Viewer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showingFilter = true }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    
                    Button(action: { showingExporter = true }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button("Clear All") {
                        viewModel.clearAllLogs()
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .sheet(isPresented: $showingExporter) {
            LogExporterView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingFilter) {
            LogFilterView(viewModel: viewModel)
        }
    }
}

// MARK: - Log List Tab
struct LogListTab: View {
    @ObservedObject var viewModel: LogViewerViewModel
    @State private var searchText = ""
    
    var body: some View {
        VStack {
            SearchBar(text: $searchText, onSearchButtonClicked: {
                viewModel.searchLogs(query: searchText)
            })
            
            List {
                ForEach(viewModel.displayedLogs, id: \.id) { log in
                    LogEntryRow(log: log)
                        .onTapGesture {
                            viewModel.selectedLog = log
                        }
                }
            }
            .refreshable {
                viewModel.refreshLogs()
            }
        }
        .sheet(item: $viewModel.selectedLog) { log in
            LogDetailView(log: log)
        }
    }
}

// MARK: - Log Entry Row
struct LogEntryRow: View {
    let log: LogEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(log.level.icon)
                    .font(.caption)
                
                Text(log.level.displayName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colorForLevel(log.level))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                
                Spacer()
                
                Text(formatTime(log.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(log.message)
                .font(.body)
                .lineLimit(2)
            
            HStack {
                Text(log.category.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(2)
                
                Text("\(log.file):\(log.line)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }
    
    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .verbose: return .gray
        case .debug: return .blue
        case .info: return .green
        case .warning: return .orange
        case .error: return .red
        case .critical: return .purple
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Log Detail View
struct LogDetailView: View {
    let log: LogEntry
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack {
                        Text(log.level.icon)
                            .font(.title)
                        
                        VStack(alignment: .leading) {
                            Text(log.level.displayName)
                                .font(.headline)
                            Text(DateFormatter.logTimestamp.string(from: log.timestamp))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    // Message
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message")
                            .font(.headline)
                        
                        Text(log.message)
                            .font(.body)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    // Location
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Location")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            DetailRow(label: "File", value: log.file)
                            DetailRow(label: "Function", value: log.function)
                            DetailRow(label: "Line", value: "\(log.line)")
                        }
                    }
                    
                    // Context
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Context")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            DetailRow(label: "Category", value: log.category.rawValue)
                            DetailRow(label: "Session ID", value: log.sessionId)
                            DetailRow(label: "Thread", value: log.threadInfo.isMainThread ? "Main" : "Background")
                            
                            if let threadName = log.threadInfo.name {
                                DetailRow(label: "Thread Name", value: threadName)
                            }
                            
                            if let queueLabel = log.threadInfo.queueLabel {
                                DetailRow(label: "Queue", value: queueLabel)
                            }
                        }
                    }
                    
                    // Device Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Device Information")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            DetailRow(label: "Device", value: log.context.deviceInfo.deviceModel)
                            DetailRow(label: "System", value: "\(log.context.deviceInfo.systemName) \(log.context.deviceInfo.systemVersion)")
                            DetailRow(label: "App Version", value: log.context.deviceInfo.appVersion)
                            DetailRow(label: "Build", value: log.context.deviceInfo.buildNumber)
                            DetailRow(label: "Simulator", value: log.context.deviceInfo.isSimulator ? "Yes" : "No")
                        }
                    }
                    
                    // Custom Data
                    if !log.context.customData.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Custom Data")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(log.context.customData.keys.sorted()), id: \.self) { key in
                                    DetailRow(label: key, value: "\(log.context.customData[key] ?? "")")
                                }
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Log Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Log Statistics Tab
struct LogStatsTab: View {
    @ObservedObject var viewModel: LogViewerViewModel
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let stats = viewModel.statistics {
                    // Overview Card
                    StatCard(title: "Overview") {
                        VStack(spacing: 8) {
                            StatRow(label: "Total Logs", value: "\(stats.totalLogs)")
                            StatRow(label: "Errors", value: "\(stats.errorCount)")
                            StatRow(label: "Warnings", value: "\(stats.warningCount)")
                        }
                    }
                    
                    // Log Levels Card
                    StatCard(title: "Log Levels") {
                        VStack(spacing: 8) {
                            ForEach(LogLevel.allCases, id: \.self) { level in
                                let count = stats.levelBreakdown[level] ?? 0
                                StatRow(
                                    label: "\(level.icon) \(level.displayName)",
                                    value: "\(count)"
                                )
                            }
                        }
                    }
                    
                    // Categories Card
                    StatCard(title: "Categories") {
                        VStack(spacing: 8) {
                            ForEach(LogCategory.allCases, id: \.self) { category in
                                let count = stats.categoryBreakdown[category] ?? 0
                                if count > 0 {
                                    StatRow(
                                        label: category.rawValue,
                                        value: "\(count)"
                                    )
                                }
                            }
                        }
                    }
                    
                    // Time Range Card
                    if let first = stats.timeRange.first, let last = stats.timeRange.last {
                        StatCard(title: "Time Range") {
                            VStack(spacing: 8) {
                                StatRow(label: "First Log", value: formatDateTime(first))
                                StatRow(label: "Last Log", value: formatDateTime(last))
                                StatRow(label: "Duration", value: formatDuration(last.timeIntervalSince(first)))
                            }
                        }
                    }
                } else {
                    Text("Loading statistics...")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .refreshable {
            viewModel.refreshStats()
        }
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Stat Card
struct StatCard<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            content
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Stat Row
struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Log Analysis Tab
struct LogAnalysisTab: View {
    @ObservedObject var viewModel: LogViewerViewModel
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let analysis = viewModel.analysis {
                    // Analysis Period Card
                    StatCard(title: "Analysis Period") {
                        VStack(spacing: 8) {
                            StatRow(
                                label: "Period",
                                value: "\(formatDateTime(analysis.analyzedPeriod.start)) - \(formatDateTime(analysis.analyzedPeriod.end))"
                            )
                            StatRow(label: "Logs Analyzed", value: "\(analysis.totalLogsAnalyzed)")
                        }
                    }
                    
                    // Error Patterns Card
                    if !analysis.errorPatterns.isEmpty {
                        StatCard(title: "Common Error Patterns") {
                            VStack(spacing: 8) {
                                ForEach(Array(analysis.errorPatterns.keys.sorted()), id: \.self) { pattern in
                                    let count = analysis.errorPatterns[pattern] ?? 0
                                    StatRow(
                                        label: String(pattern.prefix(50)) + (pattern.count > 50 ? "..." : ""),
                                        value: "\(count)x"
                                    )
                                }
                            }
                        }
                    }
                    
                    // Performance Issues Card
                    if !analysis.performanceIssues.isEmpty {
                        StatCard(title: "Performance Issues") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(analysis.performanceIssues.prefix(10)), id: \.self) { issue in
                                    Text("• " + issue)
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                    
                    // Security Events Card
                    if !analysis.securityEvents.isEmpty {
                        StatCard(title: "Security Events") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(analysis.securityEvents.prefix(10)), id: \.self) { event in
                                    Text("• " + event)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    
                    // Recommendations Card
                    if !analysis.recommendations.isEmpty {
                        StatCard(title: "Recommendations") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(analysis.recommendations, id: \.self) { recommendation in
                                    HStack(alignment: .top) {
                                        Image(systemName: "lightbulb")
                                            .foregroundColor(.yellow)
                                            .font(.caption)
                                        
                                        Text(recommendation)
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("Loading analysis...")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .refreshable {
            viewModel.refreshAnalysis()
        }
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Crash Reports Tab
struct CrashReportsTab: View {
    @State private var crashReports: [CrashReport] = []
    @State private var selectedCrash: CrashReport?
    
    var body: some View {
        List {
            ForEach(crashReports, id: \.id) { crash in
                CrashReportRow(crash: crash)
                    .onTapGesture {
                        selectedCrash = crash
                    }
            }
        }
        .onAppear {
            loadCrashReports()
        }
        .refreshable {
            loadCrashReports()
        }
        .sheet(item: $selectedCrash) { crash in
            CrashReportDetailView(crash: crash)
        }
    }
    
    private func loadCrashReports() {
        crashReports = CrashReporter.shared.getCrashReports()
    }
}

// MARK: - Crash Report Row
struct CrashReportRow: View {
    let crash: CrashReport
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                
                Text("\(crash.crashType)".capitalized)
                    .font(.headline)
                
                Spacer()
                
                Text(formatTime(crash.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let reason = crash.exceptionReason {
                Text(reason)
                    .font(.body)
                    .lineLimit(2)
            }
            
            HStack {
                Text("Session: \(crash.sessionId.prefix(8))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(crash.deviceInfo.systemName) \(crash.deviceInfo.systemVersion)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Crash Report Detail View
struct CrashReportDetailView: View {
    let crash: CrashReport
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Crash Info
                    StatCard(title: "Crash Information") {
                        VStack(spacing: 8) {
                            StatRow(label: "Type", value: "\(crash.crashType)".capitalized)
                            StatRow(label: "Time", value: DateFormatter.logTimestamp.string(from: crash.timestamp))
                            
                            if let signal = crash.signal {
                                StatRow(label: "Signal", value: "\(signal)")
                            }
                            
                            if let exceptionName = crash.exceptionName {
                                StatRow(label: "Exception", value: exceptionName)
                            }
                            
                            if let reason = crash.exceptionReason {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Reason:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text(reason)
                                        .font(.caption)
                                        .padding()
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                    
                    // Device Info
                    StatCard(title: "Device Information") {
                        VStack(spacing: 8) {
                            StatRow(label: "Model", value: crash.deviceInfo.model)
                            StatRow(label: "System", value: "\(crash.deviceInfo.systemName) \(crash.deviceInfo.systemVersion)")
                            StatRow(label: "Architecture", value: crash.deviceInfo.architecture)
                        }
                    }
                    
                    // App Info
                    StatCard(title: "Application Information") {
                        VStack(spacing: 8) {
                            StatRow(label: "Version", value: crash.appInfo.version)
                            StatRow(label: "Build", value: crash.appInfo.build)
                            StatRow(label: "Environment", value: crash.appInfo.environment)
                            StatRow(label: "Uptime", value: formatDuration(crash.appInfo.uptime))
                        }
                    }
                    
                    // Stack Trace
                    if !crash.stackTrace.isEmpty {
                        StatCard(title: "Stack Trace") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(crash.stackTrace.prefix(20).enumerated()), id: \.offset) { index, frame in
                                    Text("\(index): \(frame)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Crash Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Search Bar
struct SearchBar: View {
    @Binding var text: String
    let onSearchButtonClicked: () -> Void
    
    var body: some View {
        HStack {
            TextField("Search logs...", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit {
                    onSearchButtonClicked()
                }
            
            Button("Search", action: onSearchButtonClicked)
                .disabled(text.isEmpty)
        }
        .padding(.horizontal)
    }
}

// MARK: - Log Filter View
struct LogFilterView: View {
    @ObservedObject var viewModel: LogViewerViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section("Log Level") {
                    Picker("Minimum Level", selection: $viewModel.filterLevel) {
                        Text("All").tag(LogLevel?.none)
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Text("\(level.icon) \(level.displayName)").tag(LogLevel?.some(level))
                        }
                    }
                }
                
                Section("Category") {
                    Picker("Category", selection: $viewModel.filterCategory) {
                        Text("All Categories").tag(LogCategory?.none)
                        ForEach(LogCategory.allCases, id: \.self) { category in
                            Text(category.rawValue).tag(LogCategory?.some(category))
                        }
                    }
                }
                
                Section("Time Range") {
                    DatePicker("Since", selection: $viewModel.filterSince, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("Filter Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        viewModel.resetFilters()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        viewModel.applyFilters()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Log Exporter View
struct LogExporterView: View {
    @ObservedObject var viewModel: LogViewerViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var exportFormat: LogExportFormat = .json
    @State private var isExporting = false
    @State private var exportData: Data?
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Export Options")
                        .font(.headline)
                    
                    Picker("Format", selection: $exportFormat) {
                        Text("JSON").tag(LogExportFormat.json)
                        Text("CSV").tag(LogExportFormat.csv)
                        Text("Text").tag(LogExportFormat.txt)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Export Summary")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Logs to export: \(viewModel.displayedLogs.count)")
                        Text("Format: \(exportFormat.description)")
                        Text("Estimated size: \(estimatedSize)")
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
                
                Spacer()
                
                Button(action: exportLogs) {
                    if isExporting {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Exporting...")
                        }
                    } else {
                        Text("Export Logs")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting || viewModel.displayedLogs.isEmpty)
                .padding()
            }
            .navigationTitle("Export Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let data = exportData {
                ShareSheet(items: [data])
            }
        }
    }
    
    private var estimatedSize: String {
        let logCount = viewModel.displayedLogs.count
        let estimatedBytes: Int
        
        switch exportFormat {
        case .json:
            estimatedBytes = logCount * 1024 // ~1KB per log in JSON
        case .csv:
            estimatedBytes = logCount * 256  // ~256B per log in CSV
        case .txt:
            estimatedBytes = logCount * 512  // ~512B per log in text
        }
        
        return ByteCountFormatter.string(fromByteCount: Int64(estimatedBytes), countStyle: .file)
    }
    
    private func exportLogs() {
        isExporting = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let filter = LogFilter(
                category: viewModel.filterCategory,
                level: viewModel.filterLevel,
                since: viewModel.filterSince,
                limit: Int.max
            )
            
            let data = LogManager.shared.exportLogs(filter: filter, format: exportFormat)
            
            DispatchQueue.main.async {
                self.isExporting = false
                self.exportData = data
                
                if data != nil {
                    self.showingShareSheet = true
                } else {
                    // Handle export error
                }
            }
        }
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Extensions
extension LogExportFormat {
    var description: String {
        switch self {
        case .json: return "JSON"
        case .csv: return "CSV"
        case .txt: return "Plain Text"
        }
    }
}

extension CrashReport: Identifiable {}
extension LogEntry: Identifiable {}