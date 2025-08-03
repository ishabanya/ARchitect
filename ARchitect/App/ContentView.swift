import SwiftUI
import ARKit

struct ContentView: View {
    @State private var showingRoomScanning = false
    @State private var showingFurnitureCatalog = false
    @State private var showingMeasurementTools = false
    
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
                action: { /* AI optimization */ }
            )
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
    ContentView()
}