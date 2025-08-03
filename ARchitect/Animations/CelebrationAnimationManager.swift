import Foundation
import SwiftUI
import UIKit

// MARK: - Celebration Animation Manager

@MainActor
public class CelebrationAnimationManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var isShowingCelebration: Bool = false
    @Published public var currentCelebration: CelebrationAnimation?
    @Published public var celebrationQueue: [CelebrationAnimation] = []
    
    // MARK: - Celebration Types
    public enum CelebrationType {
        case achievement
        case levelUp
        case firstProject
        case projectCompleted
        case milestoneReached
        case perfectScore
        case weeklyGoal
        case socialShare
        case tutorial
        case dailyStreak
        
        public var displayName: String {
            switch self {
            case .achievement: return "Achievement Unlocked!"
            case .levelUp: return "Level Up!"
            case .firstProject: return "First Project!"
            case .projectCompleted: return "Project Completed!"
            case .milestoneReached: return "Milestone Reached!"
            case .perfectScore: return "Perfect Score!"
            case .weeklyGoal: return "Weekly Goal!"
            case .socialShare: return "Shared!"
            case .tutorial: return "Tutorial Complete!"
            case .dailyStreak: return "Daily Streak!"
            }
        }
        
        public var icon: String {
            switch self {
            case .achievement: return "trophy.fill"
            case .levelUp: return "arrow.up.circle.fill"
            case .firstProject: return "star.fill"
            case .projectCompleted: return "checkmark.circle.fill"
            case .milestoneReached: return "flag.fill"
            case .perfectScore: return "crown.fill"
            case .weeklyGoal: return "calendar.circle.fill"
            case .socialShare: return "heart.fill"
            case .tutorial: return "graduationcap.fill"
            case .dailyStreak: return "flame.fill"
            }
        }
        
        public var primaryColor: Color {
            switch self {
            case .achievement: return .yellow
            case .levelUp: return .blue
            case .firstProject: return .purple
            case .projectCompleted: return .green
            case .milestoneReached: return .orange
            case .perfectScore: return .pink
            case .weeklyGoal: return .indigo
            case .socialShare: return .red
            case .tutorial: return .cyan
            case .dailyStreak: return .orange
            }
        }
        
        public var animationStyle: AnimationStyle {
            switch self {
            case .achievement, .levelUp, .perfectScore: return .explosive
            case .firstProject, .milestoneReached: return .elegant
            case .projectCompleted, .tutorial: return .satisfying
            case .weeklyGoal, .dailyStreak: return .energetic
            case .socialShare: return .playful
            }
        }
        
        public var duration: TimeInterval {
            switch self {
            case .achievement, .levelUp, .firstProject: return 3.0
            case .perfectScore, .milestoneReached: return 2.5
            case .projectCompleted, .tutorial: return 2.0
            case .weeklyGoal, .dailyStreak, .socialShare: return 1.5
            }
        }
    }
    
    public enum AnimationStyle {
        case explosive
        case elegant
        case satisfying
        case energetic
        case playful
    }
    
    // MARK: - Private Properties
    private let soundManager = SoundEffectsManager()
    private let hapticGenerator = UINotificationFeedbackGenerator()
    
    // Animation state
    private var animationTimer: Timer?
    private var isProcessingQueue = false
    
    public init() {
        logInfo("Celebration Animation Manager initialized", category: .ui)
    }
    
    // MARK: - Public Interface
    
    public func celebrate(_ type: CelebrationType, title: String? = nil, subtitle: String? = nil, value: Int? = nil) {
        let celebration = CelebrationAnimation(
            type: type,
            title: title ?? type.displayName,
            subtitle: subtitle,
            value: value,
            timestamp: Date()
        )
        
        if isShowingCelebration {
            celebrationQueue.append(celebration)
        } else {
            showCelebration(celebration)
        }
        
        logInfo("Celebration triggered", category: .ui, context: LogContext(customData: [
            "type": type.displayName,
            "title": celebration.title
        ]))
    }
    
    private func showCelebration(_ celebration: CelebrationAnimation) {
        currentCelebration = celebration
        isShowingCelebration = true
        
        // Play sound and haptic
        playCelebrationFeedback(for: celebration.type)
        
        // Auto-hide after duration
        animationTimer = Timer.scheduledTimer(withTimeInterval: celebration.type.duration, repeats: false) { _ in
            Task { @MainActor in
                self.hideCelebration()
            }
        }
    }
    
    public func hideCelebration() {
        animationTimer?.invalidate()
        animationTimer = nil
        
        withAnimation(.easeOut(duration: 0.5)) {
            isShowingCelebration = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.currentCelebration = nil
            self.processQueue()
        }
    }
    
    private func processQueue() {
        guard !isProcessingQueue, !celebrationQueue.isEmpty else { return }
        
        isProcessingQueue = true
        let nextCelebration = celebrationQueue.removeFirst()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isProcessingQueue = false
            self.showCelebration(nextCelebration)
        }
    }
    
    private func playCelebrationFeedback(for type: CelebrationType) {
        // Play sound
        switch type {
        case .achievement, .levelUp, .perfectScore:
            soundManager.playSound(.achievement, withHaptic: false)
        case .firstProject, .milestoneReached:
            soundManager.playSound(.milestone, withHaptic: false)
        case .projectCompleted, .tutorial:
            soundManager.playSound(.celebration, withHaptic: false)
        case .weeklyGoal, .dailyStreak:
            soundManager.playSound(.levelUp, withHaptic: false)
        case .socialShare:
            soundManager.playSound(.unlock, withHaptic: false)
        }
        
        // Haptic feedback
        hapticGenerator.notificationOccurred(.success)
    }
    
    // MARK: - Convenience Methods
    
    public func celebrateAchievement(_ title: String, description: String) {
        celebrate(.achievement, title: title, subtitle: description)
    }
    
    public func celebrateLevelUp(_ newLevel: Int) {
        celebrate(.levelUp, title: "Level \(newLevel)!", subtitle: "You've leveled up!")
    }
    
    public func celebrateFirstProject() {
        celebrate(.firstProject, title: "First Project!", subtitle: "Welcome to AR creation!")
    }
    
    public func celebrateProjectCompletion(_ projectName: String) {
        celebrate(.projectCompleted, title: "Project Complete!", subtitle: projectName)
    }
    
    public func celebrateMilestone(_ milestone: String, value: Int) {
        celebrate(.milestoneReached, title: milestone, subtitle: "\(value) reached!", value: value)
    }
    
    public func celebratePerfectScore() {
        celebrate(.perfectScore, title: "Perfect!", subtitle: "Outstanding work!")
    }
    
    public func celebrateWeeklyGoal() {
        celebrate(.weeklyGoal, title: "Weekly Goal!", subtitle: "Keep up the great work!")
    }
    
    public func celebrateShare() {
        celebrate(.socialShare, title: "Shared!", subtitle: "Thanks for spreading the word!")
    }
    
    public func celebrateTutorialComplete(_ tutorialName: String) {
        celebrate(.tutorial, title: "Tutorial Complete!", subtitle: tutorialName)
    }
    
    public func celebrateDailyStreak(_ days: Int) {
        celebrate(.dailyStreak, title: "\(days) Day Streak!", subtitle: "You're on fire!", value: days)
    }
    
    // MARK: - Queue Management
    
    public func clearQueue() {
        celebrationQueue.removeAll()
    }
    
    public func getQueueCount() -> Int {
        return celebrationQueue.count
    }
}

