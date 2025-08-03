import ARKit
import simd

extension simd_float4x4 {
    var translation: simd_float3 {
        return simd_float3(columns.3.x, columns.3.y, columns.3.z)
    }
    
    var position: simd_float3 {
        return translation
    }
    
    var rotation: simd_quatf {
        return simd_quatf(self)
    }
    
    var eulerAngles: simd_float3 {
        let rotation = simd_quatf(self)
        return rotation.eulerAngles
    }
    
    init(translation: simd_float3) {
        self = matrix_identity_float4x4
        columns.3 = simd_float4(translation.x, translation.y, translation.z, 1.0)
    }
    
    init(translation: simd_float3, rotation: simd_quatf) {
        let rotationMatrix = matrix_float4x4(rotation)
        self = rotationMatrix
        columns.3 = simd_float4(translation.x, translation.y, translation.z, 1.0)
    }
}

extension simd_quatf {
    var eulerAngles: simd_float3 {
        let w = self.real
        let x = self.imag.x
        let y = self.imag.y
        let z = self.imag.z
        
        let sinr_cosp = 2 * (w * x + y * z)
        let cosr_cosp = 1 - 2 * (x * x + y * y)
        let roll = atan2(sinr_cosp, cosr_cosp)
        
        let sinp = 2 * (w * y - z * x)
        let pitch: Float
        if abs(sinp) >= 1 {
            pitch = copysign(Float.pi / 2, sinp)
        } else {
            pitch = asin(sinp)
        }
        
        let siny_cosp = 2 * (w * z + x * y)
        let cosy_cosp = 1 - 2 * (y * y + z * z)
        let yaw = atan2(siny_cosp, cosy_cosp)
        
        return simd_float3(roll, pitch, yaw)
    }
    
    init(eulerAngles: simd_float3) {
        let roll = eulerAngles.x
        let pitch = eulerAngles.y
        let yaw = eulerAngles.z
        
        let cy = cos(yaw * 0.5)
        let sy = sin(yaw * 0.5)
        let cp = cos(pitch * 0.5)
        let sp = sin(pitch * 0.5)
        let cr = cos(roll * 0.5)
        let sr = sin(roll * 0.5)
        
        let w = cr * cp * cy + sr * sp * sy
        let x = sr * cp * cy - cr * sp * sy
        let y = cr * sp * cy + sr * cp * sy
        let z = cr * cp * sy - sr * sp * cy
        
        self.init(real: w, imag: simd_float3(x, y, z))
    }
}

extension ARCamera {
    var projectionMatrixForViewportSize: simd_float4x4 {
        return projectionMatrix
    }
    
    func unprojectPoint(_ point: simd_float3, ontoPlane plane: simd_float4) -> simd_float3? {
        let viewMatrix = transform.inverse
        let projectionMatrix = self.projectionMatrix
        
        let clipSpacePosition = simd_float4(point, 1.0)
        let eyeSpacePosition = projectionMatrix.inverse * clipSpacePosition
        let worldSpacePosition = viewMatrix.inverse * eyeSpacePosition
        
        // Intersect with plane
        let rayOrigin = transform.translation
        let rayDirection = normalize(worldSpacePosition.xyz - rayOrigin)
        
        return rayPlaneIntersection(rayOrigin: rayOrigin, rayDirection: rayDirection, plane: plane)
    }
}

extension simd_float4 {
    var xyz: simd_float3 {
        return simd_float3(x, y, z)
    }
}

func rayPlaneIntersection(rayOrigin: simd_float3, rayDirection: simd_float3, plane: simd_float4) -> simd_float3? {
    let planeNormal = simd_float3(plane.x, plane.y, plane.z)
    let planeDistance = plane.w
    
    let denominator = dot(rayDirection, planeNormal)
    
    if abs(denominator) < 1e-6 {
        return nil // Ray is parallel to plane
    }
    
    let t = -(dot(rayOrigin, planeNormal) + planeDistance) / denominator
    
    if t < 0 {
        return nil // Intersection is behind ray origin
    }
    
    return rayOrigin + t * rayDirection
}

extension ARFrame {
    func worldPosition(for point: CGPoint, in view: ARView) -> simd_float3? {
        let results = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .any)
        return results.first?.worldTransform.translation
    }
    
    func hitTest(point: CGPoint, in view: ARView, types: ARHitTestResult.ResultType = [.existingPlaneUsingExtent]) -> [ARHitTestResult] {
        return view.hitTest(point, types: types)
    }
}

extension ARView {
    func addBoundingBox(at position: simd_float3, size: simd_float3, color: UIColor = .green) {
        let box = MeshResource.generateBox(width: size.x, height: size.y, depth: size.z)
        var material = SimpleMaterial()
        material.color = .init(tint: color.withAlphaComponent(0.3))
        material.roughness = 0.0
        material.metallic = 0.0
        
        let entity = ModelEntity(mesh: box, materials: [material])
        
        var transform = Transform()
        transform.translation = position
        
        let anchor = AnchorEntity(world: transform.matrix)
        anchor.addChild(entity)
        scene.addAnchor(anchor)
    }
    
    func addLabel(text: String, at position: simd_float3, color: UIColor = .white) {
        let textMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.05),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        
        let textMaterial = SimpleMaterial(color: color, isMetallic: false)
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
        
        var transform = Transform()
        transform.translation = position
        
        let anchor = AnchorEntity(world: transform.matrix)
        anchor.addChild(textEntity)
        scene.addAnchor(anchor)
    }
    
    func clearAllAnchors() {
        scene.anchors.removeAll()
    }
}