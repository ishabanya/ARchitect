import SwiftUI
import ARKit
import RealityKit

struct MeasurementToolsView: View {
    @StateObject private var measurementEngine: MeasurementEngine
    @StateObject private var annotations = MeasurementAnnotations()
    @State private var showingModeSelector = false
    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var showingExportSheet = false
    @State private var selectedMeasurement: Measurement?
    @State private var isInstructionsVisible = true
    
    private let sessionManager: ARSessionManager
    
    init(sessionManager: ARSessionManager) {
        self.sessionManager = sessionManager
        self._measurementEngine = StateObject(wrappedValue: MeasurementEngine(sessionManager: sessionManager))
    }
    
    var body: some View {
        ZStack {
            // AR View
            ARViewContainer(
                sessionManager: sessionManager,
                measurementEngine: measurementEngine,
                annotations: annotations
            )
            .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top Controls
                topControlsView
                
                Spacer()
                
                // Instructions
                if isInstructionsVisible {
                    instructionsView
                        .transition(.opacity)
                }
                
                Spacer()
                
                // Bottom Controls
                bottomControlsView
            }
            .padding()
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingModeSelector) {
            MeasurementModeSelector(
                selectedMode: $measurementEngine.measurementMode,
                unitSystem: measurementEngine.unitSystem
            )
        }
        .sheet(isPresented: $showingSettings) {
            MeasurementSettingsView(
                measurementEngine: measurementEngine,
                annotations: annotations
            )
        }
        .sheet(isPresented: $showingHistory) {
            MeasurementHistoryView(measurementEngine: measurementEngine)
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportMeasurementsView(measurementEngine: measurementEngine)
        }
        .sheet(item: $selectedMeasurement) { measurement in
            MeasurementDetailView(
                measurement: measurement,
                measurementEngine: measurementEngine
            )
        }
        .onAppear {
            annotations.setARView(sessionManager.arView)
            startMeasurementSession()
        }
        .onDisappear {
            measurementEngine.endMeasurementSession()
        }
    }
    
    // MARK: - UI Components
    
    private var topControlsView: some View {
        HStack {
            // Back Button
            Button {
                // Handle back navigation
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.black.opacity(0.3)))
            }
            
            Spacer()
            
            // AR Status
            ARStatusIndicator(sessionManager: sessionManager)
            
            Spacer()
            
            // Settings Button
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.black.opacity(0.3)))
            }
        }
    }
    
    private var instructionsView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: measurementEngine.measurementMode.icon)
                    .foregroundColor(.white)
                
                Text(measurementEngine.measurementMode.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    withAnimation {
                        isInstructionsVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Text(measurementEngine.measurementMode.instructions)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.leading)
            
            if measurementEngine.isCapturing {
                ProgressView("Capturing...", value: measurementEngine.captureProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .white))
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.3))
        )
    }
    
    private var bottomControlsView: some View {
        VStack(spacing: 16) {
            // Active Measurements
            if !measurementEngine.activeMeasurements.isEmpty {
                activeMeasurementsView
            }
            
            // Control Buttons
            HStack(spacing: 20) {
                // History Button
                Button {
                    showingHistory = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.title2)
                        Text("History")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(.black.opacity(0.3)))
                }
                
                // Cancel Button (if measurement in progress)
                if !measurementEngine.currentPoints.isEmpty {
                    Button {
                        measurementEngine.cancelCurrentMeasurement()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.title2)
                            Text("Cancel")
                                .font(.caption2)
                        }
                        .foregroundColor(.red)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(.black.opacity(0.3)))
                    }
                }
                
                // Complete Button (for multi-point measurements)
                if shouldShowCompleteButton {
                    Button {
                        Task {
                            await measurementEngine.completeMeasurement()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.title2)
                            Text("Complete")
                                .font(.caption2)
                        }
                        .foregroundColor(.green)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(.black.opacity(0.3)))
                    }
                }
                
                // Mode Selector
                Button {
                    showingModeSelector = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: measurementEngine.measurementMode.icon)
                            .font(.title2)
                        Text("Mode")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(.black.opacity(0.3)))
                }
                
                // Export Button
                Button {
                    showingExportSheet = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2)
                        Text("Export")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(.black.opacity(0.3)))
                }
            }
        }
    }
    
    private var activeMeasurementsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(measurementEngine.activeMeasurements) { measurement in
                    MeasurementCard(
                        measurement: measurement,
                        unitSystem: measurementEngine.unitSystem
                    ) {
                        selectedMeasurement = measurement
                    }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 100)
    }
    
    private var shouldShowCompleteButton: Bool {
        let currentPoints = measurementEngine.currentPoints.count
        let requiredPoints = measurementEngine.measurementMode.type.minimumPoints
        
        switch measurementEngine.measurementMode.type {
        case .area, .volume, .perimeter:
            return currentPoints >= requiredPoints
        default:
            return false // Auto-complete for distance, height, angle
        }
    }
    
    // MARK: - Helper Methods
    
    private func startMeasurementSession() {
        let sessionName = "Measurement Session \(Date().formatted(date: .abbreviated, time: .shortened))"
        measurementEngine.startMeasurementSession(name: sessionName)
    }
}

// MARK: - AR View Container

struct ARViewContainer: UIViewRepresentable {
    let sessionManager: ARSessionManager
    let measurementEngine: MeasurementEngine
    let annotations: MeasurementAnnotations
    
    func makeUIView(context: Context) -> ARView {
        let arView = sessionManager.arView
        
        // Add tap gesture for placing measurement points
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.measurementEngine = measurementEngine
        context.coordinator.annotations = annotations
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(measurementEngine: measurementEngine, annotations: annotations)
    }
    
    class Coordinator: NSObject {
        var measurementEngine: MeasurementEngine
        var annotations: MeasurementAnnotations
        
        init(measurementEngine: MeasurementEngine, annotations: MeasurementAnnotations) {
            self.measurementEngine = measurementEngine
            self.annotations = annotations
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            
            Task {
                let success = await measurementEngine.addMeasurementPoint(at: location)
                if success, let currentMeasurement = measurementEngine.currentMeasurement {
                    await MainActor.run {
                        annotations.addMeasurementAnnotation(for: currentMeasurement)
                    }
                }
            }
        }
    }
}

// MARK: - AR Status Indicator

struct ARStatusIndicator: View {
    @ObservedObject var sessionManager: ARSessionManager
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(sessionManager.trackingQuality.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Text("\(sessionManager.detectedPlanes.count) planes")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.black.opacity(0.3))
        )
    }
    
    private var statusColor: Color {
        switch sessionManager.trackingQuality {
        case .normal:
            return .green
        case .limited:
            return .yellow
        case .unavailable:
            return .red
        @unknown default:
            return .gray
        }
    }
}

// MARK: - Measurement Card

struct MeasurementCard: View {
    let measurement: Measurement
    let unitSystem: UnitSystem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: measurement.type.icon)
                        .foregroundColor(Color(hex: measurement.color.hexValue))
                    
                    Text(measurement.type.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    AccuracyIndicator(accuracy: measurement.accuracy)
                }
                
                Text(measurement.getValue(in: unitSystem).formattedString)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(measurement.name)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(12)
            .frame(width: 140, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Accuracy Indicator

struct AccuracyIndicator: View {
    let accuracy: MeasurementAccuracy
    
    var body: some View {
        Image(systemName: accuracy.level.icon)
            .foregroundColor(Color(accuracy.level.color))
            .font(.caption2)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}