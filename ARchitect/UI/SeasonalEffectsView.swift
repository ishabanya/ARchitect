import SwiftUI

// MARK: - Seasonal Effects View

struct SeasonalEffectsView: View {
    @StateObject private var themeManager = SeasonalThemeManager()
    @Environment(\.colorScheme) var colorScheme
    
    @State private var animateParticles = false
    @State private var particlePositions: [CGPoint] = []
    
    var body: some View {
        ZStack {
            // Background gradient
            themeManager.getBackgroundGradient()
                .ignoresSafeArea()
                .opacity(0.3)
            
            // Seasonal particles
            if themeManager.isSeasonalThemeEnabled {
                ForEach(Array(themeManager.getSeasonalParticles().enumerated()), id: \.offset) { index, particle in
                    ParticleView(
                        particle: particle,
                        position: particlePositions.indices.contains(index) ? particlePositions[index] : .zero,
                        animate: animateParticles
                    )
                }
            }
            
            // Special effects overlay
            specialEffectsOverlay
        }
        .onAppear {
            setupParticlePositions()
            startParticleAnimation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .seasonChanged)) { _ in
            refreshEffects()
        }
    }
    
    // MARK: - Special Effects Overlay
    
    @ViewBuilder
    private var specialEffectsOverlay: some View {
        ForEach(themeManager.getSpecialEffects(), id: \.rawValue) { effect in
            SpecialEffectView(effect: effect, season: themeManager.currentSeason)
        }
    }
    
    // MARK: - Animation Setup
    
    private func setupParticlePositions() {
        let particles = themeManager.getSeasonalParticles()
        particlePositions = (0..<particles.count * 15).map { _ in
            CGPoint(
                x: CGFloat.random(in: -50...UIScreen.main.bounds.width + 50),
                y: CGFloat.random(in: -50...UIScreen.main.bounds.height + 50)
            )
        }
    }
    
    private func startParticleAnimation() {
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            animateParticles = true
        }
    }
    
    private func refreshEffects() {
        setupParticlePositions()
        animateParticles = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            startParticleAnimation()
        }
    }
}

// MARK: - Particle View

struct ParticleView: View {
    let particle: SeasonalThemeManager.SeasonalParticle
    let position: CGPoint
    let animate: Bool
    
    @State private var currentPosition: CGPoint = .zero
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    
    var body: some View {
        Image(systemName: particle.type.systemImage)
            .font(.system(size: particle.size))
            .foregroundColor(particle.color)
            .position(currentPosition)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                currentPosition = position
                startParticleAnimation()
            }
            .onChange(of: animate) { shouldAnimate in
                if shouldAnimate {
                    startParticleAnimation()
                }
            }
    }
    
    private func startParticleAnimation() {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        // Movement animation
        withAnimation(.linear(duration: Double.random(in: 8...15)).repeatForever(autoreverses: false)) {
            currentPosition = CGPoint(
                x: currentPosition.x + CGFloat.random(in: -100...100),
                y: currentPosition.y + screenHeight + 100
            )
        }
        
        // Rotation animation
        withAnimation(.linear(duration: Double.random(in: 3...8)).repeatForever(autoreverses: false)) {
            rotation = 360
        }
        
        // Scale pulsing
        withAnimation(.easeInOut(duration: Double.random(in: 2...4)).repeatForever(autoreverses: true)) {
            scale = CGFloat.random(in: 0.8...1.2)
        }
        
        // Opacity flickering for certain particle types
        if [.firefly, .sparkle, .star].contains(particle.type) {
            withAnimation(.easeInOut(duration: Double.random(in: 1...3)).repeatForever(autoreverses: true)) {
                opacity = Double.random(in: 0.3...1.0)
            }
        }
    }
}

// MARK: - Special Effect View

struct SpecialEffectView: View {
    let effect: SeasonalThemeManager.SpecialEffect
    let season: SeasonalThemeManager.Season
    
    var body: some View {
        switch effect {
        case .snowfall:
            SnowfallEffect()
        case .petalsFloating:
            PetalsFloatingEffect()
        case .heartsFloating:
            HeartsFloatingEffect()
        case .leavesfalling:
            LeavesFallingEffect()
        case .fireworks:
            FireworksEffect()
        case .sparkles:
            SparklesEffect()
        case .rainbowGlow:
            RainbowGlowEffect()
        case .sunbeams:
            SunbeamsEffect()
        case .spookyFog:
            SpookyFogEffect()
        case .magicalSnow:
            MagicalSnowEffect()
        case .twinkling:
            TwinklingEffect()
        default:
            GenericEffect(effect: effect, season: season)
        }
    }
}

