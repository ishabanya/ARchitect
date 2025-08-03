import SwiftUI
import RealityKit
import ARKit
import Combine

// MARK: - Scan Visual Feedback System
public struct ScanVisualFeedback: View {
    @ObservedObject var scanner: RoomScanner
    @ObservedObject var sessionManager: ARSessionManager
    @State private var showGrid = true
    @State private var gridOpacity: Double = 0.6
    @State private var animationPhase: Double = 0
    
    public init(scanner: RoomScanner, sessionManager: ARSessionManager) {
        self.scanner = scanner
        self.sessionManager = sessionManager
    }
    
    public var body: some View {
        ZStack {
            // AR Camera View
            ARViewContainer(
                sessionManager: sessionManager,
                scanner: scanner,
                showGrid: showGrid,
                gridOpacity: gridOpacity
            )
            .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top Status Bar
                topStatusBar
                
                Spacer()
                
                // Bottom Controls and Progress
                bottomControls
            }
            .padding()
        }
        .onAppear {
            startAnimations()
        }
    }
    
    // MARK: - Top Status Bar
    private var topStatusBar: some View {
        VStack(spacing: 8) {
            // Scan Phase and Instructions
            scanPhaseIndicator
            
            // Progress Bar
            scanProgressBar
            
            // Quality Indicators
            if scanner.scanQuality != nil {
                qualityIndicators
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(radius: 4)
        )
    }
    
    private var scanPhaseIndicator: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: phaseIcon)
                    .foregroundColor(phaseColor)
                    .font(.title2)
                
                Text(scanner.scanProgress.currentPhase.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if scanner.isScanning {
                    scanningIndicator
                }
            }
            
            Text(scanner.scanProgress.currentPhase.instruction)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
    }
    
    private var scanningIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animationPhase == Double(index) ? 1.5 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: animationPhase
                    )
            }
        }
    }
    
    private var scanProgressBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Progress")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(Int(scanner.scanProgress.completionPercentage * 100))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            ProgressView(value: scanner.scanProgress.completionPercentage)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .scaleEffect(x: 1, y: 2, anchor: .center)
            
            if let timeRemaining = scanner.scanProgress.estimatedTimeRemaining {
                Text("~\(Int(timeRemaining))s remaining")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var qualityIndicators: some View {
        HStack(spacing: 16) {
            qualityMeter("Completeness", value: scanner.scanQuality?.completeness ?? 0, color: .green)
            qualityMeter("Accuracy", value: scanner.scanQuality?.accuracy ?? 0, color: .blue)
            qualityMeter("Coverage", value: scanner.scanQuality?.coverage ?? 0, color: .orange)
        }
    }
    
    private func qualityMeter(_ title: String, value: Float, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            CircularProgressView(value: value, color: color)
                .frame(width: 24, height: 24)
            
            Text("\(Int(value * 100))%")
                .font(.caption2)
                .fontWeight(.medium)
        }
    }
    
    // MARK: - Bottom Controls
    private var bottomControls: some View {
        VStack(spacing: 16) {
            // Detected Elements Summary
            detectedElementsSummary
            
            // Control Buttons
            controlButtons
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(radius: 4)
        )
    }
    
    private var detectedElementsSummary: some View {
        HStack(spacing: 20) {
            detectionCounter(
                icon: "rectangle.landscape",
                title: "Floor",
                count: scanner.mergedPlanes.filter { $0.type == .floor }.count,
                color: .blue
            )
            
            detectionCounter(
                icon: "rectangle.portrait",
                title: "Walls",
                count: scanner.mergedPlanes.filter { $0.type == .wall }.count,
                color: .green
            )
            
            detectionCounter(
                icon: "rectangle.landscape",
                title: "Ceiling",
                count: scanner.mergedPlanes.filter { $0.type == .ceiling }.count,
                color: .purple
            )
            
            if let dimensions = scanner.roomDimensions {
                dimensionDisplay(dimensions)
            }
        }
    }
    
    private func detectionCounter(icon: String, title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private func dimensionDisplay(_ dimensions: RoomDimensions) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "cube")
                .foregroundColor(.orange)
                .font(.title3)
            
            Text(dimensions.displayArea)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.orange)
            
            Text("Area")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var controlButtons: some View {
        HStack(spacing: 12) {
            // Grid Toggle
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showGrid.toggle()
                }
            } label: {
                Image(systemName: showGrid ? "grid" : "grid.slash")
                    .font(.title2)
                    .foregroundColor(showGrid ? .blue : .secondary)
            }
            .frame(width: 44, height: 44)
            .background(Circle().fill(.ultraThinMaterial))
            
            Spacer()
            
            // Main Action Button
            if scanner.isScanning {
                Button("Stop Scan") {
                    scanner.stopScanning()
                }
                .buttonStyle(PrimaryButtonStyle(color: .red))
            } else if scanner.scanState == .completed {
                Button("Save Scan") {
                    // Handle save action
                }
                .buttonStyle(PrimaryButtonStyle(color: .green))
            } else {
                Button("Start Scan") {
                    scanner.startScanning()
                }
                .buttonStyle(PrimaryButtonStyle(color: .blue))
            }
            
            Spacer()
            
            // Settings Button
            Button {
                // Handle settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 44, height: 44)
            .background(Circle().fill(.ultraThinMaterial))
        }
    }
    
    // MARK: - Computed Properties
    private var phaseIcon: String {
        switch scanner.scanProgress.currentPhase {
        case .floorDetection: return "rectangle.landscape"
        case .wallDetection: return "rectangle.portrait"
        case .detailScanning: return "viewfinder"
        case .optimization: return "gearshape"
        case .finalization: return "checkmark.circle"
        }
    }
    
    private var phaseColor: Color {
        switch scanner.scanProgress.currentPhase {
        case .floorDetection: return .blue
        case .wallDetection: return .green
        case .detailScanning: return .orange
        case .optimization: return .purple
        case .finalization: return .mint
        }
    }
    
    // MARK: - Animations
    private func startAnimations() {
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
            animationPhase = 3
        }
    }
}

