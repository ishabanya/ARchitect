import Foundation
import UIKit
import SwiftUI
import Combine
import UserNotifications

// MARK: - Feedback Response Tracking System
@MainActor
public class FeedbackResponseTrackingSystem: ObservableObject {
    public static let shared = FeedbackResponseTrackingSystem()
    
    @Published public var responses: [FeedbackResponse] = []
    @Published public var pendingResponses: [FeedbackResponse] = []
    @Published public var notifications: [ResponseNotification] = []
    @Published public var responseMetrics: ResponseMetrics?
    @Published public var isProcessingResponse = false
    @Published public var unreadResponseCount = 0
    
    private let storageManager = ResponseTrackingStorageManager()
    private let networkManager = ResponseTrackingNetworkManager()
    private let notificationManager = ResponseNotificationManager()
    private let analyticsManager = AnalyticsManager.shared
    private let hapticManager = HapticFeedbackManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    private let userId = createResponseUserId()
    
    private init() {
        loadResponses()
        setupNotifications()
        schedulePeriodicChecks()
        updateMetrics()
    }
    
    // MARK: - Public Methods
    
    public func trackFeedbackSubmission(_ feedbackId: UUID, type: FeedbackType) {
        let trackingEntry = FeedbackTrackingEntry(
            feedbackId: feedbackId,
            userId: userId,
            type: type,
            submittedAt: Date(),
            status: .submitted,
            expectedResponseTime: calculateExpectedResponseTime(for: type)
        )
        
        storageManager.saveTrackingEntry(trackingEntry)
        
        // Schedule response time check
        scheduleResponseTimeCheck(for: trackingEntry)
        
        analyticsManager.trackCustomEvent(
            name: "feedback_submission_tracked",
            parameters: [
                "feedback_id": feedbackId.uuidString,
                "feedback_type": type.rawValue,
                "expected_response_hours": trackingEntry.expectedResponseTime / 3600
            ]
        )
    }
    
    public func recordResponse(_ response: FeedbackResponse) async {
        isProcessingResponse = true
        defer { isProcessingResponse = false }
        
        // Update tracking entry
        if var trackingEntry = storageManager.loadTrackingEntry(feedbackId: response.feedbackId) {
            trackingEntry.status = .responded
            trackingEntry.respondedAt = response.timestamp
            trackingEntry.responseTime = response.timestamp.timeIntervalSince(trackingEntry.submittedAt)
            trackingEntry.responderInfo = response.responderInfo
            storageManager.saveTrackingEntry(trackingEntry)
        }
        
        // Store response
        responses.insert(response, at: 0)
        storageManager.saveResponse(response)
        
        // Mark as unread if not already seen
        if !response.isRead {
            unreadResponseCount += 1
            storageManager.saveUnreadCount(unreadResponseCount)
        }
        
        // Create notification
        let notification = ResponseNotification(
            responseId: response.id,
            feedbackId: response.feedbackId,
            title: "Response to Your Feedback",
            message: response.message,
            timestamp: response.timestamp,
            isRead: false,
            priority: response.priority
        )
        
        notifications.insert(notification, at: 0)
        storageManager.saveNotification(notification)
        
        // Send push notification if app is in background
        await notificationManager.sendResponseNotification(notification)
        
        // Update metrics
        updateMetrics()
        
        // Analytics
        analyticsManager.trackCustomEvent(
            name: "feedback_response_received",
            parameters: [
                "feedback_id": response.feedbackId.uuidString,
                "response_type": response.type.rawValue,
                "response_time_hours": (response.responseMetadata?.responseTime ?? 0) / 3600,
                "responder_role": response.responderInfo?.role.rawValue ?? "unknown"
            ],
            severity: .medium
        )
        
        hapticManager.notification(.success)
    }
    
