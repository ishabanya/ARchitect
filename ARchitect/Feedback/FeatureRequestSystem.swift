import Foundation
import UIKit
import SwiftUI
import Combine

// MARK: - Feature Request System
@MainActor
public class FeatureRequestSystem: ObservableObject {
    public static let shared = FeatureRequestSystem()
    
    @Published public var featureRequests: [FeatureRequest] = []
    @Published public var trendingRequests: [FeatureRequest] = []
    @Published public var myRequests: [FeatureRequest] = []
    @Published public var votedRequests: Set<UUID> = []
    @Published public var isSubmitting = false
    @Published public var searchText = ""
    @Published public var selectedCategory: FeatureCategory = .all
    @Published public var selectedStatus: RequestStatus = .all
    @Published public var sortBy: SortOption = .trending
    
    private let storageManager = FeatureRequestStorageManager()
    private let networkManager = FeatureRequestNetworkManager()
    private let analyticsManager = AnalyticsManager.shared
    private let hapticManager = HapticFeedbackManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    private let userId = createUserId()
    
    private init() {
        loadFeatureRequests()
        setupObservers()
    }
    
    // MARK: - Public Methods
    
    public func submitFeatureRequest(_ request: FeatureRequest) async throws -> String {
        isSubmitting = true
        defer { isSubmitting = false }
        
        do {
            // Store locally first
            var submittedRequest = request
            submittedRequest.userId = userId
            submittedRequest.status = .submitted
            
            let storedRequest = try storageManager.save(submittedRequest)
            featureRequests.append(storedRequest)
            myRequests.append(storedRequest)
            
            // Submit to server
            let submissionId = try await networkManager.submit(storedRequest)
            
            // Update analytics
            analyticsManager.trackCustomEvent(
                name: "feature_request_submitted",
                parameters: [
                    "category": request.category.rawValue,
                    "priority": request.priority.rawValue,
                    "has_mockup": request.mockupImagePaths.isEmpty ? "false" : "true",
                    "description_length": request.description.count,
                    "submission_id": submissionId
                ],
                severity: .medium
            )
            
            // Haptic feedback
            hapticManager.operationSuccess()
            
            updateTrendingRequests()
            return submissionId
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "submit_feature_request",
                "category": request.category.rawValue
            ])
            