// MARK: - ARView Container
struct ARViewContainer: UIViewRepresentable {
    let sessionManager: ARSessionManager
    let scanner: RoomScanner
    let showGrid: Bool
    let gridOpacity: Double
    
    func makeUIView(context: Context) -> ARView {
        let arView = sessionManager.arView
        
        // Add visual feedback overlays
        setupVisualFeedback(arView)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        updateVisualFeedback(uiView)
    }
    
    private func setupVisualFeedback(_ arView: ARView) {
        // Remove existing overlays
        arView.scene.anchors.removeAll()
        
        // Add grid overlay if enabled
        if showGrid {
            addGridOverlay(arView)
        }
        
        // Add plane visualizations
        addPlaneVisualizations(arView)
    }
    
    private func updateVisualFeedback(_ arView: ARView) {
        // Update grid visibility
        updateGridVisibility(arView)
        
        // Update plane visualizations
        updatePlaneVisualizations(arView)
    }
    
    private func addGridOverlay(_ arView: ARView) {
        // Create floor grid
        let gridAnchor = AnchorEntity(.plane(.horizontal, classification: .floor, minimumBounds: [0.1, 0.1]))
        
        let gridMesh = MeshResource.generatePlane(width: 10, depth: 10)
        let gridMaterial = createGridMaterial()
        let gridEntity = ModelEntity(mesh: gridMesh, materials: [gridMaterial])
        
        gridAnchor.addChild(gridEntity)
        arView.scene.addAnchor(gridAnchor)
    }
    
    private func createGridMaterial() -> Material {
        var material = UnlitMaterial()
        
        // Create grid texture
        let gridTexture = generateGridTexture()
        material.baseColor = MaterialColorParameter.texture(gridTexture)
        material.opacityThreshold = 0.1
        material.blending = .transparent(opacity: .init(floatLiteral: gridOpacity))
        
        return material
    }
    
    private func generateGridTexture() -> TextureResource {
        let size = 256
        let gridSpacing = 16
        
        // This is a simplified texture generation
        // In a real implementation, you'd create a proper grid texture
        do {
            let descriptor = TextureResource.CreateDescriptor(
                dimensions: .dimensions2D(width: size, height: size),
                channels: .rgba8Unorm,
                mipmapped: false
            )
            
            return try TextureResource.create(descriptor: descriptor) { buffer in
                let bytesPerPixel = 4
                let bytesPerRow = size * bytesPerPixel
                
                for y in 0..<size {
                    for x in 0..<size {
                        let index = y * bytesPerRow + x * bytesPerPixel
                        
                        let isGridLine = (x % gridSpacing == 0) || (y % gridSpacing == 0)
                        let alpha: UInt8 = isGridLine ? 255 : 0
                        
                        buffer[index] = 0     // R
                        buffer[index + 1] = 150 // G
                        buffer[index + 2] = 255 // B
                        buffer[index + 3] = alpha // A
                    }
                }
            }
        } catch {
            // Fallback to a simple solid color texture
            return try! TextureResource.generate(from: .white, options: .init(semantic: .color))
        }
    }
    
