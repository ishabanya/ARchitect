import Foundation
import ARKit
import RealityKit
import SwiftUI
import simd

// MARK: - Measurement Annotations Manager
@MainActor
public class MeasurementAnnotations: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var visibleAnnotations: [MeasurementAnnotation] = []
    @Published public var annotationSettings = AnnotationSettings()
    @Published public var isShowingAllAnnotations = true
    
    // MARK: - Private Properties
    private weak var arView: ARView?
    private var annotationEntities: [UUID: AnnotationEntity] = [:]
    private var measurementEntities: [UUID: MeasurementEntity] = [:]
    
    // Settings
    private let maxVisibleAnnotations = 50
    private let annotationFadeDistance: Float = 10.0
    private let labelMinimumScale: Float = 0.5
    private let labelMaximumScale: Float = 2.0
    
    public init() {
        logInfo("Measurement annotations manager initialized", category: .measurement)
    }
    
    // MARK: - Public Methods
    
    /// Set the AR view for rendering annotations
    public func setARView(_ arView: ARView) {
        self.arView = arView
        setupARView()
        logDebug("AR view set for measurement annotations", category: .measurement)
    }
    
    /// Add measurement annotation to AR space
    public func addMeasurementAnnotation(for measurement: Measurement) {
        guard let arView = arView else {
            logWarning("Cannot add measurement annotation: AR view not set", category: .measurement)
            return
        }
        
        do {
            let annotation = try createMeasurementAnnotation(for: measurement)
            visibleAnnotations.append(annotation)
            
            // Create 3D entities for the measurement
            let entities = try createMeasurementEntities(for: measurement, annotation: annotation)
            measurementEntities[measurement.id] = entities
            
            // Add entities to AR scene
            arView.scene.addAnchor(entities.anchor)
            
            // Manage annotation count
            manageMeasurementAnnotationCount()
            
            logDebug("Added measurement annotation", category: .measurement, context: LogContext(customData: [
                "measurement_id": measurement.id.uuidString,
                "measurement_type": measurement.type.rawValue,
                "visible_annotations": visibleAnnotations.count
            ]))
            
        } catch {
            logError("Failed to add measurement annotation: \(error)", category: .measurement)
        }
    }
    
    /// Remove measurement annotation from AR space
    public func removeMeasurementAnnotation(for measurementID: UUID) {
        guard let arView = arView else { return }
        
        // Remove from visible annotations
        visibleAnnotations.removeAll { $0.measurementID == measurementID }
        
        // Remove entities
        if let entities = measurementEntities.removeValue(forKey: measurementID) {
            arView.scene.removeAnchor(entities.anchor)
        }
        
        // Remove annotation entities
        annotationEntities.removeValue(forKey: measurementID)
        
        logDebug("Removed measurement annotation", category: .measurement, context: LogContext(customData: [
            "measurement_id": measurementID.uuidString
        ]))
    }
    
    /// Update measurement annotation visibility
    public func updateMeasurementAnnotationVisibility(for measurementID: UUID, isVisible: Bool) {
        if let entities = measurementEntities[measurementID] {
            entities.setVisibility(isVisible)
        }
        
        if let index = visibleAnnotations.firstIndex(where: { $0.measurementID == measurementID }) {
            visibleAnnotations[index].isVisible = isVisible
        }
    }
    
    /// Update all measurement annotations visibility
    public func setAllAnnotationsVisible(_ visible: Bool) {
        isShowingAllAnnotations = visible
        
        for annotation in visibleAnnotations {
            updateMeasurementAnnotationVisibility(for: annotation.measurementID, isVisible: visible)
        }
        
        logDebug("Set all annotations visible: \(visible)", category: .measurement)
    }
    
    /// Update measurement annotation based on camera position
    public func updateAnnotations(cameraTransform: simd_float4x4) {
        let cameraPosition = simd_float3(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        
        for annotation in visibleAnnotations {
            updateAnnotationForDistance(annotation, cameraPosition: cameraPosition)
        }
    }
    
    /// Get annotation at screen position (for interaction)
    public func getAnnotation(at screenPoint: CGPoint) -> MeasurementAnnotation? {
        guard let arView = arView else { return nil }
        
        // Perform hit test against annotation entities
        let hitResults = arView.hitTest(screenPoint)
        
        for result in hitResults {
            if let annotationEntity = result.entity as? Entity,
               let measurementID = findMeasurementID(for: annotationEntity) {
                return visibleAnnotations.first { $0.measurementID == measurementID }
            }
        }
        
        return nil
    }
    
    /// Clear all measurement annotations
    public func clearAllAnnotations() {
        guard let arView = arView else { return }
        
        for entities in measurementEntities.values {
            arView.scene.removeAnchor(entities.anchor)
        }
        
        measurementEntities.removeAll()
        annotationEntities.removeAll()
        visibleAnnotations.removeAll()
        
        logInfo("Cleared all measurement annotations", category: .measurement)
    }
    
    /// Update annotation settings
    public func updateAnnotationSettings(_ settings: AnnotationSettings) {
        annotationSettings = settings
        
        // Update existing annotations
        for entities in measurementEntities.values {
            entities.updateAppearance(with: settings)
        }
        
        logDebug("Updated annotation settings", category: .measurement)
    }
    
    // MARK: - Private Methods
    
    private func setupARView() {
        guard let arView = arView else { return }
        
        // Configure AR view for annotations
        arView.renderOptions.insert(.disablePersonOcclusion)
        arView.renderOptions.insert(.disableDepthOfField)
    }
    
    private func createMeasurementAnnotation(for measurement: Measurement) throws -> MeasurementAnnotation {
        let annotation = MeasurementAnnotation(
            measurementID: measurement.id,
            type: measurement.type,
            points: measurement.points,
            value: measurement.value,
            accuracy: measurement.accuracy,
            color: measurement.color,
            isVisible: measurement.isVisible && isShowingAllAnnotations
        )
        
        return annotation
    }
    
    private func createMeasurementEntities(for measurement: Measurement, annotation: MeasurementAnnotation) throws -> MeasurementEntity {
        guard let arView = arView else {
            throw AnnotationError.arViewNotSet
        }
        
        let anchor = AnchorEntity(world: measurement.points[0].position)
        
        switch measurement.type {
        case .distance, .height:
            return try createDistanceMeasurementEntity(measurement: measurement, annotation: annotation, anchor: anchor)
        case .area:
            return try createAreaMeasurementEntity(measurement: measurement, annotation: annotation, anchor: anchor)
        case .volume:
            return try createVolumeMeasurementEntity(measurement: measurement, annotation: annotation, anchor: anchor)
        case .angle:
            return try createAngleMeasurementEntity(measurement: measurement, annotation: annotation, anchor: anchor)
        case .perimeter:
            return try createPerimeterMeasurementEntity(measurement: measurement, annotation: annotation, anchor: anchor)
        }
    }
    
    private func createDistanceMeasurementEntity(measurement: Measurement, annotation: MeasurementAnnotation, anchor: AnchorEntity) throws -> MeasurementEntity {
        guard measurement.points.count >= 2 else {
            throw AnnotationError.insufficientPoints
        }
        
        let startPoint = measurement.points[0].position
        let endPoint = measurement.points[1].position
        let midPoint = (startPoint + endPoint) / 2
        
        // Create line between points
        let lineEntity = createLineEntity(from: startPoint, to: endPoint, color: measurement.color)
        anchor.addChild(lineEntity)
        
        // Create point markers
        let startMarker = createPointMarker(at: startPoint, color: measurement.color)
        let endMarker = createPointMarker(at: endPoint, color: measurement.color)
        anchor.addChild(startMarker)
        anchor.addChild(endMarker)
        
        // Create label at midpoint
        let labelEntity = createLabelEntity(
            text: measurement.value.formattedString,
            position: midPoint,
            color: measurement.color
        )
        anchor.addChild(labelEntity)
        
        return MeasurementEntity(
            anchor: anchor,
            lineEntities: [lineEntity],
            pointEntities: [startMarker, endMarker],
            labelEntities: [labelEntity],
            fillEntities: []
        )
    }
    
    private func createAreaMeasurementEntity(measurement: Measurement, annotation: MeasurementAnnotation, anchor: AnchorEntity) throws -> MeasurementEntity {
        guard measurement.points.count >= 3 else {
            throw AnnotationError.insufficientPoints
        }
        
        var lineEntities: [Entity] = []
        var pointEntities: [Entity] = []
        
        // Create perimeter lines and point markers
        for i in 0..<measurement.points.count {
            let currentPoint = measurement.points[i].position
            let nextPoint = measurement.points[(i + 1) % measurement.points.count].position
            
            let lineEntity = createLineEntity(from: currentPoint, to: nextPoint, color: measurement.color)
            let pointMarker = createPointMarker(at: currentPoint, color: measurement.color)
            
            anchor.addChild(lineEntity)
            anchor.addChild(pointMarker)
            
            lineEntities.append(lineEntity)
            pointEntities.append(pointMarker)
        }
        
        // Create fill mesh
        let fillEntity = try createAreaFillEntity(points: measurement.points.map { $0.position }, color: measurement.color)
        anchor.addChild(fillEntity)
        
        // Create label at centroid
        let centroid = measurement.points.map { $0.position }.reduce(simd_float3(0, 0, 0), +) / Float(measurement.points.count)
        let labelEntity = createLabelEntity(
            text: measurement.value.formattedString,
            position: centroid,
            color: measurement.color
        )
        anchor.addChild(labelEntity)
        
        return MeasurementEntity(
            anchor: anchor,
            lineEntities: lineEntities,
            pointEntities: pointEntities,
            labelEntities: [labelEntity],
            fillEntities: [fillEntity]
        )
    }
    
    private func createVolumeMeasurementEntity(measurement: Measurement, annotation: MeasurementAnnotation, anchor: AnchorEntity) throws -> MeasurementEntity {
        guard measurement.points.count >= 4 else {
            throw AnnotationError.insufficientPoints
        }
        
        // Create wireframe representation of volume
        var lineEntities: [Entity] = []
        var pointEntities: [Entity] = []
        
        // Create point markers
        for point in measurement.points {
            let pointMarker = createPointMarker(at: point.position, color: measurement.color)
            anchor.addChild(pointMarker)
            pointEntities.append(pointMarker)
        }
        
        // Create bounding box lines
        let positions = measurement.points.map { $0.position }
        let boundingBox = calculateBoundingBox(positions: positions)
        let boxLines = createBoundingBoxLines(boundingBox: boundingBox, color: measurement.color)
        
        for lineEntity in boxLines {
            anchor.addChild(lineEntity)
            lineEntities.append(lineEntity)
        }
        
        // Create label at center
        let center = (boundingBox.min + boundingBox.max) / 2
        let labelEntity = createLabelEntity(
            text: measurement.value.formattedString,
            position: center,
            color: measurement.color
        )
        anchor.addChild(labelEntity)
        
        return MeasurementEntity(
            anchor: anchor,
            lineEntities: lineEntities,
            pointEntities: pointEntities,
            labelEntities: [labelEntity],
            fillEntities: []
        )
    }
    
    private func createAngleMeasurementEntity(measurement: Measurement, annotation: MeasurementAnnotation, anchor: AnchorEntity) throws -> MeasurementEntity {
        guard measurement.points.count >= 3 else {
            throw AnnotationError.insufficientPoints
        }
        
        let centerPoint = measurement.points[1].position
        let point1 = measurement.points[0].position
        let point2 = measurement.points[2].position
        
        // Create lines to form angle
        let line1 = createLineEntity(from: centerPoint, to: point1, color: measurement.color)
        let line2 = createLineEntity(from: centerPoint, to: point2, color: measurement.color)
        anchor.addChild(line1)
        anchor.addChild(line2)
        
        // Create arc to show angle
        let arcEntity = createAngleArcEntity(
            center: centerPoint,
            point1: point1,
            point2: point2,
            color: measurement.color
        )
        anchor.addChild(arcEntity)
        
        // Create point markers
        let centerMarker = createPointMarker(at: centerPoint, color: measurement.color)
        let point1Marker = createPointMarker(at: point1, color: measurement.color)
        let point2Marker = createPointMarker(at: point2, color: measurement.color)
        anchor.addChild(centerMarker)
        anchor.addChild(point1Marker)
        anchor.addChild(point2Marker)
        
        // Create label
        let labelPosition = centerPoint + simd_normalize((point1 + point2) / 2 - centerPoint) * 0.1
        let labelEntity = createLabelEntity(
            text: measurement.value.formattedString,
            position: labelPosition,
            color: measurement.color
        )
        anchor.addChild(labelEntity)
        
        return MeasurementEntity(
            anchor: anchor,
            lineEntities: [line1, line2],
            pointEntities: [centerMarker, point1Marker, point2Marker],
            labelEntities: [labelEntity],
            fillEntities: [arcEntity]
        )
    }
    
    private func createPerimeterMeasurementEntity(measurement: Measurement, annotation: MeasurementAnnotation, anchor: AnchorEntity) throws -> MeasurementEntity {
        guard measurement.points.count >= 3 else {
            throw AnnotationError.insufficientPoints
        }
        
        var lineEntities: [Entity] = []
        var pointEntities: [Entity] = []
        
        // Create perimeter lines and point markers
        for i in 0..<measurement.points.count {
            let currentPoint = measurement.points[i].position
            let nextPoint = measurement.points[(i + 1) % measurement.points.count].position
            
            let lineEntity = createLineEntity(from: currentPoint, to: nextPoint, color: measurement.color)
            let pointMarker = createPointMarker(at: currentPoint, color: measurement.color)
            
            anchor.addChild(lineEntity)
            anchor.addChild(pointMarker)
            
            lineEntities.append(lineEntity)
            pointEntities.append(pointMarker)
        }
        
        // Create label at centroid
        let centroid = measurement.points.map { $0.position }.reduce(simd_float3(0, 0, 0), +) / Float(measurement.points.count)
        let labelEntity = createLabelEntity(
            text: measurement.value.formattedString,
            position: centroid,
            color: measurement.color
        )
        anchor.addChild(labelEntity)
        
        return MeasurementEntity(
            anchor: anchor,
            lineEntities: lineEntities,
            pointEntities: pointEntities,
            labelEntities: [labelEntity],
            fillEntities: []
        )
    }
    
    // MARK: - Entity Creation Helpers
    
    private func createLineEntity(from start: simd_float3, to end: simd_float3, color: MeasurementColor) -> Entity {
        let lineEntity = Entity()
        
        let distance = simd_distance(start, end)
        let direction = simd_normalize(end - start)
        let midpoint = (start + end) / 2
        
        // Create cylinder mesh for line
        let mesh = MeshResource.generateBox(width: 0.002, height: distance, depth: 0.002)
        let material = SimpleMaterial(color: UIColor(hex: color.hexValue), isMetallic: false)
        
        let modelComponent = ModelComponent(mesh: mesh, materials: [material])
        lineEntity.components.set(modelComponent)
        
        // Position and orient the line
        lineEntity.position = midpoint - start
        
        // Calculate rotation to align with direction
        let up = simd_float3(0, 1, 0)
        if abs(simd_dot(direction, up)) < 0.99 {
            let right = simd_normalize(simd_cross(up, direction))
            let forward = simd_cross(right, up)
            let rotationMatrix = simd_float3x3(right, up, forward)
            lineEntity.orientation = simd_quatf(rotationMatrix)
        }
        
        return lineEntity
    }
    
    private func createPointMarker(at position: simd_float3, color: MeasurementColor) -> Entity {
        let markerEntity = Entity()
        
        let mesh = MeshResource.generateSphere(radius: 0.005)
        let material = SimpleMaterial(color: UIColor(hex: color.hexValue), isMetallic: false)
        
        let modelComponent = ModelComponent(mesh: mesh, materials: [material])
        markerEntity.components.set(modelComponent)
        markerEntity.position = position
        
        return markerEntity
    }
    
    private func createLabelEntity(text: String, position: simd_float3, color: MeasurementColor) -> Entity {
        let labelEntity = Entity()
        
        // Create text mesh
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.02),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        
        let material = SimpleMaterial(color: UIColor(hex: color.hexValue), isMetallic: false)
        let modelComponent = ModelComponent(mesh: mesh, materials: [material])
        labelEntity.components.set(modelComponent)
        labelEntity.position = position
        
        // Make label face camera (billboard behavior)
        let billboardComponent = BillboardComponent()
        labelEntity.components.set(billboardComponent)
        
        return labelEntity
    }
    
    private func createAreaFillEntity(points: [simd_float3], color: MeasurementColor) throws -> Entity {
        let fillEntity = Entity()
        
        // Create mesh from points
        let mesh = try createPolygonMesh(points: points)
        let material = SimpleMaterial(
            color: UIColor(hex: color.hexValue).withAlphaComponent(0.3),
            isMetallic: false
        )
        
        let modelComponent = ModelComponent(mesh: mesh, materials: [material])
        fillEntity.components.set(modelComponent)
        
        return fillEntity
    }
    
    private func createAngleArcEntity(center: simd_float3, point1: simd_float3, point2: simd_float3, color: MeasurementColor) -> Entity {
        let arcEntity = Entity()
        
        // Create arc mesh (simplified as a triangle fan)
        let radius: Float = 0.05
        let segments = 20
        
        let direction1 = simd_normalize(point1 - center)
        let direction2 = simd_normalize(point2 - center)
        let angle = acos(simd_dot(direction1, direction2))
        
        var vertices: [simd_float3] = [simd_float3(0, 0, 0)] // Center vertex
        
        for i in 0...segments {
            let t = Float(i) / Float(segments)
            let currentAngle = t * angle
            
            // Interpolate between the two directions
            let rotation = simd_quatf(angle: currentAngle, axis: simd_cross(direction1, direction2))
            let vertex = rotation.act(direction1) * radius
            vertices.append(vertex)
        }
        
        let mesh = try! MeshResource.generate(from: vertices)
        let material = SimpleMaterial(
            color: UIColor(hex: color.hexValue).withAlphaComponent(0.5),
            isMetallic: false
        )
        
        let modelComponent = ModelComponent(mesh: mesh, materials: [material])
        arcEntity.components.set(modelComponent)
        arcEntity.position = center
        
        return arcEntity
    }
    
    private func createBoundingBoxLines(boundingBox: (min: simd_float3, max: simd_float3), color: MeasurementColor) -> [Entity] {
        let min = boundingBox.min
        let max = boundingBox.max
        
        // Define 8 corners of bounding box
        let corners = [
            simd_float3(min.x, min.y, min.z),
            simd_float3(max.x, min.y, min.z),
            simd_float3(max.x, max.y, min.z),
            simd_float3(min.x, max.y, min.z),
            simd_float3(min.x, min.y, max.z),
            simd_float3(max.x, min.y, max.z),
            simd_float3(max.x, max.y, max.z),
            simd_float3(min.x, max.y, max.z)
        ]
        
        // Define 12 edges of bounding box
        let edges: [(Int, Int)] = [
            (0, 1), (1, 2), (2, 3), (3, 0), // Bottom face
            (4, 5), (5, 6), (6, 7), (7, 4), // Top face
            (0, 4), (1, 5), (2, 6), (3, 7)  // Vertical edges
        ]
        
        return edges.map { (start, end) in
            createLineEntity(from: corners[start], to: corners[end], color: color)
        }
    }
    
    private func createPolygonMesh(points: [simd_float3]) throws -> MeshResource {
        // Triangulate polygon using ear clipping algorithm (simplified)
        var vertices: [simd_float3] = []
        var indices: [UInt32] = []
        
        if points.count == 3 {
            // Simple triangle
            vertices = points
            indices = [0, 1, 2]
        } else {
            // For complex polygons, use triangle fan from first vertex
            vertices = points
            for i in 1..<(points.count - 1) {
                indices.append(0)
                indices.append(UInt32(i))
                indices.append(UInt32(i + 1))
            }
        }
        
        var meshDescriptor = MeshDescriptor()
        meshDescriptor.positions = MeshBuffers.Positions(vertices)
        meshDescriptor.primitives = .triangles(indices)
        
        return try MeshResource.generate(from: [meshDescriptor])
    }
    
    private func calculateBoundingBox(positions: [simd_float3]) -> (min: simd_float3, max: simd_float3) {
        guard !positions.isEmpty else {
            return (simd_float3(0, 0, 0), simd_float3(0, 0, 0))
        }
        
        var minPoint = positions[0]
        var maxPoint = positions[0]
        
        for position in positions {
            minPoint = simd_min(minPoint, position)
            maxPoint = simd_max(maxPoint, position)
        }
        
        return (minPoint, maxPoint)
    }
    
    private func updateAnnotationForDistance(_ annotation: MeasurementAnnotation, cameraPosition: simd_float3) {
        guard let entities = measurementEntities[annotation.measurementID] else { return }
        
        // Calculate distance to measurement
        let measurementCenter = annotation.points.map { $0.position }.reduce(simd_float3(0, 0, 0), +) / Float(annotation.points.count)
        let distance = simd_distance(cameraPosition, measurementCenter)
        
        // Update label scale based on distance
        let scale = max(labelMinimumScale, min(labelMaximumScale, 1.0 / distance))
        for labelEntity in entities.labelEntities {
            labelEntity.scale = simd_float3(scale, scale, scale)
        }
        
        // Fade out annotations that are too far
        let alpha = max(0.0, min(1.0, 1.0 - (distance - annotationFadeDistance) / annotationFadeDistance))
        entities.setAlpha(alpha)
    }
    
    private func manageMeasurementAnnotationCount() {
        if visibleAnnotations.count > maxVisibleAnnotations {
            // Remove oldest annotations
            let annotationsToRemove = visibleAnnotations.prefix(visibleAnnotations.count - maxVisibleAnnotations)
            for annotation in annotationsToRemove {
                removeMeasurementAnnotation(for: annotation.measurementID)
            }
        }
    }
    
    private func findMeasurementID(for entity: Entity) -> UUID? {
        // Walk up the entity hierarchy to find measurement ID
        var currentEntity: Entity? = entity
        while let entity = currentEntity {
            if let anchor = entity as? AnchorEntity,
               let measurementEntity = measurementEntities.first(where: { $0.value.anchor == anchor }) {
                return measurementEntity.key
            }
            currentEntity = entity.parent
        }
        return nil
    }
}