            hapticManager.operationError()
            throw error
        }
    }
    
    public func voteForRequest(_ requestId: UUID, upvote: Bool) async {
        guard !votedRequests.contains(requestId),
              let index = featureRequests.firstIndex(where: { $0.id == requestId }) else { return }
        
        do {
            // Submit vote to server
            try await networkManager.vote(requestId: requestId, upvote: upvote, userId: userId)
            
            // Update local state
            var request = featureRequests[index]
            if upvote {
                request.votes += 1
                request.userVote = .upvote
            } else {
                request.downvotes += 1
                request.userVote = .downvote
            }
            
            featureRequests[index] = request
            votedRequests.insert(requestId)
            
            // Store vote locally
            storageManager.saveVote(requestId: requestId, userId: userId, upvote: upvote)
            
            // Update trending
            updateTrendingRequests()
            
            // Analytics and haptics
            analyticsManager.trackCustomEvent(
                name: "feature_request_voted",
                parameters: [
                    "request_id": requestId.uuidString,
                    "vote_type": upvote ? "upvote" : "downvote",
                    "new_vote_count": request.votes
                ]
            )
            
            hapticManager.selectionChanged()
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "vote_feature_request",
                "request_id": requestId.uuidString
            ])
        }
    }
    
    public func addComment(to requestId: UUID, comment: String) async {
        guard let index = featureRequests.firstIndex(where: { $0.id == requestId }) else { return }
        
        let requestComment = RequestComment(
            userId: userId,
            comment: comment,
            timestamp: Date()
        )
        
        do {
            // Submit comment to server
            try await networkManager.addComment(requestId: requestId, comment: requestComment)
            
            // Update local state
            var request = featureRequests[index]
            request.comments.append(requestComment)
            request.commentCount += 1
            featureRequests[index] = request
            
            // Store locally
            try storageManager.update(request)
            
            analyticsManager.trackCustomEvent(
                name: "feature_request_commented",
                parameters: [
                    "request_id": requestId.uuidString,
                    "comment_length": comment.count
                ]
            )
            
            hapticManager.impact(.light)
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "comment_feature_request",
                "request_id": requestId.uuidString
            ])
        }
    }
    
    public func followRequest(_ requestId: UUID) {
        guard let index = featureRequests.firstIndex(where: { $0.id == requestId }) else { return }
        
        var request = featureRequests[index]
        request.isFollowing = !request.isFollowing
        featureRequests[index] = request
        
        // Store follow status
        storageManager.saveFollowStatus(requestId: requestId, userId: userId, isFollowing: request.isFollowing)
        
        analyticsManager.trackCustomEvent(
            name: "feature_request_followed",
            parameters: [
                "request_id": requestId.uuidString,
                "is_following": request.isFollowing
            ]
        )
        
        hapticManager.selectionChanged()
    }
    
    public func reportRequest(_ requestId: UUID, reason: ReportReason) async {
        do {
            try await networkManager.reportRequest(requestId: requestId, reason: reason, userId: userId)
            
            analyticsManager.trackCustomEvent(
                name: "feature_request_reported",
                parameters: [
                    "request_id": requestId.uuidString,
                    "reason": reason.rawValue
                ]
            )
            
            hapticManager.impact(.medium)
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "report_feature_request",
                "request_id": requestId.uuidString
            ])
        }
    }
    
    public func searchRequests(query: String) {
        searchText = query
        filterAndSortRequests()
    }
    
    public func filterByCategory(_ category: FeatureCategory) {
        selectedCategory = category
        filterAndSortRequests()
    }
    
    public func filterByStatus(_ status: RequestStatus) {
        selectedStatus = status
        filterAndSortRequests()
    }
    
    public func sortRequests(by option: SortOption) {
        sortBy = option
        filterAndSortRequests()
    }
    
    public func getFilteredRequests() -> [FeatureRequest] {
        var filtered = featureRequests
        
        // Apply text search
        if !searchText.isEmpty {
            filtered = filtered.filter { request in
                request.title.localizedCaseInsensitiveContains(searchText) ||
                request.description.localizedCaseInsensitiveContains(searchText) ||
                request.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        
        // Apply category filter
        if selectedCategory != .all {
            filtered = filtered.filter { $0.category == selectedCategory }
        }
        
        // Apply status filter
        if selectedStatus != .all {
            filtered = filtered.filter { $0.status == selectedStatus }
        }
        
        // Apply sorting
        switch sortBy {
        case .trending:
            filtered = filtered.sorted { calculateTrendingScore($0) > calculateTrendingScore($1) }
        case .mostVoted:
            filtered = filtered.sorted { $0.votes > $1.votes }
        case .newest:
            filtered = filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            filtered = filtered.sorted { $0.createdAt < $1.createdAt }
        case .mostCommented:
            filtered = filtered.sorted { $0.commentCount > $1.commentCount }
        case .alphabetical:
            filtered = filtered.sorted { $0.title < $1.title }
        }
        
        return filtered
    }
    
    public func getMyRequests() -> [FeatureRequest] {
        return featureRequests.filter { $0.userId == userId }
    }
    
    public func deleteRequest(_ requestId: UUID) async {
        guard let index = featureRequests.firstIndex(where: { $0.id == requestId }),
              featureRequests[index].userId == userId else { return }
        
        do {
            try await networkManager.deleteRequest(requestId: requestId, userId: userId)
            
            featureRequests.remove(at: index)
            myRequests.removeAll { $0.id == requestId }
            
            storageManager.delete(id: requestId)
            
            analyticsManager.trackCustomEvent(
                name: "feature_request_deleted",
                parameters: ["request_id": requestId.uuidString]
            )
            
            hapticManager.impact(.medium)
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "delete_feature_request",
                "request_id": requestId.uuidString
            ])
        }
    }
    
    public func duplicateRequest(original: FeatureRequest) -> FeatureRequest {
        return FeatureRequest(
            title: original.title + " (Copy)",
            description: original.description,
            category: original.category,
            priority: original.priority,
            expectedBenefit: original.expectedBenefit,
            tags: original.tags,
            mockupImagePaths: original.mockupImagePaths,
            attachments: original.attachments
        )
    }
    
    // MARK: - Private Methods
    
    private func loadFeatureRequests() {
        featureRequests = storageManager.loadAll()
        myRequests = getMyRequests()
        votedRequests = Set(storageManager.loadVotedRequests(userId: userId))
        updateTrendingRequests()
    }
    
    private func setupObservers() {
        // Auto-refresh every 5 minutes
        Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshFromServer()
            }
        }
        
        // Search text debouncing
        $searchText
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.filterAndSortRequests()
            }
            .store(in: &cancellables)
    }
    
    private func refreshFromServer() async {
        do {
            let serverRequests = try await networkManager.fetchAll()
            
            // Merge server data with local data
            mergeServerData(serverRequests)
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "refresh_feature_requests"
            ])
        }
    }
    
    private func mergeServerData(_ serverRequests: [FeatureRequest]) {
        // Update existing requests and add new ones
        for serverRequest in serverRequests {
            if let index = featureRequests.firstIndex(where: { $0.id == serverRequest.id }) {
                featureRequests[index] = serverRequest
            } else {
                featureRequests.append(serverRequest)
            }
        }
        
        updateTrendingRequests()
        filterAndSortRequests()
    }
    
    private func updateTrendingRequests() {
        trendingRequests = featureRequests
            .sorted { calculateTrendingScore($0) > calculateTrendingScore($1) }
            .prefix(10)
            .map { $0 }
    }
    
    private func calculateTrendingScore(_ request: FeatureRequest) -> Double {
        let ageInDays = Date().timeIntervalSince(request.createdAt) / 86400
        let votesScore = Double(request.votes) * 1.0
        let commentsScore = Double(request.commentCount) * 0.5
        let ageDecay = max(0.1, 1.0 - (ageInDays / 30.0)) // Decay over 30 days
        
        return (votesScore + commentsScore) * ageDecay
    }
    
    private func filterAndSortRequests() {
        // This will trigger UI updates through @Published properties
        objectWillChange.send()
    }
    
    private static func createUserId() -> String {
        if let existingId = UserDefaults.standard.string(forKey: "feature_request_user_id") {
            return existingId
        }
        
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "feature_request_user_id")
        return newId
    }
}

