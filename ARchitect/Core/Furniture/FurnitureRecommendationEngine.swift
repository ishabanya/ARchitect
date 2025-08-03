import Foundation
import simd

// MARK: - Furniture Recommendation Engine

public class FurnitureRecommendationEngine {
    
    // MARK: - Private Properties
    private let similarityThreshold: Float = 0.3
    private let maxRecommendations = 20
    private let maxSimilarItems = 10
    
    // Recommendation weights
    private struct RecommendationWeights {
        static let roomSize: Float = 0.25
        static let style: Float = 0.20
        static let category: Float = 0.15
        static let priceRange: Float = 0.15
        static let userHistory: Float = 0.10
        static let popularity: Float = 0.10
        static let availability: Float = 0.05
    }
    
    public init() {
        logInfo("Furniture recommendation engine initialized", category: .general)
    }
    
    // MARK: - Public Methods
    
    /// Get furniture recommendations for a room
    public func getRecommendations(
        for room: RoomInfo,
        from items: [FurnitureItem],
        userFavorites: [FurnitureItem],
        userRecent: [FurnitureItem]
    ) async -> [FurnitureItem] {
        
        logDebug("Generating recommendations", category: .general, context: LogContext(customData: [
            "room_area": room.area,
            "room_style": room.style?.rawValue ?? "unknown",
            "available_items": items.count
        ]))
        
        // Calculate user preferences from history
        let userPreferences = calculateUserPreferences(
            favorites: userFavorites,
            recent: userRecent
        )
        
        // Score all items
        var scoredItems: [(FurnitureItem, Float)] = []
        
        for item in items {
            let score = await calculateRecommendationScore(
                item: item,
                room: room,
                userPreferences: userPreferences
            )
            
            if score > 0 {
                scoredItems.append((item, score))
            }
        }
        
        // Sort by score and return top recommendations
        let recommendations = scoredItems
            .sorted { $0.1 > $1.1 }
            .prefix(maxRecommendations)
            .map { $0.0 }
        
        logInfo("Generated \(recommendations.count) recommendations", category: .general)
        
        return recommendations
    }
    
    /// Get items similar to a given item
    public func getSimilarItems(
        to targetItem: FurnitureItem,
        from items: [FurnitureItem],
        limit: Int = 5
    ) -> [FurnitureItem] {
        
        var similarities: [(FurnitureItem, Float)] = []
        
        for item in items {
            guard item.id != targetItem.id else { continue }
            
            let similarity = calculateSimilarityScore(targetItem, item)
            if similarity > similarityThreshold {
                similarities.append((item, similarity))
            }
        }
        
        return similarities
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }
    
    /// Get complementary items for a given item
    public func getComplementaryItems(
        for item: FurnitureItem,
        from items: [FurnitureItem],
        roomSize: Float,
        limit: Int = 5
    ) -> [FurnitureItem] {
        
        let complementaryCategories = getComplementaryCategories(for: item.category)
        let complementaryItems = items.filter { candidate in
            complementaryCategories.contains(candidate.category) &&
            candidate.id != item.id
        }
        
        var scoredItems: [(FurnitureItem, Float)] = []
        
        for candidate in complementaryItems {
            let score = calculateComplementaryScore(
                primary: item,
                candidate: candidate,
                roomSize: roomSize
            )
            
            if score > 0 {
                scoredItems.append((candidate, score))
            }
        }
        
        return scoredItems
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }
    
    /// Get space-optimized recommendations
    public func getSpaceOptimizedRecommendations(
        for roomDimensions: SIMD3<Float>,
        category: FurnitureCategory?,
        from items: [FurnitureItem]
    ) -> [FurnitureItem] {
        
        let availableSpace = roomDimensions.x * roomDimensions.y * roomDimensions.z
        let filteredItems = items.filter { item in
            // Check if category matches (if specified)
            if let category = category, item.category != category {
                return false
            }
            
            // Check if item fits in room
            let dims = item.metadata.dimensions
            return dims.width <= roomDimensions.x &&
                   dims.depth <= roomDimensions.y &&
                   dims.height <= roomDimensions.z
        }
        
        // Score items based on space efficiency
        var scoredItems: [(FurnitureItem, Float)] = []
        
        for item in filteredItems {
            let score = calculateSpaceEfficiencyScore(
                item: item,
                availableSpace: availableSpace,
                roomDimensions: roomDimensions
            )
            scoredItems.append((item, score))
        }
        
        return scoredItems
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }
    
