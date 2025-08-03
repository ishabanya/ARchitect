import SwiftUI
import ARKit
import RealityKit
import Vision

// Simple object detection struct for this view
struct SimpleDetectedObject: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect
    let timestamp: Date
    
    var confidencePercentage: Int {
        return Int(confidence * 100)
    }
}

struct RealMeasurementView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var isPlaneDetectionEnabled = true
    @State private var detectedPlanes: [DetectedPlane] = []
    @State private var measurements: [ARMeasurement] = []
    @State private var measurementPairs: [MeasurementPair] = []
    @State private var currentMeasurementPoints: [ARMeasurement] = []
    @State private var showingMeasurements = false
    @State private var detectedObjects: [SimpleDetectedObject] = []
    @State private var isObjectDetectionEnabled = false
    @State private var selectedMode: MeasurementMode = .distance
    
    var body: some View {
        ZStack {
            // AR Camera View
            ARMeasurementContainer(
                measurements: $measurements,
                measurementPairs: $measurementPairs,
                currentPoints: $currentMeasurementPoints,
                detectedObjects: $detectedObjects,
                selectedMode: $selectedMode,
                isObjectDetectionEnabled: $isObjectDetectionEnabled
            )
            .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top Bar
                topBar
                
                Spacer()
                
                // Mode Selector
                modeSelector
                
                // Detection Results
                if selectedMode == .objectDetection && !detectedObjects.isEmpty {
                    detectionResultsView
                }
                
                // Instructions
                instructionsView
                
                Spacer()
                
                // Bottom Controls
                bottomControls
            }
            .padding()
            
            // Measurements Panel
            if showingMeasurements {
                measurementsPanel
            }
        }
        .navigationBarHidden(true)
    }
    
    private var topBar: some View {
        HStack {
            Button("Close") {
                presentationMode.wrappedValue.dismiss()
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))
            .cornerRadius(20)
            
            Spacer()
            
            Text("Measurements: \(measurementPairs.count)")
                .foregroundColor(.white)
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.5))
                .cornerRadius(12)
        }
    }
    
    private var modeSelector: some View {
        HStack(spacing: 16) {
            ForEach(MeasurementMode.allCases, id: \.self) { mode in
                Button(action: { selectedMode = mode }) {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.title3)
                        Text(mode.title)
                            .font(.caption)
                    }
                    .foregroundColor(selectedMode == mode ? .blue : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Color.black.opacity(selectedMode == mode ? 0.7 : 0.5)
                    )
                    .cornerRadius(12)
                }
            }
        }
    }
    
    private var detectionResultsView: some View {
        VStack(spacing: 8) {
            ForEach(detectedObjects.prefix(3)) { obj in
                HStack {
                    Text(obj.label)
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(obj.confidencePercentage)%")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
            }
            
            if detectedObjects.count > 3 {
                Text("+ \(detectedObjects.count - 3) more")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal)
    }

    private var instructionsView: some View {
        VStack(spacing: 12) {
            Text(selectedMode.displayTitle)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(selectedMode.instructions)
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if selectedMode == .distance && currentMeasurementPoints.count == 1 {
                Text("Tap second point to complete measurement")
                    .font(.subheadline)
                    .foregroundColor(.yellow)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(16)
    }
    
    private var bottomControls: some View {
        HStack(spacing: 20) {
            // Clear Button
            Button(action: clearAllMeasurements) {
                VStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.title2)
                    Text("Clear")
                        .font(.caption)
                }
                .foregroundColor(.red)
            }
            .frame(width: 70, height: 60)
            .background(Color.black.opacity(0.5))
            .cornerRadius(30)
            
            Spacer()
            
            // Show Measurements
            Button(action: { showingMeasurements.toggle() }) {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.title2)
                    Text("List")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }
            .frame(width: 70, height: 60)
            .background(Color.black.opacity(0.5))
            .cornerRadius(30)
            
            Spacer()
            
            // Detection Toggle (only show in object detection mode)
            if selectedMode == .objectDetection {
                Button(action: { isObjectDetectionEnabled.toggle() }) {
                    VStack(spacing: 8) {
                        Image(systemName: isObjectDetectionEnabled ? "stop.fill" : "play.fill")
                            .font(.title2)
                        Text(isObjectDetectionEnabled ? "Stop" : "Start")
                            .font(.caption)
                    }
                    .foregroundColor(isObjectDetectionEnabled ? .red : .green)
                }
                .frame(width: 70, height: 60)
                .background(Color.black.opacity(0.5))
                .cornerRadius(30)
                
                Spacer()
            }
            
            // Undo Last
            Button(action: undoLastMeasurement) {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title2)
                    Text("Undo")
                        .font(.caption)
                }
                .foregroundColor(.orange)
            }
            .frame(width: 70, height: 60)
            .background(Color.black.opacity(0.5))
            .cornerRadius(30)
        }
    }
    
    private var measurementsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Measurements")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Close") {
                    showingMeasurements = false
                }
                .foregroundColor(.blue)
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(measurementPairs.indices, id: \.self) { index in
                        HStack {
                            Text("\(index + 1).")
                                .foregroundColor(.gray)
                            
                            Text(measurementPairs[index].distanceString)
                                .foregroundColor(.white)
                                .font(.system(.body, design: .monospaced))
                            
                            Spacer()
                            
                            Text(measurementPairs[index].timestamp, style: .time)
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(16)
        .transition(.move(edge: .bottom))
        .animation(.easeInOut, value: showingMeasurements)
    }
    
    private func clearAllMeasurements() {
        measurements.removeAll()
        measurementPairs.removeAll()
        currentMeasurementPoints.removeAll()
    }
    
    private func undoLastMeasurement() {
        if !measurementPairs.isEmpty {
            measurementPairs.removeLast()
        } else if !currentMeasurementPoints.isEmpty {
            currentMeasurementPoints.removeLast()
        }
    }
}