// MARK: - Supporting Types

public struct MeasurementAnnotation: Identifiable {
    public let id = UUID()
    public let measurementID: UUID
    public let type: MeasurementType
    public let points: [MeasurementPoint]
    public let value: MeasurementValue
    public let accuracy: MeasurementAccuracy
    public let color: MeasurementColor
    public var isVisible: Bool
    
    public init(
        measurementID: UUID,
        type: MeasurementType,
        points: [MeasurementPoint],
        value: MeasurementValue,
        accuracy: MeasurementAccuracy,
        color: MeasurementColor,
        isVisible: Bool = true
    ) {
        self.measurementID = measurementID
        self.type = type
        self.points = points
        self.value = value
        self.accuracy = accuracy
        self.color = color
        self.isVisible = isVisible
    }
}

public class MeasurementEntity {
    public let anchor: AnchorEntity
    public let lineEntities: [Entity]
    public let pointEntities: [Entity]
    public let labelEntities: [Entity]
    public let fillEntities: [Entity]
    
    public init(
        anchor: AnchorEntity,
        lineEntities: [Entity],
        pointEntities: [Entity],
        labelEntities: [Entity],
        fillEntities: [Entity]
    ) {
        self.anchor = anchor
        self.lineEntities = lineEntities
        self.pointEntities = pointEntities
        self.labelEntities = labelEntities
        self.fillEntities = fillEntities
    }
    
