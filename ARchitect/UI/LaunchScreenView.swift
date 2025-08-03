import SwiftUI
import RealityKit
import ARKit

// MARK: - Launch Screen View

struct LaunchScreenView: View {
    @StateObject private var launchManager = LaunchScreenManager()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Dynamic Background
            LaunchBackground(colorScheme: colorScheme)
                .ignoresSafeArea()
            
            // Main Content
            VStack(spacing: 40) {
                Spacer()
                
                // App Icon with AR Animation
                LaunchIconView(animationPhase: launchManager.animationPhase)
                
                // App Title
                LaunchTitleView(animationPhase: launchManager.animationPhase)
                
                Spacer()
                
                // Loading Progress
                LaunchProgressView(
                    progress: launchManager.loadingProgress,
                    animationPhase: launchManager.animationPhase
                )
                
                Spacer(minLength: 60)
            }
            .padding()
        }
        .onAppear {
            launchManager.startLaunchSequence()
        }
    }
}

// MARK: - Launch Screen Manager

@MainActor
class LaunchScreenManager: ObservableObject {
    @Published var animationPhase: LaunchAnimationPhase = .initial
    @Published var loadingProgress: Double = 0.0
    @Published var isComplete: Bool = false
    
    enum LaunchAnimationPhase {
        case initial
        case iconAppear
        case titleAppear
        case arEffects
        case complete
    }
    
    private var loadingTasks: [String] = [
        "Initializing AR Session...",
        "Loading 3D Models...",
        "Setting up Camera...",
        "Preparing UI...",
        "Optimizing Performance...",
        "Ready to Create!"
    ]
    
    private var currentTaskIndex = 0
    
    func startLaunchSequence() {
        Task {
            await performLaunchAnimation()
        }
    }
    
    private func performLaunchAnimation() async {
        // Phase 1: Icon Appear
        await MainActor.run {
            withAnimation(.spring(response: 1.2, dampingFraction: 0.8)) {
                animationPhase = .iconAppear
            }
        }
        
        await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
        
        // Phase 2: Title Appear
        await MainActor.run {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animationPhase = .titleAppear
            }
        }
        
        await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds
        
        // Phase 3: AR Effects and Loading
        await MainActor.run {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                animationPhase = .arEffects
            }
        }
        
        // Simulate loading tasks
        await performLoadingSequence()
        
        // Phase 4: Complete
        await MainActor.run {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                animationPhase = .complete
                isComplete = true
            }
        }
        
        await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Trigger main app transition
        NotificationCenter.default.post(name: .launchComplete, object: nil)
    }
    
    private func performLoadingSequence() async {
        for (index, task) in loadingTasks.enumerated() {
            await MainActor.run {
                currentTaskIndex = index
            }
            
            // Simulate task execution time
            let duration = Double.random(in: 0.3...0.8)
            let steps = Int(duration * 60) // 60 FPS
            
            for step in 0...steps {
                await MainActor.run {
                    let taskProgress = Double(step) / Double(steps)
                    let overallProgress = (Double(index) + taskProgress) / Double(loadingTasks.count)
                    loadingProgress = overallProgress
                }
                
                await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000 / Double(steps)))
            }
        }
    }
}

// MARK: - Launch Background

struct LaunchBackground: View {
    let colorScheme: ColorScheme
    @State private var animateGradient = false
    
    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Animated overlay
            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.3),
                    Color.clear
                ],
                center: animateGradient ? .topTrailing : .bottomLeading,
                startRadius: 0,
                endRadius: 500
            )
            .animation(
                .easeInOut(duration: 3.0)
                .repeatForever(autoreverses: true),
                value: animateGradient
            )
            
            // Particle effect
            ParticleField()
        }
        .onAppear {
            animateGradient = true
        }
    }
    
    private var backgroundColors: [Color] {
        switch colorScheme {
        case .dark:
            return [Color(red: 0.05, green: 0.05, blue: 0.15), Color(red: 0.1, green: 0.1, blue: 0.2)]
        case .light:
            return [Color(red: 0.95, green: 0.95, blue: 1.0), Color(red: 0.9, green: 0.9, blue: 0.95)]
        @unknown default:
            return [Color.blue.opacity(0.1), Color.purple.opacity(0.1)]
        }
    }
}

// MARK: - Launch Icon View

struct LaunchIconView: View {
    let animationPhase: LaunchScreenManager.LaunchAnimationPhase
    @State private var rotationAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var hologramOpacity: Double = 0.0
    
    var body: some View {
        ZStack {
            // Holographic ring effect
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(
                        Color.accentColor.opacity(0.6),
                        lineWidth: 2
                    )
                    .frame(width: 120 + CGFloat(index * 20))
                    .opacity(hologramOpacity)
                    .rotationEffect(.degrees(rotationAngle + Double(index * 45)))
                    .animation(
                        .linear(duration: 3.0)
                        .repeatForever(autoreverses: false),
                        value: rotationAngle
                    )
            }
            
            // Main app icon
            ZStack {
                // Icon background with glow
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.accentColor.opacity(0.5), radius: 20, x: 0, y: 0)
                
                // AR Symbol
                Image(systemName: "arkit")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(rotationAngle * 0.5))
                