    public func markResponseAsRead(_ responseId: UUID) {
        guard let index = responses.firstIndex(where: { $0.id == responseId }) else { return }
        
        var response = responses[index]
        if !response.isRead {
            response.isRead = true
            responses[index] = response
            
            unreadResponseCount = max(0, unreadResponseCount - 1)
            
            storageManager.saveResponse(response)
            storageManager.saveUnreadCount(unreadResponseCount)
            
            // Mark related notification as read
            if let notificationIndex = notifications.firstIndex(where: { $0.responseId == responseId }) {
                var notification = notifications[notificationIndex]
                notification.isRead = true
                notifications[notificationIndex] = notification
                storageManager.saveNotification(notification)
            }
            
            analyticsManager.trackCustomEvent(
                name: "feedback_response_read",
                parameters: [
                    "response_id": responseId.uuidString,
                    "time_to_read": Date().timeIntervalSince(response.timestamp)
                ]
            )
        }
    }
    
    public func markAllResponsesAsRead() {
        let unreadResponses = responses.filter { !$0.isRead }
        
        for (index, response) in responses.enumerated() {
            if !response.isRead {
                responses[index].isRead = true
                storageManager.saveResponse(responses[index])
            }
        }
        
        for (index, notification) in notifications.enumerated() {
            if !notification.isRead {
                notifications[index].isRead = true
                storageManager.saveNotification(notifications[index])
            }
        }
        
        unreadResponseCount = 0
        storageManager.saveUnreadCount(unreadResponseCount)
        
        analyticsManager.trackCustomEvent(
            name: "all_responses_marked_read",
            parameters: [
                "count": unreadResponses.count
            ]
        )
    }
    
