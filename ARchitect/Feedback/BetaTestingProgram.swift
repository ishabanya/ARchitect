import Foundation
import UIKit
import SwiftUI
import Combine
import TestFlight

// MARK: - Beta Testing Program
@MainActor
public class BetaTestingProgram: ObservableObject {
    public static let shared = BetaTestingProgram()
    
    @Published public var betaStatus: BetaStatus = .notEnrolled
    @Published public var currentBetaPrograms: [BetaProgram] = []
    @Published public var availableBetaPrograms: [BetaProgram] = []
    @Published public var betaFeedback: [BetaFeedback] = []
    @Published public var betaBuilds: [BetaBuild] = []
    @Published public var isCheckingForUpdates = false
    @Published public var hasNewBuild = false
    @Published public var userProfile: BetaTesterProfile?
    
    private let storageManager = BetaTestingStorageManager()
    private let networkManager = BetaTestingNetworkManager()
    private let analyticsManager = AnalyticsManager.shared
    private let hapticManager = HapticFeedbackManager.shared
    private let notificationManager = BetaNotificationManager()
    
    private var cancellables = Set<AnyCancellable>()
    private let userId = createBetaUserId()
    
    private init() {
        loadBetaData()
        setupNotifications()
        checkBetaStatus()
        schedulePeriodicUpdates()
    }
    
    // MARK: - Public Methods
    
    public func enrollInBetaProgram(_ program: BetaProgram) async throws {
        guard betaStatus != .enrolled else { return }
        
        do {
            let enrollment = BetaEnrollment(
                userId: userId,
                programId: program.id,
                enrolledAt: Date(),
                deviceInfo: DeviceInfo.current(),
                preferences: BetaTesterPreferences()
            )
            
            try await networkManager.enrollInProgram(enrollment)
            
            // Update local state
            currentBetaPrograms.append(program)
            betaStatus = .enrolled
            
            // Create tester profile if needed
            if userProfile == nil {
                userProfile = BetaTesterProfile(
                    userId: userId,
                    enrollmentDate: Date(),
                    programs: [program.id],
                    feedbackCount: 0,
                    crashReportsSubmitted: 0,
                    rating: 0.0,
                    badges: [],
                    preferences: BetaTesterPreferences()
                )
            }
            
            // Store locally
            storageManager.saveBetaStatus(.enrolled)
            storageManager.savePrograms(currentBetaPrograms)
            if let profile = userProfile {
                storageManager.saveProfile(profile)
            }
            
            // Track enrollment
            analyticsManager.trackCustomEvent(
                name: "beta_program_enrolled",
                parameters: [
                    "program_id": program.id.uuidString,
                    "program_name": program.name,
                    "program_type": program.type.rawValue
                ],
                severity: .medium
            )
            
            // Setup beta-specific notifications
            await notificationManager.setupBetaNotifications()
            
            hapticManager.operationSuccess()
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "enroll_beta_program",
                "program_id": program.id.uuidString
            ])
            