    public func setVisibility(_ visible: Bool) {
        anchor.isEnabled = visible
    }
    
    public func setAlpha(_ alpha: Float) {
        let allEntities = lineEntities + pointEntities + labelEntities + fillEntities
        for entity in allEntities {
            if var modelComponent = entity.components[ModelComponent.self] {
                for i in 0..<modelComponent.materials.count {
                    if var material = modelComponent.materials[i] as? SimpleMaterial {
                        material.color = material.color.withAlphaComponent(CGFloat(alpha))
                        modelComponent.materials[i] = material
                    }
                }
                entity.components.set(modelComponent)
            }
        }
    }
    
    public func updateAppearance(with settings: AnnotationSettings) {
        // Update colors, sizes, etc. based on settings
        // Implementation would update material properties
    }
}

public struct AnnotationSettings {
    public var showLabels: Bool = true
    public var showPoints: Bool = true
    public var showLines: Bool = true
    public var showFill: Bool = true
    public var labelScale: Float = 1.0
    public var lineThickness: Float = 1.0
    public var pointSize: Float = 1.0
    public var fadeDistance: Float = 10.0
    
    public init() {}
}

public enum AnnotationError: LocalizedError {
    case arViewNotSet
    case insufficientPoints
    case meshGenerationFailed
    
    public var errorDescription: String? {
        switch self {
        case .arViewNotSet:
            return "AR view not set for annotations"
        case .insufficientPoints:
            return "Insufficient points for annotation"
        case .meshGenerationFailed:
            return "Failed to generate mesh for annotation"
        }
    }
}

// MARK: - UIColor Extension

extension UIColor {
    convenience init(hex: String) {
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
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
}