    public func rateFeedbackResponse(_ responseId: UUID, rating: Int, comment: String?) async {
        guard let response = responses.first(where: { $0.id == responseId }) else { return }
        
        let responseRating = ResponseRating(
            responseId: responseId,
            feedbackId: response.feedbackId,
            userId: userId,
            rating: rating,
            comment: comment,
            timestamp: Date()
        )
        
        do {
            try await networkManager.submitResponseRating(responseRating)
            
            storageManager.saveResponseRating(responseRating)
            
            analyticsManager.trackCustomEvent(
                name: "feedback_response_rated",
                parameters: [
                    "response_id": responseId.uuidString,
                    "rating": rating,
                    "has_comment": comment != nil
                ]
            )
            
            hapticManager.selectionChanged()
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "rate_feedback_response",
                "response_id": responseId.uuidString
            ])
        }
    }
    
    public func followUpOnResponse(_ responseId: UUID, message: String) async {
        guard let response = responses.first(where: { $0.id == responseId }) else { return }
        
        let followUp = ResponseFollowUp(
            originalResponseId: responseId,
            feedbackId: response.feedbackId,
            userId: userId,
            message: message,
            timestamp: Date(),
            attachments: []
        )
        
        do {
            try await networkManager.submitFollowUp(followUp)
            
            storageManager.saveFollowUp(followUp)
            
            analyticsManager.trackCustomEvent(
                name: "feedback_response_followup",
                parameters: [
                    "response_id": responseId.uuidString,
                    "message_length": message.count
                ]
            )
            
            hapticManager.impact(.medium)
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "followup_response",
                "response_id": responseId.uuidString
            ])
        }
    }
    
    public func requestEscalation(_ responseId: UUID, reason: EscalationReason) async {
        guard let response = responses.first(where: { $0.id == responseId }) else { return }
        
        let escalation = ResponseEscalation(
            responseId: responseId,
            feedbackId: response.feedbackId,
            userId: userId,
            reason: reason,
            timestamp: Date(),
            additionalInfo: nil
        )
        
        do {
            try await networkManager.requestEscalation(escalation)
            
            storageManager.saveEscalation(escalation)
            
            analyticsManager.trackCustomEvent(
                name: "feedback_response_escalated",
                parameters: [
                    "response_id": responseId.uuidString,
                    "escalation_reason": reason.rawValue
                ]
            )
            
            hapticManager.impact(.heavy)
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "escalate_response",
                "response_id": responseId.uuidString
            ])
        }
    }
    
    public func getResponseHistory(for feedbackId: UUID) -> [FeedbackResponse] {
        return responses.filter { $0.feedbackId == feedbackId }.sorted { $0.timestamp > $1.timestamp }
    }
    
    public func getResponsesByStatus(_ status: ResponseStatus) -> [FeedbackResponse] {
        return responses.filter { $0.status == status }
    }
    
    public func getResponsesByType(_ type: ResponseType) -> [FeedbackResponse] {
        return responses.filter { $0.type == type }
    }
    
    public func getResponsesInTimeRange(from startDate: Date, to endDate: Date) -> [FeedbackResponse] {
        return responses.filter { response in
            response.timestamp >= startDate && response.timestamp <= endDate
        }
    }
    
    public func exportResponseData() -> Data? {
        let exportData = ResponseDataExport(
            responses: responses,
            notifications: notifications,
            metrics: responseMetrics,
            exportDate: Date(),
            userId: userId
        )
        
        return try? JSONEncoder().encode(exportData)
    }
    
    public func generateResponseReport() -> ResponseReport {
        let totalResponses = responses.count
        let averageResponseTime = calculateAverageResponseTime()
        let satisfactionRating = calculateAverageSatisfactionRating()
        let responsesByType = Dictionary(grouping: responses) { $0.type }
        let responsesByStatus = Dictionary(grouping: responses) { $0.status }
        
        return ResponseReport(
            totalResponses: totalResponses,
            averageResponseTime: averageResponseTime,
            satisfactionRating: satisfactionRating,
            responsesByType: responsesByType.mapValues { $0.count },
            responsesByStatus: responsesByStatus.mapValues { $0.count },
            generatedAt: Date(),
            period: .allTime
        )
    }
    
    // MARK: - Private Methods
    
    private func loadResponses() {
        responses = storageManager.loadResponses()
        notifications = storageManager.loadNotifications()
        unreadResponseCount = storageManager.loadUnreadCount()
        
        // Load pending responses (those awaiting response)
        loadPendingResponses()
    }
    
    private func loadPendingResponses() {
        let trackingEntries = storageManager.loadAllTrackingEntries()
        pendingResponses = trackingEntries
            .filter { $0.status == .submitted || $0.status == .acknowledged }
            .compactMap { entry in
                // Create placeholder response for pending items
                FeedbackResponse(
                    feedbackId: entry.feedbackId,
                    type: .acknowledgment,
                    message: "Your feedback is being reviewed...",
                    status: .pending,
                    timestamp: entry.submittedAt,
                    priority: .medium,
                    isRead: true,
                    responderInfo: nil,
                    attachments: [],
                    responseMetadata: ResponseMetadata(
                        responseTime: Date().timeIntervalSince(entry.submittedAt),
                        category: .automated,
                        sentiment: .neutral,
                        tags: []
                    )
                )
            }
    }
    
    private func setupNotifications() {
        // Request notification permissions
        Task {
            await notificationManager.requestPermissions()
        }
        
        // Handle app lifecycle
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task {
                    await self?.checkForNewResponses()
                }
            }
            .store(in: &cancellables)
    }
    
    private func schedulePeriodicChecks() {
        // Check for new responses every 15 minutes
        Timer.scheduledTimer(withTimeInterval: 900.0, repeats: true) { [weak self] _ in
            Task {
                await self?.checkForNewResponses()
            }
        }
        
        // Update metrics every hour
        Timer.scheduledTimer(withTimeInterval: 3600.0, repeats: true) { [weak self] _ in
            self?.updateMetrics()
        }
    }
    
    private func checkForNewResponses() async {
        do {
            let newResponses = try await networkManager.fetchNewResponses(userId: userId)
            
            for response in newResponses {
                await recordResponse(response)
            }
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "check_new_responses"
            ])
        }
    }
    
    private func calculateExpectedResponseTime(for type: FeedbackType) -> TimeInterval {
        switch type {
        case .crash:
            return 24 * 3600 // 24 hours
        case .bugReport:
            return 72 * 3600 // 72 hours
        case .featureRequest:
            return 7 * 24 * 3600 // 7 days
        case .improvement:
            return 5 * 24 * 3600 // 5 days
        case .usabilityIssue:
            return 48 * 3600 // 48 hours
        case .performance:
            return 48 * 3600 // 48 hours
        case .other:
            return 5 * 24 * 3600 // 5 days
        }
    }
    
    private func scheduleResponseTimeCheck(for entry: FeedbackTrackingEntry) {
        let checkTime = entry.submittedAt.addingTimeInterval(entry.expectedResponseTime)
        
        if checkTime > Date() {
            DispatchQueue.main.asyncAfter(deadline: .now() + checkTime.timeIntervalSinceNow) {
                self.checkResponseTimeout(for: entry)
            }
        }
    }
    
    private func checkResponseTimeout(for entry: FeedbackTrackingEntry) {
        // Check if response was received
        if let trackingEntry = storageManager.loadTrackingEntry(feedbackId: entry.feedbackId),
           trackingEntry.status == .submitted {
            
            // Mark as overdue
            var updatedEntry = trackingEntry
            updatedEntry.status = .overdue
            storageManager.saveTrackingEntry(updatedEntry)
            
            // Send notification
            let notification = ResponseNotification(
                responseId: UUID(),
                feedbackId: entry.feedbackId,
                title: "Response Overdue",
                message: "Your feedback is taking longer than expected to receive a response.",
                timestamp: Date(),
                isRead: false,
                priority: .high
            )
            
            notifications.insert(notification, at: 0)
            storageManager.saveNotification(notification)
            
            Task {
                await notificationManager.sendOverdueNotification(notification)
            }
            
            analyticsManager.trackCustomEvent(
                name: "feedback_response_overdue",
                parameters: [
                    "feedback_id": entry.feedbackId.uuidString,
                    "expected_hours": entry.expectedResponseTime / 3600,
                    "actual_hours": Date().timeIntervalSince(entry.submittedAt) / 3600
                ]
            )
        }
    }
    
    private func updateMetrics() {
        let totalResponses = responses.count
        let averageResponseTime = calculateAverageResponseTime()
        let satisfactionRating = calculateAverageSatisfactionRating()
        let responseRate = calculateResponseRate()
        let overdueCount = storageManager.loadAllTrackingEntries().filter { $0.status == .overdue }.count
        
        responseMetrics = ResponseMetrics(
            totalResponses: totalResponses,
            averageResponseTime: averageResponseTime,
            satisfactionRating: satisfactionRating,
            responseRate: responseRate,
            overdueResponses: overdueCount,
            lastUpdated: Date()
        )
    }
    
    private func calculateAverageResponseTime() -> TimeInterval {
        let responsesWithTime = responses.compactMap { $0.responseMetadata?.responseTime }
        guard !responsesWithTime.isEmpty else { return 0 }
        
        return responsesWithTime.reduce(0, +) / Double(responsesWithTime.count)
    }
    
    private func calculateAverageSatisfactionRating() -> Double {
        let ratings = storageManager.loadAllResponseRatings().map { Double($0.rating) }
        guard !ratings.isEmpty else { return 0 }
        
        return ratings.reduce(0, +) / Double(ratings.count)
    }
    
    private func calculateResponseRate() -> Double {
        let trackingEntries = storageManager.loadAllTrackingEntries()
        let respondedEntries = trackingEntries.filter { $0.status == .responded }
        
        guard !trackingEntries.isEmpty else { return 0 }
        
        return Double(respondedEntries.count) / Double(trackingEntries.count)
    }
    
    private static func createResponseUserId() -> String {
        if let existingId = UserDefaults.standard.string(forKey: "response_tracking_user_id") {
            return existingId
        }
        
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "response_tracking_user_id")
        return newId
    }
}

