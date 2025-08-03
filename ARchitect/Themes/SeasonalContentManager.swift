import Foundation
import SwiftUI
import Combine

// MARK: - Seasonal Content Manager
class SeasonalContentManager: ObservableObject {
    static let shared = SeasonalContentManager()
    
    @Published private(set) var currentSeason: Season = .winter
    @Published private(set) var activeThemes: [SeasonalTheme] = []
    @Published private(set) var featuredCollections: [FurnitureCollection] = []
    @Published private(set) var seasonalDecorations: [SeasonalDecoration] = []
    @Published private(set) var colorPalettes: [ColorPalette] = []
    
    private let featureFlags = FeatureFlagManager.shared
    private let analyticsManager = AnalyticsManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private let updateInterval: TimeInterval = 24 * 3600 // Check daily
    private var updateTimer: Timer?
    
    private init() {
        setupSeasonalContent()
        startPeriodicUpdates()
        observeFeatureFlags()
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func getCurrentSeasonalContent() -> SeasonalContentPackage {
        return SeasonalContentPackage(
            season: currentSeason,
            themes: activeThemes,
            collections: featuredCollections,
            decorations: seasonalDecorations,
            colorPalettes: colorPalettes
        )
    }
    
    func getSeasonalRecommendations(for roomType: RoomType) -> [FurnitureItem] {
        guard featureFlags.isEnabled(.seasonalContent) else { return [] }
        
        let seasonalItems = featuredCollections
            .flatMap { $0.items }
            .filter { item in
                item.roomTypes.contains(roomType) &&
                item.seasonalRelevance.contains(currentSeason)
            }
        
        analyticsManager.trackFeatureUsage(.aiOptimizationUsed, parameters: [
            "feature": "seasonal_recommendations",
            "room_type": roomType.rawValue,
            "season": currentSeason.rawValue,
            "recommendations_count": seasonalItems.count
        ])
        
        return Array(seasonalItems.prefix(10)) // Return top 10 recommendations
    }
    
    func getHolidayDecorations(for holiday: Holiday) -> [SeasonalDecoration] {
        return seasonalDecorations.filter { decoration in
            decoration.associatedHolidays.contains(holiday)
        }
    }
    
    func updateSeasonalContent() {
        Task {
            await refreshSeasonalContent()
        }
    }
    
    func trackSeasonalContentUsage(_ contentType: SeasonalContentType, contentId: String) {
        analyticsManager.trackFeatureUsage(.featureUsageMetric(from: "seasonal_content_used"), parameters: [
            "content_type": contentType.rawValue,
            "content_id": contentId,
            "season": currentSeason.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // MARK: - Private Methods
    
    private func setupSeasonalContent() {
        currentSeason = determinCurrentSeason()
        loadSeasonalContent()
    }
    
    private func startPeriodicUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.checkForSeasonalUpdates()
            }
        }
    }
    
    private func observeFeatureFlags() {
        featureFlags.$flags
            .sink { [weak self] _ in
                if self?.featureFlags.isEnabled(.seasonalContent) == true {
                    self?.loadSeasonalContent()
                }
            }
            .store(in: &cancellables)
    }
    
    private func determinCurrentSeason() -> Season {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)
        
        switch month {
        case 12, 1, 2:
            return .winter
        case 3, 4, 5:
            return .spring
        case 6, 7, 8:
            return .summer
        case 9, 10, 11:
            return .fall
        default:
            return .winter
        }
    }
    
    private func loadSeasonalContent() {
        guard featureFlags.isEnabled(.seasonalContent) else { return }
        
        activeThemes = generateSeasonalThemes(for: currentSeason)
        featuredCollections = generateFeaturedCollections(for: currentSeason)
        seasonalDecorations = generateSeasonalDecorations(for: currentSeason)
        colorPalettes = generateColorPalettes(for: currentSeason)
        
        // Track seasonal content load
        analyticsManager.trackFeatureUsage(.featureUsageMetric(from: "seasonal_content_loaded"), parameters: [
            "season": currentSeason.rawValue,
            "themes_count": activeThemes.count,
            "collections_count": featuredCollections.count,
            "decorations_count": seasonalDecorations.count
        ])
    }
    
