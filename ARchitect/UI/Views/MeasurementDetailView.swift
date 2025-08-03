import SwiftUI

struct MeasurementDetailView: View {
    let measurement: Measurement
    @ObservedObject var measurementEngine: MeasurementEngine
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteAlert = false
    @State private var editingNotes = false
    @State private var notes: String
    
    init(measurement: Measurement, measurementEngine: MeasurementEngine) {
        self.measurement = measurement
        self.measurementEngine = measurementEngine
        self._notes = State(initialValue: measurement.notes)
    }
    
    var body: some View {
        NavigationView {
            List {
                // Measurement Value
                Section {
                    VStack(alignment: .center, spacing: 16) {
                        Image(systemName: measurement.type.icon)
                            .font(.system(size: 50))
                            .foregroundColor(Color(hex: measurement.color.hexValue))
                        
                        VStack(spacing: 8) {
                            Text(measurement.getValue(in: measurementEngine.unitSystem).formattedString)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            Text(measurement.type.displayName)
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                        
                        // Unit Conversion
                        unitConversionView
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
                
                // Measurement Details
                Section("Details") {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(measurement.name)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Type")
                        Spacer()
                        Text(measurement.type.displayName)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Created")
                        Spacer()
                        Text(measurement.timestamp.formatted(date: .complete, time: .shortened))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Points")
                        Spacer()
                        Text("\(measurement.points.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Color")
                        Spacer()
                        HStack {
                            Circle()
                                .fill(Color(hex: measurement.color.hexValue))
                                .frame(width: 20, height: 20)
                            Text(measurement.color.displayName)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Accuracy Information
                Section("Accuracy") {
                    HStack {
                        Text("Level")
                        Spacer()
                        HStack {
                            Image(systemName: measurement.accuracy.level.icon)
                                .foregroundColor(Color(measurement.accuracy.level.color))
                            Text(measurement.accuracy.level.rawValue.capitalized)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Confidence")
                        Spacer()
                        Text("\(Int(measurement.accuracy.confidenceScore * 100))%")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Error Margin")
                        Spacer()
                        Text("±\(String(format: "%.1f", measurement.accuracy.errorMargin * 100))cm")
                            .foregroundColor(.secondary)
                    }
                    
                    if !measurement.accuracy.factors.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Factors Affecting Accuracy")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            ForEach(measurement.accuracy.factors, id: \.self) { factor in
                                Text("• \(factor.description)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // Points Information
                Section("Measurement Points") {
                    ForEach(Array(measurement.points.enumerated()), id: \.offset) { index, point in
                        PointDetailRow(point: point, index: index + 1)
                    }
                }
                
                // Notes
                Section("Notes") {
                    if editingNotes {
                        VStack {
                            TextEditor(text: $notes)
                                .frame(minHeight: 100)
                            
                            HStack {
                                Button("Cancel") {
                                    notes = measurement.notes
                                    editingNotes = false
                                }
                                .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button("Save") {
                                    // Save notes (would need to implement in measurement engine)
                                    editingNotes = false
                                }
                                .fontWeight(.semibold)
                            }
                        }
                    } else {
                        if measurement.notes.isEmpty {
                            Button("Add Notes") {
                                editingNotes = true
                            }
                            .foregroundColor(.accentColor)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(measurement.notes)
                                
                                Button("Edit") {
                                    editingNotes = true
                                }
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
                
                // Actions
                Section("Actions") {
                    Button {
                        measurementEngine.updateMeasurementVisibility(measurement, isVisible: !measurement.isVisible)
                    } label: {
                        HStack {
                            Image(systemName: measurement.isVisible ? "eye.slash" : "eye")
                            Text(measurement.isVisible ? "Hide in AR" : "Show in AR")
                        }
                    }
                    
                    Button("Delete Measurement", role: .destructive) {
                        showingDeleteAlert = true
                    }
                }
            }
            .navigationTitle("Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Delete Measurement", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                measurementEngine.deleteMeasurement(measurement)
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    // MARK: - Unit Conversion View
    
    private var unitConversionView: some View {
        VStack(spacing: 8) {
            if measurementEngine.unitSystem == .metric {
                // Show imperial conversion
                let imperialValue = measurement.getValue(in: .imperial)
                Text(imperialValue.formattedString)
                    .font(.title3)
                    .foregroundColor(.secondary)
            } else {
                // Show metric conversion
                let metricValue = measurement.getValue(in: .metric)
                Text(metricValue.formattedString)
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Point Detail Row

struct PointDetailRow: View {
    let point: MeasurementPoint
    let index: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Point \(index)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(confidenceColor)
                        .font(.caption)
                    
                    Text("\(Int(point.confidence * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Position")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("X: \(String(format: "%.3f", point.position.x))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Y: \(String(format: "%.3f", point.position.y))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Z: \(String(format: "%.3f", point.position.z))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Quality")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Tracking: \(Int(point.trackingQuality * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(point.timestamp.formatted(date: .omitted, time: .complete))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var confidenceColor: Color {
        if point.confidence >= 0.8 {
            return .green
        } else if point.confidence >= 0.6 {
            return .yellow
        } else {
            return .red
        }
    }
}

#Preview {
    let sessionManager = ARSessionManager()
    let measurementEngine = MeasurementEngine(sessionManager: sessionManager)
    
    // Create sample measurement
    let samplePoints = [
        MeasurementPoint(
            position: simd_float3(0, 0, 0),
            worldTransform: matrix_identity_float4x4,
            confidence: 0.9,
            trackingQuality: 0.8
        ),
        MeasurementPoint(
            position: simd_float3(1, 0, 0),
            worldTransform: matrix_identity_float4x4,
            confidence: 0.85,
            trackingQuality: 0.8
        )
    ]
    
    let sampleMeasurement = Measurement(
        type: .distance,
        name: "Sample Distance",
        points: samplePoints,
        value: MeasurementValue(primary: 1.0, unit: .meters, unitSystem: .metric),
        accuracy: MeasurementAccuracy(
            level: .good,
            confidenceScore: 0.85,
            errorMargin: 0.02
        ),
        trackingQuality: 0.8,
        sessionState: "running",
        notes: "This is a sample measurement for preview purposes."
    )
    
    return MeasurementDetailView(
        measurement: sampleMeasurement,
        measurementEngine: measurementEngine
    )
}