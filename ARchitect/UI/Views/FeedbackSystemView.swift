import SwiftUI
import Combine

// MARK: - Main Feedback System View
public struct FeedbackSystemView: View {
    @StateObject private var feedbackManager = FeedbackManager.shared
    @StateObject private var surveyManager = SatisfactionSurveyManager.shared
    @StateObject private var featureRequestSystem = FeatureRequestSystem.shared
    @StateObject private var betaTestingProgram = BetaTestingProgram.shared
    @StateObject private var responseTracker = FeedbackResponseTrackingSystem.shared
    @StateObject private var screenshotAnnotation = ScreenshotAnnotationSystem.shared
    
    @State private var selectedTab: FeedbackTab = .home
    @State private var showingFeedbackForm = false
    @State private var showingScreenshotAnnotation = false
    @State private var selectedFeedbackType: FeedbackType = .bugReport
    
    public var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                // Home Tab
                FeedbackHomeView()
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Home")
                    }
                    .tag(FeedbackTab.home)
                
                // Submit Feedback Tab
                SubmitFeedbackView()
                    .tabItem {
                        Image(systemName: "plus.message.fill")
                        Text("Submit")
                    }
                    .tag(FeedbackTab.submit)
                
                // Feature Requests Tab
                FeatureRequestsView()
                    .tabItem {
                        Image(systemName: "lightbulb.fill")
                        Text("Requests")
                    }
                    .tag(FeedbackTab.requests)
                
                // Responses Tab
                ResponsesView()
                    .tabItem {
                        Image(systemName: "bell.fill")
                        Text("Responses")
                    }
                    .badge(responseTracker.unreadResponseCount > 0 ? responseTracker.unreadResponseCount : nil)
                    .tag(FeedbackTab.responses)
                
                // Beta Tab
                if betaTestingProgram.betaStatus != .notEnrolled {
                    BetaTestingView()
                        .tabItem {
                            Image(systemName: "hammer.fill")
                            Text("Beta")
                        }
                        .tag(FeedbackTab.beta)
                }
            }
            .navigationTitle("Feedback")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Take Screenshot", action: takeScreenshot)
                        Button("View Analytics", action: showAnalytics)
                        Button("Export Data", action: exportData)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $surveyManager.isShowingSurvey) {
            if let survey = surveyManager.currentSurvey {
                SatisfactionSurveyView(survey: survey)
            }
        }
        .sheet(isPresented: $screenshotAnnotation.isAnnotating) {
            ScreenshotAnnotationView()
        }
    }
    
    private func takeScreenshot() {
        Task {
            if let screenshotPath = await ScreenshotManager.shared.captureCurrentScreen() {
                screenshotAnnotation.startAnnotation(
                    with: UIImage(contentsOfFile: screenshotPath) ?? UIImage()
                )
            }
        }
    }
    
    private func showAnalytics() {
        // Navigate to analytics view
    }
    
    private func exportData() {
        // Export feedback data
    }
}

// MARK: - Feedback Home View
struct FeedbackHomeView: View {
    @StateObject private var feedbackManager = FeedbackManager.shared
    @StateObject private var responseTracker = FeedbackResponseTrackingSystem.shared
    @StateObject private var featureRequestSystem = FeatureRequestSystem.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Quick Actions
                QuickActionsView()
                
                // Recent Activity
                RecentActivityView()
                
                // Statistics
                FeedbackStatisticsView()
                
                // Trending Feature Requests
                TrendingRequestsView()
            }
            .padding()
        }
    }
}