// MARK: - Specific Effect Implementations

struct SnowfallEffect: View {
    @State private var snowflakes: [SnowflakeData] = []
    
    var body: some View {
        ZStack {
            ForEach(snowflakes, id: \.id) { snowflake in
                Image(systemName: "snowflake")
                    .font(.system(size: snowflake.size))
                    .foregroundColor(.white.opacity(snowflake.opacity))
                    .position(snowflake.position)
                    .rotationEffect(.degrees(snowflake.rotation))
            }
        }
        .onAppear {
            createSnowflakes()
            animateSnowfall()
        }
    }
    
    private func createSnowflakes() {
        snowflakes = (0..<30).map { _ in
            SnowflakeData(
                id: UUID(),
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: -20
                ),
                size: CGFloat.random(in: 8...16),
                opacity: Double.random(in: 0.3...0.8),
                rotation: Double.random(in: 0...360)
            )
        }
    }
    
    private func animateSnowfall() {
        Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { timer in
            for index in snowflakes.indices {
                snowflakes[index].position.y += CGFloat.random(in: 1...3)
                snowflakes[index].position.x += CGFloat.random(in: -0.5...0.5)
                snowflakes[index].rotation += Double.random(in: -2...2)
                
                if snowflakes[index].position.y > UIScreen.main.bounds.height + 20 {
                    snowflakes[index].position.y = -20
                    snowflakes[index].position.x = CGFloat.random(in: 0...UIScreen.main.bounds.width)
                }
            }
        }
    }
}

struct PetalsFloatingEffect: View {
    @State private var petals: [PetalData] = []
    
    var body: some View {
        ZStack {
            ForEach(petals, id: \.id) { petal in
                Image(systemName: "leaf.fill")
                    .font(.system(size: petal.size))
                    .foregroundColor(.pink.opacity(petal.opacity))
                    .position(petal.position)
                    .rotationEffect(.degrees(petal.rotation))
            }
        }
        .onAppear {
            createPetals()
            animatePetals()
        }
    }
    
    private func createPetals() {
        petals = (0..<20).map { _ in
            PetalData(
                id: UUID(),
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: -20
                ),
                size: CGFloat.random(in: 10...18),
                opacity: Double.random(in: 0.4...0.8),
                rotation: Double.random(in: 0...360)
            )
        }
    }
    
    private func animatePetals() {
        Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { timer in
            for index in petals.indices {
                petals[index].position.y += CGFloat.random(in: 0.5...2)
                petals[index].position.x += sin(petals[index].position.y / 30) * 2
                petals[index].rotation += Double.random(in: -3...3)
                
                if petals[index].position.y > UIScreen.main.bounds.height + 20 {
                    petals[index].position.y = -20
                    petals[index].position.x = CGFloat.random(in: 0...UIScreen.main.bounds.width)
                }
            }
        }
    }
}

struct HeartsFloatingEffect: View {
    @State private var hearts: [HeartData] = []
    
    var body: some View {
        ZStack {
            ForEach(hearts, id: \.id) { heart in
                Image(systemName: "heart.fill")
                    .font(.system(size: heart.size))
                    .foregroundColor(.pink.opacity(heart.opacity))
                    .position(heart.position)
                    .scaleEffect(heart.scale)
            }
        }
        .onAppear {
            createHearts()
            animateHearts()
        }
    }
    
    private func createHearts() {
        hearts = (0..<15).map { _ in
            HeartData(
                id: UUID(),
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: UIScreen.main.bounds.height + 20
                ),
                size: CGFloat.random(in: 12...20),
                opacity: Double.random(in: 0.5...0.9),
                scale: CGFloat.random(in: 0.8...1.2)
            )
        }
    }
    
    private func animateHearts() {
        Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { timer in
            for index in hearts.indices {
                hearts[index].position.y -= CGFloat.random(in: 1...3)
                hearts[index].position.x += sin(hearts[index].position.y / 40) * 1.5
                hearts[index].scale = CGFloat.random(in: 0.8...1.2)
                
                if hearts[index].position.y < -20 {
                    hearts[index].position.y = UIScreen.main.bounds.height + 20
                    hearts[index].position.x = CGFloat.random(in: 0...UIScreen.main.bounds.width)
                }
            }
        }
    }
}

struct LeavesFallingEffect: View {
    @State private var leaves: [LeafData] = []
    
