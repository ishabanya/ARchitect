import SwiftUI

struct MeasurementHistoryView: View {
    @ObservedObject var measurementEngine: MeasurementEngine
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedSession: MeasurementSession?
    @State private var showingExportSheet = false
    @State private var showingBackupSheet = false
    
    var body: some View {
        NavigationView {
            VStack {
                if measurementEngine.measurementHistory.sessions.isEmpty {
                    emptyStateView
                } else {
                    historyContentView
                }
            }
            .navigationTitle("Measurement History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingExportSheet = true
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        
                        Button {
                            showingBackupSheet = true
                        } label: {
                            Label("Backup", systemImage: "arrow.clockwise.icloud")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search measurements")
        }
        .sheet(item: $selectedSession) { session in
            MeasurementSessionDetailView(
                session: session,
                measurementEngine: measurementEngine
            )
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportMeasurementsView(measurementEngine: measurementEngine)
        }
        .sheet(isPresented: $showingBackupSheet) {
            BackupManagementView(measurementEngine: measurementEngine)
        }
    }
    
    // MARK: - Views
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "ruler")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Measurements Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Start taking measurements to see your history here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var historyContentView: some View {
        VStack {
            // Statistics
            statisticsView
            
            // Sessions List
            List {
                ForEach(filteredSessions) { session in
                    MeasurementSessionRow(session: session) {
                        selectedSession = session
                    }
                }
            }
        }
    }
    
    private var statisticsView: some View {
        let stats = measurementEngine.measurementHistory.statistics
        
        HStack(spacing: 20) {
            StatisticView(
                title: "Sessions",
                value: "\(stats.totalSessions)",
                icon: "folder"
            )
            
            StatisticView(
                title: "Measurements",
                value: "\(stats.totalMeasurements)",
                icon: "ruler"
            )
            
            StatisticView(
                title: "Accuracy",
                value: "\(stats.accuracyPercentage)%",
                icon: "checkmark.circle"
            )
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
    
    private var filteredSessions: [MeasurementSession] {
        if searchText.isEmpty {
            return measurementEngine.measurementHistory.sessions
        } else {
            return measurementEngine.measurementHistory.sessions.filter { session in
                session.name.localizedCaseInsensitiveContains(searchText) ||
                session.measurements.contains { measurement in
                    measurement.name.localizedCaseInsensitiveContains(searchText) ||
                    measurement.notes.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
    }
}

// MARK: - Statistics View

struct StatisticView: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Session Row

struct MeasurementSessionRow: View {
    let session: MeasurementSession
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(session.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(session.timestamp.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 16) {
                    Label("\(session.measurements.count)", systemImage: "ruler")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label("\(session.accurateMeasurementsCount) accurate", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !session.notes.isEmpty {
                        Label("Notes", systemImage: "note.text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !session.measurements.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(session.measurements.prefix(5)) { measurement in
                                MeasurementTypeChip(measurement: measurement)
                            }
                            
                            if session.measurements.count > 5 {
                                Text("+\(session.measurements.count - 5)")
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Measurement Type Chip

struct MeasurementTypeChip: View {
    let measurement: Measurement
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: measurement.type.icon)
                .font(.caption2)
            
            Text(measurement.type.displayName)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(hex: measurement.color.hexValue).opacity(0.2))
        .foregroundColor(Color(hex: measurement.color.hexValue))
        .clipShape(Capsule())
    }
}

// MARK: - Session Detail View

struct MeasurementSessionDetailView: View {
    let session: MeasurementSession
    @ObservedObject var measurementEngine: MeasurementEngine
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMeasurement: Measurement?
    
    var body: some View {
        NavigationView {
            List {
                // Session Info
                Section("Session Details") {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(session.name)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Date")
                        Spacer()
                        Text(session.timestamp.formatted(date: .complete, time: .shortened))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Unit System")
                        Spacer()
                        Text(session.preferredUnitSystem.displayName)
                            .foregroundColor(.secondary)
                    }
                    
                    if !session.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(session.notes)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Session Statistics
                Section("Statistics") {
                    let summary = session.summary
                    
                    HStack {
                        Text("Total Measurements")
                        Spacer()
                        Text("\(summary.totalMeasurements)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Accurate Measurements")
                        Spacer()
                        Text("\(summary.accurateMeasurements)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Average Accuracy")
                        Spacer()
                        Text("\(summary.accuracyPercentage)%")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Measurement Types")
                        Spacer()
                        Text("\(summary.measurementTypes)")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Measurements
                if !session.measurements.isEmpty {
                    Section("Measurements") {
                        ForEach(session.measurements) { measurement in
                            MeasurementDetailRow(
                                measurement: measurement,
                                unitSystem: session.preferredUnitSystem
                            ) {
                                selectedMeasurement = measurement
                            }
                        }
                    }
                }
            }
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $selectedMeasurement) { measurement in
            MeasurementDetailView(
                measurement: measurement,
                measurementEngine: measurementEngine
            )
        }
    }
}

// MARK: - Measurement Detail Row

struct MeasurementDetailRow: View {
    let measurement: Measurement
    let unitSystem: UnitSystem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: measurement.type.icon)
                            .foregroundColor(Color(hex: measurement.color.hexValue))
                        
                        Text(measurement.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        AccuracyIndicator(accuracy: measurement.accuracy)
                    }
                    
                    Text(measurement.getValue(in: unitSystem).formattedString)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(measurement.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MeasurementHistoryView(measurementEngine: MeasurementEngine(sessionManager: ARSessionManager()))
}