// MARK: - Feature Request Model
public struct FeatureRequest: Identifiable, Codable {
    public let id: UUID
    public let title: String
    public let description: String
    public let category: FeatureCategory
    public let priority: RequestPriority
    public let expectedBenefit: String
    public let tags: [String]
    public let mockupImagePaths: [String]
    public let attachments: [RequestAttachment]
    public let createdAt: Date
    public let updatedAt: Date
    public var userId: String?
    public var status: RequestStatus
    public var votes: Int
    public var downvotes: Int
    public var userVote: VoteType?
    public var commentCount: Int
    public var comments: [RequestComment]
    public var isFollowing: Bool
    public var assignee: String?
    public var estimatedEffort: EffortEstimate?
    public var targetVersion: String?
    public var implementationNotes: String?
    public var roadmapPosition: Int?
    
    public init(
        title: String,
        description: String,
        category: FeatureCategory,
        priority: RequestPriority = .medium,
        expectedBenefit: String = "",
        tags: [String] = [],
        mockupImagePaths: [String] = [],
        attachments: [RequestAttachment] = []
    ) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.category = category
        self.priority = priority
        self.expectedBenefit = expectedBenefit
        self.tags = tags
        self.mockupImagePaths = mockupImagePaths
        self.attachments = attachments
        self.createdAt = Date()
        self.updatedAt = Date()
        self.userId = nil
        self.status = .draft
        self.votes = 0
        self.downvotes = 0
        self.userVote = nil
        self.commentCount = 0
        self.comments = []
        self.isFollowing = false
        self.assignee = nil
        self.estimatedEffort = nil
        self.targetVersion = nil
        self.implementationNotes = nil
        self.roadmapPosition = nil
    }
}

public struct RequestComment: Identifiable, Codable {
    public let id: UUID
    public let userId: String
    public let comment: String
    public let timestamp: Date
    public let replies: [RequestComment]
    
    public init(userId: String, comment: String, timestamp: Date, replies: [RequestComment] = []) {
        self.id = UUID()
        self.userId = userId
        self.comment = comment
        self.timestamp = timestamp
        self.replies = replies
    }
}

