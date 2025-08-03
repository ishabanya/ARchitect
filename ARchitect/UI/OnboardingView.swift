import SwiftUI
import ARKit

// MARK: - Onboarding View

struct OnboardingView: View {
    @StateObject private var onboardingManager = OnboardingManager()
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingPermissionDialog = false
    @State private var animateContent = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                backgroundView
                
                // Main Content
                VStack(spacing: 0) {
                    // Progress Bar
                    progressBar
                    
                    // Step Content
                    TabView(selection: $onboardingManager.currentStep) {
                        ForEach(OnboardingManager.OnboardingStep.allCases, id: \.rawValue) { step in
                            stepView(for: step, geometry: geometry)
                                .tag(step)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.5), value: onboardingManager.currentStep)
                    
                    // Navigation Controls
                    navigationControls
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8)) {
                animateContent = true
            }
        }
        .onChange(of: onboardingManager.isOnboardingComplete) { isComplete in
            if isComplete {
                dismiss()
            }
        }
    }
    
    // MARK: - Background View
    
    private var backgroundView: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.3),
                    Color.purple.opacity(0.4),
                    Color.pink.opacity(0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Animated particles
            if animateContent {
                ParticleAnimationView()
            }
        }
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Step \(onboardingManager.currentStep.rawValue + 1) of \(OnboardingManager.OnboardingStep.allCases.count)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                Button("Skip") {
                    onboardingManager.skipOnboarding()
                }
                .font(.caption)
                .foregroundColor(.white)
            }
            .padding(.horizontal)
            
            ProgressView(value: onboardingManager.tutorialProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .white))
                .background(Color.white.opacity(0.3))
                .clipShape(Capsule())
                .padding(.horizontal)
        }
        .padding(.top)
    }
    
    // MARK: - Step Views
    
    @ViewBuilder
    private func stepView(for step: OnboardingManager.OnboardingStep, geometry: GeometryProxy) -> some View {
        switch step {
        case .welcome:
            WelcomeStepView()
        case .permissions:
            PermissionsStepView(onRequestPermission: {
                showingPermissionDialog = true
            })
        case .arIntroduction:
            ARIntroductionStepView()
        case .firstPlacement:
            FirstPlacementStepView()
        case .navigation:
            NavigationStepView()
        case .customization:
            CustomizationStepView()
        case .sharing:
            SharingStepView()
        case .completion:
            CompletionStepView()
        }
    }
    
    // MARK: - Navigation Controls
    
    private var navigationControls: some View {
        HStack {
            // Previous Button
            Button("Previous") {
                onboardingManager.previousStep()
            }
            .disabled(onboardingManager.currentStep == .welcome)
            .opacity(onboardingManager.currentStep == .welcome ? 0.5 : 1.0)
            
            Spacer()
            
            // Skip Current Step
            if onboardingManager.currentStep.isInteractive {
                Button("Skip Step") {
                    onboardingManager.skipStep()
                }
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            // Next Button
            Button(onboardingManager.currentStep == .completion ? "Get Started" : "Next") {
                if onboardingManager.currentStep == .completion {
                    onboardingManager.completeOnboarding()
                } else {
                    onboardingManager.nextStep()
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.accentColor)
            )
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - Welcome Step View

struct WelcomeStepView: View {
    @State private var animateIcon = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // App Icon Animation
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.accentColor.opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                    .scaleEffect(animateIcon ? 1.0 : 0.8)
                    .opacity(animateIcon ? 1.0 : 0.7)
                
                Image(systemName: "arkit")
                    .font(.system(size: 80, weight: .light))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(animateIcon ? 360 : 0))
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    animateIcon.toggle()
                }
            }
            
            VStack(spacing: 16) {
                Text("Welcome to ARchitect")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("Your journey into augmented reality begins here")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("We'll guide you through creating your first AR experience in just a few simple steps.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Permissions Step View

struct PermissionsStepView: View {
    let onRequestPermission: () -> Void
    @State private var animateCamera = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Camera Icon Animation
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 120, height: 120)
                    .scaleEffect(animateCamera ? 1.2 : 1.0)
                    .opacity(animateCamera ? 0.5 : 1.0)
                
                Image(systemName: "camera.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.white)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    animateCamera.toggle()
                }
            }
            
            VStack(spacing: 16) {
                Text("Camera Access")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("ARchitect needs camera access to create augmented reality experiences")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 12) {
                    PermissionReasonRow(
                        icon: "viewfinder",
                        text: "Detect surfaces in your environment"
                    )
                    PermissionReasonRow(
                        icon: "cube.fill",
                        text: "Place 3D objects in the real world"
                    )
                    PermissionReasonRow(
                        icon: "camera.viewfinder",
                        text: "Capture and share your AR creations"
                    )
                }
                .padding(.top)
            }
            
            Spacer()
            
            Button("Grant Camera Access") {
                onRequestPermission()
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(Color.accentColor)
            )
        }
        .padding()
    }
}

