import SwiftUI
import ARKit
import RealityKit
import Vision

struct ObjectDetectionMeasurementView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var detectionEngine = ObjectDetectionEngine()
    @StateObject private var measurementEngine: ObjectMeasurementEngine
    @State private var showingObjectList = false
    @State private var selectedDetectionMode: DetectionMode = .objects
    @State private var isDetectionActive = false
    @State private var measurementPairs: [MeasurementPair] = []
    @State private var currentMeasurementPoints: [ARMeasurement] = []
    
    init() {
        let detection = ObjectDetectionEngine()
        let measurement = ObjectMeasurementEngine(detectionEngine: detection)
        self._measurementEngine = StateObject(wrappedValue: measurement)
    }
    
    var body: some View {
        ZStack {
            // AR Camera View
            EnhancedARMeasurementContainer(
                detectionEngine: detectionEngine,
                measurementEngine: measurementEngine,
                selectedMode: $selectedDetectionMode,
                isDetectionActive: $isDetectionActive,
                measurementPairs: $measurementPairs,
                currentPoints: $currentMeasurementPoints
            )
            .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top Bar
                topBar
                
                // Detection Mode Selector
                modeSelector
                
                Spacer()
                
                // Detection Results Overlay
                if !detectionEngine.detectedObjects.isEmpty && selectedDetectionMode == .objects {
                    detectionOverlay
                }
                
                // Instructions
                instructionsView
                
                Spacer()
                
                // Bottom Controls
                bottomControls
            }
            .padding()
            
            // Object List Panel
            if showingObjectList {
                objectListPanel
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
            
            if selectedDetectionMode == .objects {
                Text("Objects: \(detectionEngine.detectedObjects.count)")
                    .foregroundColor(.white)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(12)
            } else {
                Text("Measurements: \(measurementPairs.count)")
                    .foregroundColor(.white)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(12)
            }
        }
    }
    
    private var modeSelector: some View {
        HStack(spacing: 16) {
            ForEach(DetectionMode.allCases, id: \.self) { mode in
                Button(action: { selectedDetectionMode = mode }) {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.title2)
                        Text(mode.title)
                            .font(.caption)
                    }
                    .foregroundColor(selectedDetectionMode == mode ? .blue : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Color.black.opacity(selectedDetectionMode == mode ? 0.7 : 0.5)
                    )
                    .cornerRadius(12)
                }
            }
        }
    }
    
    private var detectionOverlay: some View {
        VStack(spacing: 8) {
            ForEach(detectionEngine.detectedObjects.prefix(3)) { obj in
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
            
            if detectionEngine.detectedObjects.count > 3 {
                Text("+ \(detectionEngine.detectedObjects.count - 3) more")
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
            Text(selectedDetectionMode.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(selectedDetectionMode.instructions)
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if selectedDetectionMode == .distance && currentMeasurementPoints.count == 1 {
                Text("Tap second point to complete measurement")
                    .font(.subheadline)
                    .foregroundColor(.yellow)
                    .padding(.top, 4)
            }
            
            if detectionEngine.isDetecting || measurementEngine.isMeasuring {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(selectedDetectionMode == .objects ? "Detecting..." : "Measuring...")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(16)
    }
    
    private var bottomControls: some View {
        HStack(spacing: 20) {
            // Detection Toggle
            Button(action: toggleDetection) {
                VStack(spacing: 8) {
                    Image(systemName: isDetectionActive ? "stop.fill" : "play.fill")
                        .font(.title2)
                    Text(isDetectionActive ? "Stop" : "Start")
                        .font(.caption)
                }
                .foregroundColor(isDetectionActive ? .red : .green)
            }
            .frame(width: 70, height: 60)
            .background(Color.black.opacity(0.5))
            .cornerRadius(30)
            
            Spacer()
            
            // Show List
            Button(action: { showingObjectList.toggle() }) {
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
            
            // Clear All
            Button(action: clearAll) {
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
        }
    }
    
    private var objectListPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedDetectionMode == .objects ? "Detected Objects" : "Measurements")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Close") {
                    showingObjectList = false
                }
                .foregroundColor(.blue)
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if selectedDetectionMode == .objects {
                        ForEach(measurementEngine.measuredObjects.indices, id: \.self) { index in
                            objectRow(measurementEngine.measuredObjects[index])
                        }
                    } else {
                        ForEach(measurementPairs.indices, id: \.self) { index in
                            measurementRow(measurementPairs[index], index: index)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(16)
        .transition(.move(edge: .bottom))
        .animation(.easeInOut, value: showingObjectList)
    }
    
    private func objectRow(_ object: MeasuredObject) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(object.detectedObject.label)
                    .foregroundColor(.white)
                    .font(.headline)
                
                Spacer()
                
                Text("\(object.detectedObject.confidencePercentage)%")
                    .foregroundColor(.green)
                    .font(.caption)
            }
            
            Text("Dimensions: \(object.dimensionsString)")
                .foregroundColor(.gray)
                .font(.caption)
            
            Text("Volume: \(object.volumeString)")
                .foregroundColor(.gray)
                .font(.caption)
            
            Text(object.timestamp, style: .time)
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
    
    private func measurementRow(_ measurement: MeasurementPair, index: Int) -> some View {
        HStack {
            Text("\(index + 1).")
                .foregroundColor(.gray)
            
            Text(measurement.distanceString)
                .foregroundColor(.white)
                .font(.system(.body, design: .monospaced))
            
            Spacer()
            
            Text(measurement.timestamp, style: .time)
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
    
    private func toggleDetection() {
        isDetectionActive.toggle()
        if !isDetectionActive {
            detectionEngine.clearDetections()
            measurementEngine.clearMeasurements()
        }
    }
    
    private func clearAll() {
        detectionEngine.clearDetections()
        measurementEngine.clearMeasurements()
        measurementPairs.removeAll()
        currentMeasurementPoints.removeAll()
    }
}

enum DetectionMode: String, CaseIterable {
    case objects = "objects"
    case distance = "distance"
    
    var title: String {
        switch self {
        case .objects: return "Object Detection"
        case .distance: return "Distance Measurement"
        }
    }
    
    var icon: String {
        switch self {
        case .objects: return "cube.box"
        case .distance: return "ruler"
        }
    }
    
    var instructions: String {
        switch self {
        case .objects: return "Point camera at objects to detect and measure them automatically"
        case .distance: return "Tap two points to measure distance between them"
        }
    }
}

struct EnhancedARMeasurementContainer: UIViewRepresentable {
    let detectionEngine: ObjectDetectionEngine
    let measurementEngine: ObjectMeasurementEngine
    @Binding var selectedMode: DetectionMode
    @Binding var isDetectionActive: Bool
    @Binding var measurementPairs: [MeasurementPair]
    @Binding var currentPoints: [ARMeasurement]
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        arView.session.run(configuration)
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        context.coordinator.arView = arView
        measurementEngine.setARSession(arView.session)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.updateDetectionMode(selectedMode)
        context.coordinator.updateDetectionState(isDetectionActive)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        var parent: EnhancedARMeasurementContainer
        var arView: ARView?
        private var detectionTimer: Timer?
        
        init(_ parent: EnhancedARMeasurementContainer) {
            self.parent = parent
            super.init()
        }
        
        func updateDetectionMode(_ mode: DetectionMode) {
            // Handle mode changes
        }
        
        func updateDetectionState(_ isActive: Bool) {
            if isActive {
                startObjectDetection()
            } else {
                stopObjectDetection()
            }
        }
        
        private func startObjectDetection() {
            guard parent.selectedMode == .objects else { return }
            
            detectionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.performObjectDetection()
            }
        }
        
        private func stopObjectDetection() {
            detectionTimer?.invalidate()
            detectionTimer = nil
        }
        
        private func performObjectDetection() {
            guard let arView = arView,
                  let frame = arView.session.currentFrame else { return }
            
            let pixelBuffer = frame.capturedImage
            parent.detectionEngine.detectObjects(in: pixelBuffer)
            
            // Measure detected objects
            parent.measurementEngine.measureDetectedObjects(in: arView, frame: frame)
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard parent.selectedMode == .distance,
                  let arView = arView else { return }
            
            let location = gesture.location(in: arView)
            let results = arView.raycast(from: location, allowing: .existingPlaneGeometry, alignment: .any)
            
            if let firstResult = results.first {
                let measurement = ARMeasurement(
                    id: UUID(),
                    position: firstResult.worldTransform.translation,
                    timestamp: Date()
                )
                
                DispatchQueue.main.async {
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

#Preview {
    ObjectDetectionMeasurementView()
}