public struct RequestAttachment: Identifiable, Codable {
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

// MARK: - Enums
public enum FeatureCategory: String, CaseIterable, Codable {
    case all = "all"
    case ar = "ar"
    case ui = "ui"
    case collaboration = "collaboration"
    case measurement = "measurement"
    case furniture = "furniture"
    case sharing = "sharing"
    case performance = "performance"
    case accessibility = "accessibility"
    case integration = "integration"
    case ai = "ai"
    case other = "other"
    
    var title: String {
        switch self {
        case .all: return "All Categories"
        case .ar: return "AR Features"
        case .ui: return "User Interface"
        case .collaboration: return "Collaboration"
        case .measurement: return "Measurement Tools"
        case .furniture: return "Furniture Catalog"
        case .sharing: return "Sharing & Export"
        case .performance: return "Performance"
        case .accessibility: return "Accessibility"
        case .integration: return "Integration"
        case .ai: return "AI Features"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .ar: return "arkit"
        case .ui: return "paintbrush"
        case .collaboration: return "person.2"
        case .measurement: return "ruler"
        case .furniture: return "bed.double"
        case .sharing: return "square.and.arrow.up"
        case .performance: return "speedometer"
        case .accessibility: return "accessibility"
        case .integration: return "link"
        case .ai: return "brain"
        case .other: return "ellipsis.circle"
        }
    }
}

public enum RequestPriority: String, CaseIterable, Codable {
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

public enum RequestStatus: String, CaseIterable, Codable {
    case all = "all"
    case draft = "draft"
    case submitted = "submitted"
    case inReview = "in_review"
    case approved = "approved"
    case inDevelopment = "in_development"
    case testing = "testing"
    case completed = "completed"
    case rejected = "rejected"
    case duplicate = "duplicate"
    case onHold = "on_hold"
    
    var title: String {
        switch self {
        case .all: return "All Statuses"
        case .draft: return "Draft"
        case .submitted: return "Submitted"
        case .inReview: return "In Review"
        case .approved: return "Approved"
        case .inDevelopment: return "In Development"
        case .testing: return "Testing"
        case .completed: return "Completed"
        case .rejected: return "Rejected"
        case .duplicate: return "Duplicate"
        case .onHold: return "On Hold"
        }
    }
    
    var color: Color {
        switch self {
        case .all: return .gray
        case .draft: return .gray
        case .submitted: return .blue
        case .inReview: return .orange
        case .approved: return .green
        case .inDevelopment: return .purple
        case .testing: return .yellow
        case .completed: return .green
        case .rejected: return .red
        case .duplicate: return .gray
        case .onHold: return .orange
        }
    }
}

public enum SortOption: String, CaseIterable {
    case trending = "trending"
    case mostVoted = "most_voted"
    case newest = "newest"
    case oldest = "oldest"
    case mostCommented = "most_commented"
    case alphabetical = "alphabetical"
    
    var title: String {
        switch self {
        case .trending: return "Trending"
        case .mostVoted: return "Most Voted"
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .mostCommented: return "Most Commented"
        case .alphabetical: return "Alphabetical"
        }
    }
}

public enum VoteType: String, Codable {
    case upvote = "upvote"
    case downvote = "downvote"
}

public enum ReportReason: String, CaseIterable, Codable {
    case spam = "spam"
    case inappropriate = "inappropriate"
    case duplicate = "duplicate"
    case offtopic = "offtopic"
    case other = "other"
    
    var title: String {
        switch self {
        case .spam: return "Spam"
        case .inappropriate: return "Inappropriate Content"
        case .duplicate: return "Duplicate Request"
        case .offtopic: return "Off Topic"
        case .other: return "Other"
        }
    }
}

public enum EffortEstimate: String, CaseIterable, Codable {
    case small = "small"      // 1-2 days
    case medium = "medium"    // 1-2 weeks
    case large = "large"      // 1-2 months
    case extraLarge = "xl"    // 3+ months
    
    var title: String {
        switch self {
        case .small: return "Small (1-2 days)"
        case .medium: return "Medium (1-2 weeks)"
        case .large: return "Large (1-2 months)"
        case .extraLarge: return "Extra Large (3+ months)"
        }
    }
}

// MARK: - Storage Manager
public class FeatureRequestStorageManager {
    private let fileManager = FileManager.default
    private let requestsDirectory: URL
    private let votesDirectory: URL
    
