import SwiftUI
import ARKit

struct SimpleContentView: View {
    @State private var showingRoomScanning = false
    @State private var showingFurnitureCatalog = false
    @State private var showingMeasurementTools = false
    @State private var showingAIOptimization = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                headerSection
                featuresGrid
                Spacer()
            }
            .padding()
            .navigationTitle("ARchitect")
            .navigationBarTitleDisplayMode(.large)
            .fullScreenCover(isPresented: $showingRoomScanning) {
                RealRoomScanningView()
            }
            .fullScreenCover(isPresented: $showingFurnitureCatalog) {
                RealFurniturePlacementView()
            }
            .fullScreenCover(isPresented: $showingMeasurementTools) {
                RealMeasurementView()
            }
            .sheet(isPresented: $showingAIOptimization) {
                AIOptimizationView()
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "house.and.flag")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Transform Your Space")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Visualize furniture placement with AR")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var featuresGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 20) {
            FeatureCard(
                icon: "viewfinder",
                title: "Scan Room",
                description: "3D room scanning",
                action: { showingRoomScanning = true }
            )
            
            FeatureCard(
                icon: "sofa",
                title: "Furniture",
                description: "Browse catalog",
                action: { showingFurnitureCatalog = true }
            )
            
            FeatureCard(
                icon: "ruler",
                title: "Measure",
                description: "Precise measurements",
                action: { showingMeasurementTools = true }
            )
            
            FeatureCard(
                icon: "brain.head.profile",
                title: "AI Optimize",
                description: "Smart suggestions",
                action: { showingAIOptimization = true }
            )
        }
    }
}

struct SimpleRoomScanningView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var isScanning = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                VStack(spacing: 16) {
                    Text("Room Scanner")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Scan your room to create a 3D model for furniture placement")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                if isScanning {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Scanning room...")
                            .font(.headline)
                    }
                } else {
                    Button(action: { isScanning = true }) {
                        HStack {
                            Image(systemName: "camera.viewfinder")
                            Text("Start Scanning")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.blue)
                        .cornerRadius(16)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Room Scanner")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct SimpleFurnitureCatalogView: View {
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                    ForEach(sampleFurniture, id: \.name) { item in
                        FurnitureItemView(item: item)
                    }
                }
                .padding()
            }
            .navigationTitle("Furniture Catalog")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    private let sampleFurniture = [
        FurnitureItem(name: "Modern Sofa", category: "Seating", image: "sofa"),
        FurnitureItem(name: "Coffee Table", category: "Tables", image: "table"),
        FurnitureItem(name: "Floor Lamp", category: "Lighting", image: "lamp.floor"),
        FurnitureItem(name: "Bookshelf", category: "Storage", image: "books.vertical"),
        FurnitureItem(name: "Dining Chair", category: "Seating", image: "chair"),
        FurnitureItem(name: "TV Stand", category: "Entertainment", image: "tv")
    ]
}

struct FurnitureItem {
    let name: String
    let category: String
    let image: String
}

struct FurnitureItemView: View {
    let item: FurnitureItem
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: item.image)
                .font(.system(size: 40))
                .foregroundColor(.blue)
                .frame(height: 60)
            
            Text(item.name)
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text(item.category)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct SimpleMeasurementToolsView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var measurements: [String] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Image(systemName: "ruler")
                    .font(.system(size: 80))
                    .foregroundColor(.orange)
                
                VStack(spacing: 16) {
                    Text("Measurement Tools")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Tap in AR space to measure distances and dimensions")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                if !measurements.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Measurements:")
                            .font(.headline)
                        
                        ForEach(measurements, id: \.self) { measurement in
                            Text("• \(measurement)")
                                .font(.body)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                Button(action: addSampleMeasurement) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add Measurement")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.orange)
                    .cornerRadius(16)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Measurements")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    private func addSampleMeasurement() {
        let sampleMeasurements = [
            "Wall length: 3.2m",
            "Table width: 1.8m", 
            "Room height: 2.4m",
            "Window width: 1.2m"
        ]
        if let randomMeasurement = sampleMeasurements.randomElement() {
            measurements.append(randomMeasurement)
        }
    }
}

struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(Color(.systemGray6))
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    SimpleContentView()
}