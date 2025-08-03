import SwiftUI
import Combine

// MARK: - Furniture Catalog View

public struct FurnitureCatalogView: View {
    
    @StateObject private var catalog = FurnitureCatalog()
    @StateObject private var modelManager = ModelManager()
    @State private var selectedCategory: FurnitureCategory?
    @State private var showingFilters = false
    @State private var showingSearch = false
    @State private var searchText = ""
    @State private var selectedTab: CatalogTab = .browse
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom Tab Bar
                catalogTabBar
                
                // Content
                Group {
                    switch selectedTab {
                    case .browse:
                        browseView
                    case .search:
                        searchView
                    case .favorites:
                        favoritesView
                    case .recent:
                        recentView
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: selectedTab)
            }
            .navigationTitle("Furniture Catalog")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button {
                            showingFilters = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .foregroundColor(.primary)
                        }
                        
                        Button {
                            Task {
                                await catalog.syncWithCloud()
                            }
                        } label: {
                            Image(systemName: catalog.cloudSyncStatus.isLoading ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.down")
                                .foregroundColor(.primary)
                                .rotationEffect(.degrees(catalog.cloudSyncStatus.isLoading ? 360 : 0))
                                .animation(.linear(duration: 1).repeatForever(autoreverses: false), 
                                         value: catalog.cloudSyncStatus.isLoading)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FurnitureFiltersView(filters: $catalog.activeFilters)
            }
            .onAppear {
                Task {
                    await catalog.initialize()
                }
            }
        }
    }
    
    // MARK: - Tab Bar
    
    private var catalogTabBar: some View {
        HStack {
            ForEach(CatalogTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20))
                        
                        Text(tab.title)
                            .font(.caption)
                    }
                    .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
    
    // MARK: - Browse View
    
    private var browseView: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Featured Items
                if !catalog.featuredItems.isEmpty {
                    featuredSection
                }
                
                // Categories
                categoriesSection
                
                // Selected Category Items
                if let selectedCategory = selectedCategory {
                    categoryItemsSection(category: selectedCategory)
                }
            }
            .padding()
        }
        .refreshable {
            await catalog.syncWithCloud()
        }
    }
    
    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Featured")
                .font(.title2)
                .fontWeight(.semibold)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(catalog.featuredItems) { item in
                        FurnitureItemCard(item: item, style: .featured) {
                            await handleItemSelection(item)
                        }
                        .frame(width: 280)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Categories")
                .font(.title2)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(catalog.categories, id: \.self) { category in
                    CategoryCard(
                        category: category,
                        itemCount: catalog.getItems(for: category).count,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = selectedCategory == category ? nil : category
                    }
                }
            }
        }
    }
    
    private func categoryItemsSection(category: FurnitureCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(category.displayName)
                .font(.title2)
                .fontWeight(.semibold)
            
            let items = catalog.getItems(for: category)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                ForEach(items.prefix(10)) { item in
                    FurnitureItemCard(item: item, style: .compact) {
                        await handleItemSelection(item)
                    }
                }
            }
            
            if items.count > 10 {
                NavigationLink(destination: CategoryDetailView(category: category, catalog: catalog)) {
                    Text("View All (\(items.count))")
                        .foregroundColor(.accentColor)
                        .padding(.vertical, 8)
                }
            }
        }
    }
    
    // MARK: - Search View
    
    private var searchView: some View {
        VStack {
            SearchBar(text: $searchText, onSearchButtonClicked: {
                Task {
                    await catalog.search(searchText)
                }
            })
            .padding(.horizontal)
            
            if catalog.searchResults.isEmpty && !searchText.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("Try adjusting your search terms or browse categories instead")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                        ForEach(catalog.searchResults) { item in
                            FurnitureItemCard(item: item, style: .compact) {
                                await handleItemSelection(item)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Favorites View
    
    private var favoritesView: some View {
        Group {
            if catalog.favoriteItems.isEmpty {
                ContentUnavailableView(
                    "No Favorites",
                    systemImage: "heart",
                    description: Text("Items you favorite will appear here")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                        ForEach(catalog.favoriteItems) { item in
                            FurnitureItemCard(item: item, style: .compact) {
                                await handleItemSelection(item)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Recent View
    
    private var recentView: some View {
        Group {
            if catalog.recentItems.isEmpty {
                ContentUnavailableView(
                    "No Recent Items",
                    systemImage: "clock",
                    description: Text("Items you view will appear here")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(catalog.recentItems) { item in
                            FurnitureItemRow(item: item) {
                                await handleItemSelection(item)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleItemSelection(_ item: FurnitureItem) async {
        await catalog.addToRecent(item)
        // Navigate to item detail or place in AR
    }
}

// MARK: - Catalog Tab Enum

private enum CatalogTab: String, CaseIterable {
    case browse = "browse"
    case search = "search"
    case favorites = "favorites"
    case recent = "recent"
    
    var title: String {
        switch self {
        case .browse: return "Browse"
        case .search: return "Search"
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        }
    }
    
    var icon: String {
        switch self {
        case .browse: return "square.grid.2x2"
        case .search: return "magnifyingglass"
        case .favorites: return "heart"
        case .recent: return "clock"
        }
    }
}

// MARK: - Category Card

private struct CategoryCard: View {
    let category: FurnitureCategory
    let itemCount: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 30))
                    .foregroundColor(isSelected ? .white : .accentColor)
                
                Text(category.displayName)
                    .font(.headline)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text("\(itemCount) items")
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator), lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Search Bar

private struct SearchBar: View {
    @Binding var text: String
    let onSearchButtonClicked: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search furniture...", text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .onSubmit {
                    onSearchButtonClicked()
                }
            
            if !text.isEmpty {
                Button {
                    text = ""
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
}

#Preview {
    FurnitureCatalogView()
}