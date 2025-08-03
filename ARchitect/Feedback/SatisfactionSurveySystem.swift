import Foundation
import UIKit
import SwiftUI
import Combine

// MARK: - Survey Models
public struct SatisfactionSurvey: Identifiable, Codable {
    public let id: UUID
    public let title: String
    public let description: String
    public let questions: [SurveyQuestion]
    public let trigger: SurveyTrigger
    public let targetAudience: TargetAudience
    public let schedule: SurveySchedule
    public let isActive: Bool
    public let createdAt: Date
    public let updatedAt: Date
    public let responseCount: Int
    public let averageRating: Double?
    public let metadata: [String: Any]
    
    public init(
        title: String,
        description: String,
        questions: [SurveyQuestion],
        trigger: SurveyTrigger,
        targetAudience: TargetAudience = .allUsers,
        schedule: SurveySchedule = .immediate
    ) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.questions = questions
        self.trigger = trigger
        self.targetAudience = targetAudience
        self.schedule = schedule
        self.isActive = true
        self.createdAt = Date()
        self.updatedAt = Date()
        self.responseCount = 0
        self.averageRating = nil
        self.metadata = [:]
    }
}

public struct SurveyQuestion: Identifiable, Codable {
    public let id: UUID
    public let text: String
    public let type: QuestionType
    public let isRequired: Bool
    public let options: [String]?
    public let validationRules: ValidationRules?
    public let order: Int
    public let metadata: [String: String]
    
    public init(
        text: String,
        type: QuestionType,
        isRequired: Bool = true,
        options: [String]? = nil,
        validationRules: ValidationRules? = nil,
        order: Int = 0
    ) {
        self.id = UUID()
        self.text = text
        self.type = type
        self.isRequired = isRequired
        self.options = options
        self.validationRules = validationRules
        self.order = order
        self.metadata = [:]
    }
}

public enum QuestionType: String, CaseIterable, Codable {
    case rating = "rating"
    case multipleChoice = "multiple_choice"
    case singleChoice = "single_choice"
    case text = "text"
    case longText = "long_text"
    case yesNo = "yes_no"
    case scale = "scale"
    case nps = "nps" // Net Promoter Score
    
    var title: String {
        switch self {
        case .rating: return "Rating"
        case .multipleChoice: return "Multiple Choice"
        case .singleChoice: return "Single Choice"
        case .text: return "Short Text"
        case .longText: return "Long Text"
        case .yesNo: return "Yes/No"
        case .scale: return "Scale"
        case .nps: return "Net Promoter Score"
        }
    }
}

public struct ValidationRules: Codable {
    public let minLength: Int?
    public let maxLength: Int?
    public let minValue: Double?
    public let maxValue: Double?
    public let pattern: String?
    public let customValidation: String?
    
    public init(
        minLength: Int? = nil,
        maxLength: Int? = nil,
        minValue: Double? = nil,
        maxValue: Double? = nil,
        pattern: String? = nil,
        customValidation: String? = nil
    ) {
        self.minLength = minLength
        self.maxLength = maxLength
        self.minValue = minValue
        self.maxValue = maxValue
        self.pattern = pattern
        self.customValidation = customValidation
    }
}

public enum SurveyTrigger: String, CaseIterable, Codable {
    case appLaunch = "app_launch"
    case sessionEnd = "session_end"
    case featureUsage = "feature_usage"
    case timeSpent = "time_spent"
    case actionCompleted = "action_completed"
    case manual = "manual"
    case scheduled = "scheduled"
    case errorOccurred = "error_occurred"
    case milestone = "milestone"
    
    var title: String {
        switch self {
        case .appLaunch: return "App Launch"
        case .sessionEnd: return "Session End"
        case .featureUsage: return "Feature Usage"
        case .timeSpent: return "Time Spent"
        case .actionCompleted: return "Action Completed"
        case .manual: return "Manual"
        case .scheduled: return "Scheduled"
        case .errorOccurred: return "Error Occurred"
        case .milestone: return "Milestone"
        }
    }
}