// MARK: - Response Models
public struct FeedbackResponse: Identifiable, Codable {
    public let id: UUID
    public let feedbackId: UUID
    public let type: ResponseType
    public let message: String
    public let status: ResponseStatus
    public let timestamp: Date
    public let priority: ResponsePriority
    public var isRead: Bool
    public let responderInfo: ResponderInfo?
    public let attachments: [ResponseAttachment]
    public let responseMetadata: ResponseMetadata?
    
    public init(
        feedbackId: UUID,
        type: ResponseType,
        message: String,
        status: ResponseStatus,
        timestamp: Date,
        priority: ResponsePriority,
        isRead: Bool = false,
        responderInfo: ResponderInfo?,
        attachments: [ResponseAttachment],
        responseMetadata: ResponseMetadata?
    ) {
        self.id = UUID()
        self.feedbackId = feedbackId
        self.type = type
        self.message = message
        self.status = status
        self.timestamp = timestamp
        self.priority = priority
        self.isRead = isRead
        self.responderInfo = responderInfo
        self.attachments = attachments
        self.responseMetadata = responseMetadata
    }
}

public struct ResponderInfo: Codable {
    public let name: String
    public let role: ResponderRole
    public let department: String?
    public let avatar: String?
}

public struct ResponseAttachment: Identifiable, Codable {
    public let id: UUID
    public let filename: String
    public let mimeType: String
    public let size: Int64
    public let downloadUrl: URL?
    public let localPath: String?
}

