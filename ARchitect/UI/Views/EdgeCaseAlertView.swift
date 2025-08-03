import SwiftUI
import Combine

// MARK: - Edge Case Alert View

struct EdgeCaseAlertView: View {
    @StateObject private var edgeCaseHandler = EdgeCaseHandler.shared
    @State private var showingAlert = false
    @State private var currentAlert: EdgeCaseAlert?
    @State private var alertTimer: Timer?
    
    private struct EdgeCaseAlert: Identifiable {
        let id = UUID()
        let result: EdgeCaseDetectionResult
        let message: String
        let primaryAction: AlertAction?
        let secondaryAction: AlertAction?
        
        struct AlertAction {
            let title: String
            let action: () -> Void
        }
    }
    
    var body: some View {
        EmptyView()
            .onReceive(NotificationCenter.default.publisher(for: .edgeCaseDetected)) { notification in
                if let result = notification.object as? EdgeCaseDetectionResult {
                    handleEdgeCaseDetection(result)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showEdgeCaseGuidance)) { _ in
                showGuidanceAlert()
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestBetterConditions)) { _ in
                showBetterConditionsAlert()
            }
            .alert(item: $currentAlert) { alert in
                createAlert(for: alert)
            }
    }
    
    private func handleEdgeCaseDetection(_ result: EdgeCaseDetectionResult) {
        // Only show alerts for high severity issues or when user action is needed
        guard result.severity.rawValue >= EdgeCaseSeverity.high.rawValue || 
              result.recommendedActions.contains(.requestBetterConditions) ||
              result.recommendedActions.contains(.showGuidance) else {
            return
        }
        
        let alert = createEdgeCaseAlert(for: result)
        
        // Cancel any existing timer
        alertTimer?.invalidate()
        
        // Show alert immediately for critical issues, or after a delay for others
        if result.severity == .critical {
            currentAlert = alert
            showingAlert = true
        } else {
            // Delay non-critical alerts to avoid spam
            alertTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                DispatchQueue.main.async {
                    currentAlert = alert
                    showingAlert = true
                }
            }
        }
    }
    
    private func createEdgeCaseAlert(for result: EdgeCaseDetectionResult) -> EdgeCaseAlert {
        let message = createMessage(for: result)
        let primaryAction = createPrimaryAction(for: result)
        let secondaryAction = createSecondaryAction(for: result)
        
        return EdgeCaseAlert(
            result: result,
            message: message,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction
        )
    }
    
    private func createMessage(for result: EdgeCaseDetectionResult) -> String {
        switch result.type {
        case .poorLighting:
            return "Poor lighting detected. Move to a better-lit area or turn on more lights for optimal scanning."
            
        case .rapidMovement:
            return "Device movement is too rapid. Please move more slowly and steadily for better tracking."
            
        case .clutteredEnvironment:
            return "Environment appears cluttered. Point the camera at clear wall and floor surfaces for better results."
            
        case .appInterruption:
            return "App was interrupted. Your scanning progress has been saved. Tap Resume to continue."
            
        case .lowStorage:
            let availableGB = result.metadata["available_gb"] as? Double ?? 0
            return "Storage space is low (\(String(format: "%.1f", availableGB))GB remaining). Consider freeing up space."
            
        case .offlineMode:
            return "Network connection lost. Switching to offline mode with limited features."
            
        case .largeRoom:
            return "Large room detected. Some features may be reduced to maintain performance."
            
        case .smallRoom:
            return "Small room detected. Move the camera closer to surfaces for detailed scanning."
            
        case .irregularRoom:
            return "Irregular room shape detected. Take extra time to scan all corners and surfaces."
            
        case .thermalThrottling:
            return "Device is overheating. Performance will be reduced. Consider letting the device cool down."
            
        case .memoryPressure:
            return "Device memory is low. Some background apps may be closed to free up resources."
            
        case .noiseInterference:
            return "Audio interference detected. Consider moving to a quieter environment."
        }
    }
    
    private func createPrimaryAction(for result: EdgeCaseDetectionResult) -> EdgeCaseAlert.AlertAction? {
        switch result.type {
        case .poorLighting:
            return EdgeCaseAlert.AlertAction(title: "Adjust Settings") {
                // Post notification to adjust AR settings for low light
                NotificationCenter.default.post(name: .adjustARForLowLight, object: nil)
            }
            
        case .rapidMovement:
            return EdgeCaseAlert.AlertAction(title: "Show Tips") {
                // Show movement guidance
                NotificationCenter.default.post(name: .showMovementGuidance, object: nil)
            }
            
        case .clutteredEnvironment:
            return EdgeCaseAlert.AlertAction(title: "Show Guide") {
                // Show scanning guidance
                NotificationCenter.default.post(name: .showScanningGuidance, object: nil)
            }
            
        case .appInterruption:
            return EdgeCaseAlert.AlertAction(title: "Resume") {
                // Resume AR session
                ARSessionManager().resumeSession()
            }
            
        case .lowStorage:
            return EdgeCaseAlert.AlertAction(title: "Manage Storage") {
                // Open storage management
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            
        case .offlineMode:
            return EdgeCaseAlert.AlertAction(title: "Continue Offline") {
                // Continue in offline mode
                OfflineManager.shared.enableOfflineMode()
            }
            
        case .largeRoom, .smallRoom, .irregularRoom:
            return EdgeCaseAlert.AlertAction(title: "Got It") {
                // Acknowledge the alert
            }
            
        case .thermalThrottling:
            return EdgeCaseAlert.AlertAction(title: "Pause Scanning") {
                // Pause AR session to cool down
                ARSessionManager().pauseSession()
            }
            
        case .memoryPressure:
            return EdgeCaseAlert.AlertAction(title: "Free Memory") {
                // Clear caches and free memory
                Task {
                    await EdgeCaseHandler.shared.clearMemory()
                }
            }
            
        case .noiseInterference:
            return EdgeCaseAlert.AlertAction(title: "Disable Audio") {
                // Disable audio features
                NotificationCenter.default.post(name: .disableAudioFeatures, object: nil)
            }
        }
    }
    
    private func createSecondaryAction(for result: EdgeCaseDetectionResult) -> EdgeCaseAlert.AlertAction? {
        switch result.type {
        case .poorLighting, .rapidMovement, .clutteredEnvironment:
            return EdgeCaseAlert.AlertAction(title: "Continue Anyway") {
                // Continue with current conditions
            }
            
        case .appInterruption:
            return EdgeCaseAlert.AlertAction(title: "Start Over") {
                // Reset and start new session
                ARSessionManager().resetSession()
            }
            
        case .lowStorage:
            return EdgeCaseAlert.AlertAction(title: "Continue") {
                // Continue with low storage
            }
            
        case .offlineMode:
            return EdgeCaseAlert.AlertAction(title: "Wait for Connection") {
                // Wait for network to reconnect
            }
            
        case .thermalThrottling:
            return EdgeCaseAlert.AlertAction(title: "Continue") {
                // Continue with reduced performance
            }
            
        default:
            return nil
        }
    }
    
    private func createAlert(for alert: EdgeCaseAlert) -> Alert {
        let title = "\(alert.result.type.displayName) - \(alert.result.severity.displayName)"
        
        if let secondaryAction = alert.secondaryAction {
            return Alert(
                title: Text(title),
                message: Text(alert.message),
                primaryButton: .default(Text(alert.primaryAction?.title ?? "OK")) {
                    alert.primaryAction?.action()
                },
                secondaryButton: .cancel(Text(secondaryAction.title)) {
                    secondaryAction.action()
                }
            )
        } else {
            return Alert(
                title: Text(title),
                message: Text(alert.message),
                dismissButton: .default(Text(alert.primaryAction?.title ?? "OK")) {
                    alert.primaryAction?.action()
                }
            )
        }
    }
    
    private func showGuidanceAlert() {
        let alert = EdgeCaseAlert(
            result: EdgeCaseDetectionResult(
                type: .rapidMovement,
                severity: .medium,
                confidence: 1.0,
                timestamp: Date(),
                metadata: [:],
                recommendedActions: [.showGuidance]
            ),
            message: "For best results, move the device slowly and steadily while scanning.",
            primaryAction: EdgeCaseAlert.AlertAction(title: "Show Tutorial") {
                NotificationCenter.default.post(name: .showARTutorial, object: nil)
            },
            secondaryAction: EdgeCaseAlert.AlertAction(title: "Continue") {
                // Continue scanning
            }
        )
        
        currentAlert = alert
        showingAlert = true
    }
    
    private func showBetterConditionsAlert() {
        let alert = EdgeCaseAlert(
            result: EdgeCaseDetectionResult(
                type: .poorLighting,
                severity: .high,
                confidence: 1.0,
                timestamp: Date(),
                metadata: [:],
                recommendedActions: [.requestBetterConditions]
            ),
            message: "Current conditions are not optimal for scanning. Please improve lighting and reduce clutter.",
            primaryAction: EdgeCaseAlert.AlertAction(title: "Try Again") {
                // Continue scanning
            },
            secondaryAction: EdgeCaseAlert.AlertAction(title: "Scan Anyway") {
                // Continue with poor conditions
            }
        )
        
        currentAlert = alert
        showingAlert = true
    }
}

