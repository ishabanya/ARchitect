import Foundation

// MARK: - Unit Converter
public class UnitConverter {
    
    public static let shared = UnitConverter()
    
    private init() {}
    
    // MARK: - Length Conversions
    
    /// Convert meters to feet
    public func metersToFeet(_ meters: Float) -> Float {
        return meters * 3.28084
    }
    
    /// Convert feet to meters
    public func feetToMeters(_ feet: Float) -> Float {
        return feet / 3.28084
    }
    
    /// Convert meters to inches
    public func metersToInches(_ meters: Float) -> Float {
        return meters * 39.3701
    }
    
    /// Convert inches to meters
    public func inchesToMeters(_ inches: Float) -> Float {
        return inches / 39.3701
    }
    
    /// Convert centimeters to inches
    public func centimetersToInches(_ cm: Float) -> Float {
        return cm / 2.54
    }
    
    /// Convert inches to centimeters
    public func inchesToCentimeters(_ inches: Float) -> Float {
        return inches * 2.54
    }
    
    // MARK: - Area Conversions
    
    /// Convert square meters to square feet
    public func squareMetersToSquareFeet(_ sqm: Float) -> Float {
        return sqm * 10.7639
    }
    
    /// Convert square feet to square meters
    public func squareFeetToSquareMeters(_ sqft: Float) -> Float {
        return sqft / 10.7639
    }
    
    /// Convert square meters to square inches
    public func squareMetersToSquareInches(_ sqm: Float) -> Float {
        return sqm * 1550.0031
    }
    
    /// Convert square inches to square meters
    public func squareInchesToSquareMeters(_ sqin: Float) -> Float {
        return sqin / 1550.0031
    }
    
    // MARK: - Volume Conversions
    
    /// Convert cubic meters to cubic feet
    public func cubicMetersToCubicFeet(_ cbm: Float) -> Float {
        return cbm * 35.3147
    }
    
    /// Convert cubic feet to cubic meters
    public func cubicFeetToCubicMeters(_ cbft: Float) -> Float {
        return cbft / 35.3147
    }
    
    /// Convert cubic meters to liters
    public func cubicMetersToLiters(_ cbm: Float) -> Float {
        return cbm * 1000
    }
    
    /// Convert liters to cubic meters
    public func litersToCubicMeters(_ liters: Float) -> Float {
        return liters / 1000
    }
    
    /// Convert cubic feet to gallons (US)
    public func cubicFeetToGallons(_ cbft: Float) -> Float {
        return cbft * 7.48052
    }
    
    /// Convert gallons (US) to cubic feet
    public func gallonsToCubicFeet(_ gallons: Float) -> Float {
        return gallons / 7.48052
    }
    
    // MARK: - Angle Conversions
    
    /// Convert degrees to radians
    public func degreesToRadians(_ degrees: Float) -> Float {
        return degrees * Float.pi / 180
    }
    
    /// Convert radians to degrees
    public func radiansToDegrees(_ radians: Float) -> Float {
        return radians * 180 / Float.pi
    }
    
    // MARK: - Smart Conversion Methods
    
    /// Convert a measurement value to the target unit system
    public func convert(_ value: MeasurementValue, to targetSystem: UnitSystem) -> MeasurementValue {
        return value.converted(to: targetSystem)
    }
    
    /// Get the most appropriate unit for a length measurement
    public func getBestLengthUnit(for value: Float, in system: UnitSystem) -> (value: Float, unit: MeasurementUnit) {
        switch system {
        case .metric:
            if value < 0.01 {
                return (value * 1000, .millimeters)
            } else if value < 1.0 {
                return (value * 100, .centimeters)
            } else {
                return (value, .meters)
            }
            
        case .imperial:
            let inches = metersToInches(value)
            if inches < 12 {
                return (inches, .inches)
            } else {
                let feet = metersToFeet(value)
                return (feet, .feet)
            }
        }
    }
    
    /// Get the most appropriate unit for an area measurement
    public func getBestAreaUnit(for value: Float, in system: UnitSystem) -> (value: Float, unit: MeasurementUnit) {
        switch system {
        case .metric:
            return (value, .squareMeters)
        case .imperial:
            return (squareMetersToSquareFeet(value), .squareFeet)
        }
    }
    
    /// Get the most appropriate unit for a volume measurement
    public func getBestVolumeUnit(for value: Float, in system: UnitSystem) -> (value: Float, unit: MeasurementUnit) {
        switch system {
        case .metric:
            return (value, .cubicMeters)
        case .imperial:
            return (cubicMetersToCubicFeet(value), .cubicFeet)
        }
    }
    
