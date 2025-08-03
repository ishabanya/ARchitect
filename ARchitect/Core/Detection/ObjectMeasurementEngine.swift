import Foundation
import ARKit
import RealityKit
import Vision

public class ObjectMeasurementEngine: ObservableObject {
    @Published public var measuredObjects: [MeasuredObject] = []
    @Published public var isMeasuring = false
    
    private var arSession: ARSession?
    private var detectionEngine: ObjectDetectionEngine
    
    public init(detectionEngine: ObjectDetectionEngine) {
        self.detectionEngine = detectionEngine
    }
    
    public func setARSession(_ session: ARSession) {
        self.arSession = session
    }
    
    public func measureDetectedObjects(in arView: ARView, frame: ARFrame) {
        guard !isMeasuring else { return }
        
        isMeasuring = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let detectedObjects = self.detectionEngine.detectedObjects
            var newMeasuredObjects: [MeasuredObject] = []
            
            for detectedObject in detectedObjects {
                if let measuredObject = self.calculateObjectDimensions(
                    detectedObject: detectedObject,
                    in: arView,
                    frame: frame
                ) {
                    newMeasuredObjects.append(measuredObject)
                }
            }
            
            DispatchQueue.main.async {
                self.measuredObjects = newMeasuredObjects
                self.isMeasuring = false
            }
        }
    }
    
    private func calculateObjectDimensions(
        detectedObject: DetectedObject,
        in arView: ARView,
        frame: ARFrame
    ) -> MeasuredObject? {
        
        let boundingBox = detectedObject.boundingBox
        let imageSize = CGSize(width: CVPixelBufferGetWidth(frame.capturedImage),
                              height: CVPixelBufferGetHeight(frame.capturedImage))
        
        // Convert normalized bounding box to pixel coordinates
        let pixelBox = CGRect(
            x: boundingBox.origin.x * imageSize.width,
            y: (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height,
            width: boundingBox.width * imageSize.width,
            height: boundingBox.height * imageSize.height
        )
        
        // Convert pixel coordinates to view coordinates
        let viewSize = arView.bounds.size
        let scaleX = viewSize.width / imageSize.width
        let scaleY = viewSize.height / imageSize.height
        
        let viewBox = CGRect(
            x: pixelBox.origin.x * scaleX,
            y: pixelBox.origin.y * scaleY,
            width: pixelBox.width * scaleX,
            height: pixelBox.height * scaleY
        )
        
        // Get multiple raycast points to estimate object bounds
        let cornerPoints = [
            CGPoint(x: viewBox.minX, y: viewBox.minY), // Top-left
            CGPoint(x: viewBox.maxX, y: viewBox.minY), // Top-right
            CGPoint(x: viewBox.minX, y: viewBox.maxY), // Bottom-left
            CGPoint(x: viewBox.maxX, y: viewBox.maxY), // Bottom-right
            CGPoint(x: viewBox.midX, y: viewBox.midY)  // Center
        ]
        
        var worldPositions: [simd_float3] = []
        
        for point in cornerPoints {
            let results = arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .any)
            if let firstResult = results.first {
                worldPositions.append(firstResult.worldTransform.translation)
            }
        }
        
        guard worldPositions.count >= 2 else {
            return nil
        }
        
        // Calculate dimensions from world positions
        let dimensions = calculateDimensionsFromPoints(worldPositions)
        let centerPosition = worldPositions.reduce(simd_float3(0, 0, 0)) { $0 + $1 } / Float(worldPositions.count)
        
        // Estimate object type-specific dimensions
        let estimatedDimensions = estimateObjectDimensions(
            for: detectedObject.label,
            measuredDimensions: dimensions
        )
        
        return MeasuredObject(
            id: UUID(),
            detectedObject: detectedObject,
            worldPosition: centerPosition,
            dimensions: estimatedDimensions,
            volume: estimatedDimensions.x * estimatedDimensions.y * estimatedDimensions.z,
            timestamp: Date()
        )
    }
    
    private func calculateDimensionsFromPoints(_ points: [simd_float3]) -> simd_float3 {
        guard !points.isEmpty else { return simd_float3(0, 0, 0) }
        
        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
            minZ = min(minZ, point.z)
            maxZ = max(maxZ, point.z)
        }
        
        return simd_float3(
            max(0.01, maxX - minX), // Width
            max(0.01, maxY - minY), // Height
            max(0.01, maxZ - minZ)  // Depth
        )
    }
    
    private func estimateObjectDimensions(for objectType: String, measuredDimensions: simd_float3) -> simd_float3 {
        // Apply object-specific dimension estimation
        let typicalDimensions: [String: simd_float3] = [
            "Chair": simd_float3(0.6, 0.9, 0.6),
            "Table": simd_float3(1.2, 0.75, 0.8),
            "Sofa": simd_float3(2.0, 0.85, 0.9),
            "Bed": simd_float3(2.0, 0.6, 1.5),
            "Desk": simd_float3(1.4, 0.75, 0.7),
            "Lamp": simd_float3(0.3, 1.5, 0.3),
            "Television": simd_float3(1.2, 0.7, 0.1),
            "Book": simd_float3(0.15, 0.2, 0.03),
            "Bottle": simd_float3(0.07, 0.25, 0.07),
            "Cup": simd_float3(0.08, 0.1, 0.08),
            "Plant": simd_float3(0.3, 0.5, 0.3),
            "Laptop": simd_float3(0.35, 0.02, 0.25),
            "Phone": simd_float3(0.07, 0.015, 0.14)
        ]
        
        if let typical = typicalDimensions[objectType] {
            // Use measured dimensions but constrain to reasonable bounds for the object type
            return simd_float3(
                max(typical.x * 0.5, min(typical.x * 2.0, measuredDimensions.x)),
                max(typical.y * 0.5, min(typical.y * 2.0, measuredDimensions.y)),
                max(typical.z * 0.5, min(typical.z * 2.0, measuredDimensions.z))
            )
        }
        
        return measuredDimensions
    }
    
    public func clearMeasurements() {
        measuredObjects.removeAll()
    }
    
    public func addMeasuredObjectToScene(_ measuredObject: MeasuredObject, in arView: ARView) {
        // Create bounding box visualization
        let box = MeshResource.generateBox(
            width: measuredObject.dimensions.x,
            height: measuredObject.dimensions.y,
            depth: measuredObject.dimensions.z
        )
        
        var material = SimpleMaterial()
        material.color = .init(tint: .green.withAlphaComponent(0.3))
        material.roughness = 0.0
        material.metallic = 0.0
        
        let entity = ModelEntity(mesh: box, materials: [material])
        
        var transform = Transform()
        transform.translation = measuredObject.worldPosition
        
        let anchor = AnchorEntity(world: transform.matrix)
        anchor.addChild(entity)
        
        // Add text label
        let textMesh = MeshResource.generateText(
            measuredObject.detectedObject.label,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.05),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        
        let textMaterial = SimpleMaterial(color: .white, isMetallic: false)
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
        textEntity.position.y = measuredObject.dimensions.y / 2 + 0.1
        
        anchor.addChild(textEntity)
        arView.scene.addAnchor(anchor)
    }
}

public struct MeasuredObject: Identifiable, Codable {
    public let id: UUID
    public let detectedObject: DetectedObject
    public let worldPosition: simd_float3
    public let dimensions: simd_float3
    public let volume: Float
    public let timestamp: Date
    
    public var dimensionsString: String {
        return String(format: "%.2f × %.2f × %.2f m", dimensions.x, dimensions.y, dimensions.z)
    }
    
    public var volumeString: String {
        return String(format: "%.3f m³", volume)
    }
    
    public var widthString: String {
        return String(format: "%.2f m", dimensions.x)
    }
    
    public var heightString: String {
        return String(format: "%.2f m", dimensions.y)
    }
    
    public var depthString: String {
        return String(format: "%.2f m", dimensions.z)
    }
}