    var body: some View {
        ZStack {
            ForEach(leaves, id: \.id) { leaf in
                Image(systemName: "leaf.fill")
                    .font(.system(size: leaf.size))
                    .foregroundColor(leaf.color.opacity(leaf.opacity))
                    .position(leaf.position)
                    .rotationEffect(.degrees(leaf.rotation))
            }
        }
        .onAppear {
            createLeaves()
            animateLeaves()
        }
    }
    
    private func createLeaves() {
        let autumnColors: [Color] = [.orange, .red, .yellow, .brown]
        
        leaves = (0..<25).map { _ in
            LeafData(
                id: UUID(),
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: -20
                ),
                size: CGFloat.random(in: 12...20),
                opacity: Double.random(in: 0.6...0.9),
                rotation: Double.random(in: 0...360),
                color: autumnColors.randomElement() ?? .orange
            )
        }
    }
    
    private func animateLeaves() {
        Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { timer in
            for index in leaves.indices {
                leaves[index].position.y += CGFloat.random(in: 1...4)
                leaves[index].position.x += sin(leaves[index].position.y / 25) * 3
                leaves[index].rotation += Double.random(in: -5...5)
                
                if leaves[index].position.y > UIScreen.main.bounds.height + 20 {
                    leaves[index].position.y = -20
                    leaves[index].position.x = CGFloat.random(in: 0...UIScreen.main.bounds.width)
                }
            }
        }
    }
}

struct FireworksEffect: View {
    @State private var fireworks: [FireworkData] = []
    @State private var sparkles: [SparkleData] = []
    
    var body: some View {
        ZStack {
            ForEach(fireworks, id: \.id) { firework in
                Circle()
                    .fill(firework.color)
                    .frame(width: firework.size, height: firework.size)
                    .position(firework.position)
                    .opacity(firework.opacity)
                    .scaleEffect(firework.scale)
            }
            
            ForEach(sparkles, id: \.id) { sparkle in
                Image(systemName: "sparkles")
                    .font(.system(size: sparkle.size))
                    .foregroundColor(sparkle.color.opacity(sparkle.opacity))
                    .position(sparkle.position)
            }
        }
        .onAppear {
            triggerFirework()
        }
    }
    
    private func triggerFirework() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            createFirework()
        }
    }
    
    private func createFirework() {
        let colors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange, .pink]
        let centerPoint = CGPoint(
            x: CGFloat.random(in: 100...UIScreen.main.bounds.width - 100),
            y: CGFloat.random(in: 100...UIScreen.main.bounds.height - 200)
        )
        
        // Main explosion
        let firework = FireworkData(
            id: UUID(),
            position: centerPoint,
            size: 5,
            opacity: 1.0,
            scale: 1.0,
            color: colors.randomElement() ?? .red
        )
        
        fireworks.append(firework)
        
        withAnimation(.easeOut(duration: 1.0)) {
            if let index = fireworks.firstIndex(where: { $0.id == firework.id }) {
                fireworks[index].scale = 20
                fireworks[index].opacity = 0
            }
        }
        
        // Sparkles
        for _ in 0..<20 {
            let sparkle = SparkleData(
                id: UUID(),
                position: centerPoint,
                size: CGFloat.random(in: 8...16),
                opacity: 1.0,
                color: colors.randomElement() ?? .yellow
            )
            
            sparkles.append(sparkle)
            
            withAnimation(.easeOut(duration: 1.5)) {
                if let index = sparkles.firstIndex(where: { $0.id == sparkle.id }) {
                    sparkles[index].position = CGPoint(
                        x: centerPoint.x + CGFloat.random(in: -150...150),
                        y: centerPoint.y + CGFloat.random(in: -150...150)
                    )
                    sparkles[index].opacity = 0
                }
            }
        }
        
        // Cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            fireworks.removeAll { $0.opacity <= 0 }
            sparkles.removeAll { $0.opacity <= 0 }
        }
    }
}

struct SparklesEffect: View {
    @State private var sparkles: [SparkleData] = []
    
    var body: some View {
        ZStack {
            ForEach(sparkles, id: \.id) { sparkle in
                Image(systemName: "sparkles")
                    .font(.system(size: sparkle.size))
                    .foregroundColor(sparkle.color.opacity(sparkle.opacity))
                    .position(sparkle.position)
            }
        }
        .onAppear {
            createContinuousSparkles()
        }
    }
    
    private func createContinuousSparkles() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            let sparkle = SparkleData(
                id: UUID(),
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                ),
                size: CGFloat.random(in: 10...20),
                opacity: 1.0,
                color: [.yellow, .white, .cyan, .pink].randomElement() ?? .yellow
            )
            
            sparkles.append(sparkle)
            
            withAnimation(.easeInOut(duration: 2.0)) {
                if let index = sparkles.firstIndex(where: { $0.id == sparkle.id }) {
                    sparkles[index].opacity = 0
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                sparkles.removeAll { $0.opacity <= 0 }
            }
        }
    }
}

