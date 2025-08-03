import Foundation
import UIKit
import SwiftUI
import Combine
import MessageUI
import CoreImage

// MARK: - Feedback Types
public enum FeedbackType: String, CaseIterable {
    case bugReport = "bug_report"
    case featureRequest = "feature_request"
    case improvement = "improvement"
    case usabilityIssue = "usability_issue"
    case performance = "performance"
    case crash = "crash"
    case other = "other"
    
    var title: String {
        switch self {
        case .bugReport: return "Bug Report"
        case .featureRequest: return "Feature Request"
        case .improvement: return "Improvement Suggestion"
        case .usabilityIssue: return "Usability Issue"
        case .performance: return "Performance Issue"
        case .crash: return "Crash Report"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .bugReport: return "ladybug"
        case .featureRequest: return "lightbulb"
        case .improvement: return "arrow.up.circle"
        case .usabilityIssue: return "person.fill.questionmark"
        case .performance: return "speedometer"
        case .crash: return "exclamationmark.triangle"
        case .other: return "questionmark.circle"
        }
    }
}

public enum FeedbackPriority: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
    
    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
    
    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Feedback Models
public struct FeedbackItem: Identifiable, Codable {
    public let id: UUID
    public let type: FeedbackType
    public let priority: FeedbackPriority
    public let title: String
    public let description: String
    public let steps: [String]
    public let expectedBehavior: String?
    public let actualBehavior: String?
    public let reproductionRate: String?
    public let deviceInfo: DeviceInfo
    public let appVersion: String
    public let buildNumber: String
    public let userEmail: String?
    public let allowFollowUp: Bool
    public let screenshotPaths: [String]
    public let screenRecordingPath: String?
    public let logsPaths: [String]
    public let crashReportId: String?
    public let timestamp: Date
    public let sessionId: String
    public let tags: [String]
    public let attachments: [FeedbackAttachment]
    public let severity: Int
    public let votes: Int
    public let status: FeedbackStatus
    public let assignee: String?
    public let estimatedEffort: String?
    public let targetVersion: String?
    
    public init(
        type: FeedbackType,
        priority: FeedbackPriority,
        title: String,
        description: String,
        steps: [String] = [],
        expectedBehavior: String? = nil,
        actualBehavior: String? = nil,
        reproductionRate: String? = nil,
        userEmail: String? = nil,
        allowFollowUp: Bool = true,
        screenshotPaths: [String] = [],
        screenRecordingPath: String? = nil,
        logsPaths: [String] = [],
        crashReportId: String? = nil,
        tags: [String] = [],
        attachments: [FeedbackAttachment] = [],
        severity: Int = 1
    ) {
        self.id = UUID()
        self.type = type
        self.priority = priority
        self.title = title
        self.description = description
        self.steps = steps
        self.expectedBehavior = expectedBehavior
        self.actualBehavior = actualBehavior
        self.reproductionRate = reproductionRate
        self.deviceInfo = DeviceInfo.current()
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        self.buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        self.userEmail = userEmail
        self.allowFollowUp = allowFollowUp
        self.screenshotPaths = screenshotPaths
        self.screenRecordingPath = screenRecordingPath
        self.logsPaths = logsPaths
        self.crashReportId = crashReportId
        self.timestamp = Date()
        self.sessionId = AnalyticsManager.shared.sessionId
        self.tags = tags
        self.attachments = attachments
        self.severity = severity
        self.votes = 0
        self.status = .submitted
        self.assignee = nil
        self.estimatedEffort = nil
        self.targetVersion = nil
    }
}

public enum FeedbackStatus: String, CaseIterable, Codable {
    case draft = "draft"
    case submitted = "submitted"
    case inReview = "in_review"
    case accepted = "accepted"
    case inProgress = "in_progress"
    case testing = "testing"
    case completed = "completed"
    case rejected = "rejected"
    case duplicate = "duplicate"
    case wontFix = "wont_fix"
    
    var title: String {
        switch self {
        case .draft: return "Draft"
        case .submitted: return "Submitted"
        case .inReview: return "In Review"
        case .accepted: return "Accepted"
        case .inProgress: return "In Progress"
        case .testing: return "Testing"
        case .completed: return "Completed"
        case .rejected: return "Rejected"
        case .duplicate: return "Duplicate"
        case .wontFix: return "Won't Fix"
        }
    }
    
