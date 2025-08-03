import SwiftUI
import ARKit
import RealityKit

struct ARViewContainer: UIViewRepresentable {
    @Binding var isPlaneDetectionEnabled: Bool
    @Binding var detectedPlanes: [DetectedPlane]
    @Binding var measurements: [ARMeasurement]
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Set up AR session
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        
        arView.session.run(configuration)
        arView.session.delegate = context.coordinator
        
        // Add gesture recognizers
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        context.coordinator.arView = arView
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update configuration if needed
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = isPlaneDetectionEnabled ? [.horizontal, .vertical] : []
        configuration.environmentTexturing = .automatic
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        
        uiView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        var parent: ARViewContainer
        var arView: ARView?
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = arView else { return }
            
            let location = gesture.location(in: arView)
            
            // Perform raycast to find surfaces
            let results = arView.raycast(from: location, allowing: .existingPlaneGeometry, alignment: .any)
            
            if let firstResult = results.first {
                // Add measurement point
                let measurement = ARMeasurement(
                    id: UUID(),
                    position: firstResult.worldTransform.translation,
                    timestamp: Date()
                )
                
                DispatchQueue.main.async {
                    self.parent.measurements.append(measurement)
                }
                
                // Add visual indicator
                addSphere(at: firstResult.worldTransform, in: arView)
            }
        }
        
        private func addSphere(at transform: simd_float4x4, in arView: ARView) {
            let sphere = MeshResource.generateSphere(radius: 0.01)
            let material = SimpleMaterial(color: .red, isMetallic: false)
            let entity = ModelEntity(mesh: sphere, materials: [material])
            
            let anchor = AnchorEntity(world: transform)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
        }
        
        // MARK: - ARSessionDelegate
        
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                if let planeAnchor = anchor as? ARPlaneAnchor {
                    let detectedPlane = DetectedPlane(
                        id: anchor.identifier,
                        type: planeAnchor.classification.description,
                        center: planeAnchor.center,
                        extent: planeAnchor.extent,
                        transform: planeAnchor.transform
                    )
                    
                    DispatchQueue.main.async {
                        self.parent.detectedPlanes.append(detectedPlane)
                    }
                }
            }
        }
        
        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            for anchor in anchors {
                if let planeAnchor = anchor as? ARPlaneAnchor {
                    DispatchQueue.main.async {
                        if let index = self.parent.detectedPlanes.firstIndex(where: { $0.id == anchor.identifier }) {
                            self.parent.detectedPlanes[index] = DetectedPlane(
                                id: anchor.identifier,
                                type: planeAnchor.classification.description,
                                center: planeAnchor.center,
                                extent: planeAnchor.extent,
                                transform: planeAnchor.transform
                            )
                        }
                    }
                }
            }
        }
        
        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            for anchor in anchors {
                DispatchQueue.main.async {
                    self.parent.detectedPlanes.removeAll { $0.id == anchor.identifier }
                }
            }
        }
    }
}

struct DetectedPlane: Identifiable {
    let id: UUID
    let type: String
    let center: simd_float3
    let extent: simd_float3
    let transform: simd_float4x4
    
    init(id: UUID, type: String, center: simd_float3, extent: simd_float3, transform: simd_float4x4) {
        self.id = id
        self.type = type
        self.center = center
        self.extent = extent
        self.transform = transform
    }
}

struct ARMeasurement: Identifiable {
    let id: UUID
    let position: simd_float3
    let timestamp: Date
    
    var distanceString: String {
        return String(format: "%.2fm", distance(from: simd_float3(0, 0, 0)))
    }
    
    private func distance(from point: simd_float3) -> Float {
        let diff = position - point
        return sqrt(diff.x * diff.x + diff.y * diff.y + diff.z * diff.z)
    }
}

extension simd_float4x4 {
    var translation: simd_float3 {
        return simd_float3(columns.3.x, columns.3.y, columns.3.z)
    }
}

extension ARPlaneAnchor.Classification {
    var description: String {
        switch self {
        case .wall:
            return "Wall"
        case .floor:
            return "Floor"
        case .ceiling:
            return "Ceiling"
        case .table:
            return "Table"
        case .seat:
            return "Seat"
        case .door:
            return "Door"
        case .window:
            return "Window"
        default:
            return "Surface"
        }
    }
}