    /// Get budget-conscious recommendations
    public func getBudgetRecommendations(
        maxBudget: Float,
        categories: [FurnitureCategory],
        from items: [FurnitureItem]
    ) -> [FurnitureItem] {
        
        let affordableItems = items.filter { item in
            guard categories.contains(item.category) else { return false }
            guard let price = item.pricing.currentPrice else { return false }
            return price <= maxBudget
        }
        
        // Score items based on value (features/price ratio)
        var scoredItems: [(FurnitureItem, Float)] = []
        
        for item in affordableItems {
            let score = calculateValueScore(item: item, maxBudget: maxBudget)
            scoredItems.append((item, score))
        }
        
        return scoredItems
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }
    
    /// Get trending items
    public func getTrendingItems(
        from items: [FurnitureItem],
        timeframe: TrendingTimeframe = .month
    ) -> [FurnitureItem] {
        
        // Filter items based on popularity and recent activity
        let cutoffDate = Date().addingTimeInterval(-timeframe.seconds)
        
        return items
            .filter { $0.dateAdded > cutoffDate || $0.lastUpdated > cutoffDate }
            .sorted { $0.popularityScore > $1.popularityScore }
            .prefix(maxRecommendations)
            .map { $0 }
    }
    
    // MARK: - Private Methods
    
    private func calculateUserPreferences(
        favorites: [FurnitureItem],
        recent: [FurnitureItem]
    ) -> UserPreferences {
        
        var preferredCategories: [FurnitureCategory: Float] = [:]
        var preferredStyles: [FurnitureStyle: Float] = [:]
        var preferredMaterials: [FurnitureMaterial: Float] = [:]
        var preferredPriceRanges: [PriceRange: Float] = [:]
        var preferredBrands: [String: Float] = [:]
        
        let allItems = favorites + recent
        let favoriteWeight: Float = 2.0
        let recentWeight: Float = 1.0
        
        for item in favorites {
            preferredCategories[item.category, default: 0] += favoriteWeight
            preferredPriceRanges[item.pricing.priceRange, default: 0] += favoriteWeight
            
            for style in item.metadata.styles {
                preferredStyles[style, default: 0] += favoriteWeight
            }
            
            for material in item.metadata.materials {
                preferredMaterials[material, default: 0] += favoriteWeight
            }
            
            if let brand = item.brand {
                preferredBrands[brand, default: 0] += favoriteWeight
            }
        }
        
        for item in recent {
            preferredCategories[item.category, default: 0] += recentWeight
            preferredPriceRanges[item.pricing.priceRange, default: 0] += recentWeight
            
            for style in item.metadata.styles {
                preferredStyles[style, default: 0] += recentWeight
            }
            
            for material in item.metadata.materials {
                preferredMaterials[material, default: 0] += recentWeight
            }
            
            if let brand = item.brand {
                preferredBrands[brand, default: 0] += recentWeight
            }
        }
        
        // Normalize scores
        let totalWeight = Float(favorites.count) * favoriteWeight + Float(recent.count) * recentWeight
        
        if totalWeight > 0 {
            for category in preferredCategories.keys {
                preferredCategories[category]! /= totalWeight
            }
            for style in preferredStyles.keys {
                preferredStyles[style]! /= totalWeight
            }
            for material in preferredMaterials.keys {
                preferredMaterials[material]! /= totalWeight
            }
            for priceRange in preferredPriceRanges.keys {
                preferredPriceRanges[priceRange]! /= totalWeight
            }
            for brand in preferredBrands.keys {
                preferredBrands[brand]! /= totalWeight
            }
        }
        
        return UserPreferences(
            categories: preferredCategories,
            styles: preferredStyles,
            materials: preferredMaterials,
            priceRanges: preferredPriceRanges,
            brands: preferredBrands
        )
    }
    
    private func calculateRecommendationScore(
        item: FurnitureItem,
        room: RoomInfo,
        userPreferences: UserPreferences
    ) async -> Float {
        
        var score: Float = 0
        
        // Room size compatibility
        let roomSizeScore = calculateRoomSizeScore(item: item, room: room)
        score += roomSizeScore * RecommendationWeights.roomSize
        
        // Style compatibility
        let styleScore = calculateStyleScore(item: item, room: room)
        score += styleScore * RecommendationWeights.style
        
        // Category preference
        let categoryScore = userPreferences.categories[item.category] ?? 0
        score += categoryScore * RecommendationWeights.category
        
        // Price range preference
        let priceScore = userPreferences.priceRanges[item.pricing.priceRange] ?? 0
        score += priceScore * RecommendationWeights.priceRange
        
        // User history alignment
        let historyScore = calculateHistoryScore(item: item, userPreferences: userPreferences)
        score += historyScore * RecommendationWeights.userHistory
        
        // Popularity score
        score += item.popularityScore * RecommendationWeights.popularity
        
        // Availability bonus
        let availabilityScore = item.availability.inStock ? 1.0 : 0.5
        score += availabilityScore * RecommendationWeights.availability
        
        return score
    }
    
