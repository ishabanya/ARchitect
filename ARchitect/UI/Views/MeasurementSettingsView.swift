import SwiftUI

struct MeasurementSettingsView: View {
    @ObservedObject var measurementEngine: MeasurementEngine
    @ObservedObject var annotations: MeasurementAnnotations
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                // Unit System
                Section("Units") {
                    Picker("Unit System", selection: $measurementEngine.unitSystem) {
                        ForEach(UnitSystem.allCases, id: \.self) { system in
                            Text(system.displayName).tag(system)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: measurementEngine.unitSystem) { newSystem in
                        measurementEngine.changeUnitSystem(newSystem)
                    }
                }
                
                // Annotation Settings
                Section("Annotations") {
                    Toggle("Show Labels", isOn: $annotations.annotationSettings.showLabels)
                    Toggle("Show Points", isOn: $annotations.annotationSettings.showPoints)
                    Toggle("Show Lines", isOn: $annotations.annotationSettings.showLines)
                    Toggle("Show Fill Areas", isOn: $annotations.annotationSettings.showFill)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Label Scale")
                        Slider(
                            value: $annotations.annotationSettings.labelScale,
                            in: 0.5...2.0,
                            step: 0.1
                        ) {
                            Text("Label Scale")
                        } minimumValueLabel: {
                            Text("0.5x")
                                .font(.caption)
                        } maximumValueLabel: {
                            Text("2.0x")
                                .font(.caption)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fade Distance: \(String(format: "%.1f", annotations.annotationSettings.fadeDistance))m")
                        Slider(
                            value: $annotations.annotationSettings.fadeDistance,
                            in: 1.0...20.0,
                            step: 0.5
                        )
                    }
                }
                .onChange(of: annotations.annotationSettings) { newSettings in
                    annotations.updateAnnotationSettings(newSettings)
                }
                
                // Measurement History
                Section("History") {
                    NavigationLink("View History") {
                        MeasurementHistoryView(measurementEngine: measurementEngine)
                    }
                    
                    Button("Create Backup") {
                        Task {
                            do {
                                let backupURL = try await measurementEngine.createBackup()
                                // Show success message or share sheet
                            } catch {
                                // Show error
                            }
                        }
                    }
                    
                    Button("Clear All Data", role: .destructive) {
                        // Show confirmation dialog
                    }
                }
                
                // Storage Information
                Section("Storage") {
                    let persistence = MeasurementPersistence.shared
                    let stats = persistence.storageStatistics
                    
                    HStack {
                        Text("Total Size")
                        Spacer()
                        Text(stats.formattedTotalSize)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Backups")
                        Spacer()
                        Text("\(stats.backupCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    if let lastModified = stats.lastModified {
                        HStack {
                            Text("Last Modified")
                            Spacer()
                            Text(lastModified.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Active Measurements")
                        Spacer()
                        Text("\(measurementEngine.activeMeasurements.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Total Sessions")
                        Spacer()
                        Text("\(measurementEngine.measurementHistory.sessions.count)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
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
}

#Preview {
    MeasurementSettingsView(
        measurementEngine: MeasurementEngine(sessionManager: ARSessionManager()),
        annotations: MeasurementAnnotations()
    )
}