public enum TargetAudience: String, CaseIterable, Codable {
    case allUsers = "all_users"
    case newUsers = "new_users"
    case returningUsers = "returning_users"
    case powerUsers = "power_users"
    case betaTesters = "beta_testers"
    case specificSegment = "specific_segment"
    
    var title: String {
        switch self {
        case .allUsers: return "All Users"
        case .newUsers: return "New Users"
        case .returningUsers: return "Returning Users"
        case .powerUsers: return "Power Users"
        case .betaTesters: return "Beta Testers"
        case .specificSegment: return "Specific Segment"
        }
    }
}

public struct SurveySchedule: Codable {
    public let type: ScheduleType
    public let startDate: Date?
    public let endDate: Date?
    public let frequency: Int? // in days
    public let maxResponses: Int?
    public let cooldownPeriod: Int? // in days
    
    public static let immediate = SurveySchedule(
        type: .immediate,
        startDate: nil,
        endDate: nil,
        frequency: nil,
        maxResponses: nil,
        cooldownPeriod: nil
    )
    
    public init(
        type: ScheduleType,
        startDate: Date? = nil,
        endDate: Date? = nil,
        frequency: Int? = nil,
        maxResponses: Int? = nil,
        cooldownPeriod: Int? = nil
    ) {
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.frequency = frequency
        self.maxResponses = maxResponses
        self.cooldownPeriod = cooldownPeriod
    }
}

public enum ScheduleType: String, CaseIterable, Codable {
    case immediate = "immediate"
    case delayed = "delayed"
    case recurring = "recurring"
    case oneTime = "one_time"
    
    var title: String {
        switch self {
        case .immediate: return "Immediate"
        case .delayed: return "Delayed"
        case .recurring: return "Recurring"
        case .oneTime: return "One Time"
        }
    }
}

public struct SurveyResponse: Identifiable, Codable {
    public let id: UUID
    public let surveyId: UUID
    public let userId: String?
    public let sessionId: String
    public let responses: [QuestionResponse]
    public let startedAt: Date
    public let completedAt: Date?
    public let isCompleted: Bool
    public let timeSpent: TimeInterval
    public let deviceInfo: DeviceInfo
    public let appVersion: String
    public let context: [String: Any]
    
    public init(
        surveyId: UUID,
        userId: String? = nil,
        sessionId: String,
        responses: [QuestionResponse] = [],
        context: [String: Any] = [:]
    ) {
        self.id = UUID()
        self.surveyId = surveyId
        self.userId = userId
        self.sessionId = sessionId
        self.responses = responses
        self.startedAt = Date()
        self.completedAt = nil
        self.isCompleted = false
        self.timeSpent = 0
        self.deviceInfo = DeviceInfo.current()
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        self.context = context
    }
}

public struct QuestionResponse: Identifiable, Codable {
    public let id: UUID
    public let questionId: UUID
    public let answer: SurveyAnswer
    public let answeredAt: Date
    public let timeSpent: TimeInterval
    
    public init(questionId: UUID, answer: SurveyAnswer) {
        self.id = UUID()
        self.questionId = questionId
        self.answer = answer
        self.answeredAt = Date()
        self.timeSpent = 0
    }
}

public enum SurveyAnswer: Codable {
    case text(String)
    case number(Double)
    case boolean(Bool)
    case singleChoice(String)
    case multipleChoice([String])
    case rating(Int)
    case scale(Double)
    
    var stringValue: String {
        switch self {
        case .text(let value): return value
        case .number(let value): return String(value)
        case .boolean(let value): return String(value)
        case .singleChoice(let value): return value
        case .multipleChoice(let values): return values.joined(separator: ", ")
        case .rating(let value): return String(value)
        case .scale(let value): return String(value)
        }
    }
    
    var numericValue: Double? {
        switch self {
        case .number(let value): return value
        case .rating(let value): return Double(value)
        case .scale(let value): return value
        case .boolean(let value): return value ? 1.0 : 0.0
        default: return nil
        }
    }
}