    private func calculateRoomSizeScore(item: FurnitureItem, room: RoomInfo) -> Float {
        let itemFootprint = item.metadata.dimensions.footprint
        let roomArea = room.area
        
        // Ideal furniture should take 10-30% of room area
        let footprintRatio = itemFootprint / roomArea
        
        if footprintRatio < 0.05 {
            return 0.7 // Too small for the room
        } else if footprintRatio <= 0.15 {
            return 1.0 // Perfect size
        } else if footprintRatio <= 0.3 {
            return 0.8 // A bit large but acceptable
        } else {
            return 0.3 // Too large for the room
        }
    }
    
    private func calculateStyleScore(item: FurnitureItem, room: RoomInfo) -> Float {
        guard let roomStyle = room.style else { return 0.5 }
        
        return item.compatibilityScore(with: roomStyle)
    }
    
    private func calculateHistoryScore(item: FurnitureItem, userPreferences: UserPreferences) -> Float {
        var score: Float = 0
        
        // Style preferences
        for style in item.metadata.styles {
            score += userPreferences.styles[style] ?? 0
        }
        
        // Material preferences
        for material in item.metadata.materials {
            score += userPreferences.materials[material] ?? 0
        }
        
        // Brand preferences
        if let brand = item.brand {
            score += userPreferences.brands[brand] ?? 0
        }
        
        return min(score, 1.0) // Cap at 1.0
    }
    
    private func calculateSimilarityScore(_ item1: FurnitureItem, _ item2: FurnitureItem) -> Float {
        var score: Float = 0
        
        // Category similarity
        if item1.category == item2.category {
            score += 0.3
        }
        
        // Subcategory similarity
        if item1.subcategory == item2.subcategory {
            score += 0.2
        }
        
        // Style similarity
        let commonStyles = Set(item1.metadata.styles).intersection(Set(item2.metadata.styles))
        score += Float(commonStyles.count) * 0.1
        
        // Material similarity
        let commonMaterials = Set(item1.metadata.materials).intersection(Set(item2.metadata.materials))
        score += Float(commonMaterials.count) * 0.1
        
        // Price range similarity
        if item1.pricing.priceRange == item2.pricing.priceRange {
            score += 0.1
        }
        
        // Dimension similarity
        let dim1 = item1.metadata.dimensions
        let dim2 = item2.metadata.dimensions
        
        let sizeDifference = abs(dim1.volume - dim2.volume) / max(dim1.volume, dim2.volume)
        score += (1.0 - sizeDifference) * 0.2
        
        return score
    }
    
    private func calculateComplementaryScore(
        primary: FurnitureItem,
        candidate: FurnitureItem,
        roomSize: Float
    ) -> Float {
        
        var score: Float = 0
        
        // Check if categories are complementary
        let complementaryCategories = getComplementaryCategories(for: primary.category)
        if complementaryCategories.contains(candidate.category) {
            score += 0.4
        }
        
        // Style compatibility
        let commonStyles = Set(primary.metadata.styles).intersection(Set(candidate.metadata.styles))
        score += Float(commonStyles.count) * 0.2
        
        // Size compatibility
        let totalFootprint = primary.metadata.dimensions.footprint + candidate.metadata.dimensions.footprint
        let footprintRatio = totalFootprint / roomSize
        
        if footprintRatio <= 0.3 {
            score += 0.3 // Good fit together
        } else if footprintRatio <= 0.5 {
            score += 0.1 // Tight fit
        }
        
        // Color harmony
        if hasColorHarmony(primary.metadata.colors, candidate.metadata.colors) {
            score += 0.1
        }
        
        return score
    }
    
    private func calculateSpaceEfficiencyScore(
        item: FurnitureItem,
        availableSpace: Float,
        roomDimensions: SIMD3<Float>
    ) -> Float {
        
        let dims = item.metadata.dimensions
        let itemVolume = dims.volume
        
        // Space utilization score
        let utilizationRatio = itemVolume / availableSpace
        var score = 1.0 - utilizationRatio // Prefer items that don't dominate the space
        
        // Multi-functional bonus
        if item.metadata.functionalFeatures.contains(.storage) {
            score += 0.2
        }
        if item.metadata.functionalFeatures.contains(.convertible) {
            score += 0.3
        }
        if item.metadata.functionalFeatures.contains(.extendable) {
            score += 0.1
        }
        
        // Vertical space utilization
        let heightRatio = dims.height / roomDimensions.z
        if heightRatio > 0.8 {
            score += 0.1 // Good use of vertical space
        }
        
        return max(0, score)
    }
    
