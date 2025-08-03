import Foundation
import UIKit
import SwiftUI

// MARK: - App Icon Management System

@MainActor
public class AppIconManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var currentIcon: AppIcon = .default
    @Published public var availableIcons: [AppIcon] = []
    @Published public var isIconAnimating: Bool = false
    
    // MARK: - App Icon Types
    public enum AppIcon: String, CaseIterable, Identifiable {
        case `default` = "AppIcon"
        case ar = "AppIcon-AR"
        case dark = "AppIcon-Dark"
        case neon = "AppIcon-Neon"
        case minimal = "AppIcon-Minimal"
        case seasonal = "AppIcon-Seasonal"
        case developer = "AppIcon-Developer"
        
        public var id: String { rawValue }
        
        public var displayName: String {
            switch self {
            case .default: return "Classic"
            case .ar: return "AR Theme"
            case .dark: return "Dark Mode"
            case .neon: return "Neon Glow"
            case .minimal: return "Minimal"
            case .seasonal: return "Seasonal"
            case .developer: return "Developer"
            }
        }
        
        public var description: String {
            switch self {
            case .default: return "Classic ARchitect icon with modern design"
            case .ar: return "Futuristic AR-themed icon with holographic elements"
            case .dark: return "Sleek dark theme perfect for OLED displays"
            case .neon: return "Vibrant neon glow with electric blue accents"
            case .minimal: return "Clean minimal design with subtle AR hints"
            case .seasonal: return "Special seasonal theme that changes with time"
            case .developer: return "Developer edition with code elements"
            }
        }
        
        public var previewImage: String {
            return "\(rawValue)-Preview"
        }
        
        public var unlockCondition: IconUnlockCondition {
            switch self {
            case .default: return .none
            case .ar: return .none
            case .dark: return .useAppInDarkMode(times: 5)
            case .neon: return .completeProjects(count: 3)
            case .minimal: return .useAppConsecutiveDays(days: 7)
            case .seasonal: return .seasonal
            case .developer: return .enableDeveloperMode
            }
        }
        
        public var isSpecial: Bool {
            switch self {
            case .default, .ar: return false
            case .dark, .neon, .minimal, .seasonal, .developer: return true
            }
        }
    }
    
    public enum IconUnlockCondition {
        case none
        case useAppInDarkMode(times: Int)
        case completeProjects(count: Int)
        case useAppConsecutiveDays(days: Int)
        case seasonal
        case enableDeveloperMode
        case achievement(String)
        
        public var description: String {
            switch self {
            case .none: return "Available by default"
            case .useAppInDarkMode(let times): return "Use app in dark mode \(times) times"
            case .completeProjects(let count): return "Complete \(count) AR projects"
            case .useAppConsecutiveDays(let days): return "Use app for \(days) consecutive days"
            case .seasonal: return "Available during special seasons"
            case .enableDeveloperMode: return "Enable developer mode in settings"
            case .achievement(let name): return "Unlock the '\(name)' achievement"
            }
        }
    }
    
    // MARK: - Private Properties
    private let userDefaults = UserDefaults.standard
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    // Icon unlock tracking
    private var iconUnlockData: [String: IconUnlockData] = [:]
    private var achievementTracker: AchievementTracker
    
    // Animation properties
    private var iconChangeAnimation: IconChangeAnimation?
    
    public init() {
        self.achievementTracker = AchievementTracker()
        
        loadIconData()
        checkAvailableIcons()
        
        logInfo("App Icon Manager initialized", category: .ui)
    }
    
    // MARK: - Setup
    
    private func loadIconData() {
        // Load current icon
        if let iconName = userDefaults.string(forKey: "current_app_icon"),
           let icon = AppIcon(rawValue: iconName) {
            currentIcon = icon
        }
        
        // Load unlock data
        if let data = userDefaults.data(forKey: "icon_unlock_data"),
           let decoded = try? JSONDecoder().decode([String: IconUnlockData].self, from: data) {
            iconUnlockData = decoded
        }
    }
    
    private func saveIconData() {
        userDefaults.set(currentIcon.rawValue, forKey: "current_app_icon")
        
        if let encoded = try? JSONEncoder().encode(iconUnlockData) {
            userDefaults.set(encoded, forKey: "icon_unlock_data")
        }
    }
    
    private func checkAvailableIcons() {
        var available: [AppIcon] = []
        
        for icon in AppIcon.allCases {
            if isIconUnlocked(icon) {
                available.append(icon)
            }
        }
        
        availableIcons = available
    }
    
    // MARK: - Icon Management
    
    public func changeIcon(to newIcon: AppIcon) async {
        guard isIconUnlocked(newIcon) else {
            logWarning("Attempted to change to locked icon", category: .ui, context: LogContext(customData: [
                "icon": newIcon.rawValue
            ]))
            return
        }
        
        guard UIApplication.shared.supportsAlternateIcons else {
            logError("Device does not support alternate icons", category: .ui)
            return
        }
        
        isIconAnimating = true
        hapticGenerator.impactOccurred()
        
        do {
            let iconName = newIcon == .default ? nil : newIcon.rawValue
            
            // Animate icon change
            await performIconChangeAnimation(from: currentIcon, to: newIcon)
            
            try await UIApplication.shared.setAlternateIconName(iconName)
            
            currentIcon = newIcon
            saveIconData()
            
            // Track usage for achievements
            trackIconUsage(newIcon)
            
            logInfo("App icon changed successfully", category: .ui, context: LogContext(customData: [
                "from": currentIcon.rawValue,
                "to": newIcon.rawValue
            ]))
            
        } catch {
            logError("Failed to change app icon", category: .ui, error: error)
        }
        
        isIconAnimating = false
    }
    
    private func performIconChangeAnimation(from oldIcon: AppIcon, to newIcon: AppIcon) async {
        iconChangeAnimation = IconChangeAnimation(from: oldIcon, to: newIcon)
        
        // Create transition animation
        await withCheckedContinuation { continuation in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                // Animation state changes would be handled by the UI
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                continuation.resume()
            }
        }
        
        iconChangeAnimation = nil
    }
    
    // MARK: - Icon Unlock System
    
    public func isIconUnlocked(_ icon: AppIcon) -> Bool {
        switch icon.unlockCondition {
        case .none:
            return true
            
        case .useAppInDarkMode(let requiredTimes):
            let data = getUnlockData(for: icon)
            return data.darkModeUsageCount >= requiredTimes
            
        case .completeProjects(let requiredCount):
            let data = getUnlockData(for: icon)
            return data.projectsCompleted >= requiredCount
            
        case .useAppConsecutiveDays(let requiredDays):
            let data = getUnlockData(for: icon)
            return data.consecutiveDaysUsed >= requiredDays
            
        case .seasonal:
            return isSeasonalIconAvailable()
            
        case .enableDeveloperMode:
            return userDefaults.bool(forKey: "developer_mode_enabled")
            
        case .achievement(let achievementName):
            return achievementTracker.isAchievementUnlocked(achievementName)
        }
    }
    
    private func getUnlockData(for icon: AppIcon) -> IconUnlockData {
        if let data = iconUnlockData[icon.rawValue] {
            return data
        } else {
            let newData = IconUnlockData()
            iconUnlockData[icon.rawValue] = newData
            return newData
        }
    }
    
    private func isSeasonalIconAvailable() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        
        // Check for special seasons/holidays
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)
        
        // Halloween (October)
        if month == 10 { return true }
        
        // Christmas/Winter (December - January)
        if month == 12 || month == 1 { return true }
        
        // Spring (March - May)
        if month >= 3 && month <= 5 { return true }
        
        // Summer (June - August)
        if month >= 6 && month <= 8 { return true }
        
        return false
    }
    
    // MARK: - Progress Tracking
    
    public func trackDarkModeUsage() {
        for icon in AppIcon.allCases {
            if case .useAppInDarkMode = icon.unlockCondition {
                var data = getUnlockData(for: icon)
                data.darkModeUsageCount += 1
                iconUnlockData[icon.rawValue] = data
                
                checkForNewUnlocks()
            }
        }
        saveIconData()
    }
    
    public func trackProjectCompletion() {
        for icon in AppIcon.allCases {
            if case .completeProjects = icon.unlockCondition {
                var data = getUnlockData(for: icon)
                data.projectsCompleted += 1
                iconUnlockData[icon.rawValue] = data
                
                checkForNewUnlocks()
            }
        }
        saveIconData()
    }
    
    public func trackDailyUsage() {
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        
        for icon in AppIcon.allCases {
            if case .useAppConsecutiveDays = icon.unlockCondition {
                var data = getUnlockData(for: icon)
                
                if let lastUsed = data.lastUsedDate {
                    if Calendar.current.isDate(lastUsed, inSameDayAs: yesterday) {
                        data.consecutiveDaysUsed += 1
                    } else if !Calendar.current.isDate(lastUsed, inSameDayAs: today) {
                        data.consecutiveDaysUsed = 1
                    }
                } else {
                    data.consecutiveDaysUsed = 1
                }
                
                data.lastUsedDate = today
                iconUnlockData[icon.rawValue] = data
                
                checkForNewUnlocks()
            }
        }
        saveIconData()
    }
    
    private func trackIconUsage(_ icon: AppIcon) {
        var data = getUnlockData(for: icon)
        data.timesUsed += 1
        data.lastUsedDate = Date()
        iconUnlockData[icon.rawValue] = data
        saveIconData()
    }
    
    private func checkForNewUnlocks() {
        let previouslyAvailable = Set(availableIcons)
        checkAvailableIcons()
        let newlyAvailable = Set(availableIcons)
        
        let newUnlocks = newlyAvailable.subtracting(previouslyAvailable)
        
        for newIcon in newUnlocks {
            notifyIconUnlocked(newIcon)
        }
    }
    
    private func notifyIconUnlocked(_ icon: AppIcon) {
        logInfo("New app icon unlocked", category: .ui, context: LogContext(customData: [
            "icon": icon.rawValue,
            "display_name": icon.displayName
        ]))
        
        // Post notification for UI to show unlock animation
        NotificationCenter.default.post(
            name: .iconUnlocked,
            object: nil,
            userInfo: ["icon": icon]
        )
        
        hapticGenerator.impactOccurred()
    }
    
    // MARK: - Public Interface
    
    public func getUnlockProgress(for icon: AppIcon) -> IconUnlockProgress {
        let data = getUnlockData(for: icon)
        
        switch icon.unlockCondition {
        case .none:
            return IconUnlockProgress(current: 1, required: 1, percentage: 1.0)
            
        case .useAppInDarkMode(let required):
            let current = min(data.darkModeUsageCount, required)
            return IconUnlockProgress(
                current: current,
                required: required,
                percentage: Double(current) / Double(required)
            )
            
        case .completeProjects(let required):
            let current = min(data.projectsCompleted, required)
            return IconUnlockProgress(
                current: current,
                required: required,
                percentage: Double(current) / Double(required)
            )
            
        case .useAppConsecutiveDays(let required):
            let current = min(data.consecutiveDaysUsed, required)
            return IconUnlockProgress(
                current: current,
                required: required,
                percentage: Double(current) / Double(required)
            )
            
        case .seasonal:
            return IconUnlockProgress(
                current: isSeasonalIconAvailable() ? 1 : 0,
                required: 1,
                percentage: isSeasonalIconAvailable() ? 1.0 : 0.0
            )
            
        case .enableDeveloperMode:
            let unlocked = userDefaults.bool(forKey: "developer_mode_enabled")
            return IconUnlockProgress(
                current: unlocked ? 1 : 0,
                required: 1,
                percentage: unlocked ? 1.0 : 0.0
            )
            
        case .achievement(let name):
            let unlocked = achievementTracker.isAchievementUnlocked(name)
            return IconUnlockProgress(
                current: unlocked ? 1 : 0,
                required: 1,
                percentage: unlocked ? 1.0 : 0.0
            )
        }
    }
    
    public func getAllIconsWithProgress() -> [IconWithProgress] {
        return AppIcon.allCases.map { icon in
            IconWithProgress(
                icon: icon,
                isUnlocked: isIconUnlocked(icon),
                progress: getUnlockProgress(for: icon)
            )
        }
    }
    
    public func getSpecialIcons() -> [AppIcon] {
        return AppIcon.allCases.filter { $0.isSpecial }
    }
    
    public func resetIconProgress() {
        iconUnlockData.removeAll()
        saveIconData()
        checkAvailableIcons()
        
        logInfo("Icon progress reset", category: .ui)
    }
}