// MARK: - Satisfaction Survey Manager
@MainActor
public class SatisfactionSurveyManager: ObservableObject {
    public static let shared = SatisfactionSurveyManager()
    
    @Published public var availableSurveys: [SatisfactionSurvey] = []
    @Published public var currentSurvey: SatisfactionSurvey?
    @Published public var currentResponse: SurveyResponse?
    @Published public var isShowingSurvey = false
    @Published public var surveyQueue: [SatisfactionSurvey] = []
    
    private let storageManager = SurveyStorageManager()
    private let analyticsManager = AnalyticsManager.shared
    private let hapticManager = HapticFeedbackManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    private var lastSurveyShown: [UUID: Date] = [:]
    private var userSegment: TargetAudience = .allUsers
    
    private init() {
        setupDefaultSurveys()
        loadSurveys()
        setupTriggers()
        determineUserSegment()
    }
    
    // MARK: - Public Methods
    
    public func showSurvey(_ survey: SatisfactionSurvey, context: [String: Any] = [:]) {
        guard shouldShowSurvey(survey) else { return }
        
        currentSurvey = survey
        currentResponse = SurveyResponse(
            surveyId: survey.id,
            sessionId: analyticsManager.sessionId,
            context: context
        )
        isShowingSurvey = true
        
        hapticManager.impact(.medium)
        
        analyticsManager.trackCustomEvent(
            name: "survey_shown",
            parameters: [
                "survey_id": survey.id.uuidString,
                "survey_title": survey.title,
                "trigger": survey.trigger.rawValue,
                "context": context
            ],
            severity: .medium
        )
        
        lastSurveyShown[survey.id] = Date()
    }
    
    public func answerQuestion(_ questionId: UUID, answer: SurveyAnswer) {
        guard var response = currentResponse else { return }
        
        let questionResponse = QuestionResponse(questionId: questionId, answer: answer)
        
        // Update or add response
        if let index = response.responses.firstIndex(where: { $0.questionId == questionId }) {
            var responses = response.responses
            responses[index] = questionResponse
            response = SurveyResponse(
                surveyId: response.surveyId,
                userId: response.userId,
                sessionId: response.sessionId,
                responses: responses,
                context: response.context
            )
        } else {
            var responses = response.responses
            responses.append(questionResponse)
            response = SurveyResponse(
                surveyId: response.surveyId,
                userId: response.userId,
                sessionId: response.sessionId,
                responses: responses,
                context: response.context
            )
        }
        
        currentResponse = response
        
        hapticManager.selectionChanged()
        
        analyticsManager.trackCustomEvent(
            name: "survey_question_answered",
            parameters: [
                "survey_id": response.surveyId.uuidString,
                "question_id": questionId.uuidString,
                "answer_type": "\(type(of: answer))",
                "answer_value": answer.stringValue
            ]
        )
    }
    
    public func submitSurvey() {
        guard let response = currentResponse,
              let survey = currentSurvey else { return }
        
        // Mark as completed
        var completedResponse = response
        let responses = completedResponse.responses
        completedResponse = SurveyResponse(
            surveyId: response.surveyId,
            userId: response.userId,
            sessionId: response.sessionId,
            responses: responses,
            context: response.context
        )
        
        // Save response
        storageManager.saveResponse(completedResponse)
        
        // Update survey stats
        updateSurveyStats(survey, response: completedResponse)
        
        // Clear current survey
        dismissSurvey()
        
        hapticManager.operationSuccess()
        
        analyticsManager.trackCustomEvent(
            name: "survey_submitted",
            parameters: [
                "survey_id": survey.id.uuidString,
                "response_id": completedResponse.id.uuidString,
                "questions_answered": completedResponse.responses.count,
                "time_spent": completedResponse.timeSpent,
                "completion_rate": calculateCompletionRate(survey, response: completedResponse)
            ],
            severity: .medium
        )
    }
    
    public func skipSurvey() {
        guard let survey = currentSurvey else { return }
        
        analyticsManager.trackCustomEvent(
            name: "survey_skipped",
            parameters: [
                "survey_id": survey.id.uuidString,
                "survey_title": survey.title
            ]
        )
        
        dismissSurvey()
        hapticManager.impact(.light)
    }
    