public struct ResponseMetadata: Codable {
    public let responseTime: TimeInterval
    public let category: ResponseCategory
    public let sentiment: ResponseSentiment
    public let tags: [String]
}

public struct ResponseNotification: Identifiable, Codable {
    public let id: UUID
    public let responseId: UUID
    public let feedbackId: UUID
    public let title: String
    public let message: String
    public let timestamp: Date
    public var isRead: Bool
    public let priority: ResponsePriority
    
    public init(responseId: UUID, feedbackId: UUID, title: String, message: String, timestamp: Date, isRead: Bool, priority: ResponsePriority) {
        self.id = UUID()
        self.responseId = responseId
        self.feedbackId = feedbackId
        self.title = title
        self.message = message
        self.timestamp = timestamp
        self.isRead = isRead
        self.priority = priority
    }
}

public struct FeedbackTrackingEntry: Codable {
    public let feedbackId: UUID
    public let userId: String
    public let type: FeedbackType
    public let submittedAt: Date
    public var status: TrackingStatus
    public var respondedAt: Date?
    public var responseTime: TimeInterval?
    public let expectedResponseTime: TimeInterval
    public var responderInfo: ResponderInfo?
    
    public init(feedbackId: UUID, userId: String, type: FeedbackType, submittedAt: Date, status: TrackingStatus, expectedResponseTime: TimeInterval) {
        self.feedbackId = feedbackId
        self.userId = userId
        self.type = type
        self.submittedAt = submittedAt
        self.status = status
        self.expectedResponseTime = expectedResponseTime
        self.respondedAt = nil
        self.responseTime = nil
        self.responderInfo = nil
    }
}

public struct ResponseRating: Identifiable, Codable {
    public let id: UUID
    public let responseId: UUID
    public let feedbackId: UUID
    public let userId: String
    public let rating: Int
    public let comment: String?
    public let timestamp: Date
    
    public init(responseId: UUID, feedbackId: UUID, userId: String, rating: Int, comment: String?, timestamp: Date) {
        self.id = UUID()
        self.responseId = responseId
        self.feedbackId = feedbackId
        self.userId = userId
        self.rating = rating
        self.comment = comment
        self.timestamp = timestamp
    }
}

public struct ResponseFollowUp: Identifiable, Codable {
    public let id: UUID
    public let originalResponseId: UUID
    public let feedbackId: UUID
    public let userId: String
    public let message: String
    public let timestamp: Date
    public let attachments: [ResponseAttachment]
    
    public init(originalResponseId: UUID, feedbackId: UUID, userId: String, message: String, timestamp: Date, attachments: [ResponseAttachment]) {
        self.id = UUID()
        self.originalResponseId = originalResponseId
        self.feedbackId = feedbackId
        self.userId = userId
        self.message = message
        self.timestamp = timestamp
        self.attachments = attachments
    }
}

public struct ResponseEscalation: Identifiable, Codable {
    public let id: UUID
    public let responseId: UUID
    public let feedbackId: UUID
    public let userId: String
    public let reason: EscalationReason
    public let timestamp: Date
    public let additionalInfo: String?
    
    public init(responseId: UUID, feedbackId: UUID, userId: String, reason: EscalationReason, timestamp: Date, additionalInfo: String?) {
        self.id = UUID()
        self.responseId = responseId
        self.feedbackId = feedbackId
        self.userId = userId
        self.reason = reason
        self.timestamp = timestamp
        self.additionalInfo = additionalInfo
    }
}

public struct ResponseMetrics: Codable {
    public let totalResponses: Int
    public let averageResponseTime: TimeInterval
    public let satisfactionRating: Double
    public let responseRate: Double
    public let overdueResponses: Int
    public let lastUpdated: Date
}

