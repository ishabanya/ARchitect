import SwiftUI

// MARK: - Category Detail View

public struct CategoryDetailView: View {
    let category: FurnitureCategory
    let catalog: FurnitureCatalog
    
    @State private var selectedSubcategory: FurnitureSubcategory?
    @State private var sortOption: SortOption = .popularity
    @State private var showingFilters = false
    @State private var searchText = ""
    
    public init(category: FurnitureCategory, catalog: FurnitureCatalog) {
        self.category = category
        self.catalog = catalog
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Search and Sort Bar
            searchAndSortBar
            
            // Subcategory Filter
            subcategoryFilter
            
            // Items Grid
            itemsGrid
        }
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingFilters = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(.primary)
                }
            }
        }
        .sheet(isPresented: $showingFilters) {
            FurnitureFiltersView(filters: .constant(catalog.activeFilters))
        }
    }
    
    // MARK: - Search and Sort Bar
    
    private var searchAndSortBar: some View {
        HStack {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search \(category.displayName.lowercased())...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
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
            
            // Sort
            Menu {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button {
                        sortOption = option
                    } label: {
                        HStack {
                            Text(option.displayName)
                            if sortOption == option {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text("Sort")
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Subcategory Filter
    
    private var subcategoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // All button
                SubcategoryChip(
                    title: "All",
                    isSelected: selectedSubcategory == nil
                ) {
                    selectedSubcategory = nil
                }
                
                // Subcategory buttons
                ForEach(category.subcategories, id: \.self) { subcategory in
                    SubcategoryChip(
                        title: subcategory.displayName,
                        isSelected: selectedSubcategory == subcategory
                    ) {
                        selectedSubcategory = selectedSubcategory == subcategory ? nil : subcategory
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
    
    // MARK: - Items Grid
    
    private var itemsGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                ForEach(filteredAndSortedItems) { item in
                    FurnitureItemCard(item: item, style: .standard) {
                        await handleItemSelection(item)
                    }
                }
            }
            .padding()
        }
        .refreshable {
            await catalog.syncWithCloud()
        }
    }
    
    // MARK: - Computed Properties
    
    private var filteredAndSortedItems: [FurnitureItem] {
        var items = catalog.getItems(for: category)
        
        // Apply subcategory filter
        if let selectedSubcategory = selectedSubcategory {
            items = items.filter { $0.subcategory == selectedSubcategory }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            items = items.filter { item in
                item.name.localizedCaseInsensitiveContains(searchText) ||
                item.description.localizedCaseInsensitiveContains(searchText) ||
                item.brand?.localizedCaseInsensitiveContains(searchText) == true ||
                item.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        
        // Apply sorting
        switch sortOption {
        case .name:
            items.sort { $0.name < $1.name }
        case .priceLowToHigh:
            items.sort { ($0.pricing.currentPrice ?? 0) < ($1.pricing.currentPrice ?? 0) }
        case .priceHighToLow:
            items.sort { ($0.pricing.currentPrice ?? 0) > ($1.pricing.currentPrice ?? 0) }
        case .newest:
            items.sort { $0.dateAdded > $1.dateAdded }
        case .popularity:
            items.sort { $0.popularityScore > $1.popularityScore }
        case .rating:
            items.sort { $0.userRating > $1.userRating }
        }
        
        return items
    }
    
    // MARK: - Helper Methods
    
    private func handleItemSelection(_ item: FurnitureItem) async {
        await catalog.addToRecent(item)
        // Navigate to item detail or place in AR
    }
}

// MARK: - Subcategory Chip

private struct SubcategoryChip: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Color.accentColor : Color(.systemGray6))
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Sort Option

private enum SortOption: String, CaseIterable {
    case name = "name"
    case priceLowToHigh = "price_low_high"
    case priceHighToLow = "price_high_low"
    case newest = "newest"
    case popularity = "popularity"
    case rating = "rating"
    
    var displayName: String {
        switch self {
        case .name: return "Name A-Z"
        case .priceLowToHigh: return "Price: Low to High"
        case .priceHighToLow: return "Price: High to Low"
        case .newest: return "Newest First"
        case .popularity: return "Most Popular"
        case .rating: return "Highest Rated"
        }
    }
}

#Preview {
    NavigationView {
        CategoryDetailView(
            category: .seating,
            catalog: FurnitureCatalog()
        )
    }
}