// MARK: - Celebration Animation Data

public struct CelebrationAnimation {
    public let type: CelebrationAnimationManager.CelebrationType
    public let title: String
    public let subtitle: String?
    public let value: Int?
    public let timestamp: Date
    
    public init(type: CelebrationAnimationManager.CelebrationType, title: String, subtitle: String? = nil, value: Int? = nil, timestamp: Date = Date()) {
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.timestamp = timestamp
    }
}

// MARK: - Celebration View

struct CelebrationView: View {
    let celebration: CelebrationAnimation
    let onDismiss: () -> Void
    
    @State private var animationPhase: AnimationPhase = .initial
    @State private var particles: [ParticleData] = []
    
    enum AnimationPhase {
        case initial
        case entrance
        case celebration
        case exit
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            // Main celebration content
            switch celebration.type.animationStyle {
            case .explosive:
                ExplosiveCelebrationView(celebration: celebration, animationPhase: $animationPhase)
            case .elegant:
                ElegantCelebrationView(celebration: celebration, animationPhase: $animationPhase)
            case .satisfying:
                SatisfyingCelebrationView(celebration: celebration, animationPhase: $animationPhase)
            case .energetic:
                EnergeticCelebrationView(celebration: celebration, animationPhase: $animationPhase)
            case .playful:
                PlayfulCelebrationView(celebration: celebration, animationPhase: $animationPhase)
            }
            