    // MARK: - Formatting Methods
    
    /// Format a length measurement with appropriate precision
    public func formatLength(_ value: Float, unit: MeasurementUnit, precision: Int = 2) -> String {
        switch unit {
        case .millimeters:
            return String(format: "%.0f mm", value)
        case .centimeters:
            return String(format: "%.1f cm", value)
        case .meters:
            if value < 1.0 {
                return String(format: "%.0f cm", value * 100)
            } else {
                return String(format: "%.\(precision)f m", value)
            }
        case .inches:
            return String(format: "%.1f\"", value)
        case .feet:
            let feet = Int(value)
            let inches = (value - Float(feet)) * 12
            if feet > 0 && inches > 0.1 {
                return String(format: "%d' %.1f\"", feet, inches)
            } else if feet > 0 {
                return String(format: "%d'", feet)
            } else {
                return String(format: "%.1f\"", value * 12)
            }
        default:
            return String(format: "%.\(precision)f", value)
        }
    }
    
    /// Format an area measurement with appropriate precision
    public func formatArea(_ value: Float, unit: MeasurementUnit, precision: Int = 2) -> String {
        switch unit {
        case .squareMeters:
            return String(format: "%.\(precision)f m²", value)
        case .squareFeet:
            return String(format: "%.\(precision)f ft²", value)
        default:
            return String(format: "%.\(precision)f", value)
        }
    }
    
    /// Format a volume measurement with appropriate precision
    public func formatVolume(_ value: Float, unit: MeasurementUnit, precision: Int = 2) -> String {
        switch unit {
        case .cubicMeters:
            return String(format: "%.\(precision)f m³", value)
        case .cubicFeet:
            return String(format: "%.\(precision)f ft³", value)
        default:
            return String(format: "%.\(precision)f", value)
        }
    }
    
    /// Format an angle measurement
    public func formatAngle(_ value: Float, unit: MeasurementUnit, precision: Int = 1) -> String {
        switch unit {
        case .degrees:
            return String(format: "%.\(precision)f°", value)
        case .radians:
            return String(format: "%.\(precision)f rad", value)
        default:
            return String(format: "%.\(precision)f", value)
        }
    }
    
    // MARK: - Validation Methods
    
    /// Validate if a measurement value is reasonable
    public func validateMeasurement(_ value: MeasurementValue, type: MeasurementType) -> ValidationResult {
        let minValues: [MeasurementType: Float] = [
            .distance: 0.001,  // 1mm
            .height: 0.001,    // 1mm
            .area: 0.0001,     // 1cm²
            .volume: 0.000001, // 1cm³
            .perimeter: 0.003, // 3mm (minimum triangle)
            .angle: 0.1        // 0.1 degrees
        ]
        
        let maxValues: [MeasurementType: Float] = [
            .distance: 1000,   // 1km
            .height: 1000,     // 1km
            .area: 1000000,    // 1km²
            .volume: 1000000000, // 1km³
            .perimeter: 10000, // 10km
            .angle: 360        // 360 degrees
        ]
        
        guard let minValue = minValues[type],
              let maxValue = maxValues[type] else {
            return ValidationResult(isValid: true, message: nil)
        }
        
        let meterValue = value.unitSystem == .metric ? value.primary : 
                        UnitConverter.shared.feetToMeters(value.primary)
        
        if meterValue < minValue {
            return ValidationResult(
                isValid: false,
                message: "Measurement too small (minimum: \(formatLength(minValue, unit: .meters)))"
            )
        }
        
        if meterValue > maxValue {
            return ValidationResult(
                isValid: false,
                message: "Measurement too large (maximum: \(formatLength(maxValue, unit: .meters)))"
            )
        }
        
        return ValidationResult(isValid: true, message: nil)
    }
    
    /// Check if two measurements are equivalent within tolerance
    public func areEquivalent(_ value1: MeasurementValue, _ value2: MeasurementValue, tolerance: Float = 0.01) -> Bool {
        // Convert both to same unit system for comparison
        let converted2 = value2.converted(to: value1.unitSystem)
        
        let difference = abs(value1.primary - converted2.primary)
        return difference <= tolerance
    }
    
    // MARK: - Conversion History
    
    private var conversionHistory: [ConversionRecord] = []
    private let maxHistoryCount = 100
    