    public func dismissSurvey() {
        currentSurvey = nil
        currentResponse = nil
        isShowingSurvey = false
        
        // Show next survey in queue if any
        if !surveyQueue.isEmpty {
            let nextSurvey = surveyQueue.removeFirst()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.showSurvey(nextSurvey)
            }
        }
    }
    
    public func triggerSurveyForEvent(_ trigger: SurveyTrigger, context: [String: Any] = [:]) {
        let eligibleSurveys = availableSurveys.filter { survey in
            survey.isActive &&
            survey.trigger == trigger &&
            shouldShowSurvey(survey) &&
            matchesTargetAudience(survey)
        }
        
        // Prioritize surveys and show the most relevant one
        if let survey = prioritizeSurveys(eligibleSurveys).first {
            if isShowingSurvey {
                // Add to queue if another survey is showing
                surveyQueue.append(survey)
            } else {
                showSurvey(survey, context: context)
            }
        }
    }
    
    public func getSurveyResponses(surveyId: UUID) -> [SurveyResponse] {
        return storageManager.getResponses(for: surveyId)
    }
    
    public func getSurveyAnalytics(surveyId: UUID) -> SurveyAnalytics {
        let responses = getSurveyResponses(surveyId: surveyId)
        return SurveyAnalytics(responses: responses)
    }
    
    // MARK: - Private Methods
    
    private func setupDefaultSurveys() {
        // App Satisfaction Survey
        let appSatisfactionSurvey = SatisfactionSurvey(
            title: "How are you enjoying ARchitect?",
            description: "We'd love to hear about your experience with the app.",
            questions: [
                SurveyQuestion(
                    text: "How would you rate your overall experience with ARchitect?",
                    type: .rating,
                    order: 1
                ),
                SurveyQuestion(
                    text: "How likely are you to recommend ARchitect to a friend or colleague?",
                    type: .nps,
                    order: 2
                ),
                SurveyQuestion(
                    text: "What feature do you find most valuable?",
                    type: .singleChoice,
                    options: ["AR Room Scanning", "Furniture Placement", "Measurements", "Collaboration", "AI Optimization"],
                    order: 3
                ),
                SurveyQuestion(
                    text: "Is there anything we could improve?",
                    type: .longText,
                    isRequired: false,
                    order: 4
                )
            ],
            trigger: .sessionEnd,
            targetAudience: .allUsers,
            schedule: SurveySchedule(
                type: .recurring,
                frequency: 7,
                maxResponses: 1,
                cooldownPeriod: 30
            )
        )
        
        // Feature-specific Survey
        let arFeatureSurvey = SatisfactionSurvey(
            title: "AR Room Scanning Feedback",
            description: "Help us improve the AR room scanning experience.",
            questions: [
                SurveyQuestion(
                    text: "How easy was it to scan your room?",
                    type: .scale,
                    validationRules: ValidationRules(minValue: 1, maxValue: 5),
                    order: 1
                ),
                SurveyQuestion(
                    text: "Did the scan capture your room accurately?",
                    type: .yesNo,
                    order: 2
                ),
                SurveyQuestion(
                    text: "What could we improve about the scanning process?",
                    type: .multipleChoice,
                    options: ["Speed", "Accuracy", "Guidance", "Visual Feedback", "Error Handling"],
                    isRequired: false,
                    order: 3
                )
            ],
            trigger: .actionCompleted,
            targetAudience: .allUsers
        )
        
        // Beta Tester Survey
        let betaSurvey = SatisfactionSurvey(
            title: "Beta Tester Feedback",
            description: "As a beta tester, your feedback is invaluable to us.",
            questions: [
                SurveyQuestion(
                    text: "How stable has this beta version been for you?",
                    type: .rating,
                    order: 1
                ),
                SurveyQuestion(
                    text: "Have you encountered any bugs or issues?",
                    type: .yesNo,
                    order: 2
                ),
                SurveyQuestion(
                    text: "What new features would you like to see?",
                    type: .longText,
                    isRequired: false,
                    order: 3
                )
            ],
            trigger: .manual,
            targetAudience: .betaTesters
        )
        
        availableSurveys = [appSatisfactionSurvey, arFeatureSurvey, betaSurvey]
    }
    
    private func loadSurveys() {
        let savedSurveys = storageManager.loadSurveys()
        if !savedSurveys.isEmpty {
            availableSurveys = savedSurveys
        }
        
        // Save default surveys if none exist
        for survey in availableSurveys {
            storageManager.saveSurvey(survey)
        }
    }
    
    private func setupTriggers() {
        // App lifecycle triggers
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.triggerSurveyForEvent(.sessionEnd)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.triggerSurveyForEvent(.appLaunch)
            }
            .store(in: &cancellables)
    }
    
    private func shouldShowSurvey(_ survey: SatisfactionSurvey) -> Bool {
        // Check cooldown period
        if let lastShown = lastSurveyShown[survey.id],
           let cooldown = survey.schedule.cooldownPeriod {
            let daysSinceLastShown = Calendar.current.dateComponents([.day], from: lastShown, to: Date()).day ?? 0
            if daysSinceLastShown < cooldown {
                return false
            }
        }
        
        // Check schedule
        if let startDate = survey.schedule.startDate, Date() < startDate {
            return false
        }
        
        if let endDate = survey.schedule.endDate, Date() > endDate {
            return false
        }
        
        // Check response limit
        if let maxResponses = survey.schedule.maxResponses {
            let responseCount = getSurveyResponses(surveyId: survey.id).count
            if responseCount >= maxResponses {
                return false
            }
        }
        
        return true
    }
    
    private func matchesTargetAudience(_ survey: SatisfactionSurvey) -> Bool {
        switch survey.targetAudience {
        case .allUsers:
            return true
        case .newUsers:
            return isNewUser()
        case .returningUsers:
            return !isNewUser()
        case .powerUsers:
            return isPowerUser()
        case .betaTesters:
            return isBetaTester()
        case .specificSegment:
            return userSegment == survey.targetAudience
        }
    }
    
    private func prioritizeSurveys(_ surveys: [SatisfactionSurvey]) -> [SatisfactionSurvey] {
        return surveys.sorted { survey1, survey2 in
            // Prioritize by trigger type and response count
            let priority1 = getTriggerPriority(survey1.trigger)
            let priority2 = getTriggerPriority(survey2.trigger)
            
            if priority1 != priority2 {
                return priority1 > priority2
            }
            
            // Then by response count (fewer responses = higher priority)
            return survey1.responseCount < survey2.responseCount
        }
    }
    
    private func getTriggerPriority(_ trigger: SurveyTrigger) -> Int {
        switch trigger {
        case .errorOccurred: return 5
        case .milestone: return 4
        case .actionCompleted: return 3
        case .sessionEnd: return 2
        case .appLaunch: return 1
        default: return 0
        }
    }
    
    private func updateSurveyStats(_ survey: SatisfactionSurvey, response: SurveyResponse) {
        let responses = getSurveyResponses(surveyId: survey.id)
        let totalResponses = responses.count
        
        // Calculate average rating if any rating questions exist
        let ratingAnswers = responses.flatMap { response in
            response.responses.compactMap { questionResponse in
                questionResponse.answer.numericValue
            }
        }
        
        let averageRating = ratingAnswers.isEmpty ? nil : ratingAnswers.reduce(0, +) / Double(ratingAnswers.count)
        
        // Update survey with new stats
        var updatedSurvey = survey
        // Note: In a real implementation, you'd need to make SatisfactionSurvey mutable or use a different approach
        
        storageManager.saveSurvey(updatedSurvey)
    }
    
    private func calculateCompletionRate(_ survey: SatisfactionSurvey, response: SurveyResponse) -> Double {
        let requiredQuestions = survey.questions.filter { $0.isRequired }.count
        let answeredRequired = response.responses.filter { questionResponse in
            survey.questions.first { $0.id == questionResponse.questionId }?.isRequired == true
        }.count
        
        return requiredQuestions == 0 ? 1.0 : Double(answeredRequired) / Double(requiredQuestions)
    }
    
    private func determineUserSegment() {
        // This would analyze user behavior to determine segment
        // For now, use simple heuristics
        
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "has_launched_before")
        let sessionCount = UserDefaults.standard.integer(forKey: "session_count")
        let isBeta = Bundle.main.infoDictionary?["CFBundleVersion"]?.description.contains("beta") == true
        
        if isBeta {
            userSegment = .betaTesters
        } else if !hasLaunchedBefore || sessionCount < 3 {
            userSegment = .newUsers
        } else if sessionCount > 50 {
            userSegment = .powerUsers
        } else {
            userSegment = .returningUsers
        }
    }
    
    private func isNewUser() -> Bool {
        return !UserDefaults.standard.bool(forKey: "has_launched_before") ||
               UserDefaults.standard.integer(forKey: "session_count") < 3
    }
    
    private func isPowerUser() -> Bool {
        return UserDefaults.standard.integer(forKey: "session_count") > 50
    }
    
    private func isBetaTester() -> Bool {
        return Bundle.main.infoDictionary?["CFBundleVersion"]?.description.contains("beta") == true
    }
}

