import Foundation
import Combine

// MARK: - Feature Flag Definition
struct FeatureFlag {
    let key: String
    let name: String
    let description: String
    let defaultValue: Bool
    let category: FeatureFlagCategory
    let rolloutStrategy: RolloutStrategy
    let dependencies: [String]
    let minimumAppVersion: String?
    let maximumAppVersion: String?
    let enabledForEnvironments: [AppEnvironment]
    
    enum FeatureFlagCategory {
        case ui
        case ar
        case ai
        case performance
        case analytics
        case experimental
        case bugFix
    }
    
    enum RolloutStrategy {
        case disabled
        case enabled
        case percentage(Double) // 0.0 to 1.0
        case userSegment([UserSegment])
        case deviceType([DeviceType])
        case gradualRollout(GradualRolloutConfig)
        
        enum UserSegment {
            case beta
            case premium
            case developer
            case newUser
            case returningUser
        }
        
        enum DeviceType {
            case iPhone
            case iPad
            case simulator
            case specificModel(String)
        }
        
        struct GradualRolloutConfig {
            let startDate: Date
            let endDate: Date
            let initialPercentage: Double
            let finalPercentage: Double
        }
    }
}

// MARK: - Feature Flag Manager
class FeatureFlagManager: ObservableObject {
    static let shared = FeatureFlagManager()
    
    @Published private(set) var flags: [String: Bool] = [:]
    @Published private(set) var lastUpdateTime: Date?
    
    private let userDefaults = UserDefaults.standard
    private let secureStorage = SecureConfigurationStorage.shared
    private let errorManager = ErrorManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private let flagUpdateInterval: TimeInterval = 300 // 5 minutes
    private var updateTimer: Timer?
    