// MARK: - Quick Actions View
struct QuickActionsView: View {
    @State private var showingFeedbackForm = false
    @State private var showingFeatureRequestForm = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Quick Actions")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                QuickActionButton(
                    icon: "ladybug.fill",
                    title: "Report Bug",
                    color: .red
                ) {
                    showingFeedbackForm = true
                }
                
                QuickActionButton(
                    icon: "lightbulb.fill",
                    title: "Feature Request",
                    color: .blue
                ) {
                    showingFeatureRequestForm = true
                }
                
                QuickActionButton(
                    icon: "camera.fill",
                    title: "Screenshot Report",
                    color: .green
                ) {
                    takeScreenshotReport()
                }
                
                QuickActionButton(
                    icon: "star.fill",
                    title: "Rate Experience",
                    color: .orange
                ) {
                    triggerSatisfactionSurvey()
                }
            }
        }
        .sheet(isPresented: $showingFeedbackForm) {
            FeedbackFormView(feedbackType: .bugReport)
        }
        .sheet(isPresented: $showingFeatureRequestForm) {
            FeatureRequestFormView()
        }
    }
    
    private func takeScreenshotReport() {
        // Implement screenshot report
    }
    
    private func triggerSatisfactionSurvey() {
        SatisfactionSurveyManager.shared.triggerSurveyForEvent(.manual)
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Recent Activity View
struct RecentActivityView: View {
    @StateObject private var feedbackManager = FeedbackManager.shared
    @StateObject private var responseTracker = FeedbackResponseTrackingSystem.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                
                NavigationLink("View All") {
                    ActivityHistoryView()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            VStack(spacing: 12) {
                ForEach(recentActivity.prefix(3), id: \.id) { activity in
                    ActivityRowView(activity: activity)
                }
                
                if recentActivity.isEmpty {
                    Text("No recent activity")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }
        }
    }
    
    private var recentActivity: [ActivityItem] {
        var activities: [ActivityItem] = []
        
        // Add recent feedback
        activities.append(contentsOf: feedbackManager.feedbackItems.prefix(2).map { feedback in
            ActivityItem(
                id: feedback.id,
                type: .feedbackSubmitted,
                title: feedback.title,
                timestamp: feedback.timestamp,
                status: feedback.status.title
            )
        })
        
        // Add recent responses
        activities.append(contentsOf: responseTracker.responses.prefix(2).map { response in
            ActivityItem(
                id: response.id,
                type: .responseReceived,
                title: "Response to feedback",
                timestamp: response.timestamp,
                status: response.status.title
            )
        })
        
        return activities.sorted { $0.timestamp > $1.timestamp }
    }
}

struct ActivityItem: Identifiable {
    let id: UUID
    let type: ActivityType
    let title: String
    let timestamp: Date
    let status: String
    
    enum ActivityType {
        case feedbackSubmitted
        case responseReceived
        case featureRequestSubmitted
        case surveyCompleted
    }
}

struct ActivityRowView: View {
    let activity: ActivityItem
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.type.icon)
                .foregroundColor(activity.type.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Text(activity.status)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(activity.type.color.opacity(0.2))
                        .cornerRadius(4)
                    
                    Text(activity.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

extension ActivityItem.ActivityType {
    var icon: String {
        switch self {
        case .feedbackSubmitted: return "paperplane.fill"
        case .responseReceived: return "bell.fill"
        case .featureRequestSubmitted: return "lightbulb.fill"
        case .surveyCompleted: return "checkmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .feedbackSubmitted: return .blue
        case .responseReceived: return .green
        case .featureRequestSubmitted: return .orange
        case .surveyCompleted: return .purple
        }
    }
}

// MARK: - Feedback Statistics View
struct FeedbackStatisticsView: View {
    @StateObject private var feedbackManager = FeedbackManager.shared
    @StateObject private var responseTracker = FeedbackResponseTrackingSystem.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Feedback Statistics")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                StatisticCard(
                    title: "Total Feedback",
                    value: "\(feedbackManager.feedbackItems.count)",
                    icon: "message.fill",
                    color: .blue
                )
                
                StatisticCard(
                    title: "Responses Received",
                    value: "\(responseTracker.responses.count)",
                    icon: "bell.fill",
                    color: .green
                )
                
                StatisticCard(
                    title: "Average Response Time",
                    value: responseTracker.responseMetrics?.responseTimeDescription ?? "N/A",
                    icon: "clock.fill",
                    color: .orange
                )
                
                StatisticCard(
                    title: "Satisfaction",
                    value: responseTracker.responseMetrics?.satisfactionDescription ?? "N/A",
                    icon: "star.fill",
                    color: .yellow
                )
            }
        }
    }
}

