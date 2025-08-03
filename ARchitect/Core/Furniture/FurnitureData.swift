import Foundation
import UIKit
import simd

// MARK: - Furniture Item

/// Represents a furniture item with comprehensive metadata
public struct FurnitureItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let description: String
    public let category: FurnitureCategory
    public let subcategory: FurnitureSubcategory
    public let brand: String?
    public let model3D: Model3D
    public let metadata: FurnitureMetadata
    public let pricing: FurniturePricing
    public let availability: FurnitureAvailability
    public let tags: [String]
    public let dateAdded: Date
    public let lastUpdated: Date
    public var isFeatured: Bool
    public var isCustom: Bool
    public var userRating: Float
    public var popularityScore: Float
    
    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        category: FurnitureCategory,
        subcategory: FurnitureSubcategory,
        brand: String? = nil,
        model3D: Model3D,
        metadata: FurnitureMetadata,
        pricing: FurniturePricing = FurniturePricing(),
        availability: FurnitureAvailability = FurnitureAvailability(),
        tags: [String] = [],
        dateAdded: Date = Date(),
        lastUpdated: Date = Date(),
        isFeatured: Bool = false,
        isCustom: Bool = false,
        userRating: Float = 0.0,
        popularityScore: Float = 0.0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.subcategory = subcategory
        self.brand = brand
        self.model3D = model3D
        self.metadata = metadata
        self.pricing = pricing
        self.availability = availability
        self.tags = tags
        self.dateAdded = dateAdded
        self.lastUpdated = lastUpdated
        self.isFeatured = isFeatured
        self.isCustom = isCustom
        self.userRating = userRating
        self.popularityScore = popularityScore
    }
    
    /// Get dimensions as formatted string
    public var formattedDimensions: String {
        let dims = metadata.dimensions
        return String(format: "%.1f × %.1f × %.1f cm", 
                     dims.width * 100, dims.depth * 100, dims.height * 100)
    }
    
    /// Get price as formatted string
    public var formattedPrice: String {
        if let price = pricing.retailPrice {
            return String(format: "$%.2f", price)
        }
        return "Price on request"
    }
    
    /// Check if item fits in given space
    public func fitsInSpace(width: Float, depth: Float, height: Float) -> Bool {
        let dims = metadata.dimensions
        return dims.width <= width && dims.depth <= depth && dims.height <= height
    }
    
    /// Get compatibility score with room style
    public func compatibilityScore(with style: RoomStyle) -> Float {
        return metadata.styleCompatibility[style] ?? 0.0
    }
    
    public static func == (lhs: FurnitureItem, rhs: FurnitureItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Furniture Categories

public enum FurnitureCategory: String, CaseIterable, Codable {
    case seating = "seating"
    case tables = "tables"
    case storage = "storage"
    case bedroom = "bedroom"
    case lighting = "lighting"
    case decor = "decor"
    case outdoor = "outdoor"
    case office = "office"
    case kitchen = "kitchen"
    case bathroom = "bathroom"
    
    public var displayName: String {
        switch self {
        case .seating: return "Seating"
        case .tables: return "Tables"
        case .storage: return "Storage"
        case .bedroom: return "Bedroom"
        case .lighting: return "Lighting"
        case .decor: return "Decor"
        case .outdoor: return "Outdoor"
        case .office: return "Office"
        case .kitchen: return "Kitchen"
        case .bathroom: return "Bathroom"
        }
    }
    
    public var icon: String {
        switch self {
        case .seating: return "chair.fill"
        case .tables: return "table.furniture"
        case .storage: return "cabinet.fill"
        case .bedroom: return "bed.double.fill"
        case .lighting: return "lightbulb.fill"
        case .decor: return "paintbrush.fill"
        case .outdoor: return "tree.fill"
        case .office: return "desktopcomputer"
        case .kitchen: return "refrigerator.fill"
        case .bathroom: return "bathtub.fill"
        }
    }
    
    public var subcategories: [FurnitureSubcategory] {
        switch self {
        case .seating:
            return [.sofa, .chair, .armchair, .stool, .bench, .ottoman]
        case .tables:
            return [.diningTable, .coffeeTable, .sideTable, .desk, .console]
        case .storage:
            return [.wardrobe, .dresser, .bookshelf, .cabinet, .chest]
        case .bedroom:
            return [.bed, .nightstand, .mattress, .headboard]
        case .lighting:
            return [.floorLamp, .tableLamp, .ceilingLight, .chandelier]
        case .decor:
            return [.artwork, .mirror, .plant, .vase, .sculpture]
        case .outdoor:
            return [.outdoorSeating, .outdoorTable, .umbrellas, .planters]
        case .office:
            return [.officeChair, .officeDesk, .filing, .conference]
        case .kitchen:
            return [.kitchenTable, .kitchenChair, .island, .appliances]
        case .bathroom:
            return [.vanity, .storage, .accessories, .fixtures]
        }
    }
}

public enum FurnitureSubcategory: String, CaseIterable, Codable {
    // Seating
    case sofa = "sofa"
    case chair = "chair"
    case armchair = "armchair"
    case stool = "stool"
    case bench = "bench"
    case ottoman = "ottoman"
    
    // Tables
    case diningTable = "dining_table"
    case coffeeTable = "coffee_table"
    case sideTable = "side_table"
    case desk = "desk"
    case console = "console"
    
    // Storage
    case wardrobe = "wardrobe"
    case dresser = "dresser"
    case bookshelf = "bookshelf"
    case cabinet = "cabinet"
    case chest = "chest"
    
    // Bedroom
    case bed = "bed"
    case nightstand = "nightstand"
    case mattress = "mattress"
    case headboard = "headboard"
    
    // Lighting
    case floorLamp = "floor_lamp"
    case tableLamp = "table_lamp"
    case ceilingLight = "ceiling_light"
    case chandelier = "chandelier"
    
    // Decor
    case artwork = "artwork"
    case mirror = "mirror"
    case plant = "plant"
    case vase = "vase"
    case sculpture = "sculpture"
    
    // Outdoor
    case outdoorSeating = "outdoor_seating"
    case outdoorTable = "outdoor_table"
    case umbrellas = "umbrellas"
    case planters = "planters"
    
    // Office
    case officeChair = "office_chair"
    case officeDesk = "office_desk"
    case filing = "filing"
    case conference = "conference"
    
    // Kitchen
    case kitchenTable = "kitchen_table"
    case kitchenChair = "kitchen_chair"
    case island = "island"
    case appliances = "appliances"
    
    // Bathroom
    case vanity = "vanity"
    case storage = "storage"
    case accessories = "accessories"
    case fixtures = "fixtures"
    
    public var displayName: String {
        return rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Furniture Metadata

public struct FurnitureMetadata: Codable, Equatable {
    public let dimensions: FurnitureDimensions
    public let materials: [FurnitureMaterial]
    public let colors: [FurnitureColor]
    public let styles: [FurnitureStyle]
    public let weight: Float // in kg
    public let assemblyRequired: Bool
    public let careInstructions: String
    public let warranty: FurnitureWarranty?
    public let sustainability: SustainabilityInfo?
    public let styleCompatibility: [RoomStyle: Float] // 0.0 to 1.0 compatibility scores
    public let functionalFeatures: [FunctionalFeature]
    public let placementSuggestions: [PlacementSuggestion]
    
    public init(
        dimensions: FurnitureDimensions,
        materials: [FurnitureMaterial],
        colors: [FurnitureColor],
        styles: [FurnitureStyle],
        weight: Float,
        assemblyRequired: Bool = false,
        careInstructions: String = "",
        warranty: FurnitureWarranty? = nil,
        sustainability: SustainabilityInfo? = nil,
        styleCompatibility: [RoomStyle: Float] = [:],
        functionalFeatures: [FunctionalFeature] = [],
        placementSuggestions: [PlacementSuggestion] = []
    ) {
        self.dimensions = dimensions
        self.materials = materials
        self.colors = colors
        self.styles = styles
        self.weight = weight
        self.assemblyRequired = assemblyRequired
        self.careInstructions = careInstructions
        self.warranty = warranty
        self.sustainability = sustainability
        self.styleCompatibility = styleCompatibility
        self.functionalFeatures = functionalFeatures
        self.placementSuggestions = placementSuggestions
    }
}

public struct FurnitureDimensions: Codable, Equatable {
    public let width: Float  // in meters
    public let depth: Float  // in meters
    public let height: Float // in meters
    public let seatHeight: Float? // for seating furniture
    public let armHeight: Float?  // for chairs/sofas
    
    public init(width: Float, depth: Float, height: Float, seatHeight: Float? = nil, armHeight: Float? = nil) {
        self.width = width
        self.depth = depth
        self.height = height
        self.seatHeight = seatHeight
        self.armHeight = armHeight
    }
    
    public var volume: Float {
        return width * depth * height
    }
    
    public var footprint: Float {
        return width * depth
    }
}

// MARK: - Materials and Colors

public enum FurnitureMaterial: String, CaseIterable, Codable {
    case wood = "wood"
    case metal = "metal"
    case fabric = "fabric"
    case leather = "leather"
    case plastic = "plastic"
    case glass = "glass"
    case marble = "marble"
    case ceramic = "ceramic"
    case rattan = "rattan"
    case bamboo = "bamboo"
    case stone = "stone"
    case composite = "composite"
    
    public var displayName: String {
        return rawValue.capitalized
    }
    
    public var durabilityScore: Float {
        switch self {
        case .metal, .stone, .marble: return 0.9
        case .wood, .ceramic, .glass: return 0.8
        case .leather, .composite: return 0.7
        case .fabric, .rattan, .bamboo: return 0.6
        case .plastic: return 0.5
        }
    }
    
    public var maintenanceLevel: MaintenanceLevel {
        switch self {
        case .plastic, .metal, .glass: return .low
        case .wood, .ceramic, .composite: return .medium
        case .fabric, .leather, .rattan, .bamboo, .marble, .stone: return .high
        }
    }
}

public struct FurnitureColor: Codable, Equatable {
    public let name: String
    public let hexValue: String
    public let colorFamily: ColorFamily
    public let finish: ColorFinish
    
    public init(name: String, hexValue: String, colorFamily: ColorFamily, finish: ColorFinish = .matte) {
        self.name = name
        self.hexValue = hexValue
        self.colorFamily = colorFamily
        self.finish = finish
    }
}

public enum ColorFamily: String, CaseIterable, Codable {
    case neutral = "neutral"
    case warm = "warm"
    case cool = "cool"
    case earth = "earth"
    case bold = "bold"
    case pastel = "pastel"
    
    public var displayName: String {
        return rawValue.capitalized
    }
}

public enum ColorFinish: String, CaseIterable, Codable {
    case matte = "matte"
    case glossy = "glossy"
    case satin = "satin"
    case textured = "textured"
    case metallic = "metallic"
    case distressed = "distressed"
}

// MARK: - Styles and Features

public enum FurnitureStyle: String, CaseIterable, Codable {
    case modern = "modern"
    case contemporary = "contemporary"
    case traditional = "traditional"
    case rustic = "rustic"
    case industrial = "industrial"
    case scandinavian = "scandinavian"
    case midCentury = "mid_century"
    case bohemian = "bohemian"
    case minimalist = "minimalist"
    case artDeco = "art_deco"
    case farmhouse = "farmhouse"
    case transitional = "transitional"
    
    public var displayName: String {
        switch self {
        case .midCentury: return "Mid-Century"
        case .artDeco: return "Art Deco"
        default: return rawValue.capitalized
        }
    }
}

public enum RoomStyle: String, CaseIterable, Codable {
    case modern = "modern"
    case traditional = "traditional"
    case contemporary = "contemporary"
    case rustic = "rustic"
    case industrial = "industrial"
    case scandinavian = "scandinavian"
    case bohemian = "bohemian"
    case minimalist = "minimalist"
    case eclectic = "eclectic"
    
    public var displayName: String {
        return rawValue.capitalized
    }
}

public enum FunctionalFeature: String, CaseIterable, Codable {
    case storage = "storage"
    case reclining = "reclining"
    case convertible = "convertible"
    case swivel = "swivel"
    case adjustableHeight = "adjustable_height"
    case extendable = "extendable"
    case foldable = "foldable"
    case modular = "modular"
    case builtin_usb = "builtin_usb"
    case builtin_lighting = "builtin_lighting"
    case wireless_charging = "wireless_charging"
    case ergonomic = "ergonomic"
    
    public var displayName: String {
        return rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    public var icon: String {
        switch self {
        case .storage: return "archivebox"
        case .reclining: return "chair.lounge"
        case .convertible: return "arrow.triangle.2.circlepath"
        case .swivel: return "arrow.clockwise"
        case .adjustableHeight: return "arrow.up.and.down"
        case .extendable: return "arrow.left.and.right"
        case .foldable: return "rectangle.compress.vertical"
        case .modular: return "square.grid.3x3"
        case .builtin_usb: return "bolt"
        case .builtin_lighting: return "lightbulb"
        case .wireless_charging: return "battery.100.bolt"
        case .ergonomic: return "figure.seated.side"
        }
    }
}

public enum PlacementSuggestion: String, CaseIterable, Codable {
    case againstWall = "against_wall"
    case centerOfRoom = "center_of_room"
    case cornerPlacement = "corner_placement"
    case nearWindow = "near_window"
    case floatingLayout = "floating_layout"
    case underStairs = "under_stairs"
    case entryway = "entryway"
    case diningArea = "dining_area"
    case livingArea = "living_area"
    case bedroom = "bedroom"
    
    public var displayName: String {
        return rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    public var description: String {
        switch self {
        case .againstWall: return "Best placed against a wall for stability and space efficiency"
        case .centerOfRoom: return "Works well as a centerpiece or room divider"
        case .cornerPlacement: return "Perfect for corner spaces to maximize room usage"
        case .nearWindow: return "Ideal near windows for natural light"
        case .floatingLayout: return "Can be placed freely without wall support"
        case .underStairs: return "Fits nicely in under-stair spaces"
        case .entryway: return "Suitable for entrance areas"
        case .diningArea: return "Designed for dining spaces"
        case .livingArea: return "Perfect for living rooms"
        case .bedroom: return "Ideal for bedroom use"
        }
    }
}

// MARK: - Pricing and Availability

public struct FurniturePricing: Codable, Equatable {
    public let retailPrice: Float?
    public let salePrice: Float?
    public let currency: String
    public let priceRange: PriceRange
    public let isOnSale: Bool
    public let saleEndDate: Date?
    public let financing: FinancingOption?
    
    public init(
        retailPrice: Float? = nil,
        salePrice: Float? = nil,
        currency: String = "USD",
        priceRange: PriceRange = .medium,
        isOnSale: Bool = false,
        saleEndDate: Date? = nil,
        financing: FinancingOption? = nil
    ) {
        self.retailPrice = retailPrice
        self.salePrice = salePrice
        self.currency = currency
        self.priceRange = priceRange
        self.isOnSale = isOnSale
        self.saleEndDate = saleEndDate
        self.financing = financing
    }
    
    public var currentPrice: Float? {
        return isOnSale ? salePrice : retailPrice
    }
    
    public var discountPercentage: Float? {
        guard let retail = retailPrice, let sale = salePrice, retail > 0 else { return nil }
        return ((retail - sale) / retail) * 100
    }
}

public enum PriceRange: String, CaseIterable, Codable {
    case budget = "budget"        // < $200
    case low = "low"             // $200-500
    case medium = "medium"       // $500-1500
    case high = "high"          // $1500-3000
    case luxury = "luxury"      // > $3000
    
    public var displayName: String {
        switch self {
        case .budget: return "Budget ($0-200)"
        case .low: return "Low ($200-500)"
        case .medium: return "Medium ($500-1,500)"
        case .high: return "High ($1,500-3,000)"
        case .luxury: return "Luxury ($3,000+)"
        }
    }
    
    public var range: ClosedRange<Float> {
        switch self {
        case .budget: return 0...200
        case .low: return 200...500
        case .medium: return 500...1500
        case .high: return 1500...3000
        case .luxury: return 3000...Float.greatestFiniteMagnitude
        }
    }
}

public struct FinancingOption: Codable, Equatable {
    public let provider: String
    public let monthlyPayment: Float
    public let termMonths: Int
    public let interestRate: Float
    public let qualificationRequired: Bool
    
    public init(provider: String, monthlyPayment: Float, termMonths: Int, interestRate: Float, qualificationRequired: Bool = true) {
        self.provider = provider
        self.monthlyPayment = monthlyPayment
        self.termMonths = termMonths
        self.interestRate = interestRate
        self.qualificationRequired = qualificationRequired
    }
}

public struct FurnitureAvailability: Codable, Equatable {
    public let inStock: Bool
    public let stockLevel: StockLevel
    public let estimatedDelivery: Date?
    public let shippingOptions: [ShippingOption]
    public let regions: [String] // Available regions/countries
    
    public init(
        inStock: Bool = true,
        stockLevel: StockLevel = .inStock,
        estimatedDelivery: Date? = nil,
        shippingOptions: [ShippingOption] = [],
        regions: [String] = ["US", "CA"]
    ) {
        self.inStock = inStock
        self.stockLevel = stockLevel
        self.estimatedDelivery = estimatedDelivery
        self.shippingOptions = shippingOptions
        self.regions = regions
    }
}

public enum StockLevel: String, CaseIterable, Codable {
    case inStock = "in_stock"
    case lowStock = "low_stock"
    case outOfStock = "out_of_stock"
    case preOrder = "pre_order"
    case discontinued = "discontinued"
    
    public var displayName: String {
        switch self {
        case .inStock: return "In Stock"
        case .lowStock: return "Low Stock"
        case .outOfStock: return "Out of Stock"
        case .preOrder: return "Pre-Order"
        case .discontinued: return "Discontinued"
        }
    }
    
    public var color: String {
        switch self {
        case .inStock: return "green"
        case .lowStock: return "orange"
        case .outOfStock: return "red"
        case .preOrder: return "blue"
        case .discontinued: return "gray"
        }
    }
}

public struct ShippingOption: Codable, Equatable {
    public let method: String
    public let cost: Float
    public let estimatedDays: Int
    public let trackingAvailable: Bool
    
    public init(method: String, cost: Float, estimatedDays: Int, trackingAvailable: Bool = true) {
        self.method = method
        self.cost = cost
        self.estimatedDays = estimatedDays
        self.trackingAvailable = trackingAvailable
    }
}

// MARK: - Sustainability and Warranty

public struct SustainabilityInfo: Codable, Equatable {
    public let ecoFriendly: Bool
    public let certifications: [SustainabilityCertification]
    public let recycledContent: Float // 0.0 to 1.0
    public let carbonFootprint: CarbonFootprint?
    public let repairability: RepairabilityScore
    
    public init(
        ecoFriendly: Bool,
        certifications: [SustainabilityCertification] = [],
        recycledContent: Float = 0.0,
        carbonFootprint: CarbonFootprint? = nil,
        repairability: RepairabilityScore = .medium
    ) {
        self.ecoFriendly = ecoFriendly
        self.certifications = certifications
        self.recycledContent = recycledContent
        self.carbonFootprint = carbonFootprint
        self.repairability = repairability
    }
}

public enum SustainabilityCertification: String, CaseIterable, Codable {
    case fsc = "fsc"                    // Forest Stewardship Council
    case greenguard = "greenguard"      // Low emissions
    case cradle2cradle = "cradle2cradle" // Circular design
    case energyStar = "energy_star"     // Energy efficient
    case recycled = "recycled"          // Recycled materials
    
    public var displayName: String {
        switch self {
        case .fsc: return "FSC Certified"
        case .greenguard: return "GREENGUARD"
        case .cradle2cradle: return "Cradle to Cradle"
        case .energyStar: return "ENERGY STAR"
        case .recycled: return "Recycled Materials"
        }
    }
}

public struct CarbonFootprint: Codable, Equatable {
    public let productionKgCO2: Float
    public let shippingKgCO2: Float
    public let lifetimeKgCO2: Float
    
    public var totalKgCO2: Float {
        return productionKgCO2 + shippingKgCO2 + lifetimeKgCO2
    }
}

public enum RepairabilityScore: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    public var displayName: String {
        return rawValue.capitalized
    }
    
    public var score: Float {
        switch self {
        case .low: return 0.3
        case .medium: return 0.6
        case .high: return 0.9
        }
    }
}

public struct FurnitureWarranty: Codable, Equatable {
    public let duration: Int // in years
    public let type: WarrantyType
    public let coverage: String
    public let provider: String
    public let transferable: Bool
    
    public init(duration: Int, type: WarrantyType, coverage: String, provider: String, transferable: Bool = false) {
        self.duration = duration
        self.type = type
        self.coverage = coverage
        self.provider = provider
        self.transferable = transferable
    }
}

public enum WarrantyType: String, CaseIterable, Codable {
    case manufacturer = "manufacturer"
    case extended = "extended"
    case lifetime = "lifetime"
    case limited = "limited"
    
    public var displayName: String {
        return rawValue.capitalized
    }
}

public enum MaintenanceLevel: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    public var displayName: String {
        return rawValue.capitalized
    }
    
    public var description: String {
        switch self {
        case .low: return "Minimal care required"
        case .medium: return "Regular maintenance needed"
        case .high: return "Frequent care required"
        }
    }
}