    var color: Color {
        switch self {
        case .draft: return .gray
        case .submitted: return .blue
        case .inReview: return .orange
        case .accepted: return .green
        case .inProgress: return .purple
        case .testing: return .yellow
        case .completed: return .green
        case .rejected: return .red
        case .duplicate: return .gray
        case .wontFix: return .red
        }
    }
}

public struct FeedbackAttachment: Identifiable, Codable {
    public let id: UUID
    public let filename: String
    public let mimeType: String
    public let size: Int64
    public let localPath: String
    public let uploadUrl: String?
    public let timestamp: Date
    
    public init(filename: String, mimeType: String, size: Int64, localPath: String) {
        self.id = UUID()
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.localPath = localPath
        self.uploadUrl = nil
        self.timestamp = Date()
    }
}

public struct DeviceInfo: Codable {
    public let model: String
    public let systemName: String
    public let systemVersion: String
    public let architecture: String
    public let screenSize: String
    public let screenScale: Float
    public let orientation: String
    public let batteryLevel: Float?
    public let batteryState: String
    public let isJailbroken: Bool
    public let availableStorage: Int64
    public let totalMemory: Int64
    public let processorType: String
    public let isSimulator: Bool
    public let locale: String
    public let timezone: String
    
    public static func current() -> DeviceInfo {
        let device = UIDevice.current
        let screen = UIScreen.main
        
        return DeviceInfo(
            model: device.model,
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            architecture: getArchitecture(),
            screenSize: "\(Int(screen.bounds.width))x\(Int(screen.bounds.height))",
            screenScale: Float(screen.scale),
            orientation: getOrientation(),
            batteryLevel: device.batteryLevel >= 0 ? device.batteryLevel : nil,
            batteryState: device.batteryState.description,
            isJailbroken: isJailbroken(),
            availableStorage: getAvailableStorage(),
            totalMemory: Int64(ProcessInfo.processInfo.physicalMemory),
            processorType: getProcessorType(),
            isSimulator: TARGET_OS_SIMULATOR != 0,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )
    }
    
    private static func getArchitecture() -> String {
        var info = utsname()
        uname(&info)
        return String(cString: &info.machine.0)
    }
    
    private static func getOrientation() -> String {
        switch UIDevice.current.orientation {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        case .faceUp: return "faceUp"
        case .faceDown: return "faceDown"
        default: return "unknown"
        }
    }
    
    private static func isJailbroken() -> Bool {
        let paths = ["/Applications/Cydia.app", "/private/var/lib/apt/", "/private/var/lib/cydia"]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }
    
    private static func getAvailableStorage() -> Int64 {
        do {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            return Int64(values.volumeAvailableCapacity ?? 0)
        } catch {
            return 0
        }
    }
    
    private static func getProcessorType() -> String {
        #if arch(arm64)
        return "ARM64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "Unknown"
        #endif
    }
}

// MARK: - Feedback Manager
@MainActor
public class FeedbackManager: ObservableObject {
    public static let shared = FeedbackManager()
    
    @Published public var feedbackItems: [FeedbackItem] = []
    @Published public var isSubmitting = false
    @Published public var lastSubmissionResult: Result<String, Error>?
    