            hapticManager.operationError()
            throw error
        }
    }
    
    public func leaveBetaProgram(_ programId: UUID) async throws {
        guard let programIndex = currentBetaPrograms.firstIndex(where: { $0.id == programId }) else { return }
        
        do {
            try await networkManager.leaveBetaProgram(userId: userId, programId: programId)
            
            let program = currentBetaPrograms.remove(at: programIndex)
            
            if currentBetaPrograms.isEmpty {
                betaStatus = .notEnrolled
                userProfile = nil
            }
            
            // Update storage
            storageManager.saveBetaStatus(betaStatus)
            storageManager.savePrograms(currentBetaPrograms)
            
            analyticsManager.trackCustomEvent(
                name: "beta_program_left",
                parameters: [
                    "program_id": programId.uuidString,
                    "program_name": program.name
                ]
            )
            
            hapticManager.impact(.medium)
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "leave_beta_program",
                "program_id": programId.uuidString
            ])
            
            hapticManager.operationError()
            throw error
        }
    }
    
    public func submitBetaFeedback(_ feedback: BetaFeedback) async throws -> String {
        do {
            let submissionId = try await networkManager.submitFeedback(feedback)
            
            // Update local state
            betaFeedback.insert(feedback, at: 0)
            
            // Update profile
            if var profile = userProfile {
                profile.feedbackCount += 1
                profile.lastActiveDate = Date()
                userProfile = profile
                storageManager.saveProfile(profile)
            }
            
            // Store feedback
            storageManager.saveFeedback(feedback)
            
            // Track submission
            analyticsManager.trackCustomEvent(
                name: "beta_feedback_submitted",
                parameters: [
                    "feedback_type": feedback.type.rawValue,
                    "build_number": feedback.buildNumber,
                    "has_screenshot": !feedback.screenshotPaths.isEmpty,
                    "submission_id": submissionId
                ],
                severity: .medium
            )
            
            // Check for achievements
            checkForAchievements()
            
            hapticManager.operationSuccess()
            
            return submissionId
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "submit_beta_feedback",
                "feedback_type": feedback.type.rawValue
            ])
            
            hapticManager.operationError()
            throw error
        }
    }
    
    public func checkForNewBuilds() async {
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        
        do {
            let availableBuilds = try await networkManager.getAvailableBuilds(userId: userId)
            
            let newBuilds = availableBuilds.filter { build in
                !betaBuilds.contains { $0.id == build.id }
            }
            
            if !newBuilds.isEmpty {
                betaBuilds.append(contentsOf: newBuilds)
                hasNewBuild = true
                
                // Send notification for new builds
                await notificationManager.notifyNewBuild(newBuilds.first!)
                
                analyticsManager.trackCustomEvent(
                    name: "new_beta_build_available",
                    parameters: [
                        "build_count": newBuilds.count,
                        "latest_build": newBuilds.first?.buildNumber ?? "unknown"
                    ]
                )
            }
            
            storageManager.saveBuilds(betaBuilds)
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "check_new_builds"
            ])
        }
    }
    
    public func installBuild(_ build: BetaBuild) async {
        // This would integrate with TestFlight or internal distribution
        analyticsManager.trackCustomEvent(
            name: "beta_build_install_initiated",
            parameters: [
                "build_id": build.id.uuidString,
                "build_number": build.buildNumber,
                "version": build.version
            ]
        )
        
        // Open TestFlight or trigger download
        if let testFlightURL = URL(string: "itms-beta://beta.itunes.apple.com/v1/app/\(build.appId)") {
            await MainActor.run {
                UIApplication.shared.open(testFlightURL)
            }
        }
        
        hapticManager.impact(.medium)
    }
    
    public func reportBug(in build: BetaBuild, description: String, steps: [String]) async throws {
        let bugReport = BetaBugReport(
            buildId: build.id,
            buildNumber: build.buildNumber,
            title: "Bug Report - Build \(build.buildNumber)",
            description: description,
            stepsToReproduce: steps,
            deviceInfo: DeviceInfo.current(),
            reportedBy: userId,
            severity: .medium,
            category: .functionality
        )
        
        try await networkManager.submitBugReport(bugReport)
        
        // Update profile
        if var profile = userProfile {
            profile.crashReportsSubmitted += 1
            userProfile = profile
            storageManager.saveProfile(profile)
        }
        
        analyticsManager.trackCustomEvent(
            name: "beta_bug_reported",
            parameters: [
                "build_id": build.id.uuidString,
                "build_number": build.buildNumber,
                "severity": bugReport.severity.rawValue
            ]
        )
        
        hapticManager.operationSuccess()
    }
    
    public func rateBuild(_ build: BetaBuild, rating: Int, feedback: String?) async throws {
        let buildRating = BuildRating(
            buildId: build.id,
            userId: userId,
            rating: rating,
            feedback: feedback,
            timestamp: Date()
        )
        
        try await networkManager.submitBuildRating(buildRating)
        
        analyticsManager.trackCustomEvent(
            name: "beta_build_rated",
            parameters: [
                "build_id": build.id.uuidString,
                "rating": rating,
                "has_feedback": feedback != nil
            ]
        )
        
        hapticManager.selectionChanged()
    }
    
    public func updatePreferences(_ preferences: BetaTesterPreferences) async {
        guard var profile = userProfile else { return }
        
        profile.preferences = preferences
        userProfile = profile
        
        storageManager.saveProfile(profile)
        
        do {
            try await networkManager.updatePreferences(userId: userId, preferences: preferences)
            
            analyticsManager.trackCustomEvent(
                name: "beta_preferences_updated",
                parameters: [
                    "notification_frequency": preferences.notificationFrequency.rawValue,
                    "auto_download": preferences.autoDownloadBuilds,
                    "feedback_reminders": preferences.feedbackReminders
                ]
            )
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "update_beta_preferences"
            ])
        }
    }
    
    public func getBetaStatistics() -> BetaStatistics {
        let profile = userProfile ?? BetaTesterProfile(userId: userId, enrollmentDate: Date(), programs: [], feedbackCount: 0, crashReportsSubmitted: 0, rating: 0.0, badges: [], preferences: BetaTesterPreferences())
        
        return BetaStatistics(
            enrollmentDate: profile.enrollmentDate,
            totalFeedback: profile.feedbackCount,
            totalBugReports: profile.crashReportsSubmitted,
            programsJoined: profile.programs.count,
            buildsInstalled: betaBuilds.count,
            achievementsUnlocked: profile.badges.count,
            overallRating: profile.rating,
            lastActiveDate: profile.lastActiveDate
        )
    }
    
    public func exportBetaData() -> Data? {
        let exportData = BetaDataExport(
            profile: userProfile,
            programs: currentBetaPrograms,
            feedback: betaFeedback,
            builds: betaBuilds,
            statistics: getBetaStatistics(),
            exportDate: Date()
        )
        
        return try? JSONEncoder().encode(exportData)
    }
    
    // MARK: - Private Methods
    
    private func loadBetaData() {
        betaStatus = storageManager.loadBetaStatus()
        currentBetaPrograms = storageManager.loadPrograms()
        betaFeedback = storageManager.loadFeedback()
        betaBuilds = storageManager.loadBuilds()
        userProfile = storageManager.loadProfile()
        
        if betaStatus == .enrolled {
            Task {
                await loadAvailablePrograms()
            }
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task {
                    await self?.checkForNewBuilds()
                }
            }
            .store(in: &cancellables)
    }
    
    private func checkBetaStatus() {
        // Check if running a beta build
        if let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
           buildNumber.contains("beta") || buildNumber.contains("b") {
            if betaStatus == .notEnrolled {
                betaStatus = .eligible
            }
        }
    }
    
    private func schedulePeriodicUpdates() {
        // Check for new builds every hour
        Timer.scheduledTimer(withTimeInterval: 3600.0, repeats: true) { [weak self] _ in
            Task {
                await self?.checkForNewBuilds()
            }
        }
        
        // Load available programs daily
        Timer.scheduledTimer(withTimeInterval: 86400.0, repeats: true) { [weak self] _ in
            Task {
                await self?.loadAvailablePrograms()
            }
        }
    }
    
    private func loadAvailablePrograms() async {
        do {
            availableBetaPrograms = try await networkManager.getAvailablePrograms()
            storageManager.saveAvailablePrograms(availableBetaPrograms)
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "load_available_programs"
            ])
        }
    }
    
    private func checkForAchievements() {
        guard var profile = userProfile else { return }
        
        let achievements = BetaAchievementChecker.checkAchievements(profile: profile, feedback: betaFeedback)
        let newAchievements = achievements.filter { !profile.badges.contains($0) }
        
        if !newAchievements.isEmpty {
            profile.badges.append(contentsOf: newAchievements)
            userProfile = profile
            storageManager.saveProfile(profile)
            
            // Notify about new achievements
            for achievement in newAchievements {
                notificationManager.notifyAchievement(achievement)
            }
            
            analyticsManager.trackCustomEvent(
                name: "beta_achievements_unlocked",
                parameters: [
                    "new_achievements": newAchievements.map { $0.rawValue },
                    "total_achievements": profile.badges.count
                ]
            )
        }
    }
    
    private static func createBetaUserId() -> String {
        if let existingId = UserDefaults.standard.string(forKey: "beta_tester_user_id") {
            return existingId
        }
        
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "beta_tester_user_id")
        return newId
    }
}

