import SwiftUI
import Foundation

class ReferralManager: ObservableObject {
    static let shared = ReferralManager()
    
    @Published var referralCode: String = ""
    @Published var referralCount: Int = 0
    @Published var availableRewards: [ReferralReward] = []
    
    private let userDefaults = UserDefaults.standard
    
    private enum UserDefaultsKeys {
        static let referralCode = "UserReferralCode"
        static let referralCount = "UserReferralCount"
        static let claimedRewards = "ClaimedReferralRewards"
    }
    
    struct ReferralReward: Identifiable, Codable {
        let id = UUID()
        let title: String
        let description: String
        let requiredReferrals: Int
        let rewardType: RewardType
        var isClaimed: Bool = false
        
        enum RewardType: String, Codable, CaseIterable {
            case premiumFeatures = "premium_features"
            case exclusiveContent = "exclusive_content"
            case earlyAccess = "early_access"
            case specialBadge = "special_badge"
        }
    }
    
    private init() {
        loadReferralData()
        setupDefaultRewards()
    }
    
    private func loadReferralData() {
        referralCode = userDefaults.string(forKey: UserDefaultsKeys.referralCode) ?? generateReferralCode()
        referralCount = userDefaults.integer(forKey: UserDefaultsKeys.referralCount)
        
        if let rewardData = userDefaults.data(forKey: UserDefaultsKeys.claimedRewards),
           let rewards = try? JSONDecoder().decode([ReferralReward].self, from: rewardData) {
            availableRewards = rewards
        }
    }
    
    private func setupDefaultRewards() {
        if availableRewards.isEmpty {
            availableRewards = [
                ReferralReward(
                    title: "First Referral",
                    description: "Unlock premium furniture collection",
                    requiredReferrals: 1,
                    rewardType: .premiumFeatures
                ),
                ReferralReward(
                    title: "Social Sharer",
                    description: "Exclusive AR filters and effects",
                    requiredReferrals: 3,
                    rewardType: .exclusiveContent
                ),
                ReferralReward(
                    title: "Community Builder",
                    description: "Early access to new features",
                    requiredReferrals: 5,
                    rewardType: .earlyAccess
                ),
                ReferralReward(
                    title: "ARchitect Ambassador",
                    description: "Special ambassador badge and recognition",
                    requiredReferrals: 10,
                    rewardType: .specialBadge
                )
            ]
            saveRewards()
        }
    }
    
    private func generateReferralCode() -> String {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let code = String((0..<6).map { _ in characters.randomElement()! })
        userDefaults.set(code, forKey: UserDefaultsKeys.referralCode)
        return code
    }
    
    func shareReferralCode() -> String {
        let appStoreURL = "https://apps.apple.com/app/architect-ar/id123456789"
        return """
        Check out ARchitect - the amazing AR room design app! 🏠✨
        
        Use my referral code: \(referralCode)
        
        Download: \(appStoreURL)?referral=\(referralCode)
        
        #ARchitect #AugmentedReality #HomeDesign
        """
    }
    
    func processReferral(code: String) -> Bool {
        guard code != referralCode else { return false }
        
        referralCount += 1
        userDefaults.set(referralCount, forKey: UserDefaultsKeys.referralCount)
        
        checkForNewRewards()
        
        AnalyticsManager.shared.trackUserEngagement(.referralSuccessful, parameters: [
            "referral_count": referralCount,
            "referrer_code": code
        ])
        
        return true
    }
    
    private func checkForNewRewards() {
        for index in availableRewards.indices {
            if !availableRewards[index].isClaimed &&
               referralCount >= availableRewards[index].requiredReferrals {
                availableRewards[index].isClaimed = true
                
                AnalyticsManager.shared.trackUserEngagement(.rewardEarned, parameters: [
                    "reward_type": availableRewards[index].rewardType.rawValue,
                    "referral_count": referralCount
                ])
                
                showRewardNotification(availableRewards[index])
            }
        }
        saveRewards()
    }
    
    private func showRewardNotification(_ reward: ReferralReward) {
        DispatchQueue.main.async {
            let notification = UNMutableNotificationContent()
            notification.title = "Reward Unlocked! 🎉"
            notification.body = "You've earned: \(reward.title)"
            notification.sound = .default
            
            let request = UNNotificationRequest(
                identifier: "referral_reward_\(reward.id)",
                content: notification,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    private func saveRewards() {
        if let encoded = try? JSONEncoder().encode(availableRewards) {
            userDefaults.set(encoded, forKey: UserDefaultsKeys.claimedRewards)
        }
    }
    
    func getShareableLink() -> URL? {
        let urlString = "https://architect-app.com/referral/\(referralCode)"
        return URL(string: urlString)
    }
    
    func getReferralProgress() -> [(reward: ReferralReward, progress: Double)] {
        return availableRewards.map { reward in
            let progress = min(Double(referralCount) / Double(reward.requiredReferrals), 1.0)
            return (reward: reward, progress: progress)
        }
    }
}

import UserNotifications