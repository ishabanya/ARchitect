import Foundation
import ARKit
import Vision
import CoreML
import RealityKit

public class RealTimeDetectionManager: NSObject, ObservableObject {
    @Published public var detectedObjects: [DetectedObject] = []
    @Published public var measuredObjects: [MeasuredObject] = []
    @Published public var isProcessing = false
    
    private var objectDetectionEngine: ObjectDetectionEngine
    private var objectMeasurementEngine: ObjectMeasurementEngine
    private var processingQueue = DispatchQueue(label: "detection.processing", qos: .userInitiated)
    private var lastProcessingTime: Date = Date()
    private let processingInterval: TimeInterval = 0.5 // Process every 500ms
    
    public override init() {
        self.objectDetectionEngine = ObjectDetectionEngine()
        self.objectMeasurementEngine = ObjectMeasurementEngine(detectionEngine: objectDetectionEngine)
        super.init()
        
        // Observe detection engine updates
        objectDetectionEngine.$detectedObjects
            .receive(on: DispatchQueue.main)
            .assign(to: &$detectedObjects)
        
        objectMeasurementEngine.$measuredObjects
            .receive(on: DispatchQueue.main)
            .assign(to: &$measuredObjects)
    }
    
    public func processFrame(_ frame: ARFrame, in arView: ARView) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessingTime) >= processingInterval,
              !isProcessing else { return }
        
        lastProcessingTime = now
        isProcessing = true
        
        processingQueue.async { [weak self] in
            self?.performDetection(frame: frame, arView: arView)
        }
    }
    
    private func performDetection(frame: ARFrame, arView: ARView) {
        let pixelBuffer = frame.capturedImage
        
        // Perform object detection
        objectDetectionEngine.detectObjects(in: pixelBuffer) { [weak self] in
            // Once detection is complete, perform measurement
            self?.objectMeasurementEngine.measureDetectedObjects(in: arView, frame: frame) {
                DispatchQueue.main.async {
                    self?.isProcessing = false
                }
            }
        }
    }
    
    public func startDetection(with arSession: ARSession) {
        objectMeasurementEngine.setARSession(arSession)
    }
    
    public func stopDetection() {
        clearDetections()
    }
    
    public func clearDetections() {
        objectDetectionEngine.clearDetections()
        objectMeasurementEngine.clearMeasurements()
    }
    
    public func visualizeDetectedObjects(in arView: ARView) {
        // Clear previous visualizations
        removeDetectionVisualizations(from: arView)
        
        // Add new visualizations
        for measuredObject in measuredObjects {
            visualizeMeasuredObject(measuredObject, in: arView)
        }
    }
    
    private func visualizeMeasuredObject(_ object: MeasuredObject, in arView: ARView) {
        // Create bounding box
        let box = MeshResource.generateBox(
            width: object.dimensions.x,
            height: object.dimensions.y,
            depth: object.dimensions.z
        )
        
        var material = SimpleMaterial()
        material.color = .init(tint: getColorForObject(object.detectedObject.label))
        material.roughness = 0.2
        material.metallic = 0.0
        
        let boxEntity = ModelEntity(mesh: box, materials: [material])
        boxEntity.name = "detection_box_\(object.id.uuidString)"
        
        // Create label
        let labelText = "\(object.detectedObject.label)\n\(object.dimensionsString)"
        let textMesh = MeshResource.generateText(
            labelText,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.03),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        
        let textMaterial = SimpleMaterial(color: .white, isMetallic: false)
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
        textEntity.position.y = object.dimensions.y / 2 + 0.1
        textEntity.name = "detection_label_\(object.id.uuidString)"
        
        // Create anchor
        var transform = Transform()
        transform.translation = object.worldPosition
        
        let anchor = AnchorEntity(world: transform.matrix)
        anchor.name = "detection_anchor_\(object.id.uuidString)"
        anchor.addChild(boxEntity)
        anchor.addChild(textEntity)
        
        arView.scene.addAnchor(anchor)
    }
    
    private func removeDetectionVisualizations(from arView: ARView) {
        let anchorsToRemove = arView.scene.anchors.filter { anchor in
            anchor.name?.hasPrefix("detection_anchor_") == true
        }
        
        for anchor in anchorsToRemove {
            arView.scene.removeAnchor(anchor)
        }
    }
    
    private func getColorForObject(_ label: String) -> UIColor {
        let colors: [UIColor] = [
            .systemRed, .systemBlue, .systemGreen, .systemOrange,
            .systemPurple, .systemYellow, .systemPink, .systemTeal
        ]
        
        let hash = abs(label.hashValue)
        return colors[hash % colors.count].withAlphaComponent(0.4)
    }
}