// MARK: - Beta Models
public struct BetaProgram: Identifiable, Codable {
    public let id: UUID
    public let name: String
    public let description: String
    public let type: ProgramType
    public let status: ProgramStatus
    public let startDate: Date
    public let endDate: Date?
    public let maxParticipants: Int?
    public let currentParticipants: Int
    public let requirements: [String]
    public let features: [String]
    public let targetAudience: String
    public let contactEmail: String
    
    public enum ProgramType: String, CaseIterable, Codable {
        case closedBeta = "closed_beta"
        case openBeta = "open_beta"
        case alphaTest = "alpha_test"
        case featurePreview = "feature_preview"
        case performanceTesting = "performance_testing"
        
        var title: String {
            switch self {
            case .closedBeta: return "Closed Beta"
            case .openBeta: return "Open Beta"
            case .alphaTest: return "Alpha Test"
            case .featurePreview: return "Feature Preview"
            case .performanceTesting: return "Performance Testing"
            }
        }
    }
    
    public enum ProgramStatus: String, Codable {
        case upcoming = "upcoming"
        case active = "active"
        case full = "full"
        case ended = "ended"
        case suspended = "suspended"
    }
}

public struct BetaFeedback: Identifiable, Codable {
    public let id: UUID
    public let type: FeedbackType
    public let title: String
    public let description: String
    public let buildNumber: String
    public let version: String
    public let feature: String?
    public let severity: FeedbackSeverity
    public let category: FeedbackCategory
    public let screenshotPaths: [String]
    public let logPaths: [String]
    public let deviceInfo: DeviceInfo
    public let timestamp: Date
    public let userId: String
    public let isResolved: Bool
    public let developerResponse: String?
    