    private func calculateValueScore(item: FurnitureItem, maxBudget: Float) -> Float {
        guard let price = item.pricing.currentPrice else { return 0 }
        
        var score: Float = 0
        
        // Price efficiency (cheaper is better for budget recommendations)
        let priceRatio = price / maxBudget
        score += (1.0 - priceRatio) * 0.4
        
        // Feature count bonus
        let featureCount = Float(item.metadata.functionalFeatures.count)
        score += min(featureCount * 0.1, 0.3)
        
        // Quality indicators
        if let warranty = item.metadata.warranty {
            score += min(Float(warranty.duration) * 0.05, 0.2)
        }
        
        // Sustainability bonus
        if let sustainability = item.metadata.sustainability, sustainability.ecoFriendly {
            score += 0.1
        }
        
        return score
    }
    
    private func getComplementaryCategories(for category: FurnitureCategory) -> [FurnitureCategory] {
        switch category {
        case .seating:
            return [.tables, .lighting, .storage]
        case .tables:
            return [.seating, .lighting, .decor]
        case .storage:
            return [.seating, .decor, .lighting]
        case .bedroom:
            return [.storage, .lighting, .decor]
        case .lighting:
            return [.seating, .tables, .decor]
        case .decor:
            return [.lighting, .storage]
        case .outdoor:
            return [.outdoor, .lighting]
        case .office:
            return [.storage, .lighting]
        case .kitchen:
            return [.seating, .storage]
        case .bathroom:
            return [.storage, .decor]
        }
    }
    
    private func hasColorHarmony(_ colors1: [FurnitureColor], _ colors2: [FurnitureColor]) -> Bool {
        let families1 = Set(colors1.map { $0.colorFamily })
        let families2 = Set(colors2.map { $0.colorFamily })
        
        // Check for complementary color families
        let harmonious: [(ColorFamily, ColorFamily)] = [
            (.neutral, .warm),
            (.neutral, .cool),
            (.warm, .earth),
            (.cool, .pastel),
            (.neutral, .bold)
        ]
        
        for (family1, family2) in harmonious {
            if (families1.contains(family1) && families2.contains(family2)) ||
               (families1.contains(family2) && families2.contains(family1)) {
                return true
            }
        }
        
        // Same family is also harmonious
        return !families1.intersection(families2).isEmpty
    }
}

// MARK: - Supporting Types

public struct RoomInfo {
    public let area: Float // in square meters
    public let dimensions: SIMD3<Float> // width, depth, height in meters
    public let style: RoomStyle?
    public let existingFurniture: [FurnitureItem]
    public let lightingConditions: LightingConditions
    public let usage: RoomUsage
    
    public init(
        area: Float,
        dimensions: SIMD3<Float>,
        style: RoomStyle? = nil,
        existingFurniture: [FurnitureItem] = [],
        lightingConditions: LightingConditions = .natural,
        usage: RoomUsage = .general
    ) {
        self.area = area
        self.dimensions = dimensions
        self.style = style
        self.existingFurniture = existingFurniture
        self.lightingConditions = lightingConditions
        self.usage = usage
    }
}

public enum LightingConditions: String, CaseIterable, Codable {
    case natural = "natural"
    case artificial = "artificial"
    case mixed = "mixed"
    case low = "low"
}

public enum RoomUsage: String, CaseIterable, Codable {
    case general = "general"
    case entertaining = "entertaining"
    case work = "work"
    case relaxation = "relaxation"
    case dining = "dining"
    case sleeping = "sleeping"
}

public enum TrendingTimeframe {
    case week
    case month
    case quarter
    case year
    
    var seconds: TimeInterval {
        switch self {
        case .week: return 7 * 24 * 60 * 60
        case .month: return 30 * 24 * 60 * 60
        case .quarter: return 90 * 24 * 60 * 60
        case .year: return 365 * 24 * 60 * 60
        }
    }
}

private struct UserPreferences {
    let categories: [FurnitureCategory: Float]
    let styles: [FurnitureStyle: Float]
    let materials: [FurnitureMaterial: Float]
    let priceRanges: [PriceRange: Float]
    let brands: [String: Float]
}