    private init() {
        loadLocalFlags()
        startPeriodicUpdates()
        setupFeatureFlags()
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func isEnabled(_ flag: FeatureFlagKey) -> Bool {
        return flags[flag.rawValue] ?? flag.defaultValue
    }
    
    func isEnabled(_ flagKey: String) -> Bool {
        guard let flag = FeatureFlagKey(rawValue: flagKey) else {
            return false
        }
        return isEnabled(flag)
    }
    
    func enableFlag(_ flag: FeatureFlagKey, temporarily: Bool = false) {
        updateFlag(flag, enabled: true, temporarily: temporarily)
    }
    
    func disableFlag(_ flag: FeatureFlagKey, temporarily: Bool = false) {
        updateFlag(flag, enabled: false, temporarily: temporarily)
    }
    
    func resetFlag(_ flag: FeatureFlagKey) {
        flags[flag.rawValue] = flag.defaultValue
        userDefaults.removeObject(forKey: "ff_\(flag.rawValue)")
        saveFlags()
    }
    
    func resetAllFlags() {
        for flag in FeatureFlagKey.allCases {
            resetFlag(flag)
        }
    }
    
    func refreshFlags() async {
        await fetchRemoteFlags()
    }
    
    func getFlagInfo(_ flag: FeatureFlagKey) -> FeatureFlag? {
        return allFeatureFlags[flag.rawValue]
    }
    
    // MARK: - Private Methods
    
    private func updateFlag(_ flag: FeatureFlagKey, enabled: Bool, temporarily: Bool) {
        flags[flag.rawValue] = enabled
        
        if !temporarily {
            userDefaults.set(enabled, forKey: "ff_\(flag.rawValue)")
        }
        
        saveFlags()
    }
    
    private func loadLocalFlags() {
        for flag in FeatureFlagKey.allCases {
            if userDefaults.object(forKey: "ff_\(flag.rawValue)") != nil {
                flags[flag.rawValue] = userDefaults.bool(forKey: "ff_\(flag.rawValue)")
            } else {
                flags[flag.rawValue] = evaluateFlag(flag)
            }
        }
    }
    
    private func saveFlags() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    private func evaluateFlag(_ flag: FeatureFlagKey) -> Bool {
        guard let featureFlag = allFeatureFlags[flag.rawValue] else {
            return flag.defaultValue
        }
        
        // Check environment constraints
        let currentEnvironment = AppEnvironment.current
        if !featureFlag.enabledForEnvironments.isEmpty &&
           !featureFlag.enabledForEnvironments.contains(currentEnvironment) {
            return false
        }
        
        // Check app version constraints
        if let minVersion = featureFlag.minimumAppVersion,
           !isAppVersionGreaterOrEqual(minVersion) {
            return false
        }
        
        if let maxVersion = featureFlag.maximumAppVersion,
           isAppVersionGreaterOrEqual(maxVersion) {
            return false
        }
        
        // Check dependencies
        for dependency in featureFlag.dependencies {
            if let dependencyFlag = FeatureFlagKey(rawValue: dependency),
               !isEnabled(dependencyFlag) {
                return false
            }
        }
        
        // Evaluate rollout strategy
        return evaluateRolloutStrategy(featureFlag.rolloutStrategy)
    }
    
    private func evaluateRolloutStrategy(_ strategy: FeatureFlag.RolloutStrategy) -> Bool {
        switch strategy {
        case .disabled:
            return false
        case .enabled:
            return true
        case .percentage(let percentage):
            return evaluatePercentageRollout(percentage)
        case .userSegment(let segments):
            return evaluateUserSegment(segments)
        case .deviceType(let types):
            return evaluateDeviceType(types)
        case .gradualRollout(let config):
            return evaluateGradualRollout(config)
        }
    }
    
    private func evaluatePercentageRollout(_ percentage: Double) -> Bool {
        let userHash = getUserHash()
        let threshold = UInt32(percentage * Double(UInt32.max))
        return userHash < threshold
    }
    
    private func evaluateUserSegment(_ segments: [FeatureFlag.RolloutStrategy.UserSegment]) -> Bool {
        for segment in segments {
            switch segment {
            case .beta:
                return isBetaUser()
            case .premium:
                return isPremiumUser()
            case .developer:
                return isDeveloperUser()
            case .newUser:
                return isNewUser()
            case .returningUser:
                return isReturningUser()
            }
        }
        return false
    }
    
    private func evaluateDeviceType(_ types: [FeatureFlag.RolloutStrategy.DeviceType]) -> Bool {
        for type in types {
            switch type {
            case .iPhone:
                return UIDevice.current.userInterfaceIdiom == .phone
            case .iPad:
                return UIDevice.current.userInterfaceIdiom == .pad
            case .simulator:
                return TARGET_OS_SIMULATOR != 0
            case .specificModel(let model):
                return UIDevice.current.model.contains(model)
            }
        }
        return false
    }
    
    private func evaluateGradualRollout(_ config: FeatureFlag.RolloutStrategy.GradualRolloutConfig) -> Bool {
        let now = Date()
        
        guard now >= config.startDate && now <= config.endDate else {
            return now > config.endDate ? config.finalPercentage == 1.0 : false
        }
        
        let totalDuration = config.endDate.timeIntervalSince(config.startDate)
        let elapsed = now.timeIntervalSince(config.startDate)
        let progress = elapsed / totalDuration
        
        let currentPercentage = config.initialPercentage + 
            (config.finalPercentage - config.initialPercentage) * progress
        
        return evaluatePercentageRollout(currentPercentage)
    }
    
    private func startPeriodicUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: flagUpdateInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchRemoteFlags()
            }
        }
    }
    
    private func fetchRemoteFlags() async {
        // This would typically fetch from a remote configuration service
        // For now, we'll simulate with local evaluation
        
        do {
            // Simulate network delay
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            var updatedFlags: [String: Bool] = [:]
            
            for flag in FeatureFlagKey.allCases {
                updatedFlags[flag.rawValue] = evaluateFlag(flag)
            }
            
            await MainActor.run {
                self.flags = updatedFlags
                self.lastUpdateTime = Date()
                self.saveFlags()
            }
            
        } catch {
            errorManager.reportError(NetworkError.serverError(500))
        }
    }
    
    // MARK: - User Segment Evaluation
    
    private func getUserHash() -> UInt32 {
        let userID = UIDevice.current.identifierForVendor?.uuidString ?? "anonymous"
        return userID.hash.magnitude
    }
    
    private func isBetaUser() -> Bool {
        return AppEnvironment.current != .production
    }
    
    private func isPremiumUser() -> Bool {
        // Check premium status from user defaults or secure storage
        return userDefaults.bool(forKey: "user_is_premium")
    }
    
    private func isDeveloperUser() -> Bool {
        return AppEnvironment.current == .development
    }
    
    private func isNewUser() -> Bool {
        let installDate = userDefaults.object(forKey: "app_install_date") as? Date ?? Date()
        let daysSinceInstall = Date().timeIntervalSince(installDate) / (24 * 3600)
        return daysSinceInstall <= 7
    }
    
    private func isReturningUser() -> Bool {
        let lastLaunchDate = userDefaults.object(forKey: "last_launch_date") as? Date
        let isReturning = lastLaunchDate != nil
        userDefaults.set(Date(), forKey: "last_launch_date")
        return isReturning
    }
    
    private func isAppVersionGreaterOrEqual(_ version: String) -> Bool {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return currentVersion.compare(version, options: .numeric) != .orderedAscending
    }
    
    // MARK: - Feature Flag Definitions
    
    private func setupFeatureFlags() {
        // Initialize flags with their evaluated values
        for flag in FeatureFlagKey.allCases {
            if flags[flag.rawValue] == nil {
                flags[flag.rawValue] = evaluateFlag(flag)
            }
        }
    }
}