    public enum FeedbackType: String, CaseIterable, Codable {
        case bug = "bug"
        case enhancement = "enhancement"
        case usability = "usability"
        case performance = "performance"
        case crash = "crash"
        case general = "general"
        
        var title: String {
            switch self {
            case .bug: return "Bug Report"
            case .enhancement: return "Enhancement"
            case .usability: return "Usability Issue"
            case .performance: return "Performance Issue"
            case .crash: return "Crash Report"
            case .general: return "General Feedback"
            }
        }
    }
    
    public enum FeedbackSeverity: String, CaseIterable, Codable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
        
        var color: Color {
            switch self {
            case .low: return .green
            case .medium: return .yellow
            case .high: return .orange
            case .critical: return .red
            }
        }
    }
    
    public enum FeedbackCategory: String, CaseIterable, Codable {
        case functionality = "functionality"
        case ui = "ui"
        case performance = "performance"
        case integration = "integration"
        case security = "security"
        case accessibility = "accessibility"
        case documentation = "documentation"
        case other = "other"
    }
}

public struct BetaBuild: Identifiable, Codable {
    public let id: UUID
    public let buildNumber: String
    public let version: String
    public let releaseDate: Date
    public let changes: [String]
    public let knownIssues: [String]
    public let testingFocus: [String]
    public let expirationDate: Date?
    public let downloadURL: URL?
    public let installInstructions: String
    public let minimumOSVersion: String
    public let buildType: BuildType
    public let status: BuildStatus
    public let appId: String
    
    public enum BuildType: String, Codable {
        case alpha = "alpha"
        case beta = "beta"
        case releaseCandidate = "rc"
        case hotfix = "hotfix"
    }
    