                // Scanning lines effect
                if animationPhase == .arEffects || animationPhase == .complete {
                    VStack(spacing: 4) {
                        ForEach(0..<8, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 1)
                        }
                    }
                    .frame(width: 80)
                    .opacity(0.7)
                    .animation(
                        .easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true),
                        value: animationPhase
                    )
                }
            }
            .scaleEffect(iconScale)
            .opacity(iconOpacity)
            .scaleEffect(pulseScale)
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseScale)
        }
        .onAppear {
            startIconAnimations()
        }
        .onChange(of: animationPhase) { phase in
            updateAnimationForPhase(phase)
        }
    }
    
    private var iconScale: CGFloat {
        switch animationPhase {
        case .initial: return 0.1
        case .iconAppear, .titleAppear, .arEffects, .complete: return 1.0
        }
    }
    
    private var iconOpacity: Double {
        switch animationPhase {
        case .initial: return 0.0
        case .iconAppear, .titleAppear, .arEffects, .complete: return 1.0
        }
    }
    
    private func startIconAnimations() {
        withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
        
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.05
        }
    }
    
    private func updateAnimationForPhase(_ phase: LaunchScreenManager.LaunchAnimationPhase) {
        switch phase {
        case .arEffects, .complete:
            withAnimation(.easeInOut(duration: 0.8)) {
                hologramOpacity = 1.0
            }
        default:
            break
        }
    }
}

// MARK: - Launch Title View

struct LaunchTitleView: View {
    let animationPhase: LaunchScreenManager.LaunchAnimationPhase
    @State private var letterAnimations: [Bool] = Array(repeating: false, count: 9) // "ARchitect"
    
    var body: some View {
        VStack(spacing: 8) {
            // Main title with letter-by-letter animation
            HStack(spacing: 2) {
                ForEach(Array("ARchitect".enumerated()), id: \.offset) { index, letter in
                    Text(String(letter))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.primary, Color.accentColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(letterAnimations[index] ? 1.0 : 0.5)
                        .opacity(letterAnimations[index] ? 1.0 : 0.0)
                        .offset(y: letterAnimations[index] ? 0 : 20)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.7)
                            .delay(Double(index) * 0.1),
                            value: letterAnimations[index]
                        )
                }
            }
            
            // Subtitle
            Text("Augmented Reality Designer")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .opacity(subtitleOpacity)
                .offset(y: subtitleOffset)
        }
        .onChange(of: animationPhase) { phase in
            updateTitleAnimation(for: phase)
        }
    }
    
    private var subtitleOpacity: Double {
        switch animationPhase {
        case .initial, .iconAppear: return 0.0
        case .titleAppear, .arEffects, .complete: return 1.0
        }
    }
    
    private var subtitleOffset: CGFloat {
        switch animationPhase {
        case .initial, .iconAppear: return 20
        case .titleAppear, .arEffects, .complete: return 0
        }
    }
    
    private func updateTitleAnimation(for phase: LaunchScreenManager.LaunchAnimationPhase) {
        if phase == .titleAppear || phase == .arEffects || phase == .complete {
            for i in 0..<letterAnimations.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                    letterAnimations[i] = true
                }
            }
        }
    }
}

// MARK: - Launch Progress View

struct LaunchProgressView: View {
    let progress: Double
    let animationPhase: LaunchScreenManager.LaunchAnimationPhase
    
    var body: some View {
        VStack(spacing: 16) {
            // Progress bar
            VStack(spacing: 8) {
                HStack {
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 8)
                        
                        // Progress
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progress, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: progress)
                        
                        // Shimmer effect
                        if progress > 0 && progress < 1 {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.clear,
                                            Color.white.opacity(0.6),
                                            Color.clear
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 30, height: 8)
                                .offset(x: (geometry.size.width * progress) - 15)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                .frame(height: 8)
            }
            
            // Version info
            Text("Version 1.0")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .opacity(progressOpacity)
        .offset(y: progressOffset)
    }
    
    private var progressOpacity: Double {
        switch animationPhase {
        case .initial, .iconAppear, .titleAppear: return 0.0
        case .arEffects: return 1.0
        case .complete: return 0.0
        }
    }
    
    private var progressOffset: CGFloat {
        switch animationPhase {
        case .initial, .iconAppear, .titleAppear: return 20
        case .arEffects: return 0
        case .complete: return -20
        }
    }
}

// MARK: - Particle Field

struct ParticleField: View {
    @State private var particles: [Particle] = []
    
    var body: some View {
        ZStack {
            ForEach(particles.indices, id: \.self) { index in
                Circle()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: particles[index].size, height: particles[index].size)
                    .position(particles[index].position)
                    .opacity(particles[index].opacity)
                    .animation(.linear(duration: particles[index].duration), value: particles[index].position)
            }
        }
        .onAppear {
            createParticles()
            startParticleAnimation()
        }
    }
    
    private func createParticles() {
        particles = (0..<20).map { _ in
            Particle(
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                ),
                size: CGFloat.random(in: 2...6),
                duration: Double.random(in: 2...5),
                opacity: Double.random(in: 0.2...0.6)
            )
        }
    }
    
    private func startParticleAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateParticles()
        }
    }
    
    private func updateParticles() {
        for index in particles.indices {
            particles[index].position.x += CGFloat.random(in: -1...1)
            particles[index].position.y += CGFloat.random(in: -1...1)
            
            // Wrap around screen
            if particles[index].position.x < 0 {
                particles[index].position.x = UIScreen.main.bounds.width
            } else if particles[index].position.x > UIScreen.main.bounds.width {
                particles[index].position.x = 0
            }
            
            if particles[index].position.y < 0 {
                particles[index].position.y = UIScreen.main.bounds.height
            } else if particles[index].position.y > UIScreen.main.bounds.height {
                particles[index].position.y = 0
            }
        }
    }
}

struct Particle {
    var position: CGPoint
    let size: CGFloat
    let duration: Double
    let opacity: Double
}

// MARK: - Notification Extension

extension Notification.Name {
    static let launchComplete = Notification.Name("launchComplete")
}

// MARK: - Preview

struct LaunchScreenView_Previews: PreviewProvider {
    static var previews: some View {
        LaunchScreenView()
            .preferredColorScheme(.dark)
        
        LaunchScreenView()
            .preferredColorScheme(.light)
    }
}