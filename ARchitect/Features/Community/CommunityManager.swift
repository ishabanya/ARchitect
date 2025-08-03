import Foundation
import SwiftUI
import Combine

// MARK: - Community Manager
class CommunityManager: ObservableObject {
    static let shared = CommunityManager()
    
    @Published private(set) var userProfile: CommunityProfile?
    @Published private(set) var featuredProjects: [CommunityProject] = []
    @Published private(set) var followingProjects: [CommunityProject] = []
    @Published private(set) var designChallenges: [DesignChallenge] = []
    @Published private(set) var expertConsultations: [ExpertConsultation] = []
    @Published private(set) var notifications: [CommunityNotification] = []
    
    private let featureFlags = FeatureFlagManager.shared
    private let analyticsManager = AnalyticsManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        observeFeatureFlags()
        setupCommunityFeatures()
    }
    
    // MARK: - User Profile Management
    
    func createUserProfile(displayName: String, bio: String?, profileImage: UIImage?) async throws {
        guard featureFlags.isEnabled(.communityFeatures) else {
            throw CommunityError.featureDisabled
        }
        
        let profile = CommunityProfile(
            id: UUID().uuidString,
            displayName: displayName,
            bio: bio,
            profileImageURL: nil, // Would upload image and get URL
            joinDate: Date(),
            followerCount: 0,
            followingCount: 0,
            projectCount: 0,
            reputation: 0,
            badges: [],
            isExpert: false,
            specialties: []
        )
        
        await MainActor.run {
            self.userProfile = profile
        }
        
        analyticsManager.trackFeatureUsage(.tutorialCompleted, parameters: [
            "feature": "community_profile_created",
            "display_name_length": displayName.count,
            "has_bio": bio != nil,
            "has_profile_image": profileImage != nil
        ])
    }
    
    func updateUserProfile(_ profile: CommunityProfile) async throws {
        await MainActor.run {
            self.userProfile = profile
        }
        
        analyticsManager.trackFeatureUsage(.settingsChanged, parameters: [
            "feature": "community_profile_updated",
            "profile_id": profile.id
        ])
    }
    
    func followUser(_ userId: String) async throws {
        guard featureFlags.isEnabled(.communityFeatures) else {
            throw CommunityError.featureDisabled
        }
        
        // In real implementation, this would make an API call
        analyticsManager.trackFeatureUsage(.featureDiscovered, parameters: [
            "feature": "user_followed",
            "followed_user_id": userId
        ])
    }
    
    func unfollowUser(_ userId: String) async throws {
        guard featureFlags.isEnabled(.communityFeatures) else {
            throw CommunityError.featureDisabled
        }
        
        analyticsManager.trackFeatureUsage(.featureDiscovered, parameters: [
            "feature": "user_unfollowed",
            "unfollowed_user_id": userId
        ])
    }
    
    // MARK: - Project Sharing
    
    func shareProject(_ project: ProjectShareData) async throws -> CommunityProject {
        guard featureFlags.isEnabled(.communityFeatures) else {
            throw CommunityError.featureDisabled
        }
        
        let communityProject = CommunityProject(
            id: UUID().uuidString,
            title: project.title,
            description: project.description,
            authorId: userProfile?.id ?? "anonymous",
            authorName: userProfile?.displayName ?? "Anonymous",
            thumbnailURL: project.thumbnailURL,
            imageURLs: project.imageURLs,
            projectData: project.projectData,
            roomType: project.roomType,
            style: project.style,
            tags: project.tags,
            createdAt: Date(),
            updatedAt: Date(),
            likeCount: 0,
            commentCount: 0,
            shareCount: 0,
            viewCount: 0,
            isPublic: true,
            isFeatured: false,
            difficulty: project.difficulty
        )
        
        // In real implementation, this would upload to server
        await MainActor.run {
            self.featuredProjects.insert(communityProject, at: 0)
        }
        
        analyticsManager.trackFeatureUsage(.shareAction, parameters: [
            "feature": "project_shared",
            "project_id": communityProject.id,
            "room_type": project.roomType.rawValue,
            "tag_count": project.tags.count
        ])
        
        return communityProject
    }
    
    func likeProject(_ projectId: String) async throws {
        guard featureFlags.isEnabled(.communityFeatures) else {
            throw CommunityError.featureDisabled
        }
        
        // Update local project
        await MainActor.run {
            if let index = featuredProjects.firstIndex(where: { $0.id == projectId }) {
                featuredProjects[index].likeCount += 1
            }
        }
        
        analyticsManager.trackFeatureUsage(.userInteraction, parameters: [
            "feature": "project_liked",
            "project_id": projectId
        ])
    }
    
    func commentOnProject(_ projectId: String, comment: String) async throws {
        guard featureFlags.isEnabled(.communityFeatures) else {
            throw CommunityError.featureDisabled
        }
        
        let projectComment = ProjectComment(
            id: UUID().uuidString,
            projectId: projectId,
            authorId: userProfile?.id ?? "anonymous",
            authorName: userProfile?.displayName ?? "Anonymous",
            content: comment,
            createdAt: Date(),
            likeCount: 0
        )
        
        analyticsManager.trackFeatureUsage(.userInteraction, parameters: [
            "feature": "project_commented",
            "project_id": projectId,
            "comment_length": comment.count
        ])
    }
    
    // MARK: - Design Challenges
    
    func loadDesignChallenges() async {
        guard featureFlags.isEnabled(.designChallenges) else { return }
        
        let challenges = generateSampleDesignChallenges()
        
        await MainActor.run {
            self.designChallenges = challenges
        }
        
        analyticsManager.trackFeatureUsage(.featureDiscovered, parameters: [
            "feature": "design_challenges_loaded",
            "challenge_count": challenges.count
        ])
    }
    
    func participateInChallenge(_ challengeId: String, projectId: String) async throws {
        guard featureFlags.isEnabled(.designChallenges) else {
            throw CommunityError.featureDisabled
        }
        
        analyticsManager.trackFeatureUsage(.featureDiscovered, parameters: [
            "feature": "challenge_participated",
            "challenge_id": challengeId,
            "project_id": projectId
        ])
    }
    
    func voteInChallenge(_ challengeId: String, projectId: String) async throws {
        guard featureFlags.isEnabled(.designChallenges) else {
            throw CommunityError.featureDisabled
        }
        
        analyticsManager.trackFeatureUsage(.userInteraction, parameters: [
            "feature": "challenge_voted",
            "challenge_id": challengeId,
            "voted_project_id": projectId
        ])
    }
    
    // MARK: - Expert Consultations
    
    func loadExpertConsultations() async {
        guard featureFlags.isEnabled(.expertConsultations) else { return }
        
        let consultations = generateSampleExpertConsultations()
        
        await MainActor.run {
            self.expertConsultations = consultations
        }
        
        analyticsManager.trackFeatureUsage(.featureDiscovered, parameters: [
            "feature": "expert_consultations_loaded",
            "consultation_count": consultations.count
        ])
    }
    
    func bookConsultation(_ consultationId: String, timeSlot: Date, message: String) async throws {
        guard featureFlags.isEnabled(.expertConsultations) else {
            throw CommunityError.featureDisabled
        }
        
        analyticsManager.trackFeatureUsage(.featureDiscovered, parameters: [
            "feature": "consultation_booked",
            "consultation_id": consultationId,
            "time_slot": timeSlot.timeIntervalSince1970,
            "message_length": message.count
        ])
    }
    
    // MARK: - Content Discovery
    
    func loadFeaturedProjects() async {
        guard featureFlags.isEnabled(.communityFeatures) else { return }
        
        let projects = generateSampleProjects()
        
        await MainActor.run {
            self.featuredProjects = projects
        }
        
        analyticsManager.trackFeatureUsage(.screenView, parameters: [
            "screen_name": "community_featured",
            "project_count": projects.count
        ])
    }
    
    func searchProjects(query: String, filters: ProjectFilters) async -> [CommunityProject] {
        guard featureFlags.isEnabled(.communityFeatures) else { return [] }
        
        let results = featuredProjects.filter { project in
            let matchesQuery = query.isEmpty || 
                project.title.localizedCaseInsensitiveContains(query) ||
                project.description.localizedCaseInsensitiveContains(query) ||
                project.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            
            let matchesFilters = (filters.roomType == nil || project.roomType == filters.roomType) &&
                (filters.style == nil || project.style == filters.style) &&
                (filters.difficulty == nil || project.difficulty == filters.difficulty)
            
            return matchesQuery && matchesFilters
        }
        
        analyticsManager.trackFeatureUsage(.featureDiscovered, parameters: [
            "feature": "projects_searched",
            "search_query": query,
            "results_count": results.count,
            "has_filters": filters.hasFilters
        ])
        
        return results
    }
    
    // MARK: - Notifications
    
    func loadNotifications() async {
        guard featureFlags.isEnabled(.communityFeatures) else { return }
        
        let notifications = generateSampleNotifications()
        
        await MainActor.run {
            self.notifications = notifications
        }
    }
    
    func markNotificationAsRead(_ notificationId: String) async {
        await MainActor.run {
            if let index = notifications.firstIndex(where: { $0.id == notificationId }) {
                notifications[index].isRead = true
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func observeFeatureFlags() {
        featureFlags.$flags
            .sink { [weak self] _ in
                Task {
                    await self?.setupCommunityFeatures()
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupCommunityFeatures() {
        guard featureFlags.isEnabled(.communityFeatures) else { return }
        
        Task {
            await loadFeaturedProjects()
            await loadNotifications()
            
            if featureFlags.isEnabled(.designChallenges) {
                await loadDesignChallenges()
            }
            
            if featureFlags.isEnabled(.expertConsultations) {
                await loadExpertConsultations()
            }
        }
    }
    
    // MARK: - Sample Data Generation
    
    private func generateSampleProjects() -> [CommunityProject] {
        return [
            CommunityProject(
                id: "project_1",
                title: "Modern Living Room Makeover",
                description: "Complete transformation of a small living room using contemporary furniture and smart space planning.",
                authorId: "user_1",
                authorName: "Sarah Designer",
                thumbnailURL: "project_1_thumb",
                imageURLs: ["project_1_img1", "project_1_img2", "project_1_img3"],
                projectData: nil, // Would contain actual project data
                roomType: .livingRoom,
                style: .modern,
                tags: ["modern", "small-space", "contemporary", "makeover"],
                createdAt: Date().addingTimeInterval(-86400 * 3), // 3 days ago
                updatedAt: Date().addingTimeInterval(-86400 * 3),
                likeCount: 42,
                commentCount: 8,
                shareCount: 15,
                viewCount: 234,
                isPublic: true,
                isFeatured: true,
                difficulty: .intermediate
            ),
            CommunityProject(
                id: "project_2",
                title: "Cozy Bedroom Retreat",
                description: "Creating a peaceful bedroom sanctuary with warm colors and comfortable textures.",
                authorId: "user_2",
                authorName: "Mike Home",
                thumbnailURL: "project_2_thumb",
                imageURLs: ["project_2_img1", "project_2_img2"],
                projectData: nil,
                roomType: .bedroom,
                style: .traditional,
                tags: ["cozy", "bedroom", "warm", "retreat"],
                createdAt: Date().addingTimeInterval(-86400 * 7), // 1 week ago
                updatedAt: Date().addingTimeInterval(-86400 * 7),
                likeCount: 28,
                commentCount: 5,
                shareCount: 9,
                viewCount: 156,
                isPublic: true,
                isFeatured: false,
                difficulty: .beginner
            )
        ]
    }
    
    private func generateSampleDesignChallenges() -> [DesignChallenge] {
        return [
            DesignChallenge(
                id: "challenge_1",
                title: "Small Space, Big Style",
                description: "Design a functional and stylish living space under 400 square feet.",
                organizerName: "ARchitect Team",
                startDate: Date(),
                endDate: Date().addingTimeInterval(30 * 24 * 3600), // 30 days
                participantCount: 67,
                maxParticipants: 100,
                prize: "Premium subscription + featured placement",
                rules: [
                    "Space must be under 400 sq ft",
                    "Must include at least 3 functional areas",
                    "Budget constraint: $5,000 max"
                ],
                tags: ["small-space", "functional", "budget"],
                difficulty: .intermediate,
                isActive: true
            )
        ]
    }
    
    private func generateSampleExpertConsultations() -> [ExpertConsultation] {
        return [
            ExpertConsultation(
                id: "expert_1",
                expertName: "Jennifer Walsh",
                title: "Interior Design Expert",
                bio: "20+ years experience in residential and commercial design",
                specialties: [.spacePlanning, .colorConsultation, .furnitureSelection],
                rating: 4.9,
                reviewCount: 127,
                hourlyRate: 75.00,
                availableSlots: generateAvailableSlots(),
                profileImageURL: "expert_1_profile",
                isVerified: true,
                responseTime: "Usually responds within 2 hours"
            )
        ]
    }
    
    private func generateAvailableSlots() -> [Date] {
        var slots: [Date] = []
        let calendar = Calendar.current
        let now = Date()
        
        for day in 1...14 { // Next 2 weeks
            let date = calendar.date(byAdding: .day, value: day, to: now)!
            let startHour = 9
            let endHour = 17
            
            for hour in stride(from: startHour, to: endHour, by: 2) {
                if let slotTime = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) {
                    slots.append(slotTime)
                }
            }
        }
        
        return slots
    }
    
    private func generateSampleNotifications() -> [CommunityNotification] {
        return [
            CommunityNotification(
                id: "notif_1",
                type: .projectLiked,
                title: "Your project was liked",
                message: "Sarah Designer liked your 'Modern Living Room Makeover' project",
                createdAt: Date().addingTimeInterval(-3600), // 1 hour ago
                isRead: false,
                actionURL: "project/project_1"
            ),
            CommunityNotification(
                id: "notif_2",
                type: .challengeStarted,
                title: "New design challenge",
                message: "Small Space, Big Style challenge has started. Join now!",
                createdAt: Date().addingTimeInterval(-7200), // 2 hours ago
                isRead: false,
                actionURL: "challenge/challenge_1"
            )
        ]
    }
}

// MARK: - Data Models

struct CommunityProfile: Identifiable, Codable {
    let id: String
    var displayName: String
    var bio: String?
    var profileImageURL: String?
    let joinDate: Date
    var followerCount: Int
    var followingCount: Int
    var projectCount: Int
    var reputation: Int
    var badges: [UserBadge]
    var isExpert: Bool
    var specialties: [ExpertSpecialty]
}

struct CommunityProject: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let authorId: String
    let authorName: String
    let thumbnailURL: String
    let imageURLs: [String]
    let projectData: Data? // Encoded project data
    let roomType: RoomType
    let style: DesignStyle
    let tags: [String]
    let createdAt: Date
    let updatedAt: Date
    var likeCount: Int
    var commentCount: Int
    var shareCount: Int
    var viewCount: Int
    let isPublic: Bool
    let isFeatured: Bool
    let difficulty: ProjectDifficulty
}

struct ProjectComment: Identifiable, Codable {
    let id: String
    let projectId: String
    let authorId: String
    let authorName: String
    let content: String
    let createdAt: Date
    var likeCount: Int
}

struct DesignChallenge: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let organizerName: String
    let startDate: Date
    let endDate: Date
    var participantCount: Int
    let maxParticipants: Int?
    let prize: String
    let rules: [String]
    let tags: [String]
    let difficulty: ProjectDifficulty
    let isActive: Bool
}

struct ExpertConsultation: Identifiable, Codable {
    let id: String
    let expertName: String
    let title: String
    let bio: String
    let specialties: [ExpertSpecialty]
    let rating: Double
    let reviewCount: Int
    let hourlyRate: Double
    let availableSlots: [Date]
    let profileImageURL: String
    let isVerified: Bool
    let responseTime: String
}

struct CommunityNotification: Identifiable, Codable {
    let id: String
    let type: NotificationType
    let title: String
    let message: String
    let createdAt: Date
    var isRead: Bool
    let actionURL: String?
}

struct ProjectShareData {
    let title: String
    let description: String
    let thumbnailURL: String
    let imageURLs: [String]
    let projectData: Data
    let roomType: RoomType
    let style: DesignStyle
    let tags: [String]
    let difficulty: ProjectDifficulty
}

struct ProjectFilters {
    let roomType: RoomType?
    let style: DesignStyle?
    let difficulty: ProjectDifficulty?
    
    var hasFilters: Bool {
        return roomType != nil || style != nil || difficulty != nil
    }
}

enum UserBadge: String, Codable, CaseIterable {
    case earlyAdopter = "early_adopter"
    case topContributor = "top_contributor"
    case helpfulReviewer = "helpful_reviewer"
    case challengeWinner = "challenge_winner"
    case expertConsultant = "expert_consultant"
    
    var displayName: String {
        switch self {
        case .earlyAdopter: return "Early Adopter"
        case .topContributor: return "Top Contributor"
        case .helpfulReviewer: return "Helpful Reviewer"
        case .challengeWinner: return "Challenge Winner"
        case .expertConsultant: return "Expert Consultant"
        }
    }
    
    var icon: String {
        switch self {
        case .earlyAdopter: return "star.fill"
        case .topContributor: return "crown.fill"
        case .helpfulReviewer: return "hand.thumbsup.fill"
        case .challengeWinner: return "trophy.fill"
        case .expertConsultant: return "graduationcap.fill"
        }
    }
}

enum ExpertSpecialty: String, Codable, CaseIterable {
    case spacePlanning = "space_planning"
    case colorConsultation = "color_consultation"
    case furnitureSelection = "furniture_selection"
    case lightingDesign = "lighting_design"
    case kitchenDesign = "kitchen_design"
    case bathroomDesign = "bathroom_design"
    case homeStaging = "home_staging"
    
    var displayName: String {
        switch self {
        case .spaceP

Planning: return "Space Planning"
        case .colorConsultation: return "Color Consultation"
        case .furnitureSelection: return "Furniture Selection"
        case .lightingDesign: return "Lighting Design"
        case .kitchenDesign: return "Kitchen Design"
        case .bathroomDesign: return "Bathroom Design"
        case .homeStaging: return "Home Staging"
        }
    }
}

enum DesignStyle: String, Codable, CaseIterable {
    case modern = "modern"
    case traditional = "traditional"
    case contemporary = "contemporary"
    case scandinavian = "scandinavian"
    case industrial = "industrial"
    case bohemian = "bohemian"
    case minimalist = "minimalist"
    case farmhouse = "farmhouse"
    
    var displayName: String {
        switch self {
        case .modern: return "Modern"
        case .traditional: return "Traditional"
        case .contemporary: return "Contemporary"
        case .scandinavian: return "Scandinavian"
        case .industrial: return "Industrial"
        case .bohemian: return "Bohemian"
        case .minimalist: return "Minimalist"
        case .farmhouse: return "Farmhouse"
        }
    }
}

enum ProjectDifficulty: String, Codable, CaseIterable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
    case expert = "expert"
    
    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        case .expert: return "Expert"
        }
    }
    
    var color: Color {
        switch self {
        case .beginner: return .green
        case .intermediate: return .blue
        case .advanced: return .orange
        case .expert: return .red
        }
    }
}

enum NotificationType: String, Codable {
    case projectLiked = "project_liked"
    case projectCommented = "project_commented"
    case newFollower = "new_follower"
    case challengeStarted = "challenge_started"
    case challengeEnding = "challenge_ending"
    case expertResponse = "expert_response"
    case systemUpdate = "system_update"
    
    var icon: String {
        switch self {
        case .projectLiked: return "heart.fill"
        case .projectCommented: return "message.fill"
        case .newFollower: return "person.badge.plus"
        case .challengeStarted: return "flag.fill"
        case .challengeEnding: return "clock.fill"
        case .expertResponse: return "graduationcap.fill"
        case .systemUpdate: return "gear"
        }
    }
}

enum CommunityError: Error, LocalizedError {
    case featureDisabled
    case notAuthenticated
    case insufficientPermissions
    case networkError
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "Community features are not available"
        case .notAuthenticated:
            return "Please sign in to access community features"
        case .insufficientPermissions:
            return "You don't have permission to perform this action"
        case .networkError:
            return "Network connection error"
        case .invalidData:
            return "Invalid data provided"
        }
    }
}