    public enum BuildStatus: String, Codable {
        case available = "available"
        case installing = "installing"
        case installed = "installed"
        case expired = "expired"
        case withdrawn = "withdrawn"
    }
}

public struct BetaTesterProfile: Identifiable, Codable {
    public let id: UUID
    public let userId: String
    public let enrollmentDate: Date
    public var programs: [UUID]
    public var feedbackCount: Int
    public var crashReportsSubmitted: Int
    public var rating: Double
    public var badges: [BetaAchievement]
    public var preferences: BetaTesterPreferences
    public var lastActiveDate: Date?
    
    public init(userId: String, enrollmentDate: Date, programs: [UUID], feedbackCount: Int, crashReportsSubmitted: Int, rating: Double, badges: [BetaAchievement], preferences: BetaTesterPreferences) {
        self.id = UUID()
        self.userId = userId
        self.enrollmentDate = enrollmentDate
        self.programs = programs
        self.feedbackCount = feedbackCount
        self.crashReportsSubmitted = crashReportsSubmitted
        self.rating = rating
        self.badges = badges
        self.preferences = preferences
        self.lastActiveDate = nil
    }
}

public struct BetaTesterPreferences: Codable {
    public var notificationFrequency: NotificationFrequency
    public var autoDownloadBuilds: Bool
    public var feedbackReminders: Bool
    public var crashReporting: Bool
    public var analyticsSharing: Bool
    public var preferredTestingAreas: [String]
    
    public init() {
        self.notificationFrequency = .weekly
        self.autoDownloadBuilds = false
        self.feedbackReminders = true
        self.crashReporting = true
        self.analyticsSharing = true
        self.preferredTestingAreas = []
    }
    
    public enum NotificationFrequency: String, CaseIterable, Codable {
        case never = "never"
        case weekly = "weekly"
        case daily = "daily"
        case immediate = "immediate"
        
        var title: String {
            switch self {
            case .never: return "Never"
            case .weekly: return "Weekly"
            case .daily: return "Daily"
            case .immediate: return "Immediate"
            }
        }
    }
}

public struct BetaEnrollment: Codable {
    public let userId: String
    public let programId: UUID
    public let enrolledAt: Date
    public let deviceInfo: DeviceInfo
    public let preferences: BetaTesterPreferences
}

public struct BetaBugReport: Identifiable, Codable {
    public let id: UUID
    public let buildId: UUID
    public let buildNumber: String
    public let title: String
    public let description: String
    public let stepsToReproduce: [String]
    public let expectedBehavior: String?
    public let actualBehavior: String?
    public let deviceInfo: DeviceInfo
    public let timestamp: Date
    public let reportedBy: String
    public let severity: BetaFeedback.FeedbackSeverity
    public let category: BetaFeedback.FeedbackCategory
    public let attachments: [String]
    
    public init(buildId: UUID, buildNumber: String, title: String, description: String, stepsToReproduce: [String], deviceInfo: DeviceInfo, reportedBy: String, severity: BetaFeedback.FeedbackSeverity, category: BetaFeedback.FeedbackCategory) {
        self.id = UUID()
        self.buildId = buildId
        self.buildNumber = buildNumber
        self.title = title
        self.description = description
        self.stepsToReproduce = stepsToReproduce
        self.expectedBehavior = nil
        self.actualBehavior = nil
        self.deviceInfo = deviceInfo
        self.timestamp = Date()
        self.reportedBy = reportedBy
        self.severity = severity
        self.category = category
        self.attachments = []
    }
}

public struct BuildRating: Codable {
    public let buildId: UUID
    public let userId: String
    public let rating: Int
    public let feedback: String?
    public let timestamp: Date
}

public struct BetaStatistics {
    public let enrollmentDate: Date
    public let totalFeedback: Int
    public let totalBugReports: Int
    public let programsJoined: Int
    public let buildsInstalled: Int
    public let achievementsUnlocked: Int
    public let overallRating: Double
    public let lastActiveDate: Date?
}

