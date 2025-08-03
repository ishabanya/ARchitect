import SwiftUI
import Combine

// MARK: - 60 FPS Optimized Animation System

public struct AnimationSystem {
    
    // MARK: - Performance Configuration
    
    public struct Performance {
        public static let targetFrameRate: Int = 60
        public static let frameTime: TimeInterval = 1.0 / Double(targetFrameRate)
        public static let maxAnimationDuration: TimeInterval = 0.5
        public static let preferredLayerBacking: Bool = true
        
        public static func optimizeForPerformance() {
            CATransaction.begin()
            CATransaction.setDisableActions(false)
            CATransaction.setAnimationDuration(frameTime)
            CATransaction.commit()
        }
    }
    
    // MARK: - Transition Definitions
    
    public struct Transitions {
        
        // MARK: - Modal Transitions
        public static let modalSlideUp: AnyTransition = .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
        
        public static let modalFade: AnyTransition = .opacity
        
        public static let modalScale: AnyTransition = .scale(scale: 0.95).combined(with: .opacity)
        
        // MARK: - Page Transitions
        public static let pageSlideLeft: AnyTransition = .asymmetric(
            insertion: .move(edge: .trailing),
            removal: .move(edge: .leading)
        )
        
        public static let pageSlideRight: AnyTransition = .asymmetric(
            insertion: .move(edge: .leading),
            removal: .move(edge: .trailing)
        )
        
        public static let pageFade: AnyTransition = .opacity
        
        // MARK: - Card Transitions
        public static let cardAppear: AnyTransition = .scale(scale: 0.9).combined(with: .opacity)
        
        public static let cardSlideIn: AnyTransition = .move(edge: .bottom).combined(with: .opacity)
        
        // MARK: - Toast Transitions
        public static let toastFromTop: AnyTransition = .move(edge: .top).combined(with: .opacity)
        
        public static let toastFromBottom: AnyTransition = .move(edge: .bottom).combined(with: .opacity)
        
        // MARK: - Custom Transitions
        public static func customSlide(edge: Edge, distance: CGFloat = 100) -> AnyTransition {
            .asymmetric(
                insertion: .move(edge: edge),
                removal: .move(edge: edge)
            )
        }
        
        public static func customScale(scale: CGFloat = 0.8, opacity: Double = 0.0) -> AnyTransition {
            .scale(scale: scale).combined(with: .opacity)
        }
    }
    
    // MARK: - Spring Configurations
    
    public struct Springs {
        
        // MARK: - 60 FPS Optimized Springs
        public static let gentle = Animation.spring(
            response: 0.4,
            dampingFraction: 0.85,
            blendDuration: Performance.frameTime
        )
        
        public static let snappy = Animation.spring(
            response: 0.25,
            dampingFraction: 0.75,
            blendDuration: Performance.frameTime
        )
        
        public static let bouncy = Animation.spring(
            response: 0.35,
            dampingFraction: 0.65,
            blendDuration: Performance.frameTime
        )
        
        public static let smooth = Animation.spring(
            response: 0.45,
            dampingFraction: 0.9,
            blendDuration: Performance.frameTime
        )
        
        public static let quick = Animation.spring(
            response: 0.15,
            dampingFraction: 0.8,
            blendDuration: Performance.frameTime
        )
        
        // MARK: - Custom Spring Builder
        public static func custom(
            response: Double = 0.4,
            dampingFraction: Double = 0.8,
            blendDuration: Double = 0.1
        ) -> Animation {
            return .spring(
                response: response,
                dampingFraction: dampingFraction,
                blendDuration: blendDuration
            )
        }
    }
    
    // MARK: - Easing Curves
    
    public struct Easings {
        public static let easeIn = Animation.easeIn(duration: 0.25)
        public static let easeOut = Animation.easeOut(duration: 0.25)
        public static let easeInOut = Animation.easeInOut(duration: 0.25)
        public static let linear = Animation.linear(duration: 0.25)
        
        public static func customEase(duration: TimeInterval = 0.25, curve: Animation = .easeInOut(duration: 0.25)) -> Animation {
            return curve
        }
    }
    
    // MARK: - Animation Context Manager
    
    @MainActor
    public class AnimationContext: ObservableObject {
        @Published public var reduceMotion: Bool = false
        @Published public var animationScale: Double = 1.0
        @Published public var preferredDuration: TimeInterval = 0.25
        
        public init() {
            updateAccessibilitySettings()
            
            NotificationCenter.default.addObserver(
                forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
                object: nil,
                queue: .main
            ) { _ in
                self.updateAccessibilitySettings()
            }
        }
        
