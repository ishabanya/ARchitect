import SwiftUI

struct AIOptimizationView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var isAnalyzing = false
    @State private var analysisComplete = false
    @State private var suggestions: [OptimizationSuggestion] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if isAnalyzing {
                    analyzingView
                } else if analysisComplete {
                    suggestionsView
                } else {
                    startView
                }
            }
            .padding()
            .navigationTitle("AI Optimization")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    private var startView: some View {
        VStack(spacing: 30) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 80))
                .foregroundColor(.purple)
            
            VStack(spacing: 16) {
                Text("AI Space Optimization")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Let AI analyze your space and provide smart layout suggestions based on traffic flow, lighting, and ergonomics.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            Button(action: startAnalysis) {
                HStack {
                    Image(systemName: "wand.and.rays")
                    Text("Start AI Analysis")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.purple)
                .cornerRadius(16)
            }
        }
    }
    
    private var analyzingView: some View {
        VStack(spacing: 30) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.purple)
            
            VStack(spacing: 12) {
                Text("Analyzing Your Space")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("AI is evaluating traffic patterns, lighting conditions, and spatial relationships...")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                
                Text("Analysis Complete!")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(suggestions) { suggestion in
                        SuggestionCard(suggestion: suggestion)
                    }
                }
            }
        }
    }
    
    private func startAnalysis() {
        isAnalyzing = true
        
        // Simulate AI analysis
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            isAnalyzing = false
            analysisComplete = true
            loadSuggestions()
        }
    }
    
    private func loadSuggestions() {
        suggestions = [
            OptimizationSuggestion(
                id: UUID(),
                title: "Improve Traffic Flow",
                description: "Move the coffee table 2 feet to the left to create a clearer pathway",
                impact: .high,
                icon: "figure.walk"
            ),
            OptimizationSuggestion(
                id: UUID(),
                title: "Optimize Natural Light",
                description: "Rotate the sofa 45° to take advantage of the east-facing window",
                impact: .medium,
                icon: "sun.max.fill"
            ),
            OptimizationSuggestion(
                id: UUID(),
                title: "Create Conversation Zone",
                description: "Position chairs closer together for better social interaction",
                impact: .medium,
                icon: "bubble.left.and.bubble.right.fill"
            )
        ]
    }
}

struct SuggestionCard: View {
    let suggestion: OptimizationSuggestion
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: suggestion.icon)
                .font(.title2)
                .foregroundColor(suggestion.impact.color)
                .frame(width: 40, height: 40)
                .background(suggestion.impact.color.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(suggestion.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            VStack {
                Text(suggestion.impact.rawValue.uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(suggestion.impact.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(suggestion.impact.color.opacity(0.1))
                    .cornerRadius(6)
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct OptimizationSuggestion: Identifiable {
    let id: UUID
    let title: String
    let description: String
    let impact: Impact
    let icon: String
    
    enum Impact: String, CaseIterable {
        case high = "high"
        case medium = "medium"
        case low = "low"
        
        var color: Color {
            switch self {
            case .high: return .red
            case .medium: return .orange
            case .low: return .green
            }
        }
    }
}

#Preview {
    AIOptimizationView()
}