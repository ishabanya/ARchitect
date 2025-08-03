import SwiftUI
import RealityKit

// MARK: - Furniture Item Detail View

public struct FurnitureItemDetailView: View {
    let item: FurnitureItem
    @StateObject private var catalog = FurnitureCatalog()
    @StateObject private var modelManager = ModelManager()
    
    @State private var selectedImageIndex = 0
    @State private var isFavorite = false
    @State private var showingARPreview = false
    @State private var showingRecommendations = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @Environment(\.dismiss) private var dismiss
    
    public init(item: FurnitureItem) {
        self.item = item
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Image Gallery
                imageGallery
                
                // Main Info
                mainInfoSection
                
                // Action Buttons
                actionButtons
                
                // Specifications
                specificationsSection
                
                // Features
                if !item.metadata.functionalFeatures.isEmpty {
                    featuresSection
                }
                
                // Pricing and Availability
                pricingSection
                
                // Similar Items
                similarItemsSection
                
                // Recommendations
                recommendationsSection
            }
            .padding(.bottom, 100) // Space for floating buttons
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                favoriteButton
            }
        }
        .overlay(alignment: .bottom) {
            floatingActionBar
        }
        .sheet(isPresented: $showingARPreview) {
            ARPreviewView(item: item)
        }
        .sheet(isPresented: $showingRecommendations) {
            RecommendationsSheet(item: item, catalog: catalog)
        }
        .onAppear {
            Task {
                await catalog.addToRecent(item)
                isFavorite = catalog.favoriteItems.contains(where: { $0.id == item.id })
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Image Gallery
    
    private var imageGallery: some View {
        ZStack {
            // Main Image
            if let thumbnailData = item.model3D.thumbnail,
               let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 300)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 300)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: item.category.icon)
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            
                            Text("Loading Preview...")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }
            }
            
            // Badges
            VStack {
                HStack {
                    if item.isFeatured {
                        Badge(text: "Featured", color: .orange)
                    }
                    
                    if item.isCustom {
                        Badge(text: "Custom", color: .blue)
                    }
                    
                    if item.pricing.isOnSale {
                        Badge(text: "Sale", color: .red)
                    }
                    
                    Spacer()
                }
                .padding()
                
                Spacer()
                
                // AR Preview Button
                HStack {
                    Spacer()
                    
                    Button {
                        showingARPreview = true
                    } label: {
                        HStack {
                            Image(systemName: "arkit")
                            Text("AR Preview")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .cornerRadius(20)
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Main Info Section
    
    private var mainInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let brand = item.brand {
                        Text("by \(brand)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Rating
                if item.userRating > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        
                        Text(String(format: "%.1f", item.userRating))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
            
            Text(item.description)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                showingRecommendations = true
            } label: {
                HStack {
                    Image(systemName: "lightbulb")
                    Text("Recommendations")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
            }
            
            Button {
                Task {
                    await shareItem()
                }
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Specifications Section
    
    private var specificationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Specifications")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                SpecRow(title: "Dimensions", value: item.formattedDimensions)
                SpecRow(title: "Weight", value: "\(item.metadata.weight, specifier: "%.1f") kg")
                SpecRow(title: "Materials", value: item.metadata.materials.map { $0.displayName }.joined(separator: ", "))
                SpecRow(title: "Colors", value: item.metadata.colors.map { $0.name }.joined(separator: ", "))
                SpecRow(title: "Styles", value: item.metadata.styles.map { $0.displayName }.joined(separator: ", "))
                SpecRow(title: "Assembly Required", value: item.metadata.assemblyRequired ? "Yes" : "No")
                
                if let warranty = item.metadata.warranty {
                    SpecRow(title: "Warranty", value: "\(warranty.duration) years (\(warranty.type.displayName))")
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Features Section
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Features")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(item.metadata.functionalFeatures, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: feature.icon)
                            .foregroundColor(.accentColor)
                            .frame(width: 20)
                        
                        Text(feature.displayName)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Pricing Section
    
    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pricing & Availability")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                // Price
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if item.pricing.isOnSale, let salePrice = item.pricing.salePrice {
                            HStack(spacing: 8) {
                                Text("$\(salePrice, specifier: "%.2f")")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                
                                if let retailPrice = item.pricing.retailPrice {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("$\(retailPrice, specifier: "%.2f")")
                                            .font(.subheadline)
                                            .strikethrough()
                                            .foregroundColor(.secondary)
                                        
                                        if let discount = item.pricing.discountPercentage {
                                            Text("\(Int(discount))% off")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                                .fontWeight(.medium)
                                        }
                                    }
                                }
                            }
                        } else if let price = item.pricing.retailPrice {
                            Text("$\(price, specifier: "%.2f")")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        } else {
                            Text("Price on request")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(item.pricing.priceRange.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Stock Status
                HStack {
                    Circle()
                        .fill(Color(item.availability.stockLevel.color))
                        .frame(width: 12, height: 12)
                    
                    Text(item.availability.stockLevel.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                }
                
                // Delivery
                if let deliveryDate = item.availability.estimatedDelivery {
                    HStack {
                        Image(systemName: "truck")
                            .foregroundColor(.secondary)
                        
                        Text("Estimated delivery: \(deliveryDate, style: .date)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Similar Items Section
    
    private var similarItemsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Similar Items")
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(catalog.getSimilarItems(to: item)) { similarItem in
                        FurnitureItemCard(item: similarItem, style: .compact) {
                            // Navigate to similar item
                        }
                        .frame(width: 160)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Recommendations Section
    
    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("You Might Also Like")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("View All") {
                    showingRecommendations = true
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    // This would show recommended items based on the recommendation engine
                    ForEach(catalog.recentItems.prefix(5)) { recommendedItem in
                        FurnitureItemCard(item: recommendedItem, style: .compact) {
                            // Navigate to recommended item
                        }
                        .frame(width: 160)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Floating Action Bar
    
    private var floatingActionBar: some View {
        HStack(spacing: 16) {
            Button {
                Task {
                    await toggleFavorite()
                }
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundColor(isFavorite ? .red : .primary)
                    .frame(width: 50, height: 50)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            
            Button {
                Task {
                    await placeInAR()
                }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arkit")
                        Text("Place in AR")
                    }
                }
                .font(.headline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.accentColor)
                .cornerRadius(25)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .disabled(isLoading)
        }
        .padding(.horizontal)
        .padding(.bottom, 34) // Safe area padding
        .background(
            LinearGradient(
                colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - Favorite Button
    
    private var favoriteButton: some View {
        Button {
            Task {
                await toggleFavorite()
            }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .foregroundColor(isFavorite ? .red : .primary)
        }
    }
    
    // MARK: - Helper Methods
    
    private func toggleFavorite() async {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isFavorite.toggle()
        }
        
        await catalog.toggleFavorite(item)
    }
    
    private func placeInAR() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Load the 3D model
            let entity = try await modelManager.loadModel(item.model3D)
            
            // This would transition to AR placement view
            // For now, just show AR preview
            showingARPreview = true
            
        } catch {
            errorMessage = "Failed to load 3D model: \(error.localizedDescription)"
        }
    }
    
    private func shareItem() async {
        // Implement sharing functionality
    }
}

// MARK: - Spec Row

private struct SpecRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Badge

private struct Badge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(6)
    }
}

// MARK: - AR Preview View Placeholder

private struct ARPreviewView: View {
    let item: FurnitureItem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack {
                    Spacer()
                    
                    Text("AR Preview")
                        .font(.title)
                        .foregroundColor(.white)
                    
                    Text("3D model preview would appear here")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                }
            }
            .navigationTitle("AR Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Recommendations Sheet Placeholder

private struct RecommendationsSheet: View {
    let item: FurnitureItem
    let catalog: FurnitureCatalog
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Smart Recommendations")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding()
                
                Text("Recommendations based on this item would appear here")
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .navigationTitle("Recommendations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        FurnitureItemDetailView(
            item: FurnitureItem(
                name: "Modern 3-Seat Sofa",
                description: "Contemporary three-seater sofa with clean lines and comfortable cushioning. Perfect for modern living spaces.",
                category: .seating,
                subcategory: .sofa,
                brand: "DesignCo",
                model3D: Model3D(
                    name: "modern_sofa.usdz",
                    fileName: "modern_sofa.usdz",
                    fileSize: 1024 * 1024,
                    format: .usdz,
                    metadata: ModelMetadata(
                        triangleCount: 5000,
                        vertexCount: 2500,
                        materialCount: 2,
                        textureCount: 2,
                        boundingBox: BoundingBox(
                            min: SIMD3<Float>(-1, 0, -1),
                            max: SIMD3<Float>(1, 1, 1)
                        ),
                        complexity: .medium,
                        estimatedLoadTime: 2.0
                    )
                ),
                metadata: FurnitureMetadata(
                    dimensions: FurnitureDimensions(width: 2.1, depth: 0.9, height: 0.8, seatHeight: 0.45),
                    materials: [.fabric, .wood],
                    colors: [FurnitureColor(name: "Charcoal Gray", hexValue: "#36454F", colorFamily: .neutral)],
                    styles: [.modern, .contemporary],
                    weight: 45.0,
                    assemblyRequired: true,
                    styleCompatibility: [.modern: 1.0, .contemporary: 0.9, .minimalist: 0.8],
                    functionalFeatures: [.modular, .storage],
                    placementSuggestions: [.livingArea, .floatingLayout]
                ),
                pricing: FurniturePricing(
                    retailPrice: 899.99,
                    salePrice: 699.99,
                    isOnSale: true
                ),
                tags: ["modern", "comfortable", "living room", "gray"],
                isFeatured: true,
                popularityScore: 0.8,
                userRating: 4.5
            )
        )
    }
}