struct ARMeasurementContainer: UIViewRepresentable {
    @Binding var measurements: [ARMeasurement]
    @Binding var measurementPairs: [MeasurementPair]
    @Binding var currentPoints: [ARMeasurement]
    @Binding var detectedObjects: [SimpleDetectedObject]
    @Binding var selectedMode: MeasurementMode
    @Binding var isObjectDetectionEnabled: Bool
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        arView.session.run(configuration)
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        context.coordinator.arView = arView
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        let coordinator = context.coordinator
        
        if selectedMode == .objectDetection && isObjectDetectionEnabled {
            coordinator.startObjectDetection()
        } else {
            coordinator.stopObjectDetection()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: ARMeasurementContainer
        var arView: ARView?
        private var detectionTimer: Timer?
        private var visionRequests: [VNRequest] = []
        
        init(_ parent: ARMeasurementContainer) {
            self.parent = parent
            super.init()
            setupVision()
        }
        
        private func setupVision() {
            // For now, use a simple mock detection system
            // In a real implementation, you would set up Vision framework here
        }
        
        func startObjectDetection() {
            guard parent.selectedMode == .objectDetection else { return }
            
            detectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.performObjectDetection()
            }
        }
        
        func stopObjectDetection() {
            detectionTimer?.invalidate()
            detectionTimer = nil
        }
        
        private func performObjectDetection() {
            guard let arView = arView,
                  let _ = arView.session.currentFrame else { return }
            
            // Simulate object detection with mock data
            DispatchQueue.global(qos: .userInitiated).async {
                self.generateMockDetections()
            }
        }
        
        private func generateMockDetections() {
            DispatchQueue.main.async {
                // Generate some mock detected objects for demonstration
                let mockObjects = [
                    SimpleDetectedObject(
                        label: "Chair",
                        confidence: 0.85,
                        boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.3, height: 0.4),
                        timestamp: Date()
                    ),
                    SimpleDetectedObject(
                        label: "Table",
                        confidence: 0.92,
                        boundingBox: CGRect(x: 0.5, y: 0.4, width: 0.4, height: 0.3),
                        timestamp: Date()
                    ),
                    SimpleDetectedObject(
                        label: "Lamp",
                        confidence: 0.78,
                        boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.3),
                        timestamp: Date()
                    )
                ]
                