// MARK: - Enhanced Detection Engine

extension ObjectDetectionEngine {
    public func detectObjects(in pixelBuffer: CVPixelBuffer, completion: @escaping () -> Void) {
        guard !isDetecting else {
            completion()
            return
        }
        
        detectObjects(in: pixelBuffer)
        
        // Simulate async completion since the original method is synchronous
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            completion()
        }
    }
}

// MARK: - Enhanced Measurement Engine

extension ObjectMeasurementEngine {
    public func measureDetectedObjects(in arView: ARView, frame: ARFrame, completion: @escaping () -> Void) {
        measureDetectedObjects(in: arView, frame: frame)
        
        // Simulate async completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            completion()
        }
    }
}

// MARK: - Object Confidence Filtering

extension Array where Element == DetectedObject {
    public func filtered(byConfidence minConfidence: Float = 0.5) -> [DetectedObject] {
        return filter { $0.confidence >= minConfidence }
    }
    
    public func sorted(byConfidence ascending: Bool = false) -> [DetectedObject] {
        return sorted { first, second in
            ascending ? first.confidence < second.confidence : first.confidence > second.confidence
        }
    }
}

// MARK: - Measurement Utilities

extension MeasuredObject {
    public var isReliable: Bool {
        return detectedObject.confidence >= 0.6 && volume > 0.001 // At least 1 liter
    }
    
    public var category: ObjectCategory {
        return ObjectCategory.categorize(label: detectedObject.label)
    }
}

public enum ObjectCategory: String, CaseIterable {
    case furniture = "furniture"
    case electronics = "electronics"
    case decoration = "decoration"
    case kitchenware = "kitchenware"
    case books = "books"
    case plants = "plants"
    case unknown = "unknown"
    
    public static func categorize(label: String) -> ObjectCategory {
        let lowercaseLabel = label.lowercased()
        
        if ["chair", "table", "sofa", "bed", "desk", "shelf", "cabinet"].contains(where: { lowercaseLabel.contains($0) }) {
            return .furniture
        } else if ["tv", "television", "laptop", "computer", "phone", "tablet", "monitor"].contains(where: { lowercaseLabel.contains($0) }) {
            return .electronics
        } else if ["vase", "picture", "painting", "frame", "decoration", "ornament"].contains(where: { lowercaseLabel.contains($0) }) {
            return .decoration
        } else if ["cup", "mug", "bowl", "plate", "bottle", "glass", "fork", "spoon", "knife"].contains(where: { lowercaseLabel.contains($0) }) {
            return .kitchenware
        } else if ["book", "magazine", "newspaper"].contains(where: { lowercaseLabel.contains($0) }) {
            return .books
        } else if ["plant", "flower", "tree", "pot"].contains(where: { lowercaseLabel.contains($0) }) {
            return .plants
        } else {
            return .unknown
        }
    }
    
    public var icon: String {
        switch self {
        case .furniture: return "sofa"
        case .electronics: return "tv"
        case .decoration: return "paintbrush"
        case .kitchenware: return "cup.and.saucer"
        case .books: return "book"
        case .plants: return "leaf"
        case .unknown: return "questionmark.circle"
        }
    }
    
    public var color: UIColor {
        switch self {
        case .furniture: return .systemBrown
        case .electronics: return .systemBlue
        case .decoration: return .systemPurple
        case .kitchenware: return .systemOrange
        case .books: return .systemGreen
        case .plants: return .systemGreen
        case .unknown: return .systemGray
        }
    }
}