        private func updateAccessibilitySettings() {
            reduceMotion = UIAccessibility.isReduceMotionEnabled
            animationScale = reduceMotion ? 0.5 : 1.0
            preferredDuration = reduceMotion ? 0.1 : 0.25
        }
        
        public func animation(_ animation: Animation) -> Animation? {
            return reduceMotion ? nil : animation
        }
        
        public func transition(_ transition: AnyTransition) -> AnyTransition {
            return reduceMotion ? .opacity : transition
        }
    }
}

// MARK: - Animated Container Views

public struct AnimatedContainer<Content: View>: View {
    private let content: Content
    private let animation: Animation
    private let trigger: AnyHashable
    
    public init(
        animation: Animation = AnimationSystem.Springs.gentle,
        trigger: AnyHashable,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.animation = animation
        self.trigger = trigger
    }
    
    public var body: some View {
        content
            .animation(animation, value: trigger)
    }
}

// MARK: - Animated Visibility

public struct AnimatedVisibility<Content: View>: View {
    private let content: Content
    private let isVisible: Bool
    private let transition: AnyTransition
    private let animation: Animation
    
    @EnvironmentObject private var animationContext: AnimationSystem.AnimationContext
    
    public init(
        isVisible: Bool,
        transition: AnyTransition = AnimationSystem.Transitions.modalFade,
        animation: Animation = AnimationSystem.Springs.gentle,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.isVisible = isVisible
        self.transition = transition
        self.animation = animation
    }
    
    public var body: some View {
        Group {
            if isVisible {
                content
                    .transition(transition)
            }
        }
        .animation(animation, value: isVisible)
    }
}

// MARK: - Loading Animation Component

public struct LoadingAnimation: View {
    @State private var isAnimating = false
    private let style: LoadingStyle
    private let size: CGFloat
    private let color: Color
    
    public enum LoadingStyle {
        case spinning
        case pulsing
        case bouncing
        case breathing
        case dots
        case wave
    }
    
    public init(
        style: LoadingStyle = .spinning,
        size: CGFloat = 24,
        color: Color = DesignSystem.Colors.primary
    ) {
        self.style = style
        self.size = size
        self.color = color
    }
    
    public var body: some View {
        Group {
            switch style {
            case .spinning:
                SpinningLoader(size: size, color: color, isAnimating: $isAnimating)
            case .pulsing:
                PulsingLoader(size: size, color: color, isAnimating: $isAnimating)
            case .bouncing:
                BouncingLoader(size: size, color: color, isAnimating: $isAnimating)
            case .breathing:
                BreathingLoader(size: size, color: color, isAnimating: $isAnimating)
            case .dots:
                DotsLoader(size: size, color: color, isAnimating: $isAnimating)
            case .wave:
                WaveLoader(size: size, color: color, isAnimating: $isAnimating)
            }
        }
        .onAppear {
            isAnimating = true
        }
        .onDisappear {
            isAnimating = false
        }
    }
}

// MARK: - Loading Components

private struct SpinningLoader: View {
    let size: CGFloat
    let color: Color
    @Binding var isAnimating: Bool
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.8)
            .stroke(
                AngularGradient(
                    colors: [color.opacity(0.1), color],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: size / 8, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(
                Animation.linear(duration: 1.0).repeatForever(autoreverses: false),
                value: isAnimating
            )
    }
}

private struct PulsingLoader: View {
    let size: CGFloat
    let color: Color
    @Binding var isAnimating: Bool
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(isAnimating ? 1.2 : 0.8)
            .opacity(isAnimating ? 0.3 : 1.0)
            .animation(
                Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isAnimating
            )
    }
}

private struct BouncingLoader: View {
    let size: CGFloat
    let color: Color
    @Binding var isAnimating: Bool
    
    var body: some View {
        HStack(spacing: size / 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(color)
                    .frame(width: size / 4, height: size / 4)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
    }
}

private struct BreathingLoader: View {
    let size: CGFloat
    let color: Color
    @Binding var isAnimating: Bool
    
    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 2)
                    .frame(width: size, height: size)
                    .scaleEffect(isAnimating ? 1.5 : 0.5)
                    .opacity(isAnimating ? 0.1 : 0.8)
                    .animation(
                        Animation.easeInOut(duration: 2.0)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.5),
                        value: isAnimating
                    )
            }
        }
    }
}

private struct DotsLoader: View {
    let size: CGFloat
    let color: Color
    @Binding var isAnimating: Bool
    
    var body: some View {
        HStack(spacing: size / 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(color)
                    .frame(width: size / 6, height: size / 6)
                    .offset(y: isAnimating ? -size / 4 : 0)
                    .animation(
                        Animation.easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: isAnimating
                    )
            }
        }
    }
}

