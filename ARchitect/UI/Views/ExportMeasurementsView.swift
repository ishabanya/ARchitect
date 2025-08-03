import SwiftUI
import UniformTypeIdentifiers

struct ExportMeasurementsView: View {
    @ObservedObject var measurementEngine: MeasurementEngine
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .json
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var showingShareSheet = false
    @State private var exportError: Error?
    @State private var showingErrorAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Export Options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Export Format")
                        .font(.headline)
                    
                    VStack(spacing: 12) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            ExportFormatRow(
                                format: format,
                                isSelected: selectedFormat == format
                            ) {
                                selectedFormat = format
                            }
                        }
                    }
                }
                
                // Export Summary
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export Summary")
                        .font(.headline)
                    
                    let stats = measurementEngine.measurementHistory.statistics
                    
                    HStack {
                        Text("Sessions:")
                        Spacer()
                        Text("\(stats.totalSessions)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Measurements:")
                        Spacer()
                        Text("\(stats.totalMeasurements)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("File format:")
                        Spacer()
                        Text(selectedFormat.displayName)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Spacer()
                
                // Export Button
                Button {
                    exportMeasurements()
                } label: {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        
                        Text(isExporting ? "Exporting..." : "Export Measurements")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isExporting || measurementEngine.measurementHistory.sessions.isEmpty)
            }
            .padding()
            .navigationTitle("Export Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Export Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            if let error = exportError {
                Text(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Methods
    
    private func exportMeasurements() {
        isExporting = true
        
        Task {
            do {
                let url = try await measurementEngine.exportMeasurementHistory(format: selectedFormat)
                
                await MainActor.run {
                    exportedURL = url
                    showingShareSheet = true
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    exportError = error
                    showingErrorAlert = true
                    isExporting = false
                }
            }
        }
    }
}

// MARK: - Export Format Row

struct ExportFormatRow: View {
    let format: ExportFormat
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: formatIcon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(format.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(formatDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .font(.headline)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(.systemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
    
    private var formatIcon: String {
        switch format {
        case .json: return "doc.text"
        case .csv: return "tablecells"
        }
    }
    
    private var formatDescription: String {
        switch format {
        case .json: return "Complete data with all measurement details"
        case .csv: return "Spreadsheet format for analysis"
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

// MARK: - Backup Management View

struct BackupManagementView: View {
    @ObservedObject var measurementEngine: MeasurementEngine
    @Environment(\.dismiss) private var dismiss
    @State private var availableBackups: [BackupInfo] = []
    @State private var isLoading = false
    @State private var showingRestoreAlert = false
    @State private var selectedBackup: BackupInfo?
    @State private var errorMessage: String?
    @State private var showingErrorAlert = false
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading backups...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if availableBackups.isEmpty {
                    emptyBackupsView
                } else {
                    backupsListView
                }
            }
            .navigationTitle("Backup Management")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create Backup") {
                        createBackup()
                    }
                    .disabled(isLoading)
                }
            }
        }
        .onAppear {
            loadBackups()
        }
        .alert("Restore Backup", isPresented: $showingRestoreAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Restore", role: .destructive) {
                if let backup = selectedBackup {
                    restoreBackup(backup)
                }
            }
        } message: {
            Text("This will replace your current measurement history. This action cannot be undone.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }
    
    // MARK: - Views
    
    private var emptyBackupsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Backups Available")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create a backup to protect your measurement data")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Create First Backup") {
                createBackup()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var backupsListView: some View {
        List {
            ForEach(availableBackups) { backup in
                BackupRow(backup: backup) {
                    selectedBackup = backup
                    showingRestoreAlert = true
                }
            }
        }
    }
    
    // MARK: - Methods
    
    private func loadBackups() {
        isLoading = true
        
        Task {
            do {
                let backups = try await measurementEngine.getAvailableBackups()
                
                await MainActor.run {
                    availableBackups = backups
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                    isLoading = false
                }
            }
        }
    }
    
    private func createBackup() {
        isLoading = true
        
        Task {
            do {
                _ = try await measurementEngine.createBackup()
                loadBackups() // Refresh the list
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                    isLoading = false
                }
            }
        }
    }
    
    private func restoreBackup(_ backup: BackupInfo) {
        isLoading = true
        
        Task {
            do {
                try await measurementEngine.restoreFromBackup(backup)
                
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Backup Row

struct BackupRow: View {
    let backup: BackupInfo
    let onRestore: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(backup.filename)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(backup.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(backup.formattedSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Restore") {
                onRestore()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ExportMeasurementsView(measurementEngine: MeasurementEngine(sessionManager: ARSessionManager()))
}