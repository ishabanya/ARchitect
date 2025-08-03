import SwiftUI
import ARKit
import Combine

// MARK: - Room Scanning View
public struct RoomScanningView: View {
    @StateObject private var scanner: RoomScanner
    @StateObject private var recoveryManager: ScanRecoveryManager
    @ObservedObject private var sessionManager: ARSessionManager
    @ObservedObject private var dataManager = ScanDataManager.shared
    
    @State private var showingSettings = false
    @State private var showingRecovery = false
    @State private var showingSaveDialog = false
    @State private var showingLoadDialog = false
    @State private var scanName = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    private let settings: ScanSettings
    
    public init(sessionManager: ARSessionManager, settings: ScanSettings = .default) {
        self.sessionManager = sessionManager
        self.settings = settings
        
        let scanner = RoomScanner(sessionManager: sessionManager, settings: settings)
        let recoveryManager = ScanRecoveryManager(scanner: scanner, sessionManager: sessionManager)
        
        self._scanner = StateObject(wrappedValue: scanner)
        self._recoveryManager = StateObject(wrappedValue: recoveryManager)
    }
    
    public var body: some View {
        ZStack {
            // Main scanning interface
            ScanVisualFeedback(scanner: scanner, sessionManager: sessionManager)
                .ignoresSafeArea()
            
            // Recovery overlay
            if recoveryManager.canRecover || recoveryManager.recoveryState == .recovering {
                recoveryOverlay
            }
            
            // Scan completed overlay
            if scanner.scanState == .completed {
                scanCompletedOverlay
            }
            
            // Loading overlay
            if dataManager.isLoading {
                loadingOverlay
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            setupScanning()
        }
        .onDisappear {
            cleanupScanning()
        }
        .sheet(isPresented: $showingSettings) {
            ScanSettingsView(settings: settings)
        }
        .sheet(isPresented: $showingRecovery) {
            ScanRecoveryView(recoveryManager: recoveryManager)
        }
        .sheet(isPresented: $showingSaveDialog) {
            SaveScanView(scanner: scanner, scanName: $scanName) { success in
                if success {
                    alertMessage = "Scan saved successfully!"
                } else {
                    alertMessage = "Failed to save scan"
                }
                showingAlert = true
            }
        }
        .sheet(isPresented: $showingLoadDialog) {
            LoadScanView(dataManager: dataManager)
        }
        .alert("Scan Status", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Recovery Overlay
    private var recoveryOverlay: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                // Recovery status
                recoveryStatusCard
                
                // Recovery actions
                if recoveryManager.recoveryState == .needsRecovery {
                    recoveryActionsCard
                }
            }
            .padding()
        }
        .background(Color.black.opacity(0.3))
        .ignoresSafeArea()
    }
    