// MARK: - Edge Case Status View

struct EdgeCaseStatusView: View {
    @StateObject private var edgeCaseHandler = EdgeCaseHandler.shared
    @State private var showingDetails = false
    
    var body: some View {
        if !edgeCaseHandler.detectedCases.isEmpty {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                        .font(.system(size: 16, weight: .medium))
                    
                    Text(statusText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        showingDetails.toggle()
                    }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(statusColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(statusColor.opacity(0.3), lineWidth: 1)
                        )
                )
                
                if showingDetails {
                    EdgeCaseDetailView(cases: edgeCaseHandler.detectedCases)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showingDetails)
        }
    }
    
    private var statusIcon: String {
        let maxSeverity = edgeCaseHandler.detectedCases.map { $0.severity }.max() ?? .low
        
        switch maxSeverity {
        case .critical:
            return "exclamationmark.triangle.fill"
        case .high:
            return "exclamationmark.triangle"
        case .medium:
            return "info.circle"
        case .low:
            return "checkmark.circle"
        }
    }
    
    private var statusColor: Color {
        let maxSeverity = edgeCaseHandler.detectedCases.map { $0.severity }.max() ?? .low
        
        switch maxSeverity {
        case .critical:
            return .red
        case .high:
            return .orange
        case .medium:
            return .yellow
        case .low:
            return .blue
        }
    }
    
    private var statusText: String {
        let recentCases = edgeCaseHandler.detectedCases.filter { 
            Date().timeIntervalSince($0.timestamp) < 30 
        }
        
        if recentCases.isEmpty {
            return "Scanning conditions: Good"
        }
        
        let groupedCases = Dictionary(grouping: recentCases) { $0.type }
        let caseCount = groupedCases.count
        
        if caseCount == 1, let caseType = groupedCases.keys.first {
            return "\(caseType.displayName) detected"
        } else {
            return "\(caseCount) issues detected"
        }
    }
}