public struct ResponseReport: Codable {
    public let totalResponses: Int
    public let averageResponseTime: TimeInterval
    public let satisfactionRating: Double
    public let responsesByType: [ResponseType: Int]
    public let responsesByStatus: [ResponseStatus: Int]
    public let generatedAt: Date
    public let period: ReportPeriod
}

public struct ResponseDataExport: Codable {
    public let responses: [FeedbackResponse]
    public let notifications: [ResponseNotification]
    public let metrics: ResponseMetrics?
    public let exportDate: Date
    public let userId: String
}

// MARK: - Enums
public enum ResponseType: String, CaseIterable, Codable {
    case acknowledgment = "acknowledgment"
    case resolution = "resolution"
    case update = "update"
    case clarification = "clarification"
    case rejection = "rejection"
    case escalation = "escalation"
    
    var title: String {
        switch self {
        case .acknowledgment: return "Acknowledgment"
        case .resolution: return "Resolution"
        case .update: return "Update"
        case .clarification: return "Clarification"
        case .rejection: return "Rejection"
        case .escalation: return "Escalation"
        }
    }
}

public enum ResponseStatus: String, CaseIterable, Codable {
    case pending = "pending"
    case delivered = "delivered"
    case read = "read"
    case acknowledged = "acknowledged"
    case resolved = "resolved"
    
    var title: String {
        switch self {
        case .pending: return "Pending"
        case .delivered: return "Delivered"
        case .read: return "Read"
        case .acknowledged: return "Acknowledged"
        case .resolved: return "Resolved"
        }
    }
}

public enum ResponsePriority: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case urgent = "urgent"
    
    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }
    
    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

public enum ResponderRole: String, CaseIterable, Codable {
    case support = "support"
    case developer = "developer"
    case productManager = "product_manager"
    case designer = "designer"
    case qa = "qa"
    case management = "management"
    
    var title: String {
        switch self {
        case .support: return "Support"
        case .developer: return "Developer"
        case .productManager: return "Product Manager"
        case .designer: return "Designer"
        case .qa: return "QA"
        case .management: return "Management"
        }
    }
}

public enum TrackingStatus: String, CaseIterable, Codable {
    case submitted = "submitted"
    case acknowledged = "acknowledged"
    case responded = "responded"
    case overdue = "overdue"
    case escalated = "escalated"
    case closed = "closed"
}

public enum ResponseCategory: String, CaseIterable, Codable {
    case automated = "automated"
    case human = "human"
    case escalated = "escalated"
    case resolved = "resolved"
}

public enum ResponseSentiment: String, CaseIterable, Codable {
    case positive = "positive"
    case neutral = "neutral"
    case negative = "negative"
}

public enum EscalationReason: String, CaseIterable, Codable {
    case unsatisfiedWithResponse = "unsatisfied_with_response"
    case noResponse = "no_response"
    case incorrectInformation = "incorrect_information"
    case rude = "rude"
    case technical = "technical"
    case other = "other"
    
    var title: String {
        switch self {
        case .unsatisfiedWithResponse: return "Unsatisfied with Response"
        case .noResponse: return "No Response Received"
        case .incorrectInformation: return "Incorrect Information"
        case .rude: return "Unprofessional Response"
        case .technical: return "Technical Issue"
        case .other: return "Other"
        }
    }
}

public enum ReportPeriod: String, CaseIterable, Codable {
    case lastWeek = "last_week"
    case lastMonth = "last_month"
    case lastQuarter = "last_quarter"
    case lastYear = "last_year"
    case allTime = "all_time"
}

public enum FeedbackType: String, CaseIterable, Codable {
    case bugReport = "bug_report"
    case featureRequest = "feature_request"
    case improvement = "improvement"
    case usabilityIssue = "usability_issue"
    case performance = "performance"
    case crash = "crash"
    case other = "other"
}

// MARK: - Storage Manager
public class ResponseTrackingStorageManager {
    private let fileManager = FileManager.default
    private let responsesDirectory: URL
    
