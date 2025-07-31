import SwiftUI

// MARK: - Error Presentation View
struct ErrorPresentationView: View {
    @ObservedObject private var errorManager = ErrorManager.shared
    @State private var showingErrorDetails = false
    @State private var isRetrying = false
    
    var body: some View {
        ZStack {
            if let currentError = errorManager.currentError {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        // Allow dismissing low-severity errors by tapping background
                        if currentError.error.severity == .low {
                            errorManager.dismissCurrentError()
                        }
                    }
                
                ErrorCard(
                    errorItem: currentError,
                    isRetrying: $isRetrying,
                    showingDetails: $showingErrorDetails,
                    onRetry: {
                        isRetrying = true
                        errorManager.retryCurrentError()
                        
                        // Reset retry state after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            isRetrying = false
                        }
                    },
                    onDismiss: {
                        errorManager.dismissCurrentError()
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .scale(scale: 0.9).combined(with: .opacity)
                ))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: errorManager.currentError?.id)
            }
        }
    }
}

// MARK: - Error Card
struct ErrorCard: View {
    let errorItem: ErrorQueueItem
    @Binding var isRetrying: Bool
    @Binding var showingDetails: Bool
    let onRetry: () -> Void
    let onDismiss: () -> Void
    
    @State private var animateIcon = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Error Icon and Title
            HStack(spacing: 12) {
                errorIcon
                    .font(.title2)
                    .foregroundColor(errorColor)
                    .scaleEffect(animateIcon ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: animateIcon)
                    .onAppear {
                        if errorItem.error.severity == .critical {
                            animateIcon = true
                        }
                    }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(errorTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(errorSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { showingDetails.toggle() }) {
                    Image(systemName: showingDetails ? "chevron.up" : "info.circle")
                        .foregroundColor(.secondary)
                }
            }
            
            // Error Message
            Text(errorItem.error.userMessage)
                .font(.body)
                .multilineTextAlignment(.leading)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Retry Information
            if errorItem.error.isRetryable && errorItem.retryCount > 0 {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.orange)
                    Text("Retry attempt \(errorItem.retryCount)")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                }
            }
            
            // Error Details (expandable)
            if showingDetails {
                ErrorDetailsView(errorItem: errorItem)
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                // Secondary Action (Dismiss)
                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(SecondaryErrorButtonStyle())
                
                Spacer()
                
                // Primary Action (Recovery)
                if let recoveryAction = errorItem.error.recoveryAction {
                    Button(recoveryAction.actionTitle) {
                        executeRecoveryAction(recoveryAction)
                    }
                    .buttonStyle(PrimaryErrorButtonStyle(
                        isLoading: isRetrying && (recoveryAction == .retry || recoveryAction == .restartSession)
                    ))
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        )
        .padding(.horizontal, 20)
    }
    
    private var errorIcon: Image {
        switch errorItem.error.severity {
        case .critical:
            return Image(systemName: "exclamationmark.triangle.fill")
        case .high:
            return Image(systemName: "exclamationmark.circle.fill")
        case .medium:
            return Image(systemName: "info.circle.fill")
        case .low:
            return Image(systemName: "info.circle")
        }
    }
    
    private var errorColor: Color {
        switch errorItem.error.severity {
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
    
    private var errorTitle: String {
        switch errorItem.error.errorCategory {
        case .ar:
            return "AR Issue"
        case .network:
            return "Connection Problem"
        case .modelLoading:
            return "Loading Error"
        case .storage:
            return "Storage Issue"
        case .authentication:
            return "Authentication Required"
        case .collaboration:
            return "Collaboration Issue"
        case .ai:
            return "AI Processing Error"
        case .ui:
            return "Interface Issue"
        case .system:
            return "System Error"
        }
    }
    
    private var errorSubtitle: String {
        let severityText = errorItem.error.severity.rawValue.capitalized
        let categoryText = errorItem.error.errorCategory.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        return "\(severityText) • \(categoryText)"
    }
    
    private func executeRecoveryAction(_ action: RecoveryAction) {
        switch action {
        case .retry, .retryWithDelay:
            onRetry()
        case .restartSession:
            onRetry() // For now, same as retry
        case .requestPermission:
            openAppSettings()
        case .goToSettings:
            openAppSettings()
        case .contactSupport:
            openSupportContact()
        case .none:
            onDismiss()
        }
    }
    
    private func openAppSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
    
    private func openSupportContact() {
        // This would open support contact options
        // For now, just dismiss
        onDismiss()
    }
}

// MARK: - Error Details View
struct ErrorDetailsView: View {
    let errorItem: ErrorQueueItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                DetailRow(label: "Error Code", value: errorItem.error.errorCode)
                DetailRow(label: "Category", value: errorItem.error.errorCategory.rawValue)
                DetailRow(label: "Severity", value: errorItem.error.severity.rawValue.capitalized)
                DetailRow(label: "Time", value: formatTimestamp(errorItem.timestamp))
                
                if errorItem.retryCount > 0 {
                    DetailRow(label: "Retry Count", value: "\(errorItem.retryCount)")
                }
            }
            .font(.caption)
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Button Styles
struct PrimaryErrorButtonStyle: ButtonStyle {
    let isLoading: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .foregroundColor(.white)
            }
            
            configuration.label
                .opacity(isLoading ? 0.7 : 1.0)
        }
        .font(.body.weight(.medium))
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.blue)
                .opacity(configuration.isPressed ? 0.8 : 1.0)
        )
        .disabled(isLoading)
    }
}

struct SecondaryErrorButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundColor(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Error Banner (for non-blocking errors)
struct ErrorBannerView: View {
    let errorItem: ErrorQueueItem
    let onDismiss: () -> Void
    
    @State private var dragOffset: CGSize = .zero
    @State private var isDismissed = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: errorIcon)
                .foregroundColor(errorColor)
                .font(.body.weight(.medium))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(errorTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(errorItem.error.userMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
                    .font(.caption.weight(.medium))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
        .offset(x: dragOffset.width)
        .opacity(isDismissed ? 0 : 1)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    if abs(value.translation.x) > 100 {
                        // Swipe to dismiss
                        withAnimation(.easeOut(duration: 0.3)) {
                            isDismissed = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onDismiss()
                        }
                    } else {
                        // Snap back
                        withAnimation(.spring()) {
                            dragOffset = .zero
                        }
                    }
                }
        )
    }
    
    private var errorIcon: String {
        switch errorItem.error.severity {
        case .critical:
            return "exclamationmark.triangle.fill"
        case .high:
            return "exclamationmark.circle.fill"
        case .medium:
            return "info.circle.fill"
        case .low:
            return "info.circle"
        }
    }
    
    private var errorColor: Color {
        switch errorItem.error.severity {
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
    
    private var errorTitle: String {
        switch errorItem.error.errorCategory {
        case .ar:
            return "AR Issue"
        case .network:
            return "Connection Problem"
        case .modelLoading:
            return "Loading Error"
        case .storage:
            return "Storage Issue"
        case .authentication:
            return "Authentication Required"
        case .collaboration:
            return "Collaboration Issue"
        case .ai:
            return "AI Processing Error"
        case .ui:
            return "Interface Issue"
        case .system:
            return "System Error"
        }
    }
}

// MARK: - Preview
#Preview {
    VStack {
        ErrorBannerView(
            errorItem: ErrorQueueItem(
                error: NetworkError.noConnection,
                context: [:]
            ),
            onDismiss: {}
        )
        .padding()
        
        Spacer()
    }
    .background(Color.gray.opacity(0.1))
}