    private func checkForSeasonalUpdates() async {
        let newSeason = determinCurrentSeason()
        
        if newSeason != currentSeason {
            await MainActor.run {
                currentSeason = newSeason
                loadSeasonalContent()
            }
            
            analyticsManager.trackCustomEvent(
                name: "seasonal_transition",
                parameters: [
                    "from_season": currentSeason.rawValue,
                    "to_season": newSeason.rawValue,
                    "transition_date": Date().timeIntervalSince1970
                ],
                severity: .medium
            )
        }
    }
    
    private func refreshSeasonalContent() async {
        // In a real implementation, this would fetch from a content management system
        await MainActor.run {
            loadSeasonalContent()
        }
    }
    
    // MARK: - Content Generation
    
    private func generateSeasonalThemes(for season: Season) -> [SeasonalTheme] {
        switch season {
        case .winter:
            return [
                SeasonalTheme(
                    id: "winter_cozy",
                    name: "Winter Cozy",
                    description: "Warm and inviting winter atmosphere",
                    primaryColor: Color(red: 0.8, green: 0.7, blue: 0.6),
                    accentColor: Color(red: 0.6, green: 0.3, blue: 0.2),
                    mood: .cozy,
                    season: .winter,
                    associatedHolidays: [.christmas, .newYear]
                ),
                SeasonalTheme(
                    id: "holiday_elegance",
                    name: "Holiday Elegance",
                    description: "Sophisticated holiday decorating",
                    primaryColor: Color(red: 0.1, green: 0.3, blue: 0.1),
                    accentColor: Color(red: 0.8, green: 0.7, blue: 0.2),
                    mood: .elegant,
                    season: .winter,
                    associatedHolidays: [.christmas]
                )
            ]
        case .spring:
            return [
                SeasonalTheme(
                    id: "spring_fresh",
                    name: "Spring Fresh",
                    description: "Light and airy spring renewal",
                    primaryColor: Color(red: 0.7, green: 0.9, blue: 0.7),
                    accentColor: Color(red: 0.9, green: 0.7, blue: 0.8),
                    mood: .fresh,
                    season: .spring,
                    associatedHolidays: [.easter]
                ),
                SeasonalTheme(
                    id: "garden_inspired",
                    name: "Garden Inspired",
                    description: "Botanical and natural spring elements",
                    primaryColor: Color(red: 0.6, green: 0.8, blue: 0.4),
                    accentColor: Color(red: 0.9, green: 0.8, blue: 0.3),
                    mood: .natural,
                    season: .spring,
                    associatedHolidays: []
                )
            ]
        case .summer:
            return [
                SeasonalTheme(
                    id: "summer_breeze",
                    name: "Summer Breeze",
                    description: "Light and airy summer vibes",
                    primaryColor: Color(red: 0.7, green: 0.9, blue: 0.9),
                    accentColor: Color(red: 0.9, green: 0.8, blue: 0.2),
                    mood: .airy,
                    season: .summer,
                    associatedHolidays: [.independenceDay]
                ),
                SeasonalTheme(
                    id: "coastal_living",
                    name: "Coastal Living",
                    description: "Beach-inspired summer decor",
                    primaryColor: Color(red: 0.6, green: 0.8, blue: 0.9),
                    accentColor: Color(red: 0.9, green: 0.9, blue: 0.8),
                    mood: .relaxed,
                    season: .summer,
                    associatedHolidays: []
                )
            ]
        case .fall:
            return [
                SeasonalTheme(
                    id: "autumn_harvest",
                    name: "Autumn Harvest",
                    description: "Rich autumn colors and textures",
                    primaryColor: Color(red: 0.8, green: 0.5, blue: 0.3),
                    accentColor: Color(red: 0.7, green: 0.3, blue: 0.2),
                    mood: .warm,
                    season: .fall,
                    associatedHolidays: [.halloween, .thanksgiving]
                ),
                SeasonalTheme(
                    id: "rustic_charm",
                    name: "Rustic Charm",
                    description: "Cozy autumn farmhouse style",
                    primaryColor: Color(red: 0.7, green: 0.6, blue: 0.4),
                    accentColor: Color(red: 0.8, green: 0.4, blue: 0.3),
                    mood: .rustic,
                    season: .fall,
                    associatedHolidays: [.thanksgiving]
                )
            ]
        }
    }
    
