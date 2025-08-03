import Foundation
import SwiftUI
import UIKit

// MARK: - Seasonal Theme Manager

@MainActor
public class SeasonalThemeManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var currentSeason: Season = .spring
    @Published public var isSeasonalThemeEnabled: Bool = true
    @Published public var activeEasterEggs: [EasterEgg] = []
    @Published public var foundEasterEggs: Set<String> = []
    
    // MARK: - Seasonal Themes
    public enum Season: String, CaseIterable {
        case spring = "Spring"
        case summer = "Summer"
        case autumn = "Autumn"
        case winter = "Winter"
        case holiday = "Holiday"
        case newYear = "New Year"
        case valentine = "Valentine"
        case halloween = "Halloween"
        case thanksgiving = "Thanksgiving"
        case custom = "Custom"
        
        public var displayName: String {
            return rawValue
        }
        
        public var dateRange: (start: DateComponents, end: DateComponents) {
            switch self {
            case .spring:
                return (DateComponents(month: 3, day: 20), DateComponents(month: 6, day: 19))
            case .summer:
                return (DateComponents(month: 6, day: 20), DateComponents(month: 9, day: 22))
            case .autumn:
                return (DateComponents(month: 9, day: 23), DateComponents(month: 12, day: 20))
            case .winter:
                return (DateComponents(month: 12, day: 21), DateComponents(month: 3, day: 19))
            case .valentine:
                return (DateComponents(month: 2, day: 10), DateComponents(month: 2, day: 18))
            case .halloween:
                return (DateComponents(month: 10, day: 25), DateComponents(month: 11, day: 2))
            case .thanksgiving:
                return (DateComponents(month: 11, day: 20), DateComponents(month: 11, day: 30))
            case .holiday:
                return (DateComponents(month: 12, day: 15), DateComponents(month: 1, day: 7))
            case .newYear:
                return (DateComponents(month: 12, day: 30), DateComponents(month: 1, day: 3))
            case .custom:
                return (DateComponents(month: 1, day: 1), DateComponents(month: 12, day: 31))
            }
        }
        
        public var primaryColors: [Color] {
            switch self {
            case .spring:
                return [.green, .pink, .yellow, .mint]
            case .summer:
                return [.blue, .orange, .yellow, .cyan]
            case .autumn:
                return [.orange, .red, .brown, .yellow]
            case .winter:
                return [.blue, .white, .gray, .indigo]
            case .valentine:
                return [.pink, .red, .purple, .white]
            case .halloween:
                return [.orange, .black, .purple, .yellow]
            case .thanksgiving:
                return [.orange, .brown, .yellow, .red]
            case .holiday:
                return [.red, .green, .gold, .white]
            case .newYear:
                return [.gold, .silver, .blue, .purple]
            case .custom:
                return [.accentColor, .blue, .purple, .green]
            }
        }
        
        public var backgroundGradient: LinearGradient {
            return LinearGradient(
                colors: primaryColors.map { $0.opacity(0.3) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        
        public var icon: String {
            switch self {
            case .spring: return "leaf.fill"
            case .summer: return "sun.max.fill"
            case .autumn: return "leaf.circle.fill"
            case .winter: return "snowflake"
            case .valentine: return "heart.fill"
            case .halloween: return "face.dashed.fill"
            case .thanksgiving: return "turkey.fill"
            case .holiday: return "gift.fill"
            case .newYear: return "party.popper.fill"
            case .custom: return "paintbrush.fill"
            }
        }
        
        public var particles: [SeasonalParticle] {
            switch self {
            case .spring:
                return [
                    SeasonalParticle(type: .flower, color: .pink, size: 12),
                    SeasonalParticle(type: .leaf, color: .green, size: 10),
                    SeasonalParticle(type: .butterfly, color: .yellow, size: 8)
                ]
            case .summer:
                return [
                    SeasonalParticle(type: .sunshine, color: .yellow, size: 15),
                    SeasonalParticle(type: .wave, color: .blue, size: 12),
                    SeasonalParticle(type: .firefly, color: .orange, size: 6)
                ]
            case .autumn:
                return [
                    SeasonalParticle(type: .leaf, color: .orange, size: 14),
                    SeasonalParticle(type: .acorn, color: .brown, size: 10),
                    SeasonalParticle(type: .wind, color: .gray, size: 8)
                ]
            case .winter:
                return [
                    SeasonalParticle(type: .snowflake, color: .white, size: 12),
                    SeasonalParticle(type: .icicle, color: .blue, size: 10),
                    SeasonalParticle(type: .frost, color: .cyan, size: 8)
                ]
            case .valentine:
                return [
                    SeasonalParticle(type: .heart, color: .pink, size: 14),
                    SeasonalParticle(type: .rose, color: .red, size: 12),
                    SeasonalParticle(type: .sparkle, color: .purple, size: 10)
                ]
            case .halloween:
                return [
                    SeasonalParticle(type: .pumpkin, color: .orange, size: 16),
                    SeasonalParticle(type: .bat, color: .black, size: 12),
                    SeasonalParticle(type: .ghost, color: .white, size: 14)
                ]
            case .thanksgiving:
                return [
                    SeasonalParticle(type: .turkey, color: .brown, size: 16),
                    SeasonalParticle(type: .corn, color: .yellow, size: 12),
                    SeasonalParticle(type: .pie, color: .orange, size: 14)
                ]
            case .holiday:
                return [
                    SeasonalParticle(type: .present, color: .red, size: 14),
                    SeasonalParticle(type: .tree, color: .green, size: 16),
                    SeasonalParticle(type: .star, color: .gold, size: 12)
                ]
            case .newYear:
                return [
                    SeasonalParticle(type: .firework, color: .gold, size: 18),
                    SeasonalParticle(type: .confetti, color: .silver, size: 8),
                    SeasonalParticle(type: .balloon, color: .purple, size: 14)
                ]
            case .custom:
                return [
                    SeasonalParticle(type: .sparkle, color: .accentColor, size: 12)
                ]
            }
        }
        
        public var specialEffects: [SpecialEffect] {
            switch self {
            case .spring:
                return [.petalsFloating, .rainbowGlow, .blooming]
            case .summer:
                return [.heatWave, .sunbeams, .oceanWaves]
            case .autumn:
                return [.leavesfalling, .windSwirl, .goldHour]
            case .winter:
                return [.snowfall, .frostEffect, .iceGlimmer]
            case .valentine:
                return [.heartsFloating, .roseGlow, .cupidArrows]
            case .halloween:
                return [.spookyFog, .flickeringLight, .phantomGlow]
            case .thanksgiving:
                return [.warmGlow, .harvest, .gratitude]
            case .holiday:
                return [.magicalSnow, .twinkling, .presents]
            case .newYear:
                return [.fireworks, .celebration, .countdown]
            case .custom:
                return [.sparkles]
            }
        }
    }
    
    // MARK: - Easter Eggs
    public struct EasterEgg: Identifiable, Codable {
        public let id: String
        public let title: String
        public let description: String
        public let triggerCondition: TriggerCondition
        public let reward: Reward
        public let isHidden: Bool
        public let unlockDate: Date?
        
        public enum TriggerCondition: Codable {
            case tapSequence([String])
            case gesturePattern(String)
            case timeOfDay(hour: Int, minute: Int)
            case dateSpecific(month: Int, day: Int)
            case deviceShake(count: Int)
            case appUsage(days: Int)
            case objectPlacement(count: Int)
            case secretCode(String)
            case konami
            case developer
        }
        
        public enum Reward: Codable {
            case specialTheme(String)
            case uniqueModel(String)
            case achievement(String)
            case soundPack(String)
            case animation(String)
            case message(String)
        }
    }
    
    // MARK: - Special Effects
    public enum SpecialEffect: String, CaseIterable {
        case petalsFloating = "Petals Floating"
        case rainbowGlow = "Rainbow Glow"
        case blooming = "Blooming"
        case heatWave = "Heat Wave"
        case sunbeams = "Sunbeams"
        case oceanWaves = "Ocean Waves"
        case leavesfalling = "Leaves Falling"
        case windSwirl = "Wind Swirl"
        case goldHour = "Golden Hour"
        case snowfall = "Snowfall"
        case frostEffect = "Frost Effect"
        case iceGlimmer = "Ice Glimmer"
        case heartsFloating = "Hearts Floating"
        case roseGlow = "Rose Glow"
        case cupidArrows = "Cupid Arrows"
        case spookyFog = "Spooky Fog"
        case flickeringLight = "Flickering Light"
        case phantomGlow = "Phantom Glow"
        case warmGlow = "Warm Glow"
        case harvest = "Harvest"
        case gratitude = "Gratitude"
        case magicalSnow = "Magical Snow"
        case twinkling = "Twinkling"
        case presents = "Presents"
        case fireworks = "Fireworks"
        case celebration = "Celebration"
        case countdown = "Countdown"
        case sparkles = "Sparkles"
        
        public var icon: String {
            switch self {
            case .petalsFloating: return "leaf.fill"
            case .rainbowGlow: return "rainbow"
            case .blooming: return "flower.fill"
            case .heatWave: return "thermometer.sun.fill"
            case .sunbeams: return "sun.max.fill"
            case .oceanWaves: return "wave.3.right.fill"
            case .leavesfall,ing: return "leaf.circle.fill"
            case .windSwirl: return "wind"
            case .goldHour: return "sunrise.fill"
            case .snowfall: return "snow"
            case .frostEffect: return "snowflake"
            case .iceGlimmer: return "sparkles"
            case .heartsFloating: return "heart.fill"
            case .roseGlow: return "rose.fill"
            case .cupidArrows: return "arrow.up.heart.fill"
            case .spookyFog: return "cloud.fog.fill"
            case .flickeringLight: return "lightbulb.fill"
            case .phantomGlow: return "moon.stars.fill"
            case .warmGlow: return "flame.fill"
            case .harvest: return "leaf.arrow.circlepath"
            case .gratitude: return "hands.clap.fill"
            case .magicalSnow: return "sparkles"
            case .twinkling: return "star.fill"
            case .presents: return "gift.fill"
            case .fireworks: return "burst.fill"
            case .celebration: return "party.popper.fill"
            case .countdown: return "clock.fill"
            case .sparkles: return "sparkles"
            }
        }
    }
    
    // MARK: - Particle Data
    public struct SeasonalParticle {
        public let type: ParticleType
        public let color: Color
        public let size: CGFloat
        
        public enum ParticleType: String, CaseIterable {
            case flower, leaf, butterfly, sunshine, wave, firefly
            case acorn, wind, snowflake, icicle, frost, heart
            case rose, sparkle, pumpkin, bat, ghost, turkey
            case corn, pie, present, tree, star, firework
            case confetti, balloon
            
            public var systemImage: String {
                switch self {
                case .flower: return "flower.fill"
                case .leaf: return "leaf.fill"
                case .butterfly: return "butterfly.fill"
                case .sunshine: return "sun.max.fill"
                case .wave: return "wave.3.right.fill"
                case .firefly: return "sparkles"
                case .acorn: return "circle.fill"
                case .wind: return "wind"
                case .snowflake: return "snowflake"
                case .icicle: return "triangle.fill"
                case .frost: return "sparkles"
                case .heart: return "heart.fill"
                case .rose: return "rose.fill"
                case .sparkle: return "sparkles"
                case .pumpkin: return "circle.fill"
                case .bat: return "triangle.fill"
                case .ghost: return "cloud.fill"
                case .turkey: return "circle.fill"
                case .corn: return "oval.fill"
                case .pie: return "circle.fill"
                case .present: return "gift.fill"
                case .tree: return "tree.fill"
                case .star: return "star.fill"
                case .firework: return "burst.fill"
                case .confetti: return "rectangle.fill"
                case .balloon: return "oval.fill"
                }
            }
        }
    }
    
    // MARK: - Private Properties
    private let userDefaults = UserDefaults.standard
    private let calendar = Calendar.current
    private var easterEggTriggers: [String: Any] = [:]
    private var gestureRecognizer: UIGestureRecognizer?
    
    // Easter egg state
    private var konamiSequence: [String] = []
    private let konamiCode = ["up", "up", "down", "down", "left", "right", "left", "right", "b", "a"]
    private var tapSequence: [String] = []
    private var shakeCount = 0
    private var lastShakeTime = Date()
    
    public init() {
        loadThemeSettings()
        determineCurrentSeason()
        setupEasterEggs()
        
        logInfo("Seasonal Theme Manager initialized", category: .theme, context: LogContext(customData: [
            "current_season": currentSeason.rawValue,
            "themes_enabled": isSeasonalThemeEnabled
        ]))
    }
    
    // MARK: - Setup
    
    private func loadThemeSettings() {
        isSeasonalThemeEnabled = userDefaults.bool(forKey: "seasonal_themes_enabled")
        if userDefaults.object(forKey: "seasonal_themes_enabled") == nil {
            isSeasonalThemeEnabled = true // Default enabled
        }
        
        // Load found easter eggs
        if let eggData = userDefaults.data(forKey: "found_easter_eggs"),
           let eggs = try? JSONDecoder().decode(Set<String>.self, from: eggData) {
            foundEasterEggs = eggs
        }
    }
    
    private func saveThemeSettings() {
        userDefaults.set(isSeasonalThemeEnabled, forKey: "seasonal_themes_enabled")
        
        if let eggData = try? JSONEncoder().encode(foundEasterEggs) {
            userDefaults.set(eggData, forKey: "found_easter_eggs")
        }
    }
    
    private func determineCurrentSeason() {
        guard isSeasonalThemeEnabled else {
            currentSeason = .custom
            return
        }
        
        let now = Date()
        let currentComponents = calendar.dateComponents([.month, .day], from: now)
        
        // Check for special holidays first
        for season in [Season.valentine, .halloween, .thanksgiving, .holiday, .newYear] {
            if isDateInSeason(currentComponents, season: season) {
                currentSeason = season
                return
            }
        }
        
        // Check for regular seasons
        for season in [Season.spring, .summer, .autumn, .winter] {
            if isDateInSeason(currentComponents, season: season) {
                currentSeason = season
                return
            }
        }
        
        // Default fallback
        currentSeason = .spring
    }
    
    private func isDateInSeason(_ date: DateComponents, season: Season) -> Bool {
        let range = season.dateRange
        
        guard let month = date.month, let day = date.day,
              let startMonth = range.start.month, let startDay = range.start.day,
              let endMonth = range.end.month, let endDay = range.end.day else {
            return false
        }
        
        // Handle year wrap-around (e.g., winter season)
        if startMonth > endMonth {
            return (month > startMonth || (month == startMonth && day >= startDay)) ||
                   (month < endMonth || (month == endMonth && day <= endDay))
        } else {
            return (month > startMonth || (month == startMonth && day >= startDay)) &&
                   (month < endMonth || (month == endMonth && day <= endDay))
        }
    }
    
    private func setupEasterEggs() {
        activeEasterEggs = [
            // Konami Code
            EasterEgg(
                id: "konami",
                title: "Konami Code",
                description: "The classic cheat code still works!",
                triggerCondition: .konami,
                reward: .specialTheme("retro"),
                isHidden: true,
                unlockDate: nil
            ),
            
            // Developer Mode
            EasterEgg(
                id: "developer",
                title: "Developer",
                description: "For those who code in AR",
                triggerCondition: .developer,
                reward: .uniqueModel("developer_cube"),
                isHidden: false,
                unlockDate: nil
            ),
            
            // Shake Phone
            EasterEgg(
                id: "shake_it",
                title: "Shake It Off",
                description: "Sometimes you just gotta shake it",
                triggerCondition: .deviceShake(count: 10),
                reward: .animation("shake_celebration"),
                isHidden: false,
                unlockDate: nil
            ),
            
            // Time-based Easter Egg
            EasterEgg(
                id: "midnight",
                title: "Midnight Creator",
                description: "Creating at the witching hour",
                triggerCondition: .timeOfDay(hour: 0, minute: 0),
                reward: .specialTheme("midnight"),
                isHidden: true,
                unlockDate: nil
            ),
            
            // Secret Tap Sequence
            EasterEgg(
                id: "tap_dance",
                title: "Tap Dance",
                description: "The rhythm of creation",
                triggerCondition: .tapSequence(["top-left", "top-right", "bottom-left", "bottom-right", "center"]),
                reward: .soundPack("dance"),
                isHidden: true,
                unlockDate: nil
            ),
            
            // Date-specific (April 1st)
            EasterEgg(
                id: "april_fools",
                title: "April Fools!",
                description: "Got you!",
                triggerCondition: .dateSpecific(month: 4, day: 1),
                reward: .message("April Fools! 🎭"),
                isHidden: false,
                unlockDate: nil
            ),
            
            // Long-term usage
            EasterEgg(
                id: "dedicated_user",
                title: "Dedicated User",
                description: "30 days of AR creation",
                triggerCondition: .appUsage(days: 30),
                reward: .achievement("Master Creator"),
                isHidden: false,
                unlockDate: nil
            ),
            
            // Object placement milestone
            EasterEgg(
                id: "object_master",
                title: "Object Master",
                description: "Placed 100 objects in AR",
                triggerCondition: .objectPlacement(count: 100),
                reward: .uniqueModel("golden_cube"),
                isHidden: false,
                unlockDate: nil
            ),
            
            // Secret code
            EasterEgg(
                id: "architect",
                title: "True Architect",
                description: "Enter the secret architect code",
                triggerCondition: .secretCode("ARCHITECT"),
                reward: .specialTheme("architect_pro"),
                isHidden: true,
                unlockDate: nil
            )
        ]
    }
    
    // MARK: - Public Interface
    
    public func setSeasonalThemesEnabled(_ enabled: Bool) {
        isSeasonalThemeEnabled = enabled
        
        if enabled {
            determineCurrentSeason()
        } else {
            currentSeason = .custom
        }
        
        saveThemeSettings()
        
        logInfo("Seasonal themes \(enabled ? "enabled" : "disabled")", category: .theme)
    }
    
    public func forceSeason(_ season: Season) {
        currentSeason = season
        logInfo("Forced season change", category: .theme, context: LogContext(customData: [
            "season": season.rawValue
        ]))
    }
    
    public func refreshSeason() {
        determineCurrentSeason()
    }
    
    public func getThemeColors() -> [Color] {
        return currentSeason.primaryColors
    }
    
    public func getBackgroundGradient() -> LinearGradient {
        return currentSeason.backgroundGradient
    }
    
    public func getSeasonalParticles() -> [SeasonalParticle] {
        return currentSeason.particles
    }
    
    public func getSpecialEffects() -> [SpecialEffect] {
        return currentSeason.specialEffects
    }
    
    // MARK: - Easter Egg Triggers
    
    public func triggerKonamiSequence(_ input: String) {
        konamiSequence.append(input)
        
        if konamiSequence.count > konamiCode.count {
            konamiSequence.removeFirst()
        }
        
        if konamiSequence == konamiCode {
            triggerEasterEgg("konami")
            konamiSequence.removeAll()
        }
    }
    
    public func triggerTapSequence(_ location: String) {
        tapSequence.append(location)
        
        if tapSequence.count > 5 {
            tapSequence.removeFirst()
        }
        
        // Check for tap dance pattern
        if tapSequence == ["top-left", "top-right", "bottom-left", "bottom-right", "center"] {
            triggerEasterEgg("tap_dance")
            tapSequence.removeAll()
        }
    }
    
    public func triggerDeviceShake() {
        let now = Date()
        
        if now.timeIntervalSince(lastShakeTime) < 1.0 {
            shakeCount += 1
        } else {
            shakeCount = 1
        }
        
        lastShakeTime = now
        
        if shakeCount >= 10 {
            triggerEasterEgg("shake_it")
            shakeCount = 0
        }
    }
    
    public func triggerTimeCheck() {
        let now = Date()
        let components = calendar.dateComponents([.hour, .minute], from: now)
        
        if components.hour == 0 && components.minute == 0 {
            triggerEasterEgg("midnight")
        }
    }
    
    public func triggerDateCheck() {
        let now = Date()
        let components = calendar.dateComponents([.month, .day], from: now)
        
        if components.month == 4 && components.day == 1 {
            triggerEasterEgg("april_fools")
        }
    }
    
    public func triggerUsageCheck(_ days: Int) {
        if days >= 30 {
            triggerEasterEgg("dedicated_user")
        }
    }
    
    public func triggerObjectPlacementCheck(_ count: Int) {
        if count >= 100 {
            triggerEasterEgg("object_master")
        }
    }
    
    public func triggerSecretCode(_ code: String) {
        if code.uppercased() == "ARCHITECT" {
            triggerEasterEgg("architect")
        }
    }
    
    public func triggerDeveloperMode() {
        if userDefaults.bool(forKey: "developer_mode_enabled") {
            triggerEasterEgg("developer")
        }
    }
    
    private func triggerEasterEgg(_ id: String) {
        guard !foundEasterEggs.contains(id),
              let easterEgg = activeEasterEggs.first(where: { $0.id == id }) else {
            return
        }
        
        foundEasterEggs.insert(id)
        saveThemeSettings()
        
        // Apply reward
        applyEasterEggReward(easterEgg.reward)
        
        // Show celebration
        showEasterEggCelebration(easterEgg)
        
        logInfo("Easter egg triggered", category: .theme, context: LogContext(customData: [
            "easter_egg": easterEgg.title,
            "reward": String(describing: easterEgg.reward)
        ]))
    }
    
    private func applyEasterEggReward(_ reward: EasterEgg.Reward) {
        switch reward {
        case .specialTheme(let themeName):
            // Unlock special theme
            userDefaults.set(true, forKey: "theme_unlocked_\(themeName)")
        case .uniqueModel(let modelName):
            // Unlock unique 3D model
            userDefaults.set(true, forKey: "model_unlocked_\(modelName)")
        case .achievement(let achievementName):
            // Unlock achievement
            userDefaults.set(true, forKey: "achievement_\(achievementName)")
        case .soundPack(let packName):
            // Unlock sound pack
            userDefaults.set(true, forKey: "sounds_unlocked_\(packName)")
        case .animation(let animationName):
            // Unlock animation
            userDefaults.set(true, forKey: "animation_unlocked_\(animationName)")
        case .message(let message):
            // Show message
            break
        }
    }
    
    private func showEasterEggCelebration(_ easterEgg: EasterEgg) {
        // Post notification for UI to show celebration
        NotificationCenter.default.post(
            name: .easterEggTriggered,
            object: nil,
            userInfo: ["easterEgg": easterEgg]
        )
    }
    
    // MARK: - Theme Utilities
    
    public func getSeasonalIcon() -> String {
        return currentSeason.icon
    }
    
    public func getSeasonDescription() -> String {
        switch currentSeason {
        case .spring:
            return "Fresh blooms and new beginnings fill the air"
        case .summer:
            return "Bright sunshine and endless possibilities"
        case .autumn:
            return "Golden leaves and cozy warmth"
        case .winter:
            return "Sparkling snow and peaceful serenity"
        case .valentine:
            return "Love is in the air with hearts and roses"
        case .halloween:
            return "Spooky fun with pumpkins and treats"
        case .thanksgiving:
            return "Grateful hearts and harvest abundance"
        case .holiday:
            return "Magical celebrations with family and friends"
        case .newYear:
            return "Fresh starts and sparkling possibilities"
        case .custom:
            return "Your personalized AR experience"
        }
    }
    
    public func isEasterEggFound(_ id: String) -> Bool {
        return foundEasterEggs.contains(id)
    }
    
    public func getFoundEasterEggs() -> [EasterEgg] {
        return activeEasterEggs.filter { foundEasterEggs.contains($0.id) }
    }
    
    public func getHiddenEasterEggs() -> [EasterEgg] {
        return activeEasterEggs.filter { $0.isHidden && !foundEasterEggs.contains($0.id) }
    }
    
    public func getAllEasterEggs() -> [EasterEgg] {
        return activeEasterEggs
    }
    
    public func resetEasterEggs() {
        foundEasterEggs.removeAll()
        saveThemeSettings()
        
        logInfo("Easter eggs reset", category: .theme)
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let seasonChanged = Notification.Name("seasonChanged")
    static let easterEggTriggered = Notification.Name("easterEggTriggered")
    static let specialEffectTriggered = Notification.Name("specialEffectTriggered")
}