    private let storageManager = FeedbackStorageManager()
    private let networkManager = FeedbackNetworkManager()
    private let screenshotManager = ScreenshotManager()
    private let logCollector = FeedbackLogCollector()
    private let analyticsManager = AnalyticsManager.shared
    private let hapticManager = HapticFeedbackManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadFeedbackItems()
        setupNotifications()
    }
    
    // MARK: - Public Methods
    
    public func submitFeedback(_ feedback: FeedbackItem) async throws -> String {
        isSubmitting = true
        defer { isSubmitting = false }
        
        do {
            // Store locally first
            let storedFeedback = try storageManager.save(feedback)
            feedbackItems.append(storedFeedback)
            
            // Submit to server
            let submissionId = try await networkManager.submit(storedFeedback)
            
            // Update analytics
            analyticsManager.trackCustomEvent(
                name: "feedback_submitted",
                parameters: [
                    "type": feedback.type.rawValue,
                    "priority": feedback.priority.rawValue,
                    "has_screenshot": !feedback.screenshotPaths.isEmpty,
                    "has_logs": !feedback.logsPaths.isEmpty,
                    "submission_id": submissionId
                ],
                severity: .medium
            )
            
            // Haptic feedback
            hapticManager.operationSuccess()
            
            lastSubmissionResult = .success(submissionId)
            return submissionId
            
        } catch {
            lastSubmissionResult = .failure(error)
            
            // Track error
            analyticsManager.trackError(error: error, context: [
                "action": "submit_feedback",
                "feedback_type": feedback.type.rawValue
            ])
            
            hapticManager.operationError()
            throw error
        }
    }
    
    public func createFeedbackDraft(type: FeedbackType) -> FeedbackItem {
        var feedback = FeedbackItem(
            type: type,
            priority: .medium,
            title: "",
            description: ""
        )
        
        // Auto-collect relevant information based on type
        switch type {
        case .crash:
            if let latestCrash = CrashReporter.shared.getCrashReports().first {
                feedback = FeedbackItem(
                    type: type,
                    priority: .critical,
                    title: "App Crash: \(latestCrash.exceptionName ?? "Unknown")",
                    description: latestCrash.exceptionReason ?? "App crashed unexpectedly",
                    crashReportId: latestCrash.id.uuidString,
                    severity: 5
                )
            }
        case .performance:
            feedback = FeedbackItem(
                type: type,
                priority: .medium,
                title: "Performance Issue",
                description: "",
                tags: ["performance"],
                severity: 3
            )
        default:
            break
        }
        
        return feedback
    }
    
    public func takeScreenshot() async -> String? {
        return await screenshotManager.captureCurrentScreen()
    }
    
    public func attachScreenshot(to feedbackId: UUID, screenshotPath: String) {
        if let index = feedbackItems.firstIndex(where: { $0.id == feedbackId }) {
            var feedback = feedbackItems[index]
            var newPaths = feedback.screenshotPaths
            newPaths.append(screenshotPath)
            
            // Create updated feedback (since FeedbackItem is immutable)
            let updatedFeedback = FeedbackItem(
                type: feedback.type,
                priority: feedback.priority,
                title: feedback.title,
                description: feedback.description,
                steps: feedback.steps,
                expectedBehavior: feedback.expectedBehavior,
                actualBehavior: feedback.actualBehavior,
                reproductionRate: feedback.reproductionRate,
                userEmail: feedback.userEmail,
                allowFollowUp: feedback.allowFollowUp,
                screenshotPaths: newPaths,
                screenRecordingPath: feedback.screenRecordingPath,
                logsPaths: feedback.logsPaths,
                crashReportId: feedback.crashReportId,
                tags: feedback.tags,
                attachments: feedback.attachments,
                severity: feedback.severity
            )
            
            feedbackItems[index] = updatedFeedback
            
            // Save updated feedback
            try? storageManager.update(updatedFeedback)
        }
    }
    
    public func collectLogs(for feedback: FeedbackItem) async -> [String] {
        return await logCollector.collectRelevantLogs(for: feedback)
    }
    
    public func getFeedbackItems(status: FeedbackStatus? = nil, type: FeedbackType? = nil) -> [FeedbackItem] {
        return feedbackItems.filter { item in
            if let status = status, item.status != status { return false }
            if let type = type, item.type != type { return false }
            return true
        }
    }
    
    public func deleteFeedback(id: UUID) {
        feedbackItems.removeAll { $0.id == id }
        storageManager.delete(id: id)
        
        analyticsManager.trackCustomEvent(
            name: "feedback_deleted",
            parameters: ["feedback_id": id.uuidString]
        )
    }
    
    public func voteFeedback(id: UUID, upvote: Bool) async {
        guard let index = feedbackItems.firstIndex(where: { $0.id == id }) else { return }
        
        do {
            try await networkManager.vote(feedbackId: id, upvote: upvote)
            
            analyticsManager.trackCustomEvent(
                name: "feedback_voted",
                parameters: [
                    "feedback_id": id.uuidString,
                    "vote_type": upvote ? "upvote" : "downvote"
                ]
            )
            
            hapticManager.selectionChanged()
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "vote_feedback",
                "feedback_id": id.uuidString
            ])
        }
    }
    
    // MARK: - Private Methods
    
    private func loadFeedbackItems() {
        feedbackItems = storageManager.loadAll()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.saveAllFeedback()
            }
            .store(in: &cancellables)
    }
    
    private func saveAllFeedback() {
        for feedback in feedbackItems {
            try? storageManager.update(feedback)
        }
    }
}

// MARK: - Extensions
extension UIDevice.BatteryState {
    var description: String {
        switch self {
        case .unknown: return "unknown"
        case .unplugged: return "unplugged"
        case .charging: return "charging"
        case .full: return "full"
        @unknown default: return "unknown"
        }
    }
}