            // Particle effects
            ParticleSystemView(
                particles: particles,
                style: celebration.type.animationStyle,
                color: celebration.type.primaryColor
            )
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        createParticles()
        
        withAnimation(.easeOut(duration: 0.3)) {
            animationPhase = .entrance
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animationPhase = .celebration
            }
        }
    }
    
    private func createParticles() {
        let particleCount = switch celebration.type.animationStyle {
        case .explosive: 50
        case .elegant: 25
        case .satisfying: 30
        case .energetic: 40
        case .playful: 35
        }
        
        particles = (0..<particleCount).map { _ in
            ParticleData(
                id: UUID(),
                position: CGPoint(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY),
                velocity: CGVector(
                    dx: Double.random(in: -200...200),
                    dy: Double.random(in: -300...100)
                ),
                size: CGFloat.random(in: 4...12),
                color: celebration.type.primaryColor,
                life: 1.0
            )
        }
    }
}

// MARK: - Specific Celebration Styles

struct ExplosiveCelebrationView: View {
    let celebration: CelebrationAnimation
    @Binding var animationPhase: CelebrationView.AnimationPhase
    
    @State private var iconScale: CGFloat = 0.1
    @State private var iconRotation: Double = 0
    @State private var textOffset: CGFloat = 50
    @State private var textOpacity: Double = 0
    @State private var ringScale: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 20) {
            // Main icon with explosion effect
            ZStack {
                // Explosion rings
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(celebration.type.primaryColor.opacity(0.6), lineWidth: 3)
                        .frame(width: 120 + CGFloat(index * 40))
                        .scaleEffect(ringScale)
                        .opacity(1.0 - Double(index) * 0.3)
                }
                
                // Main icon
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [celebration.type.primaryColor, celebration.type.primaryColor.opacity(0.7)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 50
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: celebration.type.primaryColor.opacity(0.5), radius: 20)
                    
                    Image(systemName: celebration.type.icon)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(iconScale)
                .rotationEffect(.degrees(iconRotation))
            }
            
            // Text content
            VStack(spacing: 8) {
                Text(celebration.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                if let subtitle = celebration.subtitle {
                    Text(subtitle)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                
                if let value = celebration.value {
                    Text("\(value)")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundColor(celebration.type.primaryColor)
                }
            }
            .offset(y: textOffset)
            .opacity(textOpacity)
        }
        .onChange(of: animationPhase) { phase in
            switch phase {
            case .entrance:
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                    iconScale = 1.2
                    iconRotation = 360
                }
                withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                    ringScale = 1.0
                }
            case .celebration:
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    iconScale = 1.0
                    textOffset = 0
                    textOpacity = 1.0
                }
            default:
                break
            }
        }
    }
}

struct ElegantCelebrationView: View {
    let celebration: CelebrationAnimation
    @Binding var animationPhase: CelebrationView.AnimationPhase
    
    @State private var contentScale: CGFloat = 0.8
    @State private var contentOpacity: Double = 0
    @State private var shimmerOffset: CGFloat = -200
    
    var body: some View {
        VStack(spacing: 24) {
            // Elegant icon presentation
            ZStack {
                // Subtle glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [celebration.type.primaryColor.opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                
                // Icon background
                Circle()
                    .fill(celebration.type.primaryColor)
                    .frame(width: 80, height: 80)
                    .overlay {
                        // Shimmer effect
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.clear, Color.white.opacity(0.6), Color.clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 30)
                            .offset(x: shimmerOffset)
                            .clipShape(Circle())
                    }
                
                Image(systemName: celebration.type.icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.white)
            }
            
            // Refined text
            VStack(spacing: 12) {
                Text(celebration.title)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                if let subtitle = celebration.subtitle {
                    Text(subtitle)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .scaleEffect(contentScale)
        .opacity(contentOpacity)
        .onChange(of: animationPhase) { phase in
            switch phase {
            case .entrance:
                withAnimation(.easeOut(duration: 0.6)) {
                    contentScale = 1.0
                    contentOpacity = 1.0
                }
                withAnimation(.linear(duration: 1.5).delay(0.3)) {
                    shimmerOffset = 200
                }
            default:
                break
            }
        }
    }
}

struct SatisfyingCelebrationView: View {
    let celebration: CelebrationAnimation
    @Binding var animationPhase: CelebrationView.AnimationPhase
    
    @State private var checkmarkScale: CGFloat = 0
    @State private var checkmarkRotation: Double = -90
    @State private var contentOffset: CGFloat = 30
    @State private var contentOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 20) {
            // Satisfying checkmark animation
            ZStack {
                Circle()
                    .fill(celebration.type.primaryColor)
                    .frame(width: 90, height: 90)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 35, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(checkmarkScale)
                    .rotationEffect(.degrees(checkmarkRotation))
            }
            
            VStack(spacing: 8) {
                Text(celebration.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                
                if let subtitle = celebration.subtitle {
                    Text(subtitle)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .offset(y: contentOffset)
            .opacity(contentOpacity)
        }
        .onChange(of: animationPhase) { phase in
            switch phase {
            case .entrance:
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.2)) {
                    checkmarkScale = 1.0
                    checkmarkRotation = 0
                }
                withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                    contentOffset = 0
                    contentOpacity = 1.0
                }
            default:
                break
            }
        }
    }
}