public struct BetaDataExport: Codable {
    public let profile: BetaTesterProfile?
    public let programs: [BetaProgram]
    public let feedback: [BetaFeedback]
    public let builds: [BetaBuild]
    public let statistics: BetaStatistics
    public let exportDate: Date
}

// MARK: - Enums
public enum BetaStatus: String, CaseIterable {
    case notEnrolled = "not_enrolled"
    case eligible = "eligible"
    case enrolled = "enrolled"
    case suspended = "suspended"
    
    var title: String {
        switch self {
        case .notEnrolled: return "Not Enrolled"
        case .eligible: return "Eligible"
        case .enrolled: return "Enrolled"
        case .suspended: return "Suspended"
        }
    }
}

public enum BetaAchievement: String, CaseIterable, Codable {
    case firstFeedback = "first_feedback"
    case feedbackMaster = "feedback_master"
    case bugHunter = "bug_hunter"
    case earlyAdopter = "early_adopter"
    case loyalTester = "loyal_tester"
    case crashReporter = "crash_reporter"
    case featureExplorer = "feature_explorer"
    case perfectRater = "perfect_rater"
    
    var title: String {
        switch self {
        case .firstFeedback: return "First Feedback"
        case .feedbackMaster: return "Feedback Master"
        case .bugHunter: return "Bug Hunter"
        case .earlyAdopter: return "Early Adopter"
        case .loyalTester: return "Loyal Tester"
        case .crashReporter: return "Crash Reporter"
        case .featureExplorer: return "Feature Explorer"
        case .perfectRater: return "Perfect Rater"
        }
    }
    
    var description: String {
        switch self {
        case .firstFeedback: return "Submitted your first feedback"
        case .feedbackMaster: return "Submitted 10+ feedback items"
        case .bugHunter: return "Found 5+ bugs"
        case .earlyAdopter: return "Joined beta program on day 1"
        case .loyalTester: return "Active beta tester for 3+ months"
        case .crashReporter: return "Reported 3+ crashes"
        case .featureExplorer: return "Tested all major features"
        case .perfectRater: return "Rated 5+ builds"
        }
    }
    
    var icon: String {
        switch self {
        case .firstFeedback: return "star.fill"
        case .feedbackMaster: return "crown.fill"
        case .bugHunter: return "ladybug.fill"
        case .earlyAdopter: return "bolt.fill"
        case .loyalTester: return "heart.fill"
        case .crashReporter: return "exclamationmark.triangle.fill"
        case .featureExplorer: return "map.fill"
        case .perfectRater: return "star.circle.fill"
        }
    }
}

// MARK: - Storage Manager
public class BetaTestingStorageManager {
    private let fileManager = FileManager.default
    private let betaDirectory: URL
    