// MARK: - Edge Case Detail View

struct EdgeCaseDetailView: View {
    let cases: [EdgeCaseDetectionResult]
    
    private var recentCases: [EdgeCaseDetectionResult] {
        cases.filter { Date().timeIntervalSince($0.timestamp) < 60 }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(recentCases.prefix(3), id: \.timestamp) { caseResult in
                EdgeCaseRowView(caseResult: caseResult)
            }
            
            if recentCases.count > 3 {
                Text("... and \(recentCases.count - 3) more")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Edge Case Row View

struct EdgeCaseRowView: View {
    let caseResult: EdgeCaseDetectionResult
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: caseResult.type.iconName)
                .foregroundColor(caseResult.severity.color)
                .font(.system(size: 12))
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(caseResult.type.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(caseResult.type.shortDescription)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 1) {
                Text(caseResult.severity.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(caseResult.severity.color)
                
                Text(timeAgo(from: caseResult.timestamp))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "\(Int(interval))s ago"
        } else {
            return "\(Int(interval / 60))m ago"
        }
    }
}

// MARK: - Extensions

extension EdgeCaseType {
    var iconName: String {
        switch self {
        case .poorLighting:
            return "lightbulb.slash"
        case .rapidMovement:
            return "move.3d"
        case .clutteredEnvironment:
            return "square.stack.3d.down.right"
        case .appInterruption:
            return "phone"
        case .lowStorage:
            return "externaldrive.badge.minus"
        case .offlineMode:
            return "wifi.slash"
        case .largeRoom:
            return "arrow.up.left.and.arrow.down.right"
        case .smallRoom:
            return "arrow.down.right.and.arrow.up.left"
        case .irregularRoom:
            return "pentagon"
        case .noiseInterference:
            return "speaker.wave.2.circle.fill"
        case .thermalThrottling:
            return "thermometer.sun"
        case .memoryPressure:
            return "memorychip"
        }
    }
    
    var shortDescription: String {
        switch self {
        case .poorLighting:
            return "Insufficient lighting detected"
        case .rapidMovement:
            return "Device moving too quickly"
        case .clutteredEnvironment:
            return "Too many objects in view"
        case .appInterruption:
            return "Scanning was interrupted"
        case .lowStorage:
            return "Storage space running low"
        case .offlineMode:
            return "No network connection"
        case .largeRoom:
            return "Room is very large"
        case .smallRoom:
            return "Room is very small"
        case .irregularRoom:
            return "Unusual room shape"
        case .noiseInterference:
            return "Audio interference present"
        case .thermalThrottling:
            return "Device overheating"
        case .memoryPressure:
            return "Low memory available"
        }
    }
}

extension EdgeCaseSeverity {
    var color: Color {
        switch self {
        case .low:
            return .blue
        case .medium:
            return .yellow
        case .high:
            return .orange
        case .critical:
            return .red
        }
    }
}

// MARK: - Additional Notifications

extension Notification.Name {
    static let adjustARForLowLight = Notification.Name("adjustARForLowLight")
    static let showMovementGuidance = Notification.Name("showMovementGuidance")
    static let showScanningGuidance = Notification.Name("showScanningGuidance")
    static let showARTutorial = Notification.Name("showARTutorial")
    static let disableAudioFeatures = Notification.Name("disableAudioFeatures")
}

// MARK: - Preview

struct EdgeCaseAlertView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            EdgeCaseStatusView()
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
    }
}