    public init() {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        responsesDirectory = documentsDirectory.appendingPathComponent("FeedbackResponses")
        
        try? fileManager.createDirectory(at: responsesDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    public func saveResponse(_ response: FeedbackResponse) {
        let url = responsesDirectory.appendingPathComponent("response_\(response.id.uuidString).json")
        
        do {
            let data = try JSONEncoder().encode(response)
            try data.write(to: url)
        } catch {
            print("Failed to save response: \(error)")
        }
    }
    
    public func loadResponses() -> [FeedbackResponse] {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: responsesDirectory, includingPropertiesForKeys: [.creationDateKey])
            
            return fileURLs
                .filter { $0.lastPathComponent.hasPrefix("response_") }
                .compactMap { url in
                    guard let data = try? Data(contentsOf: url),
                          let response = try? JSONDecoder().decode(FeedbackResponse.self, from: data) else {
                        return nil
                    }
                    return response
                }
                .sorted { $0.timestamp > $1.timestamp }
        } catch {
            return []
        }
    }
    
    public func saveNotification(_ notification: ResponseNotification) {
        let url = responsesDirectory.appendingPathComponent("notification_\(notification.id.uuidString).json")
        
        do {
            let data = try JSONEncoder().encode(notification)
            try data.write(to: url)
        } catch {
            print("Failed to save notification: \(error)")
        }
    }
    
    public func loadNotifications() -> [ResponseNotification] {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: responsesDirectory, includingPropertiesForKeys: nil)
            
            return fileURLs
                .filter { $0.lastPathComponent.hasPrefix("notification_") }
                .compactMap { url in
                    guard let data = try? Data(contentsOf: url),
                          let notification = try? JSONDecoder().decode(ResponseNotification.self, from: data) else {
                        return nil
                    }
                    return notification
                }
                .sorted { $0.timestamp > $1.timestamp }
        } catch {
            return []
        }
    }
    
    public func saveTrackingEntry(_ entry: FeedbackTrackingEntry) {
        let url = responsesDirectory.appendingPathComponent("tracking_\(entry.feedbackId.uuidString).json")
        
        do {
            let data = try JSONEncoder().encode(entry)
            try data.write(to: url)
        } catch {
            print("Failed to save tracking entry: \(error)")
        }
    }
    
    public func loadTrackingEntry(feedbackId: UUID) -> FeedbackTrackingEntry? {
        let url = responsesDirectory.appendingPathComponent("tracking_\(feedbackId.uuidString).json")
        
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(FeedbackTrackingEntry.self, from: data) else {
            return nil
        }
        
        return entry
    }
    
    public func loadAllTrackingEntries() -> [FeedbackTrackingEntry] {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: responsesDirectory, includingPropertiesForKeys: nil)
            
            return fileURLs
                .filter { $0.lastPathComponent.hasPrefix("tracking_") }
                .compactMap { url in
                    guard let data = try? Data(contentsOf: url),
                          let entry = try? JSONDecoder().decode(FeedbackTrackingEntry.self, from: data) else {
                        return nil
                    }
                    return entry
                }
        } catch {
            return []
        }
    }
    
    public func saveResponseRating(_ rating: ResponseRating) {
        let url = responsesDirectory.appendingPathComponent("rating_\(rating.id.uuidString).json")
        
        do {
            let data = try JSONEncoder().encode(rating)
            try data.write(to: url)
        } catch {
            print("Failed to save response rating: \(error)")
        }
    }
    
    public func loadAllResponseRatings() -> [ResponseRating] {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: responsesDirectory, includingPropertiesForKeys: nil)
            
            return fileURLs
                .filter { $0.lastPathComponent.hasPrefix("rating_") }
                .compactMap { url in
                    guard let data = try? Data(contentsOf: url),
                          let rating = try? JSONDecoder().decode(ResponseRating.self, from: data) else {
                        return nil
                    }
                    return rating
                }
        } catch {
            return []
        }
    }
    
    public func saveFollowUp(_ followUp: ResponseFollowUp) {
        let url = responsesDirectory.appendingPathComponent("followup_\(followUp.id.uuidString).json")
        
        do {
            let data = try JSONEncoder().encode(followUp)
            try data.write(to: url)
        } catch {
            print("Failed to save follow up: \(error)")
        }
    }
    
    public func saveEscalation(_ escalation: ResponseEscalation) {
        let url = responsesDirectory.appendingPathComponent("escalation_\(escalation.id.uuidString).json")
        
        do {
            let data = try JSONEncoder().encode(escalation)
            try data.write(to: url)
        } catch {
            print("Failed to save escalation: \(error)")
        }
    }
    
    public func saveUnreadCount(_ count: Int) {
        UserDefaults.standard.set(count, forKey: "unread_response_count")
    }
    
    public func loadUnreadCount() -> Int {
        return UserDefaults.standard.integer(forKey: "unread_response_count")
    }
}

