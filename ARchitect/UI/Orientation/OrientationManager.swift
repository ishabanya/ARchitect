import SwiftUI
import UIKit
import Combine

// MARK: - Orientation Manager

@MainActor
public class OrientationManager: ObservableObject {
    
    // MARK: - Properties
    @Published public var currentOrientation: UIDeviceOrientation = .portrait
    @Published public var interfaceOrientation: UIInterfaceOrientation = .portrait
    @Published public var isLandscape = false
    @Published public var isPortrait = true
    
    // Size classes
    @Published public var horizontalSizeClass: UserInterfaceSizeClass = .regular
    @Published public var verticalSizeClass: UserInterfaceSizeClass = .regular
    
    // Layout properties
    @Published public var screenSize: CGSize = UIScreen.main.bounds.size
    @Published public var safeAreaInsets: EdgeInsets = EdgeInsets()
    @Published public var availableSize: CGSize = UIScreen.main.bounds.size
    
    // Transition state
    @Published public var isTransitioning = false
    @Published public var rotationProgress: Double = 0.0
    
    // Configuration
    @Published public var allowsLandscape = true
    @Published public var allowsPortrait = true
    @Published public var allowsUpsideDown = false
    @Published public var autoRotationEnabled = true
    
    // Layout constraints
    private var landscapeConstraints: [OrientationConstraint] = []
    private var portraitConstraints: [OrientationConstraint] = []
    
    private var cancellables = Set<AnyCancellable>()
    private let hapticFeedback = HapticFeedbackManager.shared
    
    public static let shared = OrientationManager()
    
    private init() {
        setupOrientationObservers()
        updateCurrentOrientation()
        setupDefaultConstraints()
        
        logDebug("Orientation manager initialized", category: .general)
    }
    
    // MARK: - Setup
    
    private func setupOrientationObservers() {
        // Device orientation changes
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .sink { [weak self] _ in
                self?.handleOrientationChange()
            }
            .store(in: &cancellables)
        
        // Application state changes
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.updateCurrentOrientation()
            }
            .store(in: &cancellables)
        