// MARK: - Survey Analytics
public struct SurveyAnalytics {
    public let totalResponses: Int
    public let completionRate: Double
    public let averageTimeSpent: TimeInterval
    public let responsesByQuestion: [UUID: [SurveyAnswer]]
    public let npsScore: Double?
    public let averageRating: Double?
    
    public init(responses: [SurveyResponse]) {
        self.totalResponses = responses.count
        
        let completedResponses = responses.filter { $0.isCompleted }
        self.completionRate = responses.isEmpty ? 0 : Double(completedResponses.count) / Double(responses.count)
        
        self.averageTimeSpent = completedResponses.isEmpty ? 0 : 
            completedResponses.map { $0.timeSpent }.reduce(0, +) / Double(completedResponses.count)
        
        // Group responses by question
        var responsesByQuestion: [UUID: [SurveyAnswer]] = [:]
        for response in completedResponses {
            for questionResponse in response.responses {
                if responsesByQuestion[questionResponse.questionId] == nil {
                    responsesByQuestion[questionResponse.questionId] = []
                }
                responsesByQuestion[questionResponse.questionId]?.append(questionResponse.answer)
            }
        }
        self.responsesByQuestion = responsesByQuestion
        
        // Calculate NPS score
        let npsAnswers = responsesByQuestion.values.flatMap { $0 }.compactMap { answer -> Double? in
            if case .scale(let value) = answer, value >= 0 && value <= 10 {
                return value
            }
            return nil
        }
        
        if !npsAnswers.isEmpty {
            let promoters = npsAnswers.filter { $0 >= 9 }.count
            let detractors = npsAnswers.filter { $0 <= 6 }.count
            self.npsScore = (Double(promoters - detractors) / Double(npsAnswers.count)) * 100
        } else {
            self.npsScore = nil
        }
        
        // Calculate average rating
        let ratingAnswers = responsesByQuestion.values.flatMap { $0 }.compactMap { $0.numericValue }
        self.averageRating = ratingAnswers.isEmpty ? nil : ratingAnswers.reduce(0, +) / Double(ratingAnswers.count)
    }
}