// MARK: - Supporting Data Structures

public struct IconUnlockData: Codable {
    var darkModeUsageCount: Int = 0
    var projectsCompleted: Int = 0
    var consecutiveDaysUsed: Int = 0
    var lastUsedDate: Date?
    var timesUsed: Int = 0
    var firstUnlockedDate: Date?
}

public struct IconUnlockProgress {
    public let current: Int
    public let required: Int
    public let percentage: Double
    
    public var isComplete: Bool {
        return current >= required
    }
}

public struct IconWithProgress {
    public let icon: AppIconManager.AppIcon
    public let isUnlocked: Bool
    public let progress: IconUnlockProgress
}

public struct IconChangeAnimation {
    public let from: AppIconManager.AppIcon
    public let to: AppIconManager.AppIcon
    public let startTime: Date = Date()
}

// MARK: - Achievement Tracker

public class AchievementTracker {
    private let userDefaults = UserDefaults.standard
    
    public func isAchievementUnlocked(_ name: String) -> Bool {
        return userDefaults.bool(forKey: "achievement_\(name)")
    }
    
    public func unlockAchievement(_ name: String) {
        userDefaults.set(true, forKey: "achievement_\(name)")
        
        NotificationCenter.default.post(
            name: .achievementUnlocked,
            object: nil,
            userInfo: ["achievement": name]
        )
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let iconUnlocked = Notification.Name("iconUnlocked")
    static let achievementUnlocked = Notification.Name("achievementUnlocked")
}