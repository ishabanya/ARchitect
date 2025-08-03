import SwiftUI

// MARK: - Scan Recovery View
struct ScanRecoveryView: View {
    @ObservedObject var recoveryManager: ScanRecoveryManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                recoveryHeader
                
                // Content
                ScrollView {
                    VStack(spacing: 20) {
                        // Current Status
                        currentStatusCard
                        
                        // Recommendations
                        if !recoveryManager.recoveryRecommendations.isEmpty {
                            recommendationsSection
                        }
                        
                        // Recovery Progress
                        if let progress = recoveryManager.recoveryProgress {
                            recoveryProgressCard(progress)
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if recoveryManager.canRecover {
                        Button("Auto Recover") {
                            Task {
                                await recoveryManager.attemptRecovery()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
    }
    
    // MARK: - Header
    private var recoveryHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: headerIcon)
                    .font(.title)
                    .foregroundColor(headerColor)
                
                Text("Scan Recovery")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(headerColor.opacity(0.1))
    }
    
    private var headerIcon: String {
        switch recoveryManager.recoveryState {
        case .monitoring: return "shield.checkered"
        case .needsRecovery: return "exclamationmark.shield"
        case .recovering: return "arrow.clockwise.circle"
        case .recovered: return "checkmark.shield"
        case .failed: return "xmark.shield"
        case .none: return "shield"
        }
    }
    
    private var headerColor: Color {
        switch recoveryManager.recoveryState {
        case .monitoring: return .blue
        case .needsRecovery: return .orange
        case .recovering: return .blue
        case .recovered: return .green
        case .failed: return .red
        case .none: return .gray
        }
    }
    
    private var headerSubtitle: String {
        switch recoveryManager.recoveryState {
        case .monitoring:
            return "Monitoring scan quality and detecting issues"
        case .needsRecovery:
            return "Issues detected that may affect scan quality"
        case .recovering:
            return "Attempting to resolve detected issues"
        case .recovered:
            return "Recovery completed successfully"
        case .failed:
            return "Recovery attempt failed - manual intervention may be needed"
        case .none:
            return "Recovery system not active"
        }
    }
    
    // MARK: - Current Status
    private var currentStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Current Status")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recovery State")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(recoveryManager.recoveryState.displayName)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(headerColor)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Can Recover")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: recoveryManager.canRecover ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(recoveryManager.canRecover ? .green : .red)
                        
                        Text(recoveryManager.canRecover ? "Yes" : "No")
                            .font(.title3)
                            .fontWeight(.medium)
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
    
    // MARK: - Recommendations Section
    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recovery Recommendations")
                .font(.headline)
                .fontWeight(.semibold)
            
            ForEach(recoveryManager.recoveryRecommendations) { recommendation in
                RecommendationCard(recommendation: recommendation)
            }
        }
    }
    
    // MARK: - Recovery Progress
    private func recoveryProgressCard(_ progress: RecoveryProgress) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recovery Progress")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                HStack {
                    Text(progress.phase.displayName)
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Text("\(Int(progress.completionPercentage * 100))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                ProgressView(value: progress.completionPercentage)
                    .progressViewStyle(LinearProgressViewStyle(tint: headerColor))
                
                if progress.estimatedTimeRemaining > 0 {
                    HStack {
                        Text("Estimated time remaining:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(Int(progress.estimatedTimeRemaining))s")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                
                if let error = progress.error {
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 8)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Recommendation Card
struct RecommendationCard: View {
    let recommendation: RecoveryRecommendation
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    // Priority indicator
                    Circle()
                        .fill(priorityColor)
                        .frame(width: 12, height: 12)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recommendation.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text(recommendation.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(recommendation.estimatedTime))s")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            
            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actions to take:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    ForEach(Array(recommendation.actions.enumerated()), id: \.offset) { index, action in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 16, alignment: .leading)
                            
                            Text(action)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .slide))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(priorityColor.opacity(0.3), lineWidth: 1)
                .fill(priorityColor.opacity(0.05))
        )
    }
    
    private var priorityColor: Color {
        switch recommendation.priority {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }
}

// MARK: - Preview
#if DEBUG
struct ScanRecoveryView_Previews: PreviewProvider {
    static var previews: some View {
        ScanRecoveryView(
            recoveryManager: ScanRecoveryManager(
                scanner: RoomScanner(sessionManager: ARSessionManager()),
                sessionManager: ARSessionManager()
            )
        )
    }
}
#endif