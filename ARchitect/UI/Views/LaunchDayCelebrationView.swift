import SwiftUI

struct LaunchDayCelebrationView: View {
    @StateObject private var launchManager = LaunchDayManager.shared
    @State private var showingConfetti = false
    @State private var animateElements = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            backgroundGradient
            
            VStack(spacing: 32) {
                Spacer()
                
                celebrationHeader
                
                featuresGrid
                
                actionButtons
                
                Spacer()
            }
            .padding()
            .opacity(animateElements ? 1 : 0)
            .scaleEffect(animateElements ? 1 : 0.8)
            .animation(.spring(response: 0.8, dampingFraction: 0.6), value: animateElements)
            
            if showingConfetti {
                ConfettiView()
            }
        }
        .onAppear {
            startCelebrationAnimation()
        }
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.blue.opacity(0.8),
                Color.purple.opacity(0.6),
                Color.pink.opacity(0.4)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    private var celebrationHeader: some View {
        VStack(spacing: 16) {
            Text("🚀")
                .font(.system(size: 80))
                .scaleEffect(animateElements ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animateElements)
            
            Text("Welcome to ARchitect!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text("Launch Week Exclusive Features")
                .font(.title2)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
            
            if launchManager.isFirstDay() {
                Text("🎉 Day 1 - You're among the first!")
                    .font(.headline)
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Capsule())
            } else {
                Text("Only \(launchManager.getDaysRemainingInLaunchWeek()) days left!")
                    .font(.headline)
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
    }
    
    private var featuresGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            ForEach(Array(launchManager.launchDayFeatures.prefix(4).enumerated()), id: \.element.id) { index, feature in
                LaunchFeatureCard(feature: feature)
                    .opacity(animateElements ? 1 : 0)
                    .offset(y: animateElements ? 0 : 20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(index) * 0.1), value: animateElements)
            }
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 16) {
            Button(action: {
                startExploring()
            }) {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Start Exploring")
                }
                .font(.headline)
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            
            Button(action: {
                shareApp()
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share the Launch")
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private func startCelebrationAnimation() {
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.3)) {
            animateElements = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showingConfetti = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            showingConfetti = false
        }
    }
    
    private func startExploring() {
        launchManager.markLaunchCelebrationSeen()
        dismiss()
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func shareApp() {
        let shareText = launchManager.getLaunchShareMessage()
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        
        let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        window.rootViewController?.present(activityVC, animated: true)
    }
}

struct LaunchFeatureCard: View {
    let feature: LaunchDayManager.LaunchFeature
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: feature.iconName)
                .font(.system(size: 32))
                .foregroundColor(.white)
            
            Text(feature.title)
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            if feature.isUnlocked {
                Text("UNLOCKED")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule())
            }
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }
}

struct ConfettiView: View {
    @State private var confettiPieces: [ConfettiPiece] = []
    
    var body: some View {
        ZStack {
            ForEach(confettiPieces) { piece in
                Rectangle()
                    .fill(piece.color)
                    .frame(width: piece.size, height: piece.size)
                    .rotationEffect(.degrees(piece.rotation))
                    .position(x: piece.x, y: piece.y)
                    .opacity(piece.opacity)
            }
        }
        .onAppear {
            createConfetti()
        }
    }
    
    private func createConfetti() {
        let colors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange, .pink]
        
        for _ in 0..<50 {
            let piece = ConfettiPiece(
                id: UUID(),
                x: Double.random(in: 0...UIScreen.main.bounds.width),
                y: -20,
                size: Double.random(in: 4...12),
                color: colors.randomElement() ?? .blue,
                rotation: Double.random(in: 0...360),
                opacity: 1.0
            )
            confettiPieces.append(piece)
        }
        
        animateConfetti()
    }
    
    private func animateConfetti() {
        withAnimation(.linear(duration: 3.0)) {
            for index in confettiPieces.indices {
                confettiPieces[index].y = UIScreen.main.bounds.height + 50
                confettiPieces[index].rotation += Double.random(in: 180...540)
                confettiPieces[index].opacity = 0.0
            }
        }
    }
}

struct ConfettiPiece: Identifiable {
    let id: UUID
    var x: Double
    var y: Double
    let size: Double
    let color: Color
    var rotation: Double
    var opacity: Double
}

#Preview {
    LaunchDayCelebrationView()
}