struct StatisticCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Trending Requests View
struct TrendingRequestsView: View {
    @StateObject private var featureRequestSystem = FeatureRequestSystem.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Trending Feature Requests")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                
                NavigationLink("View All") {
                    FeatureRequestsView()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            VStack(spacing: 8) {
                ForEach(featureRequestSystem.trendingRequests.prefix(3)) { request in
                    TrendingRequestRow(request: request)
                }
                
                if featureRequestSystem.trendingRequests.isEmpty {
                    Text("No trending requests")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }
        }
    }
}

struct TrendingRequestRow: View {
    let request: FeatureRequest
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                HStack {
                    Label("\(request.votes)", systemImage: "arrow.up")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    Label("\(request.commentCount)", systemImage: "bubble.left")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    Text(request.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Submit Feedback View
struct SubmitFeedbackView: View {
    @State private var selectedType: FeedbackType = .bugReport
    @State private var showingForm = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("What would you like to report?")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Choose the type of feedback you'd like to submit")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                    ForEach(FeedbackType.allCases, id: \.self) { type in
                        FeedbackTypeCard(
                            type: type,
                            isSelected: selectedType == type
                        ) {
                            selectedType = type
                        }
                    }
                }
                
                Button("Continue") {
                    showingForm = true
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 20)
            }
            .padding()
        }
        .navigationTitle("Submit Feedback")
        .sheet(isPresented: $showingForm) {
            FeedbackFormView(feedbackType: selectedType)
        }
    }
}

struct FeedbackTypeCard: View {
    let type: FeedbackType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: type.icon)
                    .font(.system(size: 32))
                    .foregroundColor(isSelected ? .white : type.color)
                
                Text(type.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(isSelected ? type.color : Color(.systemGray6))
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

extension FeedbackType {
    var color: Color {
        switch self {
        case .bugReport: return .red
        case .featureRequest: return .blue
        case .improvement: return .green
        case .usabilityIssue: return .orange
        case .performance: return .purple
        case .crash: return .red
        case .other: return .gray
        }
    }
}

// MARK: - Supporting Views
struct FeedbackFormView: View {
    let feedbackType: FeedbackType
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Text("Feedback Form for \(feedbackType.title)")
                .navigationTitle("New Feedback")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

struct FeatureRequestFormView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Text("Feature Request Form")
                .navigationTitle("New Feature Request")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

struct FeatureRequestsView: View {
    var body: some View {
        Text("Feature Requests")
            .navigationTitle("Feature Requests")
    }
}

struct ResponsesView: View {
    var body: some View {
        Text("Responses")
            .navigationTitle("Responses")
    }
}

struct BetaTestingView: View {
    var body: some View {
        Text("Beta Testing")
            .navigationTitle("Beta Testing")
    }
}

struct ActivityHistoryView: View {
    var body: some View {
        Text("Activity History")
            .navigationTitle("Activity History")
    }
}

struct SatisfactionSurveyView: View {
    let survey: SatisfactionSurvey
    
    var body: some View {
        Text("Survey: \(survey.title)")
    }
}

struct ScreenshotAnnotationView: View {
    var body: some View {
        Text("Screenshot Annotation")
    }
}

// MARK: - Supporting Types
enum FeedbackTab: String, CaseIterable {
    case home = "home"
    case submit = "submit"
    case requests = "requests"
    case responses = "responses"
    case beta = "beta"
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .cornerRadius(12)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Preview
struct FeedbackSystemView_Previews: PreviewProvider {
    static var previews: some View {
        FeedbackSystemView()
    }
}