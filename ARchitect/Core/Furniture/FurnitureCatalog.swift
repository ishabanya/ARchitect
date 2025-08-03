import Foundation
import Combine
import UIKit

// MARK: - Furniture Catalog

@MainActor
public class FurnitureCatalog: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var categories: [FurnitureCategory] = FurnitureCategory.allCases
    @Published public var featuredItems: [FurnitureItem] = []
    @Published public var recentItems: [FurnitureItem] = []
    @Published public var favoriteItems: [FurnitureItem] = []
    @Published public var isLoading = false
    @Published public var searchResults: [FurnitureItem] = []
    @Published public var currentSearchQuery: String = ""
    @Published public var activeFilters: FurnitureFilters = FurnitureFilters()
    @Published public var totalItemsCount: Int = 0
    @Published public var cloudSyncStatus: CloudSyncStatus = .idle
    
    // MARK: - Private Properties
    private var allItems: [FurnitureItem] = []
    private var itemsByCategory: [FurnitureCategory: [FurnitureItem]] = [:]
    private let persistenceManager: FurniturePersistenceManager
    private let cloudSyncManager: FurnitureCloudSyncManager
    private let recommendationEngine: FurnitureRecommendationEngine
    private var cancellables = Set<AnyCancellable>()
    
    // Configuration
    private let maxRecentItems = 20
    private let maxFeaturedItems = 10
    private let searchDebounceTime: TimeInterval = 0.5
    
    public init() {
        self.persistenceManager = FurniturePersistenceManager()
        self.cloudSyncManager = FurnitureCloudSyncManager()
        self.recommendationEngine = FurnitureRecommendationEngine()
        
        setupObservers()
        
        Task {
            await initialize()
        }
        
        logInfo("Furniture catalog initialized", category: .general)
    }
    
    // MARK: - Public Methods
    
    /// Initialize the catalog
    public func initialize() async {
        isLoading = true
        
        do {
            // Load cached data first
            let cachedData = try await persistenceManager.loadCatalogData()
            await updateCatalogData(cachedData)
            
            // Start cloud sync in background
            Task {
                await syncWithCloud()
            }
            
            logInfo("Catalog initialized with \(allItems.count) items", category: .general)
            
        } catch {
            logError("Failed to initialize catalog: \(error)", category: .general)
            
            // Load default/built-in items if cache fails
            await loadDefaultItems()
        }
        
        isLoading = false
    }
    
    /// Get items for a specific category
    public func getItems(for category: FurnitureCategory) -> [FurnitureItem] {
        return itemsByCategory[category] ?? []
    }
    
    /// Get items for a specific subcategory
    public func getItems(for subcategory: FurnitureSubcategory) -> [FurnitureItem] {
        return allItems.filter { $0.subcategory == subcategory }
    }
    
    /// Search furniture items
    public func search(_ query: String) async {
        currentSearchQuery = query
        
        if query.isEmpty {
            searchResults = []
            return
        }
        
        // Debounce search
        try? await Task.sleep(nanoseconds: UInt64(searchDebounceTime * 1_000_000_000))
        
        // Check if query is still current
        guard currentSearchQuery == query else { return }
        
        let results = performSearch(query: query, items: getFilteredItems())
        searchResults = results
        
        logDebug("Search completed", category: .general, context: LogContext(customData: [
            "query": query,
            "results_count": results.count
        ]))
    }
    
    /// Apply filters to the catalog
    public func applyFilters(_ filters: FurnitureFilters) {
        activeFilters = filters
        
        // Re-run search if active
        if !currentSearchQuery.isEmpty {
            Task {
                await search(currentSearchQuery)
            }
        }
    }
    
    /// Clear all filters
    public func clearFilters() {
        activeFilters = FurnitureFilters()
        
        // Re-run search if active
        if !currentSearchQuery.isEmpty {
            Task {
                await search(currentSearchQuery)
            }
        }
    }
    
    /// Add item to favorites
    public func addToFavorites(_ item: FurnitureItem) async {
        guard !favoriteItems.contains(where: { $0.id == item.id }) else { return }
        
        favoriteItems.append(item)
        
        do {
            try await persistenceManager.saveFavorites(favoriteItems.map { $0.id })
            
            // Sync with cloud
            Task {
                await cloudSyncManager.syncFavorites(favoriteItems.map { $0.id })
            }
            
            logDebug("Added item to favorites", category: .general, context: LogContext(customData: [
                "item_id": item.id.uuidString,
                "item_name": item.name
            ]))
            
        } catch {
            logError("Failed to save favorites: \(error)", category: .general)
        }
    }
    
    /// Remove item from favorites
    public func removeFromFavorites(_ item: FurnitureItem) async {
        favoriteItems.removeAll { $0.id == item.id }
        
        do {
            try await persistenceManager.saveFavorites(favoriteItems.map { $0.id })
            
            // Sync with cloud
            Task {
                await cloudSyncManager.syncFavorites(favoriteItems.map { $0.id })
            }
            
        } catch {
            logError("Failed to save favorites: \(error)", category: .general)
        }
    }
    
    /// Toggle favorite status
    public func toggleFavorite(_ item: FurnitureItem) async {
        if favoriteItems.contains(where: { $0.id == item.id }) {
            await removeFromFavorites(item)
        } else {
            await addToFavorites(item)
        }
    }
    
    /// Add item to recent items
    public func addToRecent(_ item: FurnitureItem) async {
        // Remove if already exists
        recentItems.removeAll { $0.id == item.id }
        
        // Add to front
        recentItems.insert(item, at: 0)
        
        // Maintain limit
        if recentItems.count > maxRecentItems {
            recentItems = Array(recentItems.prefix(maxRecentItems))
        }
        
        do {
            try await persistenceManager.saveRecentItems(recentItems.map { $0.id })
        } catch {
            logError("Failed to save recent items: \(error)", category: .general)
        }
    }
    
    /// Get recommendations for a room
    public func getRecommendations(for room: RoomInfo) async -> [FurnitureItem] {
        return await recommendationEngine.getRecommendations(
            for: room,
            from: allItems,
            userFavorites: favoriteItems,
            userRecent: recentItems
        )
    }
    
    /// Get similar items
    public func getSimilarItems(to item: FurnitureItem, limit: Int = 5) -> [FurnitureItem] {
        return recommendationEngine.getSimilarItems(
            to: item,
            from: allItems,
            limit: limit
        )
    }
    
    /// Import custom furniture item
    public func importCustomItem(_ item: FurnitureItem) async throws {
        var customItem = item
        customItem.isCustom = true
        
        // Add to catalog
        allItems.append(customItem)
        updateCategorizedItems()
        
        // Save to persistence
        try await persistenceManager.saveCustomItem(customItem)
        
        // Sync with cloud
        Task {
            await cloudSyncManager.syncCustomItem(customItem)
        }
        
        totalItemsCount = allItems.count
        
        logInfo("Imported custom furniture item", category: .general, context: LogContext(customData: [
            "item_id": customItem.id.uuidString,
            "item_name": customItem.name
        ]))
    }
    
    /// Delete custom item
    public func deleteCustomItem(_ itemID: UUID) async throws {
        guard let item = allItems.first(where: { $0.id == itemID && $0.isCustom }) else {
            throw FurnitureCatalogError.itemNotFound
        }
        
        // Remove from catalog
        allItems.removeAll { $0.id == itemID }
        updateCategorizedItems()
        
        // Remove from favorites and recent
        favoriteItems.removeAll { $0.id == itemID }
        recentItems.removeAll { $0.id == itemID }
        
        // Delete from persistence
        try await persistenceManager.deleteCustomItem(itemID)
        
        // Sync deletion with cloud
        Task {
            await cloudSyncManager.deleteCustomItem(itemID)
        }
        
        totalItemsCount = allItems.count
        
        logInfo("Deleted custom furniture item", category: .general, context: LogContext(customData: [
            "item_id": itemID.uuidString
        ]))
    }
    
    /// Sync with cloud
    public func syncWithCloud() async {
        cloudSyncStatus = .syncing
        
        do {
            let cloudData = try await cloudSyncManager.syncCatalog()
            
            // Update with cloud data
            await updateCatalogData(cloudData)
            
            // Save updated data locally
            try await persistenceManager.saveCatalogData(CatalogData(
                items: allItems,
                favorites: favoriteItems.map { $0.id },
                recent: recentItems.map { $0.id }
            ))
            
            cloudSyncStatus = .success
            
            logInfo("Cloud sync completed successfully", category: .general)
            
        } catch {
            cloudSyncStatus = .failed(error.localizedDescription)
            logError("Cloud sync failed: \(error)", category: .general)
        }
    }
    
    /// Get catalog statistics
    public func getCatalogStatistics() -> CatalogStatistics {
        var itemsByCategory: [FurnitureCategory: Int] = [:]
        var itemsByPriceRange: [PriceRange: Int] = [:]
        var itemsByStyle: [FurnitureStyle: Int] = [:]
        
        for item in allItems {
            itemsByCategory[item.category, default: 0] += 1
            itemsByPriceRange[item.pricing.priceRange, default: 0] += 1
            
            for style in item.metadata.styles {
                itemsByStyle[style, default: 0] += 1
            }
        }
        
        return CatalogStatistics(
            totalItems: allItems.count,
            customItems: allItems.filter { $0.isCustom }.count,
            favoriteItems: favoriteItems.count,
            recentItems: recentItems.count,
            itemsByCategory: itemsByCategory,
            itemsByPriceRange: itemsByPriceRange,
            itemsByStyle: itemsByStyle,
            lastSyncDate: cloudSyncManager.lastSyncDate
        )
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // Observe search query changes
        $currentSearchQuery
            .debounce(for: .milliseconds(Int(searchDebounceTime * 1000)), scheduler: RunLoop.main)
            .sink { [weak self] query in
                Task { @MainActor in
                    await self?.search(query)
                }
            }
            .store(in: &cancellables)
        
        // Observe filter changes
        $activeFilters
            .sink { [weak self] _ in
                Task { @MainActor in
                    if let query = self?.currentSearchQuery, !query.isEmpty {
                        await self?.search(query)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateCatalogData(_ data: CatalogData) async {
        allItems = data.items
        updateCategorizedItems()
        
        // Update favorites
        let favoriteIDs = Set(data.favorites)
        favoriteItems = allItems.filter { favoriteIDs.contains($0.id) }
        
        // Update recent items
        let recentIDs = data.recent
        recentItems = recentIDs.compactMap { id in
            allItems.first { $0.id == id }
        }
        
        // Update featured items
        featuredItems = Array(allItems.filter { $0.isFeatured }.prefix(maxFeaturedItems))
        
        totalItemsCount = allItems.count
    }
    
    private func updateCategorizedItems() {
        itemsByCategory.removeAll()
        
        for item in allItems {
            itemsByCategory[item.category, default: []].append(item)
        }
        
        // Sort items within each category by popularity
        for category in itemsByCategory.keys {
            itemsByCategory[category]?.sort { $0.popularityScore > $1.popularityScore }
        }
    }
    
    private func performSearch(query: String, items: [FurnitureItem]) -> [FurnitureItem] {
        let lowercaseQuery = query.lowercased()
        let queryWords = lowercaseQuery.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        return items.compactMap { item in
            let score = calculateSearchScore(item: item, query: lowercaseQuery, queryWords: queryWords)
            return score > 0 ? (item, score)
        }
        .sorted { $0.1 > $1.1 } // Sort by score descending
        .map { $0.0 }
    }
    
    private func calculateSearchScore(item: FurnitureItem, query: String, queryWords: [String]) -> Float {
        var score: Float = 0
        
        // Exact name match gets highest score
        if item.name.lowercased() == query {
            score += 100
        }
        // Name contains full query
        else if item.name.lowercased().contains(query) {
            score += 50
        }
        
        // Check individual words in name
        for word in queryWords {
            if item.name.lowercased().contains(word) {
                score += 10
            }
        }
        
        // Check description
        if item.description.lowercased().contains(query) {
            score += 20
        }
        
        // Check category and subcategory
        if item.category.displayName.lowercased().contains(query) {
            score += 30
        }
        if item.subcategory.displayName.lowercased().contains(query) {
            score += 25
        }
        
        // Check brand
        if let brand = item.brand, brand.lowercased().contains(query) {
            score += 15
        }
        
        // Check tags
        for tag in item.tags {
            if tag.lowercased().contains(query) {
                score += 8
            }
        }
        
        // Check materials
        for material in item.metadata.materials {
            if material.displayName.lowercased().contains(query) {
                score += 5
            }
        }
        
        // Check styles
        for style in item.metadata.styles {
            if style.displayName.lowercased().contains(query) {
                score += 5
            }
        }
        
        // Boost score for featured items
        if item.isFeatured {
            score *= 1.2
        }
        
        // Boost score based on popularity
        score += item.popularityScore * 0.1
        
        return score
    }
    
    private func getFilteredItems() -> [FurnitureItem] {
        return allItems.filter { item in
            // Category filter
            if !activeFilters.categories.isEmpty && !activeFilters.categories.contains(item.category) {
                return false
            }
            
            // Subcategory filter
            if !activeFilters.subcategories.isEmpty && !activeFilters.subcategories.contains(item.subcategory) {
                return false
            }
            
            // Price range filter
            if let priceRange = activeFilters.priceRange {
                if item.pricing.priceRange != priceRange {
                    return false
                }
            }
            
            // Price filter
            if let minPrice = activeFilters.minPrice, let currentPrice = item.pricing.currentPrice {
                if currentPrice < minPrice {
                    return false
                }
            }
            
            if let maxPrice = activeFilters.maxPrice, let currentPrice = item.pricing.currentPrice {
                if currentPrice > maxPrice {
                    return false
                }
            }
            
            // Material filter
            if !activeFilters.materials.isEmpty {
                let itemMaterials = Set(item.metadata.materials)
                let filterMaterials = Set(activeFilters.materials)
                if itemMaterials.intersection(filterMaterials).isEmpty {
                    return false
                }
            }
            
            // Color family filter
            if !activeFilters.colorFamilies.isEmpty {
                let itemColorFamilies = Set(item.metadata.colors.map { $0.colorFamily })
                let filterColorFamilies = Set(activeFilters.colorFamilies)
                if itemColorFamilies.intersection(filterColorFamilies).isEmpty {
                    return false
                }
            }
            
            // Style filter
            if !activeFilters.styles.isEmpty {
                let itemStyles = Set(item.metadata.styles)
                let filterStyles = Set(activeFilters.styles)
                if itemStyles.intersection(filterStyles).isEmpty {
                    return false
                }
            }
            
            // Features filter
            if !activeFilters.features.isEmpty {
                let itemFeatures = Set(item.metadata.functionalFeatures)
                let filterFeatures = Set(activeFilters.features)
                if itemFeatures.intersection(filterFeatures).isEmpty {
                    return false
                }
            }
            
            // Brand filter
            if !activeFilters.brands.isEmpty {
                guard let brand = item.brand, activeFilters.brands.contains(brand) else {
                    return false
                }
            }
            
            // Dimensions filter
            if let maxWidth = activeFilters.maxWidth {
                if item.metadata.dimensions.width > maxWidth {
                    return false
                }
            }
            
            if let maxDepth = activeFilters.maxDepth {
                if item.metadata.dimensions.depth > maxDepth {
                    return false
                }
            }
            
            if let maxHeight = activeFilters.maxHeight {
                if item.metadata.dimensions.height > maxHeight {
                    return false
                }
            }
            
            // Assembly filter
            if let assemblyRequired = activeFilters.assemblyRequired {
                if item.metadata.assemblyRequired != assemblyRequired {
                    return false
                }
            }
            
            // Availability filter
            if activeFilters.inStockOnly && !item.availability.inStock {
                return false
            }
            
            // Custom items filter
            if let showCustomOnly = activeFilters.showCustomOnly {
                if item.isCustom != showCustomOnly {
                    return false
                }
            }
            
            return true
        }
    }
    
    private func loadDefaultItems() async {
        // Load built-in furniture items
        let defaultItems = await loadBuiltInFurnitureItems()
        allItems = defaultItems
        updateCategorizedItems()
        
        featuredItems = Array(allItems.filter { $0.isFeatured }.prefix(maxFeaturedItems))
        totalItemsCount = allItems.count
        
        logInfo("Loaded \(defaultItems.count) default furniture items", category: .general)
    }
    
    private func loadBuiltInFurnitureItems() async -> [FurnitureItem] {
        // This would load from bundle or create sample items
        return createSampleFurnitureItems()
    }
    
    private func createSampleFurnitureItems() -> [FurnitureItem] {
        var items: [FurnitureItem] = []
        
        // Sample Modern Sofa
        let modernSofa = FurnitureItem(
            name: "Modern 3-Seat Sofa",
            description: "Contemporary three-seater sofa with clean lines and comfortable cushioning",
            category: .seating,
            subcategory: .sofa,
            brand: "DesignCo",
            model3D: createSampleModel3D(name: "modern_sofa.usdz"),
            metadata: FurnitureMetadata(
                dimensions: FurnitureDimensions(width: 2.1, depth: 0.9, height: 0.8, seatHeight: 0.45),
                materials: [.fabric, .wood],
                colors: [FurnitureColor(name: "Charcoal Gray", hexValue: "#36454F", colorFamily: .neutral)],
                styles: [.modern, .contemporary],
                weight: 45.0,
                assemblyRequired: true,
                styleCompatibility: [.modern: 1.0, .contemporary: 0.9, .minimalist: 0.8],
                functionalFeatures: [.modular],
                placementSuggestions: [.livingArea, .floatingLayout]
            ),
            pricing: FurniturePricing(
                retailPrice: 899.99,
                currency: "USD",
                priceRange: .medium
            ),
            tags: ["modern", "comfortable", "living room", "gray"],
            isFeatured: true,
            popularityScore: 0.8
        )
        items.append(modernSofa)
        
        // Sample Dining Table
        let diningTable = FurnitureItem(
            name: "Oak Dining Table",
            description: "Solid oak dining table with natural finish, seats 6 people",
            category: .tables,
            subcategory: .diningTable,
            brand: "WoodCraft",
            model3D: createSampleModel3D(name: "oak_dining_table.usdz"),
            metadata: FurnitureMetadata(
                dimensions: FurnitureDimensions(width: 1.8, depth: 0.9, height: 0.75),
                materials: [.wood],
                colors: [FurnitureColor(name: "Natural Oak", hexValue: "#D2B48C", colorFamily: .warm)],
                styles: [.traditional, .rustic],
                weight: 55.0,
                assemblyRequired: false,
                styleCompatibility: [.traditional: 1.0, .rustic: 0.9, .farmhouse: 0.8],
                placementSuggestions: [.diningArea, .centerOfRoom]
            ),
            pricing: FurniturePricing(
                retailPrice: 1299.99,
                currency: "USD",
                priceRange: .medium
            ),
            tags: ["wood", "dining", "oak", "traditional"],
            isFeatured: true,
            popularityScore: 0.9
        )
        items.append(diningTable)
        
        // Add more sample items...
        
        return items
    }
    
    private func createSampleModel3D(name: String) -> Model3D {
        return Model3D(
            name: name,
            fileName: name,
            fileSize: 1024 * 1024, // 1MB
            format: .usdz,
            category: .furniture,
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
        )
    }
}

// MARK: - Furniture Filters

public struct FurnitureFilters: Codable, Equatable {
    public var categories: [FurnitureCategory] = []
    public var subcategories: [FurnitureSubcategory] = []
    public var priceRange: PriceRange?
    public var minPrice: Float?
    public var maxPrice: Float?
    public var materials: [FurnitureMaterial] = []
    public var colorFamilies: [ColorFamily] = []
    public var styles: [FurnitureStyle] = []
    public var features: [FunctionalFeature] = []
    public var brands: [String] = []
    public var maxWidth: Float?
    public var maxDepth: Float?
    public var maxHeight: Float?
    public var assemblyRequired: Bool?
    public var inStockOnly: Bool = false
    public var showCustomOnly: Bool?
    
    public init() {}
    
    public var hasActiveFilters: Bool {
        return !categories.isEmpty ||
               !subcategories.isEmpty ||
               priceRange != nil ||
               minPrice != nil ||
               maxPrice != nil ||
               !materials.isEmpty ||
               !colorFamilies.isEmpty ||
               !styles.isEmpty ||
               !features.isEmpty ||
               !brands.isEmpty ||
               maxWidth != nil ||
               maxDepth != nil ||
               maxHeight != nil ||
               assemblyRequired != nil ||
               inStockOnly ||
               showCustomOnly != nil
    }
    
    public var activeFilterCount: Int {
        var count = 0
        if !categories.isEmpty { count += 1 }
        if !subcategories.isEmpty { count += 1 }
        if priceRange != nil { count += 1 }
        if minPrice != nil || maxPrice != nil { count += 1 }
        if !materials.isEmpty { count += 1 }
        if !colorFamilies.isEmpty { count += 1 }
        if !styles.isEmpty { count += 1 }
        if !features.isEmpty { count += 1 }
        if !brands.isEmpty { count += 1 }
        if maxWidth != nil || maxDepth != nil || maxHeight != nil { count += 1 }
        if assemblyRequired != nil { count += 1 }
        if inStockOnly { count += 1 }
        if showCustomOnly != nil { count += 1 }
        return count
    }
}

// MARK: - Supporting Types

public struct CatalogData: Codable {
    public let items: [FurnitureItem]
    public let favorites: [UUID]
    public let recent: [UUID]
    
    public init(items: [FurnitureItem], favorites: [UUID], recent: [UUID]) {
        self.items = items
        self.favorites = favorites
        self.recent = recent
    }
}

public struct CatalogStatistics {
    public let totalItems: Int
    public let customItems: Int
    public let favoriteItems: Int
    public let recentItems: Int
    public let itemsByCategory: [FurnitureCategory: Int]
    public let itemsByPriceRange: [PriceRange: Int]
    public let itemsByStyle: [FurnitureStyle: Int]
    public let lastSyncDate: Date?
}

public enum CloudSyncStatus: Equatable {
    case idle
    case syncing
    case success
    case failed(String)
    
    public var isLoading: Bool {
        if case .syncing = self { return true }
        return false
    }
}

public enum FurnitureCatalogError: LocalizedError {
    case itemNotFound
    case invalidCustomItem
    case syncFailed
    case importFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Furniture item not found"
        case .invalidCustomItem:
            return "Invalid custom furniture item"
        case .syncFailed:
            return "Failed to sync with cloud"
        case .importFailed(let reason):
            return "Failed to import item: \(reason)"
        }
    }
}