    public init() {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        requestsDirectory = documentsDirectory.appendingPathComponent("FeatureRequests")
        votesDirectory = documentsDirectory.appendingPathComponent("FeatureRequestVotes")
        
        try? fileManager.createDirectory(at: requestsDirectory, withIntermediateDirectories: true, attributes: nil)
        try? fileManager.createDirectory(at: votesDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    public func save(_ request: FeatureRequest) throws -> FeatureRequest {
        let url = requestsDirectory.appendingPathComponent("\(request.id.uuidString).json")
        
        let data = try JSONEncoder().encode(request)
        try data.write(to: url)
        
        return request
    }
    
    public func update(_ request: FeatureRequest) throws {
        _ = try save(request)
    }
    
    public func loadAll() -> [FeatureRequest] {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: requestsDirectory, includingPropertiesForKeys: nil)
            
            return fileURLs.compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let request = try? JSONDecoder().decode(FeatureRequest.self, from: data) else {
                    return nil
                }
                return request
            }
        } catch {
            return []
        }
    }
    
    public func delete(id: UUID) {
        let url = requestsDirectory.appendingPathComponent("\(id.uuidString).json")
        try? fileManager.removeItem(at: url)
    }
    
    public func saveVote(requestId: UUID, userId: String, upvote: Bool) {
        let voteData = [
            "request_id": requestId.uuidString,
            "user_id": userId,
            "upvote": upvote,
            "timestamp": Date().timeIntervalSince1970
        ] as [String : Any]
        
        let filename = "\(requestId.uuidString)_\(userId).json"
        let url = votesDirectory.appendingPathComponent(filename)
        
        do {
            let data = try JSONSerialization.data(withJSONObject: voteData)
            try data.write(to: url)
        } catch {
            print("Failed to save vote: \(error)")
        }
    }
    
    public func loadVotedRequests(userId: String) -> [UUID] {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: votesDirectory, includingPropertiesForKeys: nil)
            
            return fileURLs.compactMap { url in
                guard url.lastPathComponent.hasSuffix("_\(userId).json"),
                      let data = try? Data(contentsOf: url),
                      let voteData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let requestIdString = voteData["request_id"] as? String,
                      let requestId = UUID(uuidString: requestIdString) else {
                    return nil
                }
                return requestId
            }
        } catch {
            return []
        }
    }
    
    public func saveFollowStatus(requestId: UUID, userId: String, isFollowing: Bool) {
        let key = "following_\(requestId.uuidString)_\(userId)"
        UserDefaults.standard.set(isFollowing, forKey: key)
    }
    
    public func loadFollowStatus(requestId: UUID, userId: String) -> Bool {
        let key = "following_\(requestId.uuidString)_\(userId)"
        return UserDefaults.standard.bool(forKey: key)
    }
}

// MARK: - Network Manager
public class FeatureRequestNetworkManager {
    private let baseURL = URL(string: "https://api.architect.com/feature-requests")!
    
    public func submit(_ request: FeatureRequest) async throws -> String {
        // This would integrate with your backend API
        // For now, simulate network request
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        
        // Simulate success with submission ID
        return "FR-\(Int.random(in: 1000...9999))"
    }
    
    public func fetchAll() async throws -> [FeatureRequest] {
        // This would fetch from your backend API
        // For now, return empty array
        return []
    }
    
    public func vote(requestId: UUID, upvote: Bool, userId: String) async throws {
        // This would submit vote to your backend API
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
    }
    
    public func addComment(requestId: UUID, comment: RequestComment) async throws {
        // This would submit comment to your backend API
        try await Task.sleep(nanoseconds: 750_000_000) // 0.75 second delay
    }
    
    public func reportRequest(requestId: UUID, reason: ReportReason, userId: String) async throws {
        // This would submit report to your backend API
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
    }
    
    public func deleteRequest(requestId: UUID, userId: String) async throws {
        // This would delete from your backend API
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
    }
}

// MARK: - Extensions
extension AnalyticsManager {
    func getTotalSessions(in timeRange: TimeRange) -> Int {
        // This would get actual session count from analytics
        // For now, return a simulated value
        switch timeRange {
        case .lastWeek: return 150
        case .lastDay: return 25
        case .lastHour: return 5
        case .lastMonth: return 600
        }
    }
}