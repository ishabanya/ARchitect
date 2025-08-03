import Foundation
import Vision
import ARKit
import RealityKit
import CoreML

public class ObjectDetectionEngine: ObservableObject {
    @Published public var detectedObjects: [DetectedObject] = []
    @Published public var isDetecting = false
    
    private var visionRequests: [VNRequest] = []
    private var detectionModel: VNCoreMLModel?
    
    public init() {
        setupVision()
    }
    
    private func setupVision() {
        guard let modelURL = Bundle.main.url(forResource: "YOLOv3", withExtension: "mlmodelc") else {
            // Fallback to built-in object detection
            setupBuiltInDetection()
            return
        }
        
        do {
            let model = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                self?.processDetections(request: request, error: error)
            }
            request.imageCropAndScaleOption = .scaleFit
            visionRequests = [request]
        } catch {
            print("Failed to load Core ML model: \(error)")
            setupBuiltInDetection()
        }
    }
    
    private func setupBuiltInDetection() {
        let request = VNRecognizeObjectsRequest { [weak self] request, error in
            self?.processBuiltInDetections(request: request, error: error)
        }
        visionRequests = [request]
    }
    
    public func detectObjects(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) {
        guard !isDetecting else { return }
        
        isDetecting = true
        
        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try imageRequestHandler.perform(self.visionRequests)
            } catch {
                print("Failed to perform detection: \(error)")
                DispatchQueue.main.async {
                    self.isDetecting = false
                }
            }
        }
    }
    
    private func processDetections(request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            self.isDetecting = false
            
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                return
            }
            
            self.detectedObjects = results.compactMap { observation in
                guard let topLabel = observation.labels.first,
                      topLabel.confidence > 0.3 else {
                    return nil
                }
                
                return DetectedObject(
                    id: UUID(),
                    label: topLabel.identifier,
                    confidence: topLabel.confidence,
                    boundingBox: observation.boundingBox,
                    timestamp: Date()
                )
            }
        }
    }
    
    private func processBuiltInDetections(request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            self.isDetecting = false
            
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                return
            }
            
            self.detectedObjects = results.compactMap { observation in
                guard let topLabel = observation.labels.first,
                      topLabel.confidence > 0.5 else {
                    return nil
                }
                
                return DetectedObject(
                    id: UUID(),
                    label: self.mapLabelToReadableName(topLabel.identifier),
                    confidence: topLabel.confidence,
                    boundingBox: observation.boundingBox,
                    timestamp: Date()
                )
            }
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
            "keyboard": "Keyboard",
            "mouse": "Mouse",
            "phone": "Phone",
            "clock": "Clock",
            "vase": "Vase",
            "bowl": "Bowl",
            "refrigerator": "Refrigerator",
            "microwave": "Microwave"
        ]
        
        return commonObjects[identifier.lowercased()] ?? identifier.capitalized
    }
    
    public func clearDetections() {
        detectedObjects.removeAll()
    }
}

public struct DetectedObject: Identifiable, Codable {
    public let id: UUID
    public let label: String
    public let confidence: Float
    public let boundingBox: CGRect
    public let timestamp: Date
    public var worldPosition: simd_float3?
    public var dimensions: simd_float3?
    
    public var confidencePercentage: Int {
        return Int(confidence * 100)
    }
}