    private func generateFeaturedCollections(for season: Season) -> [FurnitureCollection] {
        switch season {
        case .winter:
            return [
                FurnitureCollection(
                    id: "winter_living",
                    name: "Winter Living Room",
                    description: "Cozy furniture for winter comfort",
                    season: .winter,
                    items: generateWinterFurniture(),
                    imageURL: "winter_living_collection",
                    tags: ["cozy", "warm", "comfortable"]
                ),
                FurnitureCollection(
                    id: "holiday_dining",
                    name: "Holiday Dining",
                    description: "Elegant dining for holiday entertaining",
                    season: .winter,
                    items: generateHolidayDining(),
                    imageURL: "holiday_dining_collection",
                    tags: ["elegant", "festive", "entertaining"]
                )
            ]
        case .spring:
            return [
                FurnitureCollection(
                    id: "spring_refresh",
                    name: "Spring Refresh",
                    description: "Light and bright spring updates",
                    season: .spring,
                    items: generateSpringFurniture(),
                    imageURL: "spring_refresh_collection",
                    tags: ["fresh", "light", "renewal"]
                )
            ]
        case .summer:
            return [
                FurnitureCollection(
                    id: "summer_outdoor",
                    name: "Summer Outdoor",
                    description: "Outdoor living and entertaining",
                    season: .summer,
                    items: generateSummerFurniture(),
                    imageURL: "summer_outdoor_collection",
                    tags: ["outdoor", "entertaining", "casual"]
                )
            ]
        case .fall:
            return [
                FurnitureCollection(
                    id: "fall_comfort",
                    name: "Fall Comfort",
                    description: "Warm and inviting fall decor",
                    season: .fall,
                    items: generateFallFurniture(),
                    imageURL: "fall_comfort_collection",
                    tags: ["warm", "comfort", "inviting"]
                )
            ]
        }
    }
    
    private func generateSeasonalDecorations(for season: Season) -> [SeasonalDecoration] {
        switch season {
        case .winter:
            return [
                SeasonalDecoration(
                    id: "christmas_tree",
                    name: "Christmas Tree",
                    description: "Traditional holiday centerpiece",
                    category: .holidayDecor,
                    season: .winter,
                    associatedHolidays: [.christmas],
                    modelFileName: "christmas_tree.usdz",
                    thumbnailURL: "christmas_tree_thumb"
                ),
                SeasonalDecoration(
                    id: "winter_wreath",
                    name: "Winter Wreath",
                    description: "Festive door decoration",
                    category: .wallDecor,
                    season: .winter,
                    associatedHolidays: [.christmas],
                    modelFileName: "winter_wreath.usdz",
                    thumbnailURL: "winter_wreath_thumb"
                )
            ]
        case .spring:
            return [
                SeasonalDecoration(
                    id: "easter_arrangement",
                    name: "Easter Arrangement",
                    description: "Spring floral centerpiece",
                    category: .centerpiece,
                    season: .spring,
                    associatedHolidays: [.easter],
                    modelFileName: "easter_arrangement.usdz",
                    thumbnailURL: "easter_arrangement_thumb"
                )
            ]
        case .summer:
            return [
                SeasonalDecoration(
                    id: "patriotic_bunting",
                    name: "Patriotic Bunting",
                    description: "Fourth of July decoration",
                    category: .wallDecor,
                    season: .summer,
                    associatedHolidays: [.independenceDay],
                    modelFileName: "patriotic_bunting.usdz",
                    thumbnailURL: "patriotic_bunting_thumb"
                )
            ]
        case .fall:
            return [
                SeasonalDecoration(
                    id: "pumpkin_display",
                    name: "Pumpkin Display",
                    description: "Autumn harvest decoration",
                    category: .centerpiece,
                    season: .fall,
                    associatedHolidays: [.halloween, .thanksgiving],
                    modelFileName: "pumpkin_display.usdz",
                    thumbnailURL: "pumpkin_display_thumb"
                )
            ]
        }
    }
    