        // Scene changes (for multi-window support)
        if #available(iOS 13.0, *) {
            NotificationCenter.default.publisher(for: UIScene.willEnterForegroundNotification)
                .sink { [weak self] _ in
                    self?.updateCurrentOrientation()
                }
                .store(in: &cancellables)
        }
    }
    
    private func setupDefaultConstraints() {
        // Portrait constraints
        portraitConstraints = [
            OrientationConstraint(
                minWidth: 320,
                maxWidth: .infinity,
                minHeight: 568,
                maxHeight: .infinity,
                aspectRatio: 9.0/16.0...16.0/9.0
            )
        ]
        
        // Landscape constraints
        landscapeConstraints = [
            OrientationConstraint(
                minWidth: 568,
                maxWidth: .infinity,
                minHeight: 320,
                maxHeight: .infinity,
                aspectRatio: 16.0/9.0...2.5
            )
        ]
    }
    
    // MARK: - Orientation Handling
    
    private func handleOrientationChange() {
        guard autoRotationEnabled else { return }
        
        let newOrientation = UIDevice.current.orientation
        
        // Skip invalid orientations
        guard newOrientation != .unknown,
              newOrientation != .faceUp,
              newOrientation != .faceDown else { return }
        
        // Check if orientation is allowed
        guard isOrientationAllowed(newOrientation) else { return }
        
        // Start transition
        startOrientationTransition(to: newOrientation)
        
        // Update properties
        updateCurrentOrientation()
        
        // Provide haptic feedback for significant changes
        if newOrientation.isLandscape != currentOrientation.isLandscape {
            hapticFeedback.impact(.light)
        }
        
        logDebug("Orientation changed", category: .general, context: LogContext(customData: [
            "from": currentOrientation.rawValue,
            "to": newOrientation.rawValue,
            "is_landscape": newOrientation.isLandscape
        ]))
    }
    
    private func updateCurrentOrientation() {
        let deviceOrientation = UIDevice.current.orientation
        
        if deviceOrientation != .unknown && deviceOrientation != .faceUp && deviceOrientation != .faceDown {
            currentOrientation = deviceOrientation
        }
        
        // Update interface orientation
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            interfaceOrientation = windowScene.interfaceOrientation
        }
        
        // Update layout properties
        updateLayoutProperties()
    }
    
    private func updateLayoutProperties() {
        // Update orientation flags
        isLandscape = currentOrientation.isLandscape
        isPortrait = !isLandscape
        
        // Update screen size
        screenSize = UIScreen.main.bounds.size
        
        // Update size classes (simplified)
        if isLandscape {
            horizontalSizeClass = .regular
            verticalSizeClass = .compact
        } else {
            horizontalSizeClass = screenSize.width > 414 ? .regular : .compact
            verticalSizeClass = .regular
        }
        
        // Update safe area (approximation)
        updateSafeAreaInsets()
        
        // Calculate available size
        availableSize = CGSize(
            width: screenSize.width - safeAreaInsets.leading - safeAreaInsets.trailing,
            height: screenSize.height - safeAreaInsets.top - safeAreaInsets.bottom
        )
    }
    
    private func updateSafeAreaInsets() {
        // Get safe area from key window
        if let window = UIApplication.shared.windows.first {
            let insets = window.safeAreaInsets
            safeAreaInsets = EdgeInsets(
                top: insets.top,
                leading: insets.left,
                bottom: insets.bottom,
                trailing: insets.right
            )
        } else {
            // Fallback to estimated values
            if isLandscape {
                safeAreaInsets = EdgeInsets(top: 0, leading: 44, bottom: 21, trailing: 44)
            } else {
                safeAreaInsets = EdgeInsets(top: 47, leading: 0, bottom: 34, trailing: 0)
            }
        }
    }
    
    // MARK: - Orientation Validation
    
    private func isOrientationAllowed(_ orientation: UIDeviceOrientation) -> Bool {
        switch orientation {
        case .portrait:
            return allowsPortrait
        case .portraitUpsideDown:
            return allowsUpsideDown
        case .landscapeLeft, .landscapeRight:
            return allowsLandscape
        default:
            return false
        }
    }
    
    public func setAllowedOrientations(portrait: Bool, landscape: Bool, upsideDown: Bool = false) {
        allowsPortrait = portrait
        allowsLandscape = landscape
        allowsUpsideDown = upsideDown
        
        // Force orientation if current is not allowed
        if !isOrientationAllowed(currentOrientation) {
            if portrait {
                forceOrientation(.portrait)
            } else if landscape {
                forceOrientation(.landscapeLeft)
            }
        }
        
        logDebug("Allowed orientations updated", category: .general, context: LogContext(customData: [
            "portrait": portrait,
            "landscape": landscape,
            "upside_down": upsideDown
        ]))
    }
    
    // MARK: - Force Orientation
    
    public func forceOrientation(_ orientation: UIDeviceOrientation) {
        guard isOrientationAllowed(orientation) else {
            logWarning("Attempted to force disallowed orientation", category: .general)
            return
        }
        
        // Disable auto-rotation temporarily
        autoRotationEnabled = false
        
        // Force the orientation
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        
        // Re-enable auto-rotation after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.autoRotationEnabled = true
        }
        
        logDebug("Forced orientation change", category: .general, context: LogContext(customData: [
            "orientation": orientation.rawValue
        ]))
    }
    
    public func forcePortrait() {
        forceOrientation(.portrait)
    }
    
    public func forceLandscape() {
        forceOrientation(.landscapeLeft)
    }
    
    // MARK: - Transition Management
    
    private func startOrientationTransition(to orientation: UIDeviceOrientation) {
        isTransitioning = true
        rotationProgress = 0.0
        
        // Animate transition progress
        withAnimation(.easeInOut(duration: 0.3)) {
            rotationProgress = 1.0
        }
        
        // Complete transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.completeOrientationTransition()
        }
    }
    
    private func completeOrientationTransition() {
        isTransitioning = false
        rotationProgress = 0.0
        
        // Notify completion
        NotificationCenter.default.post(name: .orientationTransitionCompleted, object: self)
    }
    
    // MARK: - Layout Constraints
    
    public func addConstraint(_ constraint: OrientationConstraint, for orientation: OrientationMode) {
        switch orientation {
        case .portrait:
            portraitConstraints.append(constraint)
        case .landscape:
            landscapeConstraints.append(constraint)
        case .both:
            portraitConstraints.append(constraint)
            landscapeConstraints.append(constraint)
        }
    }
    
    public func getConstraints(for orientation: OrientationMode) -> [OrientationConstraint] {
        switch orientation {
        case .portrait:
            return portraitConstraints
        case .landscape:
            return landscapeConstraints
        case .both:
            return portraitConstraints + landscapeConstraints
        }
    }
    
    public func validateConstraints() -> Bool {
        let currentConstraints = isLandscape ? landscapeConstraints : portraitConstraints
        
        for constraint in currentConstraints {
            if !constraint.isValid(for: availableSize) {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Layout Helpers
    
    public func getOptimalLayout<T>(
        portrait: T,
        landscape: T,
        compactWidth: T? = nil,
        compactHeight: T? = nil
    ) -> T {
        // Check for compact size classes first
        if let compactWidth = compactWidth, horizontalSizeClass == .compact {
            return compactWidth
        }
        
        if let compactHeight = compactHeight, verticalSizeClass == .compact {
            return compactHeight
        }
        
        // Return orientation-specific layout
        return isLandscape ? landscape : portrait
    }
    
    public func adaptiveSpacing(portrait: CGFloat, landscape: CGFloat) -> CGFloat {
        return isLandscape ? landscape : portrait
    }
    
    public func adaptivePadding(portrait: EdgeInsets, landscape: EdgeInsets) -> EdgeInsets {
        return isLandscape ? landscape : portrait
    }
    
    public func adaptiveColumns(portrait: Int, landscape: Int) -> Int {
        return isLandscape ? landscape : portrait
    }
    
    // MARK: - Device-Specific Layouts
    
    public var isIPhone: Bool {
        return UIDevice.current.userInterfaceIdiom == .phone
    }
    
    public var isIPad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad
    }
    
    public var isCompactDevice: Bool {
        return horizontalSizeClass == .compact && verticalSizeClass == .regular
    }
    
    public var isRegularDevice: Bool {
        return horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
    
    // MARK: - AR-Specific Orientation Handling
    
    public func configureForAR() {
        // AR typically works best in landscape or allows all orientations
        setAllowedOrientations(portrait: true, landscape: true, upsideDown: false)
        
        logInfo("Configured orientation for AR", category: .general)
    }
    
    public func optimizeForARView() -> OrientationConfiguration {
        return OrientationConfiguration(
            allowsPortrait: true,
            allowsLandscape: true,
            preferredOrientation: isIPad ? .landscape : .portrait,
            autoRotation: true,
            constraintsEnabled: true
        )
    }
    
    // MARK: - Accessibility
    
    public func announceOrientationChange() {
        let orientation = isLandscape ? "landscape" : "portrait"
        AccessibilityManager.shared.announce("Orientation changed to \(orientation)")
    }
    
    // MARK: - Debug Information
    
    public func getDebugInfo() -> OrientationDebugInfo {
        return OrientationDebugInfo(
            deviceOrientation: currentOrientation,
            interfaceOrientation: interfaceOrientation,
            screenSize: screenSize,
            safeAreaInsets: safeAreaInsets,
            availableSize: availableSize,
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass,
            isTransitioning: isTransitioning,
            allowedOrientations: getAllowedOrientations()
        )
    }
    
    private func getAllowedOrientations() -> [UIDeviceOrientation] {
        var allowed: [UIDeviceOrientation] = []
        
        if allowsPortrait { allowed.append(.portrait) }
        if allowsLandscape { 
            allowed.append(.landscapeLeft)
            allowed.append(.landscapeRight)
        }
        if allowsUpsideDown { allowed.append(.portraitUpsideDown) }
        
        return allowed
    }
}

// MARK: - Supporting Types

public struct OrientationConstraint {
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let aspectRatio: ClosedRange<CGFloat>
    
    public init(
        minWidth: CGFloat = 0,
        maxWidth: CGFloat = .infinity,
        minHeight: CGFloat = 0,
        maxHeight: CGFloat = .infinity,
        aspectRatio: ClosedRange<CGFloat> = 0.1...10.0
    ) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.aspectRatio = aspectRatio
    }
    
    func isValid(for size: CGSize) -> Bool {
        let width = size.width
        let height = size.height
        let ratio = width / height
        
        return width >= minWidth && width <= maxWidth &&
               height >= minHeight && height <= maxHeight &&
               aspectRatio.contains(ratio)
    }
}

public enum OrientationMode {
    case portrait
    case landscape
    case both
}

public struct OrientationConfiguration {
    let allowsPortrait: Bool
    let allowsLandscape: Bool
    let preferredOrientation: UIDeviceOrientation
    let autoRotation: Bool
    let constraintsEnabled: Bool
    
    public init(
        allowsPortrait: Bool = true,
        allowsLandscape: Bool = true,
        preferredOrientation: UIDeviceOrientation = .portrait,
        autoRotation: Bool = true,
        constraintsEnabled: Bool = false
    ) {
        self.allowsPortrait = allowsPortrait
        self.allowsLandscape = allowsLandscape
        self.preferredOrientation = preferredOrientation
        self.autoRotation = autoRotation
        self.constraintsEnabled = constraintsEnabled
    }
}

public struct OrientationDebugInfo {
    let deviceOrientation: UIDeviceOrientation
    let interfaceOrientation: UIInterfaceOrientation
    let screenSize: CGSize
    let safeAreaInsets: EdgeInsets
    let availableSize: CGSize
    let horizontalSizeClass: UserInterfaceSizeClass
    let verticalSizeClass: UserInterfaceSizeClass
    let isTransitioning: Bool
    let allowedOrientations: [UIDeviceOrientation]
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let orientationTransitionCompleted = Notification.Name("orientationTransitionCompleted")
}

// MARK: - View Modifiers

public struct OrientationModifier: ViewModifier {
    @StateObject private var orientationManager = OrientationManager.shared
    
    let portraitContent: AnyView
    let landscapeContent: AnyView
    
    public func body(content: Content) -> some View {
        Group {
            if orientationManager.isLandscape {
                landscapeContent
            } else {
                portraitContent
            }
        }
        .animation(.easeInOut(duration: 0.3), value: orientationManager.isLandscape)
    }
}

public struct AdaptiveLayoutModifier<T>: ViewModifier {
    @StateObject private var orientationManager = OrientationManager.shared
    
    let portrait: T
    let landscape: T
    let transform: (T) -> AnyView
    
    public func body(content: Content) -> some View {
        let value = orientationManager.getOptimalLayout(portrait: portrait, landscape: landscape)
        transform(value)
    }
}

public struct SafeAreaPaddingModifier: ViewModifier {
    @StateObject private var orientationManager = OrientationManager.shared
    
    let edges: Edge.Set
    
    public func body(content: Content) -> some View {
        content
            .padding(.top, edges.contains(.top) ? orientationManager.safeAreaInsets.top : 0)
            .padding(.leading, edges.contains(.leading) ? orientationManager.safeAreaInsets.leading : 0)
            .padding(.bottom, edges.contains(.bottom) ? orientationManager.safeAreaInsets.bottom : 0)
            .padding(.trailing, edges.contains(.trailing) ? orientationManager.safeAreaInsets.trailing : 0)
    }
}

// MARK: - View Extensions

extension View {
    public func orientationAdaptive<T>(
        portrait: T,
        landscape: T,
        transform: @escaping (T) -> AnyView
    ) -> some View {
        self.modifier(AdaptiveLayoutModifier(portrait: portrait, landscape: landscape, transform: transform))
    }
    
    public func orientationSpecific(
        portrait: AnyView,
        landscape: AnyView
    ) -> some View {
        self.modifier(OrientationModifier(portraitContent: portrait, landscapeContent: landscape))
    }
    
    public func safeAreaPadding(_ edges: Edge.Set = .all) -> some View {
        self.modifier(SafeAreaPaddingModifier(edges: edges))
    }
    
    public func adaptiveSpacing(portrait: CGFloat, landscape: CGFloat) -> some View {
        self.padding(OrientationManager.shared.adaptiveSpacing(portrait: portrait, landscape: landscape))
    }
    
    public func onOrientationChange(perform action: @escaping (Bool) -> Void) -> some View {
        self.onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            action(OrientationManager.shared.isLandscape)
        }
    }
}