    public init() {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        betaDirectory = documentsDirectory.appendingPathComponent("BetaTesting")
        
        try? fileManager.createDirectory(at: betaDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    public func saveBetaStatus(_ status: BetaStatus) {
        UserDefaults.standard.set(status.rawValue, forKey: "beta_status")
    }
    
    public func loadBetaStatus() -> BetaStatus {
        let statusString = UserDefaults.standard.string(forKey: "beta_status") ?? BetaStatus.notEnrolled.rawValue
        return BetaStatus(rawValue: statusString) ?? .notEnrolled
    }
    
    public func savePrograms(_ programs: [BetaProgram]) {
        let url = betaDirectory.appendingPathComponent("programs.json")
        
        do {
            let data = try JSONEncoder().encode(programs)
            try data.write(to: url)
        } catch {
            print("Failed to save beta programs: \(error)")
        }
    }
    
    public func loadPrograms() -> [BetaProgram] {
        let url = betaDirectory.appendingPathComponent("programs.json")
        
        guard let data = try? Data(contentsOf: url),
              let programs = try? JSONDecoder().decode([BetaProgram].self, from: data) else {
            return []
        }
        
        return programs
    }
    
    public func saveAvailablePrograms(_ programs: [BetaProgram]) {
        let url = betaDirectory.appendingPathComponent("available_programs.json")
        
        do {
            let data = try JSONEncoder().encode(programs)
            try data.write(to: url)
        } catch {
            print("Failed to save available beta programs: \(error)")
        }
    }
    
    public func saveFeedback(_ feedback: BetaFeedback) {
        let url = betaDirectory.appendingPathComponent("feedback_\(feedback.id.uuidString).json")
        
        do {
            let data = try JSONEncoder().encode(feedback)
            try data.write(to: url)
        } catch {
            print("Failed to save beta feedback: \(error)")
        }
    }
    
    public func loadFeedback() -> [BetaFeedback] {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: betaDirectory, includingPropertiesForKeys: nil)
            
            return fileURLs.compactMap { url in
                guard url.lastPathComponent.hasPrefix("feedback_"),
                      let data = try? Data(contentsOf: url),
                      let feedback = try? JSONDecoder().decode(BetaFeedback.self, from: data) else {
                    return nil
                }
                return feedback
            }.sorted { $0.timestamp > $1.timestamp }
        } catch {
            return []
        }
    }
    
    public func saveBuilds(_ builds: [BetaBuild]) {
        let url = betaDirectory.appendingPathComponent("builds.json")
        
        do {
            let data = try JSONEncoder().encode(builds)
            try data.write(to: url)
        } catch {
            print("Failed to save beta builds: \(error)")
        }
    }
    
    public func loadBuilds() -> [BetaBuild] {
        let url = betaDirectory.appendingPathComponent("builds.json")
        
        guard let data = try? Data(contentsOf: url),
              let builds = try? JSONDecoder().decode([BetaBuild].self, from: data) else {
            return []
        }
        
        return builds
    }
    
    public func saveProfile(_ profile: BetaTesterProfile) {
        let url = betaDirectory.appendingPathComponent("profile.json")
        
        do {
            let data = try JSONEncoder().encode(profile)
            try data.write(to: url)
        } catch {
            print("Failed to save beta profile: \(error)")
        }
    }
    
    public func loadProfile() -> BetaTesterProfile? {
        let url = betaDirectory.appendingPathComponent("profile.json")
        
        guard let data = try? Data(contentsOf: url),
              let profile = try? JSONDecoder().decode(BetaTesterProfile.self, from: data) else {
            return nil
        }
        
        return profile
    }
}

// MARK: - Network Manager
public class BetaTestingNetworkManager {
    private let baseURL = URL(string: "https://api.architect.com/beta")!
    
    public func enrollInProgram(_ enrollment: BetaEnrollment) async throws {
        // This would integrate with your backend API
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }
    
    public func leaveBetaProgram(userId: String, programId: UUID) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    public func getAvailablePrograms() async throws -> [BetaProgram] {
        // This would fetch from your backend API
        return []
    }
    
    public func submitFeedback(_ feedback: BetaFeedback) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return "BF-\(Int.random(in: 1000...9999))"
    }
    
    public func getAvailableBuilds(userId: String) async throws -> [BetaBuild] {
        // This would check TestFlight or internal distribution
        return []
    }
    
    public func submitBugReport(_ report: BetaBugReport) async throws {
        try await Task.sleep(nanoseconds: 750_000_000)
    }
    
    public func submitBuildRating(_ rating: BuildRating) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    public func updatePreferences(userId: String, preferences: BetaTesterPreferences) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }
}

// MARK: - Notification Manager
public class BetaNotificationManager {
    