    private func updateGridVisibility(_ arView: ARView) {
        // Update grid material opacity
        for anchor in arView.scene.anchors {
            for entity in anchor.children {
                if let modelEntity = entity as? ModelEntity {
                    for i in 0..<modelEntity.materials.count {
                        if var material = modelEntity.materials[i] as? UnlitMaterial {
                            material.blending = .transparent(opacity: .init(floatLiteral: showGrid ? gridOpacity : 0))
                            modelEntity.materials[i] = material
                        }
                    }
                }
            }
        }
    }
    
    private func addPlaneVisualizations(_ arView: ARView) {
        // Add visualizations for detected planes
        for plane in scanner.mergedPlanes {
            addPlaneVisualization(plane, to: arView)
        }
    }
    
    private func updatePlaneVisualizations(_ arView: ARView) {
        // Remove old plane visualizations
        arView.scene.anchors.removeAll { anchor in
            anchor.name?.hasPrefix("plane_") ?? false
        }
        
        // Add current plane visualizations
        addPlaneVisualizations(arView)
    }
    
    private func addPlaneVisualization(_ plane: MergedPlane, to arView: ARView) {
        let anchor = AnchorEntity(world: plane.center)
        anchor.name = "plane_\(plane.id.uuidString)"
        
        // Create outline mesh for the plane
        let outlineMesh = createPlaneBoundaryMesh(plane.geometry)
        let outlineMaterial = createPlaneOutlineMaterial(for: plane.type)
        let outlineEntity = ModelEntity(mesh: outlineMesh, materials: [outlineMaterial])
        
        anchor.addChild(outlineEntity)
        arView.scene.addAnchor(anchor)
        
        // Add plane label
        if plane.area > 1.0 { // Only label larger planes
            let labelEntity = createPlaneLabel(plane)
            anchor.addChild(labelEntity)
        }
    }
    
    private func createPlaneBoundaryMesh(_ geometry: [simd_float3]) -> MeshResource {
        // Create a simple line mesh for the plane boundary
        // This is simplified - in practice you'd create proper line geometry
        
        guard geometry.count >= 3 else {
            return MeshResource.generateBox(size: 0.01) // Fallback
        }
        
        // For simplicity, create a thin box outline
        let bounds = PlaneBounds(points: geometry)
        let width = bounds.size.x
        let height = bounds.size.y
        let depth = bounds.size.z
        
        return MeshResource.generateBox(
            width: max(width, 0.01),
            height: max(height, 0.01),
            depth: max(depth, 0.01)
        )
    }
    
    private func createPlaneOutlineMaterial(for type: MergedPlane.PlaneType) -> Material {
        var material = UnlitMaterial()
        
        let color: UIColor
        switch type {
        case .floor:
            color = UIColor.systemBlue.withAlphaComponent(0.6)
        case .wall:
            color = UIColor.systemGreen.withAlphaComponent(0.6)
        case .ceiling:
            color = UIColor.systemPurple.withAlphaComponent(0.6)
        case .surface:
            color = UIColor.systemOrange.withAlphaComponent(0.6)
        }
        
        material.baseColor = MaterialColorParameter.color(color)
        material.blending = .transparent(opacity: 0.6)
        
        return material
    }
    
    private func createPlaneLabel(_ plane: MergedPlane) -> Entity {
        let labelText = "\(plane.type.displayName)\n\(String(format: "%.1f m²", plane.area))"
        
        // This is simplified - in practice you'd create a proper text entity
        let labelEntity = Entity()
        labelEntity.position = simd_float3(0, 0.1, 0) // Slightly above the plane
        
        return labelEntity
    }
}

// MARK: - Circular Progress View
struct CircularProgressView: View {
    let value: Float
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 2)
            
            Circle()
                .trim(from: 0, to: CGFloat(value))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: value)
        }
    }
}

// MARK: - Primary Button Style
struct PrimaryButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(color)
                    .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview
#if DEBUG
struct ScanVisualFeedback_Previews: PreviewProvider {
    static var previews: some View {
        ScanVisualFeedback(
            scanner: RoomScanner(sessionManager: ARSessionManager()),
            sessionManager: ARSessionManager()
        )
    }
}
#endif