// MARK: - Storage Manager
public class SurveyStorageManager {
    private let fileManager = FileManager.default
    private let surveysDirectory: URL
    private let responsesDirectory: URL
    
    public init() {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        surveysDirectory = documentsDirectory.appendingPathComponent("Surveys")
        responsesDirectory = documentsDirectory.appendingPathComponent("SurveyResponses")
        
        try? fileManager.createDirectory(at: surveysDirectory, withIntermediateDirectories: true, attributes: nil)
        try? fileManager.createDirectory(at: responsesDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    public func saveSurvey(_ survey: SatisfactionSurvey) {
        let url = surveysDirectory.appendingPathComponent("\(survey.id.uuidString).json")
        
        do {
            let data = try JSONEncoder().encode(survey)
            try data.write(to: url)
        } catch {
            print("Failed to save survey: \(error)")
        }
    }
    
    public func loadSurveys() -> [SatisfactionSurvey] {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: surveysDirectory, includingPropertiesForKeys: nil)
            
            return fileURLs.compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let survey = try? JSONDecoder().decode(SatisfactionSurvey.self, from: data) else {
                    return nil
                }
                return survey
            }
        } catch {
            return []
        }
    }
    
    public func saveResponse(_ response: SurveyResponse) {
        let filename = "\(response.surveyId.uuidString)_\(response.id.uuidString).json"
        let url = responsesDirectory.appendingPathComponent(filename)
        
        do {
            let data = try JSONEncoder().encode(response)
            try data.write(to: url)
        } catch {
            print("Failed to save survey response: \(error)")
        }
    }
    
    public func getResponses(for surveyId: UUID) -> [SurveyResponse] {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: responsesDirectory, includingPropertiesForKeys: nil)
            
            return fileURLs.compactMap { url in
                guard url.lastPathComponent.hasPrefix(surveyId.uuidString),
                      let data = try? Data(contentsOf: url),
                      let response = try? JSONDecoder().decode(SurveyResponse.self, from: data) else {
                    return nil
                }
                return response
            }
        } catch {
            return []
        }
    }
}