    private func generateColorPalettes(for season: Season) -> [ColorPalette] {
        switch season {
        case .winter:
            return [
                ColorPalette(
                    id: "winter_warmth",
                    name: "Winter Warmth",
                    description: "Cozy winter colors",
                    season: .winter,
                    primaryColor: Color(red: 0.2, green: 0.3, blue: 0.4),
                    secondaryColor: Color(red: 0.8, green: 0.7, blue: 0.6),
                    accentColor: Color(red: 0.7, green: 0.3, blue: 0.2),
                    neutralColor: Color(red: 0.9, green: 0.9, blue: 0.8)
                )
            ]
        case .spring:
            return [
                ColorPalette(
                    id: "spring_awakening",
                    name: "Spring Awakening",
                    description: "Fresh spring colors",
                    season: .spring,
                    primaryColor: Color(red: 0.6, green: 0.8, blue: 0.4),
                    secondaryColor: Color(red: 0.9, green: 0.8, blue: 0.7),
                    accentColor: Color(red: 0.8, green: 0.6, blue: 0.8),
                    neutralColor: Color(red: 0.95, green: 0.95, blue: 0.9)
                )
            ]
        case .summer:
            return [
                ColorPalette(
                    id: "summer_sky",
                    name: "Summer Sky",
                    description: "Bright summer colors",
                    season: .summer,
                    primaryColor: Color(red: 0.4, green: 0.7, blue: 0.9),
                    secondaryColor: Color(red: 0.9, green: 0.9, blue: 0.7),
                    accentColor: Color(red: 0.9, green: 0.7, blue: 0.3),
                    neutralColor: Color(red: 0.98, green: 0.98, blue: 0.95)
                )
            ]
        case .fall:
            return [
                ColorPalette(
                    id: "autumn_leaves",
                    name: "Autumn Leaves",
                    description: "Rich fall colors",
                    season: .fall,
                    primaryColor: Color(red: 0.8, green: 0.4, blue: 0.2),
                    secondaryColor: Color(red: 0.7, green: 0.6, blue: 0.3),
                    accentColor: Color(red: 0.6, green: 0.2, blue: 0.1),
                    neutralColor: Color(red: 0.9, green: 0.8, blue: 0.7)
                )
            ]
        }
    }
    
    // MARK: - Furniture Generation Helpers
    
    private func generateWinterFurniture() -> [FurnitureItem] {
        return [
            FurnitureItem(
                id: "cozy_sofa",
                name: "Cozy Winter Sofa",
                category: .seating,
                subcategory: "Sofas",
                modelFileName: "cozy_sofa.usdz",
                thumbnailURL: "cozy_sofa_thumb",
                dimensions: FurnitureDimensions(width: 200, height: 85, depth: 90),
                price: 1299.99,
                description: "Plush sofa perfect for winter comfort",
                roomTypes: [.livingRoom, .familyRoom],
                seasonalRelevance: [.winter],
                tags: ["cozy", "comfortable", "winter"]
            )
        ]
    }
    
    private func generateHolidayDining() -> [FurnitureItem] {
        return [
            FurnitureItem(
                id: "holiday_table",
                name: "Holiday Dining Table",
                category: .tables,
                subcategory: "Dining Tables",
                modelFileName: "holiday_table.usdz",
                thumbnailURL: "holiday_table_thumb",
                dimensions: FurnitureDimensions(width: 180, height: 75, depth: 90),
                price: 899.99,
                description: "Elegant table for holiday entertaining",
                roomTypes: [.diningRoom],
                seasonalRelevance: [.winter],
                tags: ["elegant", "entertaining", "holiday"]
            )
        ]
    }
    
    private func generateSpringFurniture() -> [FurnitureItem] {
        return [
            FurnitureItem(
                id: "fresh_chair",
                name: "Spring Fresh Chair",
                category: .seating,
                subcategory: "Accent Chairs",
                modelFileName: "fresh_chair.usdz",
                thumbnailURL: "fresh_chair_thumb",
                dimensions: FurnitureDimensions(width: 70, height: 80, depth: 75),
                price: 399.99,
                description: "Light and airy chair for spring refresh",
                roomTypes: [.livingRoom, .bedroom],
                seasonalRelevance: [.spring],
                tags: ["fresh", "light", "spring"]
            )
        ]
    }
    
    private func generateSummerFurniture() -> [FurnitureItem] {
        return [
            FurnitureItem(
                id: "outdoor_set",
                name: "Summer Outdoor Set",
                category: .seating,
                subcategory: "Outdoor Furniture",
                modelFileName: "outdoor_set.usdz",
                thumbnailURL: "outdoor_set_thumb",
                dimensions: FurnitureDimensions(width: 150, height: 75, depth: 80),
                price: 799.99,
                description: "Perfect for summer outdoor entertaining",
                roomTypes: [.patio, .deck],
                seasonalRelevance: [.summer],
                tags: ["outdoor", "entertaining", "summer"]
            )
        ]
    }
    