private struct WaveLoader: View {
    let size: CGFloat
    let color: Color
    @Binding var isAnimating: Bool
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: size / 8, height: size / 3)
                    .scaleEffect(y: isAnimating ? 1.5 : 0.5)
                    .animation(
                        Animation.easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: isAnimating
                    )
            }
        }
    }
}

// MARK: - Success Animation

public struct SuccessAnimation: View {
    @State private var isAnimating = false
    @State private var showCheckmark = false
    private let size: CGFloat
    private let color: Color
    private let completion: (() -> Void)?
    
    public init(
        size: CGFloat = 60,
        color: Color = DesignSystem.Colors.success,
        completion: (() -> Void)? = nil
    ) {
        self.size = size
        self.color = color
        self.completion = completion
    }
    
    public var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .scaleEffect(isAnimating ? 1.0 : 0.0)
                .animation(AnimationSystem.Springs.bouncy, value: isAnimating)
            
            // Checkmark
            if showCheckmark {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(showCheckmark ? 1.0 : 0.0)
                    .animation(AnimationSystem.Springs.bouncy.delay(0.2), value: showCheckmark)
            }
        }
        .onAppear {
            isAnimating = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showCheckmark = true
                HapticFeedbackManager.shared.operationSuccess()
            }
            
            if let completion = completion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    completion()
                }
            }
        }
    }
}

// MARK: - Parallax Effect

public struct ParallaxView<Content: View>: View {
    private let content: Content
    private let multiplier: CGFloat
    @State private var offset: CGFloat = 0
    
    public init(
        multiplier: CGFloat = 0.5,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.multiplier = multiplier
    }
    
    public var body: some View {
        GeometryReader { geometry in
            content
                .offset(y: offset * multiplier)
                .onAppear {
                    updateOffset(geometry: geometry)
                }
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    offset = value
                }
        }
    }
    
    private func updateOffset(geometry: GeometryProxy) {
        let frame = geometry.frame(in: .global)
        offset = frame.midY - UIScreen.main.bounds.height / 2
    }
}

// MARK: - Morphing Button

public struct MorphingButton: View {
    @State private var isExpanded = false
    private let normalWidth: CGFloat
    private let expandedWidth: CGFloat
    private let height: CGFloat
    private let action: () -> Void
    
    public init(
        normalWidth: CGFloat = 50,
        expandedWidth: CGFloat = 150,
        height: CGFloat = 50,
        action: @escaping () -> Void
    ) {
        self.normalWidth = normalWidth
        self.expandedWidth = expandedWidth
        self.height = height
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            withAnimation(AnimationSystem.Springs.bouncy) {
                isExpanded.toggle()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                action()
                withAnimation(AnimationSystem.Springs.gentle) {
                    isExpanded = false
                }
            }
        }) {
            HStack {
                Image(systemName: isExpanded ? "checkmark" : "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                if isExpanded {
                    Text("Added!")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(width: isExpanded ? expandedWidth : normalWidth, height: height)
            .background(
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(DesignSystem.Colors.success)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preference Keys

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - View Extensions

extension View {
    
    // MARK: - Animation Helpers
    public func animateOnAppear(
        animation: Animation = AnimationSystem.Springs.gentle,
        delay: TimeInterval = 0
    ) -> some View {
        self.modifier(AnimateOnAppearModifier(animation: animation, delay: delay))
    }
    
    public func parallaxEffect(multiplier: CGFloat = 0.5) -> some View {
        ParallaxView(multiplier: multiplier) {
            self
        }
    }
    
    public func morphingScale(trigger: Bool, scale: CGFloat = 1.1) -> some View {
        self.scaleEffect(trigger ? scale : 1.0)
            .animation(AnimationSystem.Springs.quick, value: trigger)
    }
    
    public func breathingEffect(isActive: Bool = true) -> some View {
        self.modifier(BreathingEffectModifier(isActive: isActive))
    }
}

// MARK: - View Modifiers

private struct AnimateOnAppearModifier: ViewModifier {
    let animation: Animation
    let delay: TimeInterval
    @State private var isVisible = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.8)
            .animation(animation, value: isVisible)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    isVisible = true
                }
            }
    }
}

private struct BreathingEffectModifier: ViewModifier {
    let isActive: Bool
    @State private var scale: CGFloat = 1.0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                if isActive {
                    withAnimation(
                        Animation.easeInOut(duration: 2.0)
                            .repeatForever(autoreverses: true)
                    ) {
                        scale = 1.05
                    }
                }
            }
    }
}