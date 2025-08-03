import SwiftUI

// MARK: - Furniture Item Card

public struct FurnitureItemCard: View {
    let item: FurnitureItem
    let style: CardStyle
    let onTap: () async -> Void
    
    @State private var isLoading = false
    @State private var isFavorite = false
    
    public init(item: FurnitureItem, style: CardStyle = .standard, onTap: @escaping () async -> Void) {
        self.item = item
        self.style = style
        self.onTap = onTap
    }
    
    public var body: some View {
        Button {
            Task {
                await onTap()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Thumbnail
                thumbnailView
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    // Title and Favorite
                    HStack {
                        Text(item.name)
                            .font(style.titleFont)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                        
                        favoriteButton
                    }
                    
                    // Brand
                    if let brand = item.brand {
                        Text(brand)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Price
                    HStack {
                        priceView
                        Spacer()
                        
                        if item.availability.inStock {
                            stockIndicator
                        }
                    }
                    
                    // Features (for featured style only)
                    if style == .featured && !item.metadata.functionalFeatures.isEmpty {
                        featuresView
                    }
                }
                .padding(style.contentPadding)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .onAppear {
            isFavorite = false // This would check against catalog favorites
        }
    }
    
    // MARK: - Thumbnail View
    
    private var thumbnailView: some View {
        ZStack {
            // Placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .aspectRatio(style.aspectRatio, contentMode: .fit)
            
            // Thumbnail Image
            if let thumbnailData = item.model3D.thumbnail,
               let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
                    .cornerRadius(8)
            } else {
                // Default placeholder
                VStack(spacing: 8) {
                    Image(systemName: item.category.icon)
                        .font(.system(size: style.placeholderIconSize))
                        .foregroundColor(.secondary)
                    
                    if style == .featured {
                        Text("Loading...")
                            .font(.caption)
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
                    
                    Spacer()
                    
                    if item.pricing.isOnSale {
                        Badge(text: "Sale", color: .red)
                    }
                }
                Spacer()
            }
            .padding(8)
        }
    }
    
    // MARK: - Price View
    
    private var priceView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if item.pricing.isOnSale, let salePrice = item.pricing.salePrice {
                HStack(spacing: 4) {
                    Text("$\(salePrice, specifier: "%.2f")")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if let retailPrice = item.pricing.retailPrice {
                        Text("$\(retailPrice, specifier: "%.2f")")
                            .font(.caption)
                            .strikethrough()
                            .foregroundColor(.secondary)
                    }
                }
                
                if let discount = item.pricing.discountPercentage {
                    Text("\(Int(discount))% off")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } else if let price = item.pricing.retailPrice {
                Text("$\(price, specifier: "%.2f")")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            } else {
                Text("Price on request")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Stock Indicator
    
    private var stockIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(item.availability.stockLevel.color))
                .frame(width: 6, height: 6)
            
            Text(item.availability.stockLevel.displayName)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Features View
    
    private var featuresView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(item.metadata.functionalFeatures.prefix(3)), id: \.self) { feature in
                    HStack(spacing: 4) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 10))
                        Text(feature.displayName)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray6))
                    .cornerRadius(4)
                }
            }
        }
    }
    
    // MARK: - Favorite Button
    
    private var favoriteButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isFavorite.toggle()
                // TODO: Update catalog favorites
            }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 16))
                .foregroundColor(isFavorite ? .red : .secondary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Card Style

public enum CardStyle {
    case standard
    case compact
    case featured
    
    var titleFont: Font {
        switch self {
        case .standard: return .headline
        case .compact: return .subheadline
        case .featured: return .title3
        }
    }
    
    var contentPadding: CGFloat {
        switch self {
        case .standard: return 12
        case .compact: return 8
        case .featured: return 16
        }
    }
    
    var aspectRatio: CGFloat {
        switch self {
        case .standard: return 1.2
        case .compact: return 1.0
        case .featured: return 1.3
        }
    }
    
    var placeholderIconSize: CGFloat {
        switch self {
        case .standard: return 24
        case .compact: return 20
        case .featured: return 32
        }
    }
}

// MARK: - Badge

private struct Badge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(4)
    }
}

// MARK: - Furniture Item Row

public struct FurnitureItemRow: View {
    let item: FurnitureItem
    let onTap: () async -> Void
    
    public init(item: FurnitureItem, onTap: @escaping () async -> Void) {
        self.item = item
        self.onTap = onTap
    }
    
    public var body: some View {
        Button {
            Task {
                await onTap()
            }
        } label: {
            HStack(spacing: 12) {
                // Thumbnail
                thumbnailView
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if let price = item.pricing.currentPrice {
                            Text("$\(price, specifier: "%.2f")")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }
                    }
                    
                    if let brand = item.brand {
                        Text(brand)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(item.formattedDimensions)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Features
                    if !item.metadata.functionalFeatures.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(item.metadata.functionalFeatures.prefix(4)), id: \.self) { feature in
                                    Text(feature.displayName)
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(3)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(width: 60, height: 60)
            
            if let thumbnailData = item.model3D.thumbnail,
               let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipped()
                    .cornerRadius(8)
            } else {
                Image(systemName: item.category.icon)
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        FurnitureItemCard(
            item: FurnitureItem(
                name: "Modern Sofa",
                description: "A beautiful modern sofa",
                category: .seating,
                subcategory: .sofa,
                brand: "DesignCo",
                model3D: Model3D(
                    name: "sofa.usdz",
                    fileName: "sofa.usdz",
                    fileSize: 1024,
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
                    dimensions: FurnitureDimensions(width: 2.1, depth: 0.9, height: 0.8),
                    materials: [.fabric],
                    colors: [FurnitureColor(name: "Gray", hexValue: "#888888", colorFamily: .neutral)],
                    styles: [.modern],
                    weight: 45.0,
                    functionalFeatures: [.modular, .storage]
                ),
                pricing: FurniturePricing(retailPrice: 899.99),
                isFeatured: true
            ),
            style: .featured
        ) {}
        .frame(width: 280)
        
        Spacer()
    }
    .padding()
}