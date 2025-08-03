import SwiftUI
import ARKit
import RealityKit

struct RealFurniturePlacementView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedFurniture: FurnitureModel?
    @State private var placedFurniture: [PlacedFurnitureItem] = []
    @State private var showingFurnitureMenu = false
    @State private var arView: ARView?
    
    private let furnitureModels = [
        FurnitureModel(name: "Chair", modelName: "chair", icon: "chair.fill", color: .brown),
        FurnitureModel(name: "Table", modelName: "table", icon: "table.furniture.fill", color: .orange),
        FurnitureModel(name: "Sofa", modelName: "sofa", icon: "sofa.fill", color: .blue),
        FurnitureModel(name: "Lamp", modelName: "lamp", icon: "lamp.desk.fill", color: .yellow),
        FurnitureModel(name: "Plant", modelName: "plant", icon: "leaf.fill", color: .green),
        FurnitureModel(name: "TV", modelName: "tv", icon: "tv.fill", color: .black)
    ]
    
    var body: some View {
        ZStack {
            // AR View
            ARFurniturePlacementContainer(
                selectedFurniture: $selectedFurniture,
                placedFurniture: $placedFurniture,
                arView: $arView
            )
            .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top Bar
                topBar
                
                Spacer()
                
                // Instructions
                if selectedFurniture == nil {
                    instructionsView
                }
                
                Spacer()
                
                // Bottom Controls
                bottomControls
            }
            .padding()
            
            // Furniture Selection Menu
            if showingFurnitureMenu {
                furnitureSelectionMenu
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
            
            if let furniture = selectedFurniture {
                Text("Selected: \(furniture.name)")
                    .foregroundColor(.white)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(12)
            }
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Placed: \(placedFurniture.count)")
                    .foregroundColor(.white)
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))
            .cornerRadius(12)
        }
    }
    
    private var instructionsView: some View {
        VStack(spacing: 12) {
            Text("Furniture Placement")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Select furniture from the menu below, then tap on detected surfaces to place items")
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(16)
    }
    
    private var bottomControls: some View {
        HStack(spacing: 20) {
            // Clear All
            Button(action: clearAllFurniture) {
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
            
            // Furniture Menu
            Button(action: { showingFurnitureMenu.toggle() }) {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                    Text("Add")
                        .font(.caption)
                }
                .foregroundColor(.green)
            }
            .frame(width: 80, height: 60)
            .background(Color.black.opacity(0.5))
            .cornerRadius(30)
            
            Spacer()
            
            // Deselect
            Button(action: { selectedFurniture = nil }) {
                VStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                    Text("Cancel")
                        .font(.caption)
                }
                .foregroundColor(.orange)
            }
            .frame(width: 70, height: 60)
            .background(Color.black.opacity(0.5))
            .cornerRadius(30)
        }
    }
    
    private var furnitureSelectionMenu: some View {
        let menuContent = VStack(spacing: 16) {
            Text("Select Furniture")
                .font(.headline)
                .foregroundColor(.white)
            
            furnitureGrid
            
            Button("Cancel") {
                showingFurnitureMenu = false
            }
            .foregroundColor(.red)
            .padding(.top)
        }
        
        return menuContent
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(16)
            .transition(.move(edge: .bottom))
            .animation(.easeInOut, value: showingFurnitureMenu)
    }
    
    private var furnitureGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
            ForEach(furnitureModels, id: \.name) { furniture in
                furnitureButton(furniture)
            }
        }
    }
    
    private func furnitureButton(_ furniture: FurnitureModel) -> some View {
        Button(action: {
            selectedFurniture = furniture
            showingFurnitureMenu = false
        }) {
            VStack(spacing: 8) {
                Image(systemName: furniture.icon)
                    .font(.title2)
                    .foregroundColor(furniture.color)
                
                Text(furniture.name)
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .frame(width: 80, height: 80)
            .background(Color.black.opacity(0.6))
            .cornerRadius(12)
        }
    }
    
    private func clearAllFurniture() {
        placedFurniture.removeAll()
        
        // Remove all furniture from AR scene
        if let arView = arView {
            arView.scene.anchors.removeAll()
        }
    }
}

struct ARFurniturePlacementContainer: UIViewRepresentable {
    @Binding var selectedFurniture: FurnitureModel?
    @Binding var placedFurniture: [PlacedFurnitureItem]
    @Binding var arView: ARView?
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        arView.session.run(configuration)
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        context.coordinator.arView = arView
        
        DispatchQueue.main.async {
            self.arView = arView
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.selectedFurniture = selectedFurniture
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: ARFurniturePlacementContainer
        var arView: ARView?
        var selectedFurniture: FurnitureModel?
        
        init(_ parent: ARFurniturePlacementContainer) {
            self.parent = parent
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = arView,
                  let furniture = selectedFurniture else { return }
            
            let location = gesture.location(in: arView)
            let results = arView.raycast(from: location, allowing: .existingPlaneGeometry, alignment: .horizontal)
            
            if let firstResult = results.first {
                placeFurniture(furniture, at: firstResult.worldTransform, in: arView)
                
                let placedItem = PlacedFurnitureItem(
                    id: UUID(),
                    furniture: furniture,
                    position: firstResult.worldTransform.translation,
                    timestamp: Date()
                )
                
                DispatchQueue.main.async {
                    self.parent.placedFurniture.append(placedItem)
                }
            }
        }
        
        private func placeFurniture(_ furniture: FurnitureModel, at transform: simd_float4x4, in arView: ARView) {
            // Create a simple geometric representation of furniture
            let mesh: MeshResource
            let size: Float = 0.3
            
            switch furniture.name.lowercased() {
            case "chair":
                mesh = MeshResource.generateBox(width: size, height: size * 1.5, depth: size)
            case "table":
                mesh = MeshResource.generateBox(width: size * 1.5, height: size * 0.3, depth: size)
            case "sofa":
                mesh = MeshResource.generateBox(width: size * 2, height: size, depth: size * 0.8)
            case "lamp":
                mesh = MeshResource.generateBox(width: size * 0.3, height: size * 2, depth: size * 0.3)
            case "plant":
                mesh = MeshResource.generateSphere(radius: size * 0.4)
            case "tv":
                mesh = MeshResource.generateBox(width: size * 1.2, height: size * 0.8, depth: size * 0.1)
            default:
                mesh = MeshResource.generateBox(width: size, height: size, depth: size)
            }
            
            let material = SimpleMaterial(color: UIColor(furniture.color), isMetallic: false)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            
            let anchor = AnchorEntity(world: transform)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
        }
    }
}

struct FurnitureModel {
    let name: String
    let modelName: String
    let icon: String
    let color: Color
}

struct PlacedFurnitureItem: Identifiable {
    let id: UUID
    let furniture: FurnitureModel
    let position: simd_float3
    let timestamp: Date
}

#Preview {
    RealFurniturePlacementView()
}