    /// Record a conversion for history tracking
    public func recordConversion(from: MeasurementValue, to: MeasurementValue) {
        let record = ConversionRecord(
            timestamp: Date(),
            fromValue: from,
            toValue: to
        )
        
        conversionHistory.append(record)
        
        // Keep history within limits
        if conversionHistory.count > maxHistoryCount {
            conversionHistory.removeFirst(conversionHistory.count - maxHistoryCount)
        }
    }
    
    /// Get recent conversion history
    public func getConversionHistory(limit: Int = 10) -> [ConversionRecord] {
        return Array(conversionHistory.suffix(limit).reversed())
    }
    
    /// Clear conversion history
    public func clearConversionHistory() {
        conversionHistory.removeAll()
    }
}

// MARK: - Supporting Types

public struct ValidationResult {
    public let isValid: Bool
    public let message: String?
    
    public init(isValid: Bool, message: String?) {
        self.isValid = isValid
        self.message = message
    }
}

public struct ConversionRecord: Codable, Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let fromValue: MeasurementValue
    public let toValue: MeasurementValue
    
    public init(timestamp: Date, fromValue: MeasurementValue, toValue: MeasurementValue) {
        self.timestamp = timestamp
        self.fromValue = fromValue
        self.toValue = toValue
    }
}

// MARK: - Unit System Preferences

public class UnitSystemPreferences: ObservableObject {
    @Published public var preferredSystem: UnitSystem {
        didSet {
            savePreferences()
        }
    }
    
    @Published public var autoDetectRegion: Bool {
        didSet {
            savePreferences()
        }
    }
    
    @Published public var showBothUnits: Bool {
        didSet {
            savePreferences()
        }
    }
    
    @Published public var precisionSettings: PrecisionSettings {
        didSet {
            savePreferences()
        }
    }
    
    public static let shared = UnitSystemPreferences()
    
    private let userDefaults = UserDefaults.standard
    private let preferredSystemKey = "measurementPreferredSystem"
    private let autoDetectRegionKey = "measurementAutoDetectRegion"
    private let showBothUnitsKey = "measurementShowBothUnits"
    private let precisionSettingsKey = "measurementPrecisionSettings"
    
    private init() {
        // Load saved preferences
        let systemRawValue = userDefaults.string(forKey: preferredSystemKey) ?? UnitSystem.metric.rawValue
        self.preferredSystem = UnitSystem(rawValue: systemRawValue) ?? .metric
        self.autoDetectRegion = userDefaults.bool(forKey: autoDetectRegionKey)
        self.showBothUnits = userDefaults.bool(forKey: showBothUnitsKey)
        
        // Load precision settings
        if let precisionData = userDefaults.data(forKey: precisionSettingsKey),
           let precision = try? JSONDecoder().decode(PrecisionSettings.self, from: precisionData) {
            self.precisionSettings = precision
        } else {
            self.precisionSettings = PrecisionSettings()
        }
        
        // Auto-detect region if enabled
        if autoDetectRegion {
            detectRegionalPreferences()
        }
    }
    
    private func savePreferences() {
        userDefaults.set(preferredSystem.rawValue, forKey: preferredSystemKey)
        userDefaults.set(autoDetectRegion, forKey: autoDetectRegionKey)
        userDefaults.set(showBothUnits, forKey: showBothUnitsKey)
        
        if let precisionData = try? JSONEncoder().encode(precisionSettings) {
            userDefaults.set(precisionData, forKey: precisionSettingsKey)
        }
    }
    
    private func detectRegionalPreferences() {
        let locale = Locale.current
        
        // Countries that primarily use imperial system
        let imperialCountries = ["US", "LR", "MM"] // United States, Liberia, Myanmar
        
        if let countryCode = locale.regionCode,
           imperialCountries.contains(countryCode) {
            preferredSystem = .imperial
        } else {
            preferredSystem = .metric
        }
    }
}

public struct PrecisionSettings: Codable {
    public var lengthPrecision: Int
    public var areaPrecision: Int
    public var volumePrecision: Int
    public var anglePrecision: Int
    
    public init(
        lengthPrecision: Int = 2,
        areaPrecision: Int = 2,
        volumePrecision: Int = 2,
        anglePrecision: Int = 1
    ) {
        self.lengthPrecision = lengthPrecision
        self.areaPrecision = areaPrecision
        self.volumePrecision = volumePrecision
        self.anglePrecision = anglePrecision
    }
}