    private func generateFallFurniture() -> [FurnitureItem] {
        return [
            FurnitureItem(
                id: "warm_ottoman",
                name: "Fall Comfort Ottoman",
                category: .seating,
                subcategory: "Ottomans",
                modelFileName: "warm_ottoman.usdz",
                thumbnailURL: "warm_ottoman_thumb",
                dimensions: FurnitureDimensions(width: 60, height: 45, depth: 40),
                price: 299.99,
                description: "Cozy ottoman for fall comfort",
                roomTypes: [.livingRoom, .familyRoom],
                seasonalRelevance: [.fall],
                tags: ["warm", "comfort", "fall"]
            )
        ]
    }
}

// MARK: - Data Models

enum Season: String, CaseIterable, Codable {
    case spring = "spring"
    case summer = "summer"
    case fall = "fall"
    case winter = "winter"
    
    var displayName: String {
        switch self {
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .fall: return "Fall"
        case .winter: return "Winter"
        }
    }
    
    var emoji: String {
        switch self {
        case .spring: return "🌸"
        case .summer: return "☀️"
        case .fall: return "🍂"
        case .winter: return "❄️"
        }
    }
}

enum Holiday: String, CaseIterable, Codable {
    case newYear = "new_year"
    case valentines = "valentines"
    case easter = "easter"
    case mothersDay = "mothers_day"
    case fathersDay = "fathers_day"
    case independenceDay = "independence_day"
    case halloween = "halloween"
    case thanksgiving = "thanksgiving"
    case christmas = "christmas"
    
    var displayName: String {
        switch self {
        case .newYear: return "New Year"
        case .valentines: return "Valentine's Day"
        case .easter: return "Easter"
        case .mothersDay: return "Mother's Day"
        case .fathersDay: return "Father's Day"
        case .independenceDay: return "Independence Day"
        case .halloween: return "Halloween"
        case .thanksgiving: return "Thanksgiving"
        case .christmas: return "Christmas"
        }
    }
}

enum ThemeMood: String, Codable {
    case cozy, elegant, fresh, natural, airy, relaxed, warm, rustic
}

enum SeasonalContentType: String {
    case theme = "theme"
    case collection = "collection"
    case decoration = "decoration"
    case colorPalette = "color_palette"
}

enum DecorationCategory: String, Codable {
    case wallDecor = "wall_decor"
    case centerpiece = "centerpiece"
    case holidayDecor = "holiday_decor"
    case lighting = "lighting"
    case textiles = "textiles"
}

struct SeasonalTheme: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let primaryColor: Color
    let accentColor: Color
    let mood: ThemeMood
    let season: Season
    let associatedHolidays: [Holiday]
}

struct FurnitureCollection: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let season: Season
    let items: [FurnitureItem]
    let imageURL: String
    let tags: [String]
}

struct SeasonalDecoration: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let category: DecorationCategory
    let season: Season
    let associatedHolidays: [Holiday]
    let modelFileName: String
    let thumbnailURL: String
}

struct ColorPalette: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let season: Season
    let primaryColor: Color
    let secondaryColor: Color
    let accentColor: Color
    let neutralColor: Color
}

struct SeasonalContentPackage {
    let season: Season
    let themes: [SeasonalTheme]
    let collections: [FurnitureCollection]
    let decorations: [SeasonalDecoration]
    let colorPalettes: [ColorPalette]
}

// MARK: - Extensions

extension Color: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let red = try container.decode(Double.self, forKey: .red)
        let green = try container.decode(Double.self, forKey: .green)
        let blue = try container.decode(Double.self, forKey: .blue)
        let alpha = try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1.0
        
        self.init(red: red, green: green, blue: blue, opacity: alpha)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        try container.encode(Double(red), forKey: .red)
        try container.encode(Double(green), forKey: .green)
        try container.encode(Double(blue), forKey: .blue)
        try container.encode(Double(alpha), forKey: .alpha)
    }
    
    private enum CodingKeys: String, CodingKey {
        case red, green, blue, alpha
    }
}

extension FeatureUsageMetric {
    static func featureUsageMetric(from string: String) -> FeatureUsageMetric {
        return FeatureUsageMetric(rawValue: string) ?? .featureDiscovered
    }
}

extension RoomType {
    static let patio = RoomType(rawValue: "patio") ?? .other
    static let deck = RoomType(rawValue: "deck") ?? .other
    static let familyRoom = RoomType(rawValue: "family_room") ?? .livingRoom
}