// MARK: - Network Manager
public class ResponseTrackingNetworkManager {
    private let baseURL = URL(string: "https://api.architect.com/feedback-responses")!
    
    public func fetchNewResponses(userId: String) async throws -> [FeedbackResponse] {
        // This would integrate with your backend API
        // For now, simulate network request
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Return empty array - real implementation would fetch from server
        return []
    }
    
    public func submitResponseRating(_ rating: ResponseRating) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    public func submitFollowUp(_ followUp: ResponseFollowUp) async throws {
        try await Task.sleep(nanoseconds: 750_000_000)
    }
    
    public func requestEscalation(_ escalation: ResponseEscalation) async throws {
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }
}

// MARK: - Notification Manager
public class ResponseNotificationManager {
    
    public func requestPermissions() async {
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
    
    public func sendResponseNotification(_ notification: ResponseNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.message
        content.sound = .default
        content.badge = NSNumber(value: FeedbackResponseTrackingSystem.shared.unreadResponseCount)
        content.categoryIdentifier = "FEEDBACK_RESPONSE"
        
        let request = UNNotificationRequest(
            identifier: "response_\(notification.id.uuidString)",
            content: content,
            trigger: nil
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule response notification: \(error)")
        }
    }
    
    public func sendOverdueNotification(_ notification: ResponseNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.message
        content.sound = .default
        content.categoryIdentifier = "FEEDBACK_OVERDUE"
        
        let request = UNNotificationRequest(
            identifier: "overdue_\(notification.id.uuidString)",
            content: content,
            trigger: nil
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule overdue notification: \(error)")
        }
    }
    
    private func setupNotificationCategories() {
        let replyAction = UNNotificationAction(
            identifier: "REPLY_ACTION",
            title: "Reply",
            options: [.foreground]
        )
        
        let markReadAction = UNNotificationAction(
            identifier: "MARK_READ_ACTION",
            title: "Mark as Read",
            options: []
        )
        
        let responseCategory = UNNotificationCategory(
            identifier: "FEEDBACK_RESPONSE",
            actions: [replyAction, markReadAction],
            intentIdentifiers: [],
            options: []
        )
        
        let escalateAction = UNNotificationAction(
            identifier: "ESCALATE_ACTION",
            title: "Escalate",
            options: [.foreground]
        )
        
        let overdueCategory = UNNotificationCategory(
            identifier: "FEEDBACK_OVERDUE",
            actions: [escalateAction, markReadAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([responseCategory, overdueCategory])
    }
}

// MARK: - Extensions
extension ResponseMetrics {
    var responseTimeDescription: String {
        let hours = averageResponseTime / 3600
        
        if hours < 1 {
            return "< 1 hour"
        } else if hours < 24 {
            return String(format: "%.1f hours", hours)
        } else {
            let days = hours / 24
            return String(format: "%.1f days", days)
        }
    }
    
    var satisfactionDescription: String {
        switch satisfactionRating {
        case 4.5...5.0: return "Excellent"
        case 3.5..<4.5: return "Good"
        case 2.5..<3.5: return "Fair"
        case 1.5..<2.5: return "Poor"
        default: return "Very Poor"
        }
    }
}

// MARK: - Response Extensions
extension Array where Element == FeedbackResponse {
    func groupedByDate() -> [Date: [FeedbackResponse]] {
        let calendar = Calendar.current
        return Dictionary(grouping: self) { response in
            calendar.startOfDay(for: response.timestamp)
        }
    }
    
    func filterByPriority(_ priority: ResponsePriority) -> [FeedbackResponse] {
        return self.filter { $0.priority == priority }
    }
    
    func unreadResponses() -> [FeedbackResponse] {
        return self.filter { !$0.isRead }
    }
}