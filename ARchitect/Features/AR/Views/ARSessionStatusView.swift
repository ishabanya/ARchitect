import SwiftUI
import ARKit
import Combine

// MARK: - AR Session Status View
public struct ARSessionStatusView: View {
    @ObservedObject var sessionManager: ARSessionManager
    @State private var showingDiagnostics = false
    @State private var showingCoachingHelp = false
    @State private var animateStatusIcon = false
    
    public init(sessionManager: ARSessionManager) {
        self.sessionManager = sessionManager
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Main Status Card
            statusCard
            
            // Tracking Quality Indicator
            trackingQualityView
            
            // Plane Detection Status
            planeDetectionView
            
            // Performance Metrics
            performanceMetricsView
            
            // Action Buttons
            actionButtonsView
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .sheet(isPresented: $showingDiagnostics) {
            ARDiagnosticsView(sessionManager: sessionManager)
        }
        .sheet(isPresented: $showingCoachingHelp) {
            ARCoachingHelpView()
        }
        .onAppear {
            startStatusAnimation()
        }
    }
    
    // MARK: - Status Card
    private var statusCard: some View {
        HStack(spacing: 16) {
            // Status Icon
            statusIcon
                .scaleEffect(animateStatusIcon ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animateStatusIcon)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(sessionManager.sessionState.displayName)
                    .font(.headline)
                    .foregroundColor(sessionManager.sessionState.color)
                
                if let error = sessionManager.lastKnownError {
                    Text(error.userMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Text("Session Duration: \(formatDuration(sessionManager.sessionMetrics.sessionDuration))")
                    .font(.caption2)
                    .foregroundColor(.tertiary)
            }
            
            Spacer()
            
            // Session Actions Menu
            Menu {
                Button("Reset Session") {
                    sessionManager.resetSession()
                }
                
                Button("Pause Session") {
                    sessionManager.pauseSession()
                }
                
                Button("Show Diagnostics") {
                    showingDiagnostics = true
                }
                
                if sessionManager.shouldShowCoaching {
                    Button("Hide Coaching") {
                        // Hide coaching overlay
                    }
                } else {
                    Button("Show Coaching") {
                        showingCoachingHelp = true
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private var statusIcon: some View {
        Image(systemName: sessionManager.sessionState.icon)
            .font(.system(size: 32))
            .foregroundColor(sessionManager.sessionState.color)
            .frame(width: 50, height: 50)
    }
    
    // MARK: - Tracking Quality View
    private var trackingQualityView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tracking Quality")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(sessionManager.trackingQuality.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(sessionManager.trackingQuality.color.opacity(0.2))
                    .foregroundColor(sessionManager.trackingQuality.color)
                    .cornerRadius(12)
            }
            
            // Quality Progress Bar
            ProgressView(value: sessionManager.trackingQuality.score)
                .progressViewStyle(LinearProgressViewStyle(tint: sessionManager.trackingQuality.color))
                .scaleEffect(x: 1, y: 2, anchor: .center)
            
            // Quality History Chart (simplified)
            if !sessionManager.trackingQualityHistory.isEmpty {
                qualityHistoryChart
                    .frame(height: 40)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private var qualityHistoryChart: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(sessionManager.trackingQualityHistory.suffix(20).enumerated()), id: \.offset) { index, quality in
                Rectangle()
                    .fill(quality.color.opacity(0.7))
                    .frame(width: 3, height: CGFloat(quality.score * 30))
                    .cornerRadius(1)
            }
        }
    }
    
    // MARK: - Plane Detection View
    private var planeDetectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Detected Planes")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(sessionManager.detectedPlanes.count) planes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if sessionManager.detectedPlanes.isEmpty {
                HStack {
                    Image(systemName: "viewfinder")
                        .foregroundColor(.orange)
                    
                    Text("Point camera at flat surfaces")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(Array(sessionManager.detectedPlanes.prefix(6).enumerated()), id: \.offset) { index, plane in
                        planeIndicator(plane: plane, index: index)
                    }
                    
                    if sessionManager.detectedPlanes.count > 6 {
                        Text("+\(sessionManager.detectedPlanes.count - 6)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 40, height: 30)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private func planeIndicator(plane: ARPlaneAnchor, index: Int) -> some View {
        VStack(spacing: 2) {
            Image(systemName: planeIcon(for: plane.alignment))
                .font(.caption)
                .foregroundColor(planeColor(for: plane.alignment))
            
            Text("\(index + 1)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 40, height: 30)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
    
    private func planeIcon(for alignment: ARPlaneAnchor.Alignment) -> String {
        switch alignment {
        case .horizontal:
            return "rectangle.landscape"
        case .vertical:
            return "rectangle.portrait"
        @unknown default:
            return "rectangle"
        }
    }
    
    private func planeColor(for alignment: ARPlaneAnchor.Alignment) -> Color {
        switch alignment {
        case .horizontal:
            return .blue
        case .vertical:
            return .green
        @unknown default:
            return .gray
        }
    }
    
    // MARK: - Performance Metrics View
    private var performanceMetricsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Memory")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(memoryUsageText)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Quality Changes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(sessionManager.sessionMetrics.trackingStateChanges)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private var memoryUsageText: String {
        let usage = getCurrentMemoryUsage() / 1024 / 1024 // MB
        return "\(usage)MB"
    }
    
    // MARK: - Action Buttons
    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            Button("Reset") {
                sessionManager.resetSession()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Button("Diagnostics") {
                showingDiagnostics = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            if sessionManager.isCoachingActive {
                Button("Hide Coaching") {
                    // Hide coaching - this would need to be implemented
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button("Show Help") {
                    showingCoachingHelp = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Spacer()
            
            // Status indicator
            Circle()
                .fill(sessionManager.isSessionRunning ? .green : .red)
                .frame(width: 12, height: 12)
        }
    }
    
    // MARK: - Helper Methods
    private func startStatusAnimation() {
        if sessionManager.sessionState == .initializing || sessionManager.sessionState == .relocalizating {
            animateStatusIcon = true
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(abs(duration)) / 60
        let seconds = Int(abs(duration)) % 60
        return String(format: "%02d:%02d", minutes, seconds)
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

// MARK: - AR Diagnostics View
struct ARDiagnosticsView: View {
    let sessionManager: ARSessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var diagnosticsReport: ARDiagnosticsReport?
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Generating Diagnostics Report...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let report = diagnosticsReport {
                    diagnosticsContent(report: report)
                } else {
                    Text("Failed to generate diagnostics report")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("AR Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                if let report = diagnosticsReport {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ShareLink(
                            item: "AR Diagnostics Report",
                            preview: SharePreview("AR Diagnostics")
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .onAppear {
            generateReport()
        }
    }
    
    private func diagnosticsContent(report: ARDiagnosticsReport) -> some View {
        List {
            // System Information
            Section("System Information") {
                ForEach(report.systemInfo.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack {
                        Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                        Spacer()
                        Text("\(value)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // AR Capabilities
            Section("AR Capabilities") {
                ForEach(report.arCapabilities.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack {
                        Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                        Spacer()
                        
                        if let boolValue = value as? Bool {
                            Image(systemName: boolValue ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(boolValue ? .green : .red)
                        } else {
                            Text("\(value)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Session Metrics
            Section("Session Metrics") {
                ForEach(report.sessionMetrics.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack {
                        Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                        Spacer()
                        Text("\(value)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Detected Issues
            if !report.detectedIssues.isEmpty {
                Section("Detected Issues") {
                    ForEach(report.detectedIssues, id: \.category) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: iconForSeverity(issue.severity))
                                    .foregroundColor(colorForSeverity(issue.severity))
                                
                                Text(issue.category)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                Text(issue.severity.rawValue.uppercased())
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(colorForSeverity(issue.severity).opacity(0.2))
                                    .foregroundColor(colorForSeverity(issue.severity))
                                    .cornerRadius(4)
                            }
                            
                            Text(issue.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Recommendation: \(issue.recommendation)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
    
    private func generateReport() {
        DispatchQueue.global(qos: .userInitiated).async {
            let diagnostics = ARSessionDiagnostics(sessionManager: sessionManager)
            let report = diagnostics.generateDiagnosticsReport()
            
            DispatchQueue.main.async {
                self.diagnosticsReport = report
                self.isLoading = false
            }
        }
    }
    
    private func iconForSeverity(_ severity: ARDiagnosticIssue.Severity) -> String {
        switch severity {
        case .low:
            return "info.circle"
        case .medium:
            return "exclamationmark.triangle"
        case .high:
            return "exclamationmark.circle"
        case .critical:
            return "xmark.octagon"
        }
    }
    
    private func colorForSeverity(_ severity: ARDiagnosticIssue.Severity) -> Color {
        switch severity {
        case .low:
            return .blue
        case .medium:
            return .orange
        case .high:
            return .red
        case .critical:
            return .purple
        }
    }
}

// MARK: - AR Coaching Help View
struct ARCoachingHelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    coachingTip(
                        icon: "lightbulb.fill",
                        title: "Good Lighting",
                        description: "Ensure you have adequate lighting. AR works best in well-lit environments.",
                        color: .yellow
                    )
                    
                    coachingTip(
                        icon: "tortoise.fill",
                        title: "Move Slowly",
                        description: "Move your device slowly and steadily. Quick movements can disrupt tracking.",
                        color: .green
                    )
                    
                    coachingTip(
                        icon: "rectangle.landscape",
                        title: "Find Flat Surfaces",
                        description: "Point your camera at flat surfaces like floors, tables, or walls to detect planes.",
                        color: .blue
                    )
                    
                    coachingTip(
                        icon: "camera.viewfinder",
                        title: "Scan Environment",
                        description: "Move around to scan different areas of your space for better tracking.",
                        color: .purple
                    )
                    
                    coachingTip(
                        icon: "exclamationmark.triangle.fill",
                        title: "Avoid Reflective Surfaces",
                        description: "Mirrors and very shiny surfaces can interfere with AR tracking.",
                        color: .orange
                    )
                    
                    coachingTip(
                        icon: "textformat.size",
                        title: "Visual Features",
                        description: "Ensure your environment has visual details and textures. Plain white walls can be difficult to track.",
                        color: .indigo
                    )
                }
                .padding()
            }
            .navigationTitle("AR Tips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func coachingTip(icon: String, title: String, description: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Preview
#if DEBUG
struct ARSessionStatusView_Previews: PreviewProvider {
    static var previews: some View {
        ARSessionStatusView(sessionManager: ARSessionManager())
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
#endif