    private var recoveryStatusCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: recoveryStatusIcon)
                    .foregroundColor(recoveryStatusColor)
                    .font(.title2)
                
                Text(recoveryManager.recoveryState.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if recoveryManager.recoveryState == .recovering {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if let progress = recoveryManager.recoveryProgress {
                VStack(spacing: 8) {
                    HStack {
                        Text(progress.phase.displayName)
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Text("\(Int(progress.completionPercentage * 100))%")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    ProgressView(value: progress.completionPercentage)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    
                    if progress.estimatedTimeRemaining > 0 {
                        Text("~\(Int(progress.estimatedTimeRemaining))s remaining")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let error = progress.error {
                        Text("Error: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            if !recoveryManager.recoveryRecommendations.isEmpty {
                Button("View Recommendations") {
                    showingRecovery = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(radius: 8)
        )
    }
    
    private var recoveryActionsCard: some View {
        VStack(spacing: 12) {
            Text("Recovery Actions")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 12) {
                Button("Auto Recover") {
                    Task {
                        await recoveryManager.attemptRecovery()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button("Manual Fix") {
                    showingRecovery = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Continue Anyway") {
                    // Continue with current scan state
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(radius: 8)
        )
    }
    
    // MARK: - Scan Completed Overlay
    private var scanCompletedOverlay: some View {
        VStack {
            Spacer()
            
            scanResultsCard
            
            Spacer()
        }
        .background(Color.black.opacity(0.4))
        .ignoresSafeArea()
    }
    
    private var scanResultsCard: some View {
        VStack(spacing: 20) {
            // Success indicator
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Scan Complete!")
                    .font(.title)
                    .fontWeight(.bold)
                
                if let quality = scanner.scanQuality {
                    QualityBadge(quality: quality)
                }
            }
            
            // Scan summary
            if let dimensions = scanner.roomDimensions,
               let quality = scanner.scanQuality {
                scanSummary(dimensions: dimensions, quality: quality)
            }
            
            // Action buttons
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button("Save Scan") {
                        scanName = "Room \(Date().formatted(date: .abbreviated, time: .shortened))"
                        showingSaveDialog = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button("Rescan") {
                        resetScanning()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                
                Button("View Details") {
                    // Show detailed scan results
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundColor(.blue)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(radius: 12)
        )
        .padding(.horizontal, 20)
    }
    
    private func scanSummary(dimensions: RoomDimensions, quality: ScanQuality) -> some View {
        VStack(spacing: 12) {
            Text("Room Summary")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 20) {
                summaryItem("Area", value: dimensions.displayArea, icon: "square")
                summaryItem("Height", value: dimensions.displayHeight, icon: "arrow.up.and.down")
                summaryItem("Quality", value: "\(Int(quality.overallScore * 100))%", icon: "star.fill")
            }
            
            HStack(spacing: 20) {
                summaryItem("Planes", value: "\(scanner.mergedPlanes.count)", icon: "rectangle.stack")
                summaryItem("Duration", value: formatDuration(scanner.scanProgress.scanDuration), icon: "clock")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private func summaryItem(_ title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Loading Overlay
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                
                Text("Processing...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
            )
        }
    }
    
    // MARK: - Computed Properties
    private var recoveryStatusIcon: String {
        switch recoveryManager.recoveryState {
        case .monitoring: return "eye"
        case .needsRecovery: return "exclamationmark.triangle"
        case .recovering: return "arrow.clockwise"
        case .recovered: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .none: return "circle"
        }
    }
    
    private var recoveryStatusColor: Color {
        switch recoveryManager.recoveryState {
        case .monitoring: return .blue
        case .needsRecovery: return .orange
        case .recovering: return .blue
        case .recovered: return .green
        case .failed: return .red
        case .none: return .gray
        }
    }
    
    // MARK: - Methods
    private func setupScanning() {
        // Setup is handled automatically by the scanner
    }
    
    private func cleanupScanning() {
        if scanner.isScanning {
            scanner.stopScanning()
        }
        recoveryManager.stopMonitoring()
    }
    
    private func resetScanning() {
        scanner.cancelScanning()
        recoveryManager.stopMonitoring()
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Quality Badge
struct QualityBadge: View {
    let quality: ScanQuality
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: gradeIcon)
                .foregroundColor(.white)
            
            Text(quality.grade.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(gradeColor)
        )
    }
    
    private var gradeIcon: String {
        switch quality.grade {
        case .excellent: return "star.fill"
        case .good: return "checkmark.circle.fill"
        case .fair: return "minus.circle.fill"
        case .poor: return "exclamationmark.triangle.fill"
        case .incomplete: return "xmark.circle.fill"
        }
    }
    
    private var gradeColor: Color {
        switch quality.grade {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .yellow
        case .poor: return .orange
        case .incomplete: return .red
        }
    }
}

// MARK: - Save Scan View
struct SaveScanView: View {
    let scanner: RoomScanner
    @Binding var scanName: String
    let onSave: (Bool) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var isValidName = true
    @State private var isSaving = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Text("Save Room Scan")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let quality = scanner.scanQuality {
                        QualityBadge(quality: quality)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scan Name")
                        .font(.headline)
                    
                    TextField("Enter scan name", text: $scanName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: scanName) { _ in
                            isValidName = !scanName.trimmingCharacters(in: .whitespaces).isEmpty
                        }
                    
                    if !isValidName {
                        Text("Please enter a valid name")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                if let dimensions = scanner.roomDimensions {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Room Details")
                            .font(.headline)
                        
                        VStack(spacing: 4) {
                            HStack {
                                Text("Area:")
                                Spacer()
                                Text(dimensions.displayArea)
                                    .fontWeight(.medium)
                            }
                            
                            HStack {
                                Text("Dimensions:")
                                Spacer()
                                Text("\(dimensions.displayWidth) × \(dimensions.displayLength)")
                                    .fontWeight(.medium)
                            }
                            
                            HStack {
                                Text("Height:")
                                Spacer()
                                Text(dimensions.displayHeight)
                                    .fontWeight(.medium)
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                
                Spacer()
                
                Button("Save Scan") {
                    saveScan()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!isValidName || isSaving)
                .opacity(isSaving ? 0.6 : 1.0)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func saveScan() {
        guard let currentScan = scanner.getCurrentScan(name: scanName.trimmingCharacters(in: .whitespaces)) else {
            onSave(false)
            dismiss()
            return
        }
        
        isSaving = true
        
        Task {
            do {
                try await ScanDataManager.shared.saveScan(currentScan)
                
                await MainActor.run {
                    onSave(true)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    onSave(false)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Load Scan View
struct LoadScanView: View {
    @ObservedObject var dataManager: ScanDataManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(dataManager.savedScans) { scan in
                    ScanListItem(scan: scan) {
                        // Load scan action
                        dismiss()
                    }
                }
                .onDelete(perform: deleteScans)
            }
            .navigationTitle("Saved Scans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
    }
    
    private func deleteScans(offsets: IndexSet) {
        for index in offsets {
            let scan = dataManager.savedScans[index]
            Task {
                try? await dataManager.deleteScan(id: scan.id)
            }
        }
    }
}

// MARK: - Scan List Item
struct ScanListItem: View {
    let scan: RoomScan
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scan.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(scan.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        Label(scan.roomDimensions.displayArea, systemImage: "square")
                        Label("\(Int(scan.scanQuality.overallScore * 100))%", systemImage: "star.fill")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                QualityBadge(quality: scan.scanQuality)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview
#if DEBUG
struct RoomScanningView_Previews: PreviewProvider {
    static var previews: some View {
        RoomScanningView(sessionManager: ARSessionManager())
    }
}
#endif