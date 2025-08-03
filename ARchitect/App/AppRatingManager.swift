import SwiftUI
import StoreKit

class AppRatingManager: ObservableObject {
    static let shared = AppRatingManager()
    
    private let userDefaults = UserDefaults.standard
    private let minimumUseCount = 5
    private let minimumDaysSinceInstall = 3
    private let daysBetweenPrompts = 30
    
    private enum UserDefaultsKeys {
        static let usageCount = "AppRatingUsageCount"
        static let lastPromptDate = "AppRatingLastPromptDate"
        static let firstLaunchDate = "AppRatingFirstLaunchDate"
    }
    
    private init() {
        setFirstLaunchDateIfNeeded()
    }
    
    private func setFirstLaunchDateIfNeeded() {
        if userDefaults.object(forKey: UserDefaultsKeys.firstLaunchDate) == nil {
            userDefaults.set(Date(), forKey: UserDefaultsKeys.firstLaunchDate)
        }
    }
    
    func incrementUsageCount() {
        let currentCount = userDefaults.integer(forKey: UserDefaultsKeys.usageCount)
        userDefaults.set(currentCount + 1, forKey: UserDefaultsKeys.usageCount)
    }
    
    func requestReviewIfAppropriate() {
        guard shouldRequestReview() else { return }
        
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                SKStoreReviewController.requestReview(in: windowScene)
                self.userDefaults.set(Date(), forKey: UserDefaultsKeys.lastPromptDate)
                
                AnalyticsManager.shared.trackUserEngagement(.appRatingPrompted, parameters: [
                    "usage_count": self.userDefaults.integer(forKey: UserDefaultsKeys.usageCount)
                ])
            }
        }
    }
    
    private func shouldRequestReview() -> Bool {
        let usageCount = userDefaults.integer(forKey: UserDefaultsKeys.usageCount)
        
        guard usageCount >= minimumUseCount else { return false }
        
        guard let firstLaunchDate = userDefaults.object(forKey: UserDefaultsKeys.firstLaunchDate) as? Date else { return false }
        
        let daysSinceInstall = Calendar.current.dateComponents([.day], from: firstLaunchDate, to: Date()).day ?? 0
        guard daysSinceInstall >= minimumDaysSinceInstall else { return false }
        
        if let lastPromptDate = userDefaults.object(forKey: UserDefaultsKeys.lastPromptDate) as? Date {
            let daysSinceLastPrompt = Calendar.current.dateComponents([.day], from: lastPromptDate, to: Date()).day ?? 0
            guard daysSinceLastPrompt >= daysBetweenPrompts else { return false }
        }
        
        return true
    }
    
    func shouldShowCustomRatingPrompt() -> Bool {
        let usageCount = userDefaults.integer(forKey: UserDefaultsKeys.usageCount)
        return usageCount == minimumUseCount + 2
    }
}

extension AppRatingManager {
    enum RatingTrigger {
        case roomScanned
        case furniturePlaced
        case measurementTaken
        case sessionCompleted
        case featureDiscovered
    }
    
    func handleRatingTrigger(_ trigger: RatingTrigger) {
        incrementUsageCount()
        
        switch trigger {
        case .roomScanned, .sessionCompleted:
            requestReviewIfAppropriate()
        case .furniturePlaced, .measurementTaken:
            if userDefaults.integer(forKey: UserDefaultsKeys.usageCount) % 3 == 0 {
                requestReviewIfAppropriate()
            }
        case .featureDiscovered:
            break
        }
    }
}