    public func setupBetaNotifications() async {
        // Request notification permissions and setup categories
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                setupNotificationCategories()
            }
        } catch {
            print("Failed to request notification authorization: \(error)")
        }
    }
    
    public func notifyNewBuild(_ build: BetaBuild) async {
        let content = UNMutableNotificationContent()
        content.title = "New Beta Build Available"
        content.body = "Build \(build.buildNumber) is now available for testing"
        content.sound = .default
        content.badge = 1
        
        let request = UNNotificationRequest(
            identifier: "new_build_\(build.id.uuidString)",
            content: content,
            trigger: nil
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule new build notification: \(error)")
        }
    }
    
    public func notifyAchievement(_ achievement: BetaAchievement) {
        let content = UNMutableNotificationContent()
        content.title = "Achievement Unlocked!"
        content.body = "You earned: \(achievement.title)"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "achievement_\(achievement.rawValue)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule achievement notification: \(error)")
            }
        }
    }
    
    private func setupNotificationCategories() {
        let feedbackAction = UNNotificationAction(
            identifier: "FEEDBACK_ACTION",
            title: "Provide Feedback",
            options: [.foreground]
        )
        
        let installAction = UNNotificationAction(
            identifier: "INSTALL_ACTION",
            title: "Install Now",
            options: [.foreground]
        )
        
        let newBuildCategory = UNNotificationCategory(
            identifier: "NEW_BUILD",
            actions: [installAction, feedbackAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([newBuildCategory])
    }
}

// MARK: - Achievement Checker
public class BetaAchievementChecker {
    public static func checkAchievements(profile: BetaTesterProfile, feedback: [BetaFeedback]) -> [BetaAchievement] {
        var achievements: [BetaAchievement] = []
        
        // First Feedback
        if profile.feedbackCount >= 1 && !profile.badges.contains(.firstFeedback) {
            achievements.append(.firstFeedback)
        }
        
        // Feedback Master
        if profile.feedbackCount >= 10 && !profile.badges.contains(.feedbackMaster) {
            achievements.append(.feedbackMaster)
        }
        
        // Bug Hunter
        let bugReports = feedback.filter { $0.type == .bug }.count
        if bugReports >= 5 && !profile.badges.contains(.bugHunter) {
            achievements.append(.bugHunter)
        }
        
        // Crash Reporter
        if profile.crashReportsSubmitted >= 3 && !profile.badges.contains(.crashReporter) {
            achievements.append(.crashReporter)
        }
        
        // Loyal Tester
        let threeMonthsAgo = Date().addingTimeInterval(-90 * 24 * 3600)
        if profile.enrollmentDate <= threeMonthsAgo && !profile.badges.contains(.loyalTester) {
            achievements.append(.loyalTester)
        }
        
        return achievements
    }
}

// MARK: - Extensions
extension BetaStatistics: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enrollmentDate = try container.decode(Date.self, forKey: .enrollmentDate)
        totalFeedback = try container.decode(Int.self, forKey: .totalFeedback)
        totalBugReports = try container.decode(Int.self, forKey: .totalBugReports)
        programsJoined = try container.decode(Int.self, forKey: .programsJoined)
        buildsInstalled = try container.decode(Int.self, forKey: .buildsInstalled)
        achievementsUnlocked = try container.decode(Int.self, forKey: .achievementsUnlocked)
        overallRating = try container.decode(Double.self, forKey: .overallRating)
        lastActiveDate = try container.decodeIfPresent(Date.self, forKey: .lastActiveDate)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enrollmentDate, forKey: .enrollmentDate)
        try container.encode(totalFeedback, forKey: .totalFeedback)
        try container.encode(totalBugReports, forKey: .totalBugReports)
        try container.encode(programsJoined, forKey: .programsJoined)
        try container.encode(buildsInstalled, forKey: .buildsInstalled)
        try container.encode(achievementsUnlocked, forKey: .achievementsUnlocked)
        try container.encode(overallRating, forKey: .overallRating)
        try container.encodeIfPresent(lastActiveDate, forKey: .lastActiveDate)
    }
    
    private enum CodingKeys: String, CodingKey {
        case enrollmentDate, totalFeedback, totalBugReports, programsJoined
        case buildsInstalled, achievementsUnlocked, overallRating, lastActiveDate
    }
}