struct EnergeticCelebrationView: View {
    let celebration: CelebrationAnimation
    @Binding var animationPhase: CelebrationView.AnimationPhase
    
    @State private var bounceScale: CGFloat = 0.5
    @State private var bounceCount = 0
    @State private var contentOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 16) {
            // Bouncy icon
            ZStack {
                Circle()
                    .fill(celebration.type.primaryColor)
                    .frame(width: 70, height: 70)
                
                Image(systemName: celebration.type.icon)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
            .scaleEffect(bounceScale)
            
            VStack(spacing: 6) {
                Text(celebration.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                if let subtitle = celebration.subtitle {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .opacity(contentOpacity)
        }
        .onChange(of: animationPhase) { phase in
            switch phase {
            case .entrance:
                performBounceAnimation()
            default:
                break
            }
        }
    }
    
    private func performBounceAnimation() {
        let bounces: [CGFloat] = [1.3, 0.9, 1.1, 0.95, 1.0]
        
        for (index, scale) in bounces.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    bounceScale = scale
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.3)) {
                contentOpacity = 1.0
            }
        }
    }
}

struct PlayfulCelebrationView: View {
    let celebration: CelebrationAnimation
    @Binding var animationPhase: CelebrationView.AnimationPhase
    
    @State private var iconWiggle: Double = 0
    @State private var iconScale: CGFloat = 0.8
    @State private var contentOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 16) {
            // Playful wiggling icon
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(celebration.type.primaryColor)
                    .frame(width: 60, height: 60)
                
                Image(systemName: celebration.type.icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
            }
            .scaleEffect(iconScale)
            .rotationEffect(.degrees(iconWiggle))
            
            VStack(spacing: 4) {
                Text(celebration.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                if let subtitle = celebration.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .opacity(contentOpacity)
        }
        .onChange(of: animationPhase) { phase in
            switch phase {
            case .entrance:
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    iconScale = 1.0
                }
                withAnimation(.easeInOut(duration: 0.2).repeatCount(3, autoreverses: true).delay(0.2)) {
                    iconWiggle = 15
                }
                withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
                    contentOpacity = 1.0
                }
            default:
                break
            }
        }
    }
}

// MARK: - Particle System

struct ParticleData: Identifiable {
    let id: UUID
    var position: CGPoint
    var velocity: CGVector
    var size: CGFloat
    var color: Color
    var life: Double
}

struct ParticleSystemView: View {
    @State var particles: [ParticleData]
    let style: CelebrationAnimationManager.AnimationStyle
    let color: Color
    
    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color.opacity(particle.life))
                    .frame(width: particle.size, height: particle.size)
                    .position(particle.position)
            }
        }
        .onAppear {
            startParticleSystem()
        }
    }
    
    private func startParticleSystem() {
        Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { timer in
            updateParticles()
            
            if particles.allSatisfy({ $0.life <= 0 }) {
                timer.invalidate()
            }
        }
    }
    
    private func updateParticles() {
        for index in particles.indices {
            particles[index].position.x += particles[index].velocity.dx / 60
            particles[index].position.y += particles[index].velocity.dy / 60
            particles[index].velocity.dy += 200 / 60 // Gravity
            particles[index].life -= 1.0 / 60
        }
    }
}

// MARK: - Preview

struct CelebrationView_Previews: PreviewProvider {
    static var previews: some View {
        CelebrationView(
            celebration: CelebrationAnimation(
                type: .achievement,
                title: "Achievement Unlocked!",
                subtitle: "First AR Object Placed"
            ),
            onDismiss: {}
        )
    }
}