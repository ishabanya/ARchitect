import SwiftUI
import Foundation

class LaunchDayManager: ObservableObject {
    static let shared = LaunchDayManager()
    
    @Published var isLaunchWeek: Bool = false
    @Published var launchDayFeatures: [LaunchFeature] = []
    @Published var showLaunchCelebration: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private let launchDate = Calendar.current.date(from: DateComponents(year: 2024, month: 8, day: 15)) ?? Date()
    
    struct LaunchFeature: Identifiable, Codable {
        let id = UUID()
        let title: String
        let description: String
        let iconName: String
        let isUnlocked: Bool
        let unlockDate: Date?
        let featureType: FeatureType
        
        enum FeatureType: String, Codable, CaseIterable {
            case exclusiveContent = "exclusive_content"
            case premiumFeatures = "premium_features"
            case specialEffects = "special_effects"
            case bonusRewards = "bonus_rewards"
        }
    }
    
    private enum UserDefaultsKeys {
        static let hasSeenLaunchCelebration = "HasSeenLaunchCelebration"
        static let launchFeaturesUnlocked = "LaunchFeaturesUnlocked"
    }
    
    private init() {
        checkLaunchWeekStatus()
        setupLaunchFeatures()
        checkForLaunchCelebration()
    }
    
    private func checkLaunchWeekStatus() {
        let calendar = Calendar.current
        let now = Date()
        
        let weekAfterLaunch = calendar.date(byAdding: .day, value: 7, to: launchDate) ?? launchDate
        
        isLaunchWeek = now >= launchDate && now <= weekAfterLaunch
    }
    
    private func setupLaunchFeatures() {
        let calendar = Calendar.current
        
        launchDayFeatures = [
            LaunchFeature(
                title: "Launch Day Exclusive Furniture",
                description: "Limited-time premium furniture collection",
                iconName: "sofa.fill",
                isUnlocked: isLaunchWeek,
                unlockDate: launchDate,
                featureType: .exclusiveContent
            ),
            LaunchFeature(
                title: "Golden Hour AR Effects",
                description: "Special lighting effects for your AR scenes",
                iconName: "sun.max.fill",
                isUnlocked: isLaunchWeek,
                unlockDate: launchDate,
                featureType: .specialEffects
            ),
            LaunchFeature(
                title: "Double Referral Rewards",
                description: "Earn 2x rewards for each successful referral",
                iconName: "person.2.fill",
                isUnlocked: isLaunchWeek,
                unlockDate: calendar.date(byAdding: .day, value: 1, to: launchDate),
                featureType: .bonusRewards
            ),
            LaunchFeature(
                title: "Premium Templates Pack",
                description: "Pre-designed room layouts from top designers",
                iconName: "rectangle.3.group.fill",
                isUnlocked: isLaunchWeek,
                unlockDate: calendar.date(byAdding: .day, value: 2, to: launchDate),
                featureType: .premiumFeatures
            ),
            LaunchFeature(
                title: "AR Photo Studio",
                description: "Professional photo modes for your designs",
                iconName: "camera.fill",
                isUnlocked: isLaunchWeek,
                unlockDate: calendar.date(byAdding: .day, value: 3, to: launchDate),
                featureType: .specialEffects
            )
        ]
    }
    
    private func checkForLaunchCelebration() {
        let hasSeenCelebration = userDefaults.bool(forKey: UserDefaultsKeys.hasSeenLaunchCelebration)
        
        if isLaunchWeek && !hasSeenCelebration {
            showLaunchCelebration = true
        }
    }
    
    func markLaunchCelebrationSeen() {
        userDefaults.set(true, forKey: UserDefaultsKeys.hasSeenLaunchCelebration)
        showLaunchCelebration = false
        
        AnalyticsManager.shared.trackUserEngagement(.launchCelebrationViewed, parameters: [
            "launch_day": isFirstDay()
        ])
    }
    
    func unlockFeature(_ feature: LaunchFeature) {
        guard let index = launchDayFeatures.firstIndex(where: { $0.id == feature.id }) else { return }
        
        if isLaunchWeek {
            launchDayFeatures[index] = LaunchFeature(
                title: feature.title,
                description: feature.description,
                iconName: feature.iconName,
                isUnlocked: true,
                unlockDate: feature.unlockDate,
                featureType: feature.featureType
            )
            
            AnalyticsManager.shared.trackUserEngagement(.launchFeatureUnlocked, parameters: [
                "feature_type": feature.featureType.rawValue,
                "feature_title": feature.title
            ])
        }
    }
    
    func isFirstDay() -> Bool {
        let calendar = Calendar.current
        return calendar.isDate(Date(), inSameDayAs: launchDate)
    }
    
    func getDaysUntilLaunch() -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: launchDate)
        return max(components.day ?? 0, 0)
    }
    
    func getDaysRemainingInLaunchWeek() -> Int {
        guard isLaunchWeek else { return 0 }
        
        let calendar = Calendar.current
        let weekAfterLaunch = calendar.date(byAdding: .day, value: 7, to: launchDate) ?? launchDate
        let components = calendar.dateComponents([.day], from: Date(), to: weekAfterLaunch)
        return max(components.day ?? 0, 0)
    }
    
    func getUnlockedFeaturesCount() -> Int {
        return launchDayFeatures.filter { $0.isUnlocked }.count
    }
    
    func shouldShowLaunchBanner() -> Bool {
        return isLaunchWeek || getDaysUntilLaunch() <= 3
    }
}

extension LaunchDayManager {
    func getLaunchShareMessage() -> String {
        return """
        🚀 ARchitect just launched! 
        
        Experience the future of room design with AR technology. 
        
        Launch week exclusive features:
        ✨ Premium furniture collection
        🌅 Golden hour AR effects  
        📐 Professional measurement tools
        🎨 Designer templates
        
        Download now and transform your space!
        
        #ARchitect #LaunchWeek #AugmentedReality #HomeDesign
        """
    }
}