struct PermissionReasonRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            Text(text)
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - AR Introduction Step View

struct ARIntroductionStepView: View {
    @State private var scanningAnimation = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // AR Scanning Animation
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 200, height: 150)
                
                // Scanning lines
                VStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { index in
                        Rectangle()
                            .fill(Color.accentColor.opacity(scanningAnimation ? 0.8 : 0.3))
                            .frame(height: 2)
                            .animation(
                                .easeInOut(duration: 0.8)
                                .delay(Double(index) * 0.1)
                                .repeatForever(autoreverses: true),
                                value: scanningAnimation
                            )
                    }
                }
                .frame(width: 180)
                
                // AR dots overlay
                ForEach(0..<12, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 4, height: 4)
                        .position(
                            x: CGFloat.random(in: 20...180),
                            y: CGFloat.random(in: 20...130)
                        )
                        .opacity(scanningAnimation ? 1.0 : 0.0)
                        .animation(
                            .easeInOut(duration: 0.5)
                            .delay(Double(index) * 0.1),
                            value: scanningAnimation
                        )
                }
            }
            .onAppear {
                scanningAnimation = true
            }
            
            VStack(spacing: 16) {
                Text("AR Basics")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Point your camera at a flat surface like a table or floor")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("When ARchitect detects a surface, you'll see small dots appear. This means you're ready to place objects!")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - First Placement Step View

struct FirstPlacementStepView: View {
    @State private var pulseAnimation = false
    @State private var showTapHint = true
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Tap gesture animation
            ZStack {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 3)
                    .frame(width: 100, height: 100)
                    .scaleEffect(pulseAnimation ? 1.5 : 1.0)
                    .opacity(pulseAnimation ? 0.0 : 1.0)
                
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                
                if showTapHint {
                    Text("TAP HERE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                        .offset(y: 60)
                        .opacity(pulseAnimation ? 0.5 : 1.0)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    pulseAnimation.toggle()
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    showTapHint = false
                }
            }
            
            VStack(spacing: 16) {
                Text("Place Your First Object")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Tap anywhere on the detected surface to place your first 3D object")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("Watch as your object appears and stays anchored to the real world!")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Navigation Step View

struct NavigationStepView: View {
    @State private var deviceAnimation = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Device movement animation
            ZStack {
                // Object (stays stationary)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor)
                    .frame(width: 40, height: 40)
                
                // Device (moves around object)
                Image(systemName: "iphone")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .offset(
                        x: deviceAnimation ? 60 : -60,
                        y: deviceAnimation ? -30 : 30
                    )
                    .animation(
                        .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                        value: deviceAnimation
                    )
                
                // Movement path
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2, dash: [5, 5])
                    .frame(width: 160, height: 120)
            }
            .onAppear {
                deviceAnimation = true
            }
            
            VStack(spacing: 16) {
                Text("Navigate in AR")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Move around to see your object from different angles")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("Walk around it, get closer, or view it from above. The object will stay perfectly anchored in place!")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Customization Step View

struct CustomizationStepView: View {
    @State private var colorCycle = 0
    private let colors: [Color] = [.red, .blue, .green, .yellow, .purple]
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Color changing animation
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colors[colorCycle])
                    .frame(width: 80, height: 80)
                    .shadow(radius: 8)
                
                Image(systemName: "paintbrush.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .scaleEffect(1.2)
            }
            .onAppear {
                Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    withAnimation(.easeInOut(duration: 0.5)) {
                        colorCycle = (colorCycle + 1) % colors.count
                    }
                }
            }
            
            VStack(spacing: 16) {
                Text("Customize Objects")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Make objects your own with colors and materials")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("Tap on any object to select it, then use the customization tools to change its appearance.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Sharing Step View

struct SharingStepView: View {
    @State private var shareAnimation = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Share animation
            ZStack {
                // Phone outline
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 60, height: 100)
                
                // Content inside phone
                VStack(spacing: 4) {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 40, height: 25)
                        .cornerRadius(4)
                    
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.white.opacity(0.6))
                                .frame(width: 12, height: 2)
                        }
                    }
                }
                
                // Share arrows
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                        .offset(
                            x: 40 + CGFloat(index * 20),
                            y: -20 - CGFloat(index * 15)
                        )
                        .opacity(shareAnimation ? 1.0 : 0.0)
                        .animation(
                            .easeOut(duration: 0.8)
                            .delay(Double(index) * 0.3)
                            .repeatForever(autoreverses: false),
                            value: shareAnimation
                        )
                }
            }
            .onAppear {
                shareAnimation = true
            }
            
            VStack(spacing: 16) {
                Text("Share Your Creations")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Show off your AR creations to the world")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("Take screenshots, record videos, or share your entire project with friends and family.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Completion Step View

struct CompletionStepView: View {
    @State private var celebrationAnimation = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Celebration animation
            ZStack {
                // Confetti
                ForEach(0..<20, id: \.self) { index in
                    Rectangle()
                        .fill([Color.red, Color.blue, Color.green, Color.yellow, Color.purple].randomElement() ?? .blue)
                        .frame(width: 8, height: 8)
                        .rotationEffect(.degrees(celebrationAnimation ? 360 : 0))
                        .offset(
                            x: celebrationAnimation ? .random(in: -100...100) : 0,
                            y: celebrationAnimation ? .random(in: -150...50) : 0
                        )
                        .opacity(celebrationAnimation ? 0 : 1)
                        .animation(
                            .easeOut(duration: 2.0)
                            .delay(Double(index) * 0.1),
                            value: celebrationAnimation
                        )
                }
                
                // Success checkmark
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 100, height: 100)
                        .scaleEffect(celebrationAnimation ? 1.0 : 0.5)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    celebrationAnimation = true
                }
            }
            
            VStack(spacing: 16) {
                Text("You're All Set!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("🎉 Congratulations! 🎉")
                    .font(.title2)
                    .foregroundColor(.white)
                
                Text("You've completed the ARchitect tutorial and you're ready to create amazing AR experiences!")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("Have fun creating and sharing your AR projects!")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Particle Animation View

struct ParticleAnimationView: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            ForEach(0..<15, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: CGFloat.random(in: 4...12))
                    .position(
                        x: animate ? .random(in: 0...UIScreen.main.bounds.width) : .random(in: 0...UIScreen.main.bounds.width),
                        y: animate ? .random(in: 0...UIScreen.main.bounds.height) : .random(in: 0...UIScreen.main.bounds.height)
                    )
                    .animation(
                        .linear(duration: Double.random(in: 8...15))
                        .repeatForever(autoreverses: false),
                        value: animate
                    )
            }
        }
        .onAppear {
            animate = true
        }
    }
}

// MARK: - Preview

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}