// MARK: - Generic and Simple Effects

struct RainbowGlowEffect: View {
    @State private var hueRotation: Double = 0
    
    var body: some View {
        Rectangle()
            .fill(.clear)
            .background(
                LinearGradient(
                    colors: [.red, .orange, .yellow, .green, .blue, .purple].map { $0.opacity(0.1) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .hueRotation(.degrees(hueRotation))
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    hueRotation = 360
                }
            }
    }
}

struct SunbeamsEffect: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.yellow.opacity(0.1), .clear],
                            startPoint: .center,
                            endPoint: .leading
                        )
                    )
                    .frame(width: 300, height: 4)
                    .offset(x: 150)
                    .rotationEffect(.degrees(Double(index) * 45 + rotation))
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

struct SpookyFogEffect: View {
    @State private var fogOffset: CGFloat = 0
    
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Ellipse()
                    .fill(.gray.opacity(0.2))
                    .frame(width: 200, height: 60)
                    .offset(x: fogOffset + CGFloat(index * 100), y: CGFloat(index * 50))
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                fogOffset = 100
            }
        }
    }
}

struct MagicalSnowEffect: View {
    @State private var twinkle: Bool = false
    
    var body: some View {
        ZStack {
            ForEach(0..<20, id: \.self) { index in
                Image(systemName: "sparkles")
                    .font(.system(size: CGFloat.random(in: 8...16)))
                    .foregroundColor(.white.opacity(twinkle ? 0.2 : 0.8))
                    .position(
                        x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                        y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                    )
                    .animation(
                        .easeInOut(duration: Double.random(in: 1...3))
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                        value: twinkle
                    )
            }
        }
        .onAppear {
            twinkle = true
        }
    }
}

struct TwinklingEffect: View {
    @State private var stars: [StarData] = []
    
    var body: some View {
        ZStack {
            ForEach(stars, id: \.id) { star in
                Image(systemName: "star.fill")
                    .font(.system(size: star.size))
                    .foregroundColor(.yellow.opacity(star.opacity))
                    .position(star.position)
                    .scaleEffect(star.scale)
            }
        }
        .onAppear {
            createTwinklingStars()
        }
    }
    
    private func createTwinklingStars() {
        stars = (0..<15).map { _ in
            StarData(
                id: UUID(),
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                ),
                size: CGFloat.random(in: 10...18),
                opacity: Double.random(in: 0.3...1.0),
                scale: CGFloat.random(in: 0.5...1.5)
            )
        }
        
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            for index in stars.indices {
                withAnimation(.easeInOut(duration: Double.random(in: 0.5...2.0))) {
                    stars[index].opacity = Double.random(in: 0.2...1.0)
                    stars[index].scale = CGFloat.random(in: 0.5...1.5)
                }
            }
        }
    }
}

struct GenericEffect: View {
    let effect: SeasonalThemeManager.SpecialEffect
    let season: SeasonalThemeManager.Season
    
    var body: some View {
        Text("🌟")
            .font(.title)
            .opacity(0.3)
            .scaleEffect(1.5)
    }
}

// MARK: - Data Structures

struct SnowflakeData: Identifiable {
    let id: UUID
    var position: CGPoint
    let size: CGFloat
    let opacity: Double
    var rotation: Double
}

struct PetalData: Identifiable {
    let id: UUID
    var position: CGPoint
    let size: CGFloat
    let opacity: Double
    var rotation: Double
}

struct HeartData: Identifiable {
    let id: UUID
    var position: CGPoint
    let size: CGFloat
    let opacity: Double
    var scale: CGFloat
}

struct LeafData: Identifiable {
    let id: UUID
    var position: CGPoint
    let size: CGFloat
    let opacity: Double
    var rotation: Double
    let color: Color
}

struct FireworkData: Identifiable {
    let id: UUID
    var position: CGPoint
    var size: CGFloat
    var opacity: Double
    var scale: CGFloat
    let color: Color
}

struct SparkleData: Identifiable {
    let id: UUID
    var position: CGPoint
    let size: CGFloat
    var opacity: Double
    let color: Color
}

struct StarData: Identifiable {
    let id: UUID
    let position: CGPoint
    let size: CGFloat
    var opacity: Double
    var scale: CGFloat
}

// MARK: - Preview

struct SeasonalEffectsView_Previews: PreviewProvider {
    static var previews: some View {
        SeasonalEffectsView()
    }
}