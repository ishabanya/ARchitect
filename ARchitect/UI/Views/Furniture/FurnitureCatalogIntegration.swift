import SwiftUI
import RealityKit

// MARK: - Furniture Catalog Integration

public struct FurnitureCatalogIntegration {
    
    /// Create a furniture catalog button for integration into other views
    public static func catalogButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "chair.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading) {
                    Text("Furniture Catalog")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Browse 3D furniture models")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    /// Create a quick access furniture toolbar
    public static func quickAccessToolbar(catalog: FurnitureCatalog) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(FurnitureCategory.allCases.prefix(6), id: \.self) { category in
                    quickCategoryButton(category: category, catalog: catalog)
                }
            }
            .padding(.horizontal)
        }
    }
    
    private static func quickCategoryButton(category: FurnitureCategory, catalog: FurnitureCatalog) -> some View {
        VStack(spacing: 6) {
            Image(systemName: category.icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.accentColor)
                .clipShape(Circle())
            
            Text(category.displayName)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .frame(width: 60)
        .onTapGesture {
            // Navigate to category
        }
    }
    
    /// Create a furniture item quick preview card
    public static func quickPreviewCard(item: FurnitureItem, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Thumbnail
                thumbnailView(for: item)
                    .aspectRatio(1, contentMode: .fit)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    if let price = item.pricing.currentPrice {
                        Text("$\(price, specifier: "%.0f")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(width: 100)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private static func thumbnailView(for item: FurnitureItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray5))
            
            if let thumbnailData = item.model3D.thumbnail,
               let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
                    .cornerRadius(6)
            } else {
                Image(systemName: item.category.icon)
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .clipped()
        .cornerRadius(6)
    }
}

// MARK: - AR Placement Integration

public struct ARPlacementIntegration {
    
    /// Create an AR placement button for furniture items
    public static func placementButton(item: FurnitureItem, onPlace: @escaping () async -> Void) -> some View {
        Button {
            Task {
                await onPlace()
            }
        } label: {
            HStack {
                Image(systemName: "arkit")
                    .font(.headline)
                
                Text("Place in AR")
                    .font(.headline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.accentColor)
            .cornerRadius(8)
        }
    }
    
    /// Create a floating AR action button
    public static func floatingARButton(onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Image(systemName: "arkit")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - Search Integration

public struct FurnitureSearchIntegration {
    
    /// Create a search bar for furniture catalog
    public static func searchBar(text: Binding<String>, onSearch: @escaping (String) -> Void) -> some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search furniture...", text: text)
                .textFieldStyle(.plain)
                .onSubmit {
                    onSearch(text.wrappedValue)
                }
            
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    /// Create quick search suggestions
    public static func searchSuggestions(suggestions: [String], onSelect: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        onSelect(suggestion)
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Model Loading Integration

public struct ModelLoadingIntegration {
    
    /// Create a loading indicator for 3D models
    public static func loadingIndicator(progress: Float) -> some View {
        VStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                .scaleEffect(1.5)
            
            Text("Loading 3D Model...")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .foregroundColor(.tertiary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
    
    /// Create a model preview placeholder
    public static func modelPreviewPlaceholder(category: FurnitureCategory) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray5))
                .aspectRatio(1, contentMode: .fit)
            
            VStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                
                Text("3D Preview Loading...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Extension for Easy Integration

extension View {
    /// Add furniture catalog integration to any view
    public func withFurnitureCatalog() -> some View {
        self.environmentObject(FurnitureCatalog())
    }
    
    /// Add model manager integration to any view
    public func withModelManager() -> some View {
        self.environmentObject(ModelManager())
    }
}

#Preview {
    VStack(spacing: 20) {
        FurnitureCatalogIntegration.catalogButton {
            print("Catalog tapped")
        }
        
        FurnitureSearchIntegration.searchBar(text: .constant("")) { query in
            print("Search: \(query)")
        }
        
        ModelLoadingIntegration.loadingIndicator(progress: 0.7)
        
        ARPlacementIntegration.floatingARButton {
            print("AR button tapped")
        }
    }
    .padding()
}