// MARK: - Codable Extensions
extension SurveyResponse {
    private enum CodingKeys: String, CodingKey {
        case id, surveyId, userId, sessionId, responses, startedAt, completedAt
        case isCompleted, timeSpent, deviceInfo, appVersion, context
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        surveyId = try container.decode(UUID.self, forKey: .surveyId)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        responses = try container.decode([QuestionResponse].self, forKey: .responses)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        timeSpent = try container.decode(TimeInterval.self, forKey: .timeSpent)
        deviceInfo = try container.decode(DeviceInfo.self, forKey: .deviceInfo)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        
        // Handle context as JSON
        if let contextData = try container.decodeIfPresent(Data.self, forKey: .context) {
            context = (try? JSONSerialization.jsonObject(with: contextData) as? [String: Any]) ?? [:]
        } else {
            context = [:]
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(surveyId, forKey: .surveyId)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(responses, forKey: .responses)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(timeSpent, forKey: .timeSpent)
        try container.encode(deviceInfo, forKey: .deviceInfo)
        try container.encode(appVersion, forKey: .appVersion)
        
        // Encode context as JSON data
        let contextData = try JSONSerialization.data(withJSONObject: context)
        try container.encode(contextData, forKey: .context)
    }
}

extension SatisfactionSurvey {
    private enum CodingKeys: String, CodingKey {
        case id, title, description, questions, trigger, targetAudience, schedule
        case isActive, createdAt, updatedAt, responseCount, averageRating, metadata
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        questions = try container.decode([SurveyQuestion].self, forKey: .questions)
        trigger = try container.decode(SurveyTrigger.self, forKey: .trigger)
        targetAudience = try container.decode(TargetAudience.self, forKey: .targetAudience)
        schedule = try container.decode(SurveySchedule.self, forKey: .schedule)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        responseCount = try container.decode(Int.self, forKey: .responseCount)
        averageRating = try container.decodeIfPresent(Double.self, forKey: .averageRating)
        
        // Handle metadata as JSON
        if let metadataData = try container.decodeIfPresent(Data.self, forKey: .metadata) {
            metadata = (try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any]) ?? [:]
        } else {
            metadata = [:]
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(questions, forKey: .questions)
        try container.encode(trigger, forKey: .trigger)
        try container.encode(targetAudience, forKey: .targetAudience)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(responseCount, forKey: .responseCount)
        try container.encodeIfPresent(averageRating, forKey: .averageRating)
        
        // Encode metadata as JSON data
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        try container.encode(metadataData, forKey: .metadata)
    }
}