                self.parent.detectedObjects = mockObjects
            }
        }
        
        private func mapLabelToReadableName(_ identifier: String) -> String {
            let commonObjects = [
                "chair": "Chair",
                "table": "Table",
                "sofa": "Sofa",
                "bed": "Bed",
                "desk": "Desk",
                "lamp": "Lamp",
                "tv": "Television",
                "book": "Book",
                "bottle": "Bottle",
                "cup": "Cup",
                "plant": "Plant",
                "laptop": "Laptop",
                "phone": "Phone"
            ]
            
            return commonObjects[identifier.lowercased()] ?? identifier.capitalized
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = arView,
                  parent.selectedMode == .distance else { return }
            
            let location = gesture.location(in: arView)
            let results = arView.raycast(from: location, allowing: .existingPlaneGeometry, alignment: .any)
            
            if let firstResult = results.first {
                let measurement = ARMeasurement(
                    id: UUID(),
                    position: firstResult.worldTransform.translation,
                    timestamp: Date()
                )
                
                DispatchQueue.main.async {
                    self.parent.measurements.append(measurement)
                    self.parent.currentPoints.append(measurement)
                    
                    // Add visual indicator
                    self.addSphere(at: firstResult.worldTransform, in: arView)
                    
                    // Check if we have two points for a measurement
                    if self.parent.currentPoints.count == 2 {
                        let pair = MeasurementPair(
                            id: UUID(),
                            startPoint: self.parent.currentPoints[0],
                            endPoint: self.parent.currentPoints[1],
                            timestamp: Date()
                        )
                        
                        self.parent.measurementPairs.append(pair)
                        self.parent.currentPoints.removeAll()
                        
                        // Add line between points
                        self.addLine(from: pair.startPoint.position, to: pair.endPoint.position, in: arView)
                    }
                }
            }
        }
        
        private func addSphere(at transform: simd_float4x4, in arView: ARView) {
            let sphere = MeshResource.generateSphere(radius: 0.005)
            let material = SimpleMaterial(color: .red, isMetallic: false)
            let entity = ModelEntity(mesh: sphere, materials: [material])
            
            let anchor = AnchorEntity(world: transform)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
        }
        
        private func addLine(from start: simd_float3, to end: simd_float3, in arView: ARView) {
            let distance = simd_distance(start, end)
            let midPoint = (start + end) / 2
            
            // Create a box to represent the line
            let box = MeshResource.generateBox(width: 0.002, height: 0.002, depth: distance)
            let material = SimpleMaterial(color: .blue, isMetallic: false)
            let entity = ModelEntity(mesh: box, materials: [material])
            
            // Calculate rotation to align with the line
            let direction = normalize(end - start)
            let up = simd_float3(0, 1, 0)
            let right = normalize(cross(up, direction))
            let actualUp = cross(direction, right)
            
            let rotationMatrix = simd_float3x3(right, actualUp, direction)
            entity.transform.rotation = simd_quatf(rotationMatrix)
            
            var transform = Transform()
            transform.translation = midPoint
            let anchor = AnchorEntity(world: transform.matrix)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
        }
    }
}

struct MeasurementPair: Identifiable {
    let id: UUID
    let startPoint: ARMeasurement
    let endPoint: ARMeasurement
    let timestamp: Date
    
    var distance: Float {
        return simd_distance(startPoint.position, endPoint.position)
    }
    
    var distanceString: String {
        let meters = distance
        if meters < 1.0 {
            return String(format: "%.0f cm", meters * 100)
        } else {
            return String(format: "%.2f m", meters)
        }
    }
}

enum MeasurementMode: String, CaseIterable {
    case distance = "distance"
    case objectDetection = "object_detection"
    
    var title: String {
        switch self {
        case .distance: return "Distance"
        case .objectDetection: return "Objects"
        }
    }
    
    var displayTitle: String {
        switch self {
        case .distance: return "Distance Measurement"
        case .objectDetection: return "Object Detection"
        }
    }
    
    var icon: String {
        switch self {
        case .distance: return "ruler"
        case .objectDetection: return "cube.box"
        }
    }
    
    var instructions: String {
        switch self {
        case .distance: return "Tap two points to measure distance between them"
        case .objectDetection: return "Point camera at objects to detect and measure them"
        }
    }
}



#Preview {
    RealMeasurementView()
}