// MARK: - Feature Flag Keys
enum FeatureFlagKey: String, CaseIterable {
    // UI Features
    case newOnboardingFlow = "new_onboarding_flow"
    case darkModeSupport = "dark_mode_support"
    case improvedErrorUI = "improved_error_ui"
    
    // AR Features
    case advancedMeshGeneration = "advanced_mesh_generation"
    case peopleOcclusion = "people_occlusion"
    case multiRoomScanning = "multi_room_scanning"
    case realTimeCollaboration = "realtime_collaboration"
    
    // AI Features
    case aiLayoutSuggestions = "ai_layout_suggestions"
    case smartObjectDetection = "smart_object_detection"
    case voiceCommands = "voice_commands"
    
    // Performance Features
    case improvedRendering = "improved_rendering"
    case backgroundProcessing = "background_processing"
    case thermalManagement = "thermal_management"
    
    // Analytics Features
    case detailedAnalytics = "detailed_analytics"
    case crashReporting = "crash_reporting"
    case performanceMetrics = "performance_metrics"
    
    // Experimental Features
    case betaFeatures = "beta_features"
    case experimentalUI = "experimental_ui"
    
    var defaultValue: Bool {
        switch self {
        case .newOnboardingFlow, .darkModeSupport, .improvedErrorUI:
            return true
        case .advancedMeshGeneration, .peopleOcclusion:
            return false
        case .multiRoomScanning, .realTimeCollaboration:
            return false
        case .aiLayoutSuggestions, .smartObjectDetection:
            return false
        case .voiceCommands:
            return false
        case .improvedRendering:
            return true
        case .backgroundProcessing:
            return false
        case .thermalManagement:
            return true
        case .detailedAnalytics, .crashReporting:
            return true
        case .performanceMetrics:
            return AppEnvironment.current != .production
        case .betaFeatures, .experimentalUI:
            return AppEnvironment.current == .development
        }
    }
}

// MARK: - Feature Flag Definitions Dictionary
private let allFeatureFlags: [String: FeatureFlag] = [
    FeatureFlagKey.newOnboardingFlow.rawValue: FeatureFlag(
        key: FeatureFlagKey.newOnboardingFlow.rawValue,
        name: "New Onboarding Flow",
        description: "Enhanced user onboarding experience with interactive tutorials",
        defaultValue: true,
        category: .ui,
        rolloutStrategy: .enabled,
        dependencies: [],
        minimumAppVersion: "1.0.0",
        maximumAppVersion: nil,
        enabledForEnvironments: [.staging, .production]
    ),
    
    FeatureFlagKey.advancedMeshGeneration.rawValue: FeatureFlag(
        key: FeatureFlagKey.advancedMeshGeneration.rawValue,
        name: "Advanced Mesh Generation",
        description: "High-quality 3D mesh generation for better AR experiences",
        defaultValue: false,
        category: .ar,
        rolloutStrategy: .percentage(0.1),
        dependencies: [],
        minimumAppVersion: "1.1.0",
        maximumAppVersion: nil,
        enabledForEnvironments: [.development, .staging]
    ),
    
    FeatureFlagKey.aiLayoutSuggestions.rawValue: FeatureFlag(
        key: FeatureFlagKey.aiLayoutSuggestions.rawValue,
        name: "AI Layout Suggestions",
        description: "AI-powered furniture layout recommendations",
        defaultValue: false,
        category: .ai,
        rolloutStrategy: .gradualRollout(
            FeatureFlag.RolloutStrategy.GradualRolloutConfig(
                startDate: Date().addingTimeInterval(-7 * 24 * 3600), // 1 week ago
                endDate: Date().addingTimeInterval(30 * 24 * 3600), // 30 days from now
                initialPercentage: 0.05,
                finalPercentage: 0.5
            )
        ),
        dependencies: ["smart_object_detection"],
        minimumAppVersion: "1.2.0",
        maximumAppVersion: nil,
        enabledForEnvironments: [.staging, .production]
    ),
    
    FeatureFlagKey.realTimeCollaboration.rawValue: FeatureFlag(
        key: FeatureFlagKey.realTimeCollaboration.rawValue,
        name: "Real-time Collaboration",
        description: "Share AR sessions with multiple users in real-time",
        defaultValue: false,
        category: .ar,
        rolloutStrategy: .userSegment([.premium, .beta]),
        dependencies: [],
        minimumAppVersion: "1.3.0",
        maximumAppVersion: nil,
        enabledForEnvironments: [.development, .staging]
    ),
    
    FeatureFlagKey.betaFeatures.rawValue: FeatureFlag(
        key: FeatureFlagKey.betaFeatures.rawValue,
        name: "Beta Features",
        description: "Access to experimental and beta features",
        defaultValue: false,
        category: .experimental,
        rolloutStrategy: .userSegment([.beta, .developer]),
        dependencies: [],
        minimumAppVersion: nil,
        maximumAppVersion: nil,
        enabledForEnvironments: [.development, .staging]
    )
]

// MARK: - SwiftUI Integration
extension View {
    func featureFlag(_ flag: FeatureFlagKey) -> some View {
        self.modifier(FeatureFlagModifier(flag: flag))
    }
    
    func featureFlag(_ flag: FeatureFlagKey, fallback: @escaping () -> some View) -> some View {
        self.modifier(FeatureFlagModifier(flag: flag, fallback: AnyView(fallback())))
    }
}

struct FeatureFlagModifier: ViewModifier {
    let flag: FeatureFlagKey
    let fallback: AnyView?
    
    @ObservedObject private var featureFlags = FeatureFlagManager.shared
    
    init(flag: FeatureFlagKey, fallback: AnyView? = nil) {
        self.flag = flag
        self.fallback = fallback
    }
    
    func body(content: Content) -> some View {
        if featureFlags.isEnabled(flag) {
            content
        } else if let fallback = fallback {
            fallback
        } else {
            EmptyView()
        }
    }
}