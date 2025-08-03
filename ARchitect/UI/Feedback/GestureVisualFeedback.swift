import SwiftUI
import UIKit
import CoreHaptics

// MARK: - Gesture Visual Feedback Manager
@MainActor
public class GestureVisualFeedback: ObservableObject {
    public static let shared = GestureVisualFeedback()
    
    @Published public var isEnabled: Bool = true
    @Published public var feedbackIntensity: FeedbackIntensity = .medium
    @Published public var showTouchIndicators: Bool = true
    @Published public var animationDuration: TimeInterval = 0.3
    
    // MARK: - Haptic Engine
    private var hapticEngine: CHHapticEngine?
    private var supportsHaptics: Bool = false
    
    // MARK: - Visual Effects
    private var activeIndicators: [TouchIndicator] = []
    private var gestureTrails: [GestureTrail] = []
    
    private init() {
        setupHapticsEngine()
        setupNotifications()
    }
    
    deinit {
        cleanupHapticsEngine()
    }
    
    // MARK: - Setup
    
    private func setupHapticsEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            logInfo("Device does not support haptics", category: .ui)
            return
        }
        
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
            supportsHaptics = true
            
            logInfo("Haptic engine initialized successfully", category: .ui)
        } catch {
            logError("Failed to create haptic engine", category: .ui, error: error)
            supportsHaptics = false
        }
    }
    
    private func cleanupHapticsEngine() {
        hapticEngine?.stop()
        hapticEngine = nil
    }
    
    private func setupNotifications() {
        // Listen for app state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        hapticEngine?.stop()
    }
    
    @objc private func appWillEnterForeground() {
        if supportsHaptics {
            try? hapticEngine?.start()
        }
    }
    
    // MARK: - Touch Feedback
    
    public func showTouchFeedback(at point: CGPoint, in view: UIView, type: TouchType = .tap) {
        guard isEnabled && showTouchIndicators else { return }
        
        let indicator = TouchIndicator(
            id: UUID(),
            position: point,
            type: type,
            startTime: Date(),
            view: view
        )
        
        activeIndicators.append(indicator)
        
        // Create visual effect
        createTouchVisualEffect(indicator)
        
        // Play haptic feedback
        playHapticFeedback(for: type)
        
        // Schedule cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration * 2) {
            self.removeIndicator(indicator.id)
        }
    }
    
    public func showDragFeedback(from startPoint: CGPoint, to endPoint: CGPoint, in view: UIView) {
        guard isEnabled else { return }
        
        let trail = GestureTrail(
            id: UUID(),
            startPoint: startPoint,
            endPoint: endPoint,
            startTime: Date(),
            view: view
        )
        
        gestureTrails.append(trail)
        
        // Create drag visual effect
        createDragVisualEffect(trail)
        
        // Play drag haptic feedback
        playDragHapticFeedback(distance: distance(from: startPoint, to: endPoint))
        
        // Schedule cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration * 1.5) {
            self.removeTrail(trail.id)
        }
    }
    
    public func showPinchFeedback(at center: CGPoint, scale: CGFloat, in view: UIView) {
        guard isEnabled else { return }
        
        let indicator = TouchIndicator(
            id: UUID(),
            position: center,
            type: .pinch(scale),
            startTime: Date(),
            view: view
        )
        
        activeIndicators.append(indicator)
        
        // Create pinch visual effect
        createPinchVisualEffect(indicator, scale: scale)
        
        // Play scale-based haptic feedback
        playScaleHapticFeedback(scale: scale)
        
        // Schedule cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            self.removeIndicator(indicator.id)
        }
    }
    
    public func showRotationFeedback(at center: CGPoint, rotation: CGFloat, in view: UIView) {
        guard isEnabled else { return }
        
        let indicator = TouchIndicator(
            id: UUID(),
            position: center,
            type: .rotation(rotation),
            startTime: Date(),
            view: view
        )
        
        activeIndicators.append(indicator)
        
        // Create rotation visual effect
        createRotationVisualEffect(indicator, rotation: rotation)
        
        // Play rotation haptic feedback
        playRotationHapticFeedback(rotation: rotation)
        
        // Schedule cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            self.removeIndicator(indicator.id)
        }
    }
    
    public func showLongPressFeedback(at point: CGPoint, in view: UIView, progress: Double) {
        guard isEnabled else { return }
        
        let indicator = TouchIndicator(
            id: UUID(),
            position: point,
            type: .longPress(progress),
            startTime: Date(),
            view: view
        )
        
        activeIndicators.append(indicator)
        
        // Create long press visual effect
        createLongPressVisualEffect(indicator, progress: progress)
        
        // Play progressive haptic feedback
        if progress >= 1.0 {
            playHapticFeedback(for: .longPressComplete)
        }
        
        // Schedule cleanup based on progress
        let cleanupDelay = progress >= 1.0 ? animationDuration : animationDuration * 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + cleanupDelay) {
            self.removeIndicator(indicator.id)
        }
    }
    
    // MARK: - AR Gesture Feedback
    
    public func showARPlacementFeedback(at screenPoint: CGPoint, in view: UIView, success: Bool) {
        let type: TouchType = success ? .arPlacementSuccess : .arPlacementFailure
        
        let indicator = TouchIndicator(
            id: UUID(),
            position: screenPoint,
            type: type,
            startTime: Date(),
            view: view
        )
        
        activeIndicators.append(indicator)
        
        // Create AR placement visual effect
        createARPlacementVisualEffect(indicator, success: success)
        
        // Play contextual haptic feedback
        playHapticFeedback(for: success ? .success : .failure)
        
        // Schedule cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration * 1.5) {
            self.removeIndicator(indicator.id)
        }
    }
    
    public func showARSelectionFeedback(at screenPoint: CGPoint, in view: UIView) {
        showTouchFeedback(at: screenPoint, in: view, type: .arSelection)
    }
    
    public func showARManipulationFeedback(at screenPoint: CGPoint, in view: UIView, type: ARManipulationType) {
        let touchType: TouchType
        
        switch type {
        case .move:
            touchType = .arMove
        case .rotate:
            touchType = .arRotate
        case .scale:
            touchType = .arScale
        }
        
        showTouchFeedback(at: screenPoint, in: view, type: touchType)
    }
    
    // MARK: - Visual Effects Creation
    
    private func createTouchVisualEffect(_ indicator: TouchIndicator) {
        let effectView = createRippleEffect(at: indicator.position, in: indicator.view, for: indicator.type)
        
        // Animate the effect
        UIView.animate(
            withDuration: animationDuration,
            delay: 0,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0.8,
            options: [.curveEaseOut],
            animations: {
                effectView.transform = CGAffineTransform(scaleX: 2.0, y: 2.0)
                effectView.alpha = 0.0
            },
            completion: { _ in
                effectView.removeFromSuperview()
            }
        )
    }
    
    private func createDragVisualEffect(_ trail: GestureTrail) {
        let pathView = createDragPathEffect(trail)
        
        // Animate the path
        UIView.animate(
            withDuration: animationDuration * 1.5,
            delay: 0,
            options: [.curveEaseOut],
            animations: {
                pathView.alpha = 0.0
            },
            completion: { _ in
                pathView.removeFromSuperview()
            }
        )
    }
    
    private func createPinchVisualEffect(_ indicator: TouchIndicator, scale: CGFloat) {
        let effectView = createScaleIndicator(at: indicator.position, in: indicator.view, scale: scale)
        
        let targetScale = scale > 1.0 ? 1.5 : 0.5
        
        UIView.animate(
            withDuration: animationDuration,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 1.0,
            options: [.curveEaseOut],
            animations: {
                effectView.transform = CGAffineTransform(scaleX: targetScale, y: targetScale)
                effectView.alpha = 0.0
            },
            completion: { _ in
                effectView.removeFromSuperview()
            }
        )
    }
    
    private func createRotationVisualEffect(_ indicator: TouchIndicator, rotation: CGFloat) {
        let effectView = createRotationIndicator(at: indicator.position, in: indicator.view)
        
        UIView.animate(
            withDuration: animationDuration,
            delay: 0,
            options: [.curveEaseOut],
            animations: {
                effectView.transform = CGAffineTransform(rotationAngle: rotation)
                effectView.alpha = 0.0
            },
            completion: { _ in
                effectView.removeFromSuperview()
            }
        )
    }
    
    private func createLongPressVisualEffect(_ indicator: TouchIndicator, progress: Double) {
        let effectView = createProgressIndicator(at: indicator.position, in: indicator.view, progress: progress)
        
        let duration = progress >= 1.0 ? animationDuration : animationDuration * 0.5
        
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseOut],
            animations: {
                if progress >= 1.0 {
                    effectView.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
                }
                effectView.alpha = progress >= 1.0 ? 0.8 : 0.0
            },
            completion: { _ in
                effectView.removeFromSuperview()
            }
        )
    }
    
    private func createARPlacementVisualEffect(_ indicator: TouchIndicator, success: Bool) {
        let effectView = createARPlacementIndicator(at: indicator.position, in: indicator.view, success: success)
        
        UIView.animate(
            withDuration: animationDuration * 1.5,
            delay: 0,
            usingSpringWithDamping: 0.5,
            initialSpringVelocity: 1.2,
            options: [.curveEaseOut],
            animations: {
                effectView.transform = CGAffineTransform(scaleX: 1.8, y: 1.8)
                effectView.alpha = 0.0
            },
            completion: { _ in
                effectView.removeFromSuperview()
            }
        )
    }
    
    // MARK: - Visual Effect Helpers
    
    private func createRippleEffect(at point: CGPoint, in view: UIView, for type: TouchType) -> UIView {
        let size: CGFloat = type.effectSize
        let effectView = UIView(frame: CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size))
        
        effectView.backgroundColor = type.effectColor.withAlphaComponent(0.3)
        effectView.layer.cornerRadius = size / 2
        effectView.layer.borderWidth = 2.0
        effectView.layer.borderColor = type.effectColor.cgColor
        
        // Add pulse animation
        let pulseAnimation = CABasicAnimation(keyPath: "opacity")
        pulseAnimation.fromValue = 0.8
        pulseAnimation.toValue = 0.2
        pulseAnimation.duration = animationDuration * 0.5
        pulseAnimation.repeatCount = 2
        pulseAnimation.autoreverses = true
        effectView.layer.add(pulseAnimation, forKey: "pulse")
        
        view.addSubview(effectView)
        return effectView
    }
    
    private func createDragPathEffect(_ trail: GestureTrail) -> UIView {
        let pathView = UIView(frame: trail.view.bounds)
        pathView.backgroundColor = .clear
        pathView.alpha = 0.6
        
        let shapeLayer = CAShapeLayer()
        let path = UIBezierPath()
        path.move(to: trail.startPoint)
        path.addLine(to: trail.endPoint)
        
        shapeLayer.path = path.cgPath
        shapeLayer.strokeColor = UIColor.systemBlue.cgColor
        shapeLayer.lineWidth = 4.0
        shapeLayer.lineCap = .round
        shapeLayer.fillColor = UIColor.clear.cgColor
        
        // Add dash pattern for visual appeal
        shapeLayer.lineDashPattern = [8, 4]
        
        pathView.layer.addSublayer(shapeLayer)
        trail.view.addSubview(pathView)
        
        return pathView
    }
    
    private func createScaleIndicator(at point: CGPoint, in view: UIView, scale: CGFloat) -> UIView {
        let size: CGFloat = 60
        let effectView = UIView(frame: CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size))
        
        effectView.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.3)
        effectView.layer.cornerRadius = size / 2
        effectView.layer.borderWidth = 3.0
        effectView.layer.borderColor = UIColor.systemOrange.cgColor
        
        // Add scale text
        let label = UILabel(frame: effectView.bounds)
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .systemOrange
        label.text = String(format: "%.1fx", scale)
        effectView.addSubview(label)
        
        view.addSubview(effectView)
        return effectView
    }
    
    private func createRotationIndicator(at point: CGPoint, in view: UIView) -> UIView {
        let size: CGFloat = 50
        let effectView = UIView(frame: CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size))
        
        // Create rotation arrow
        let imageView = UIImageView(frame: effectView.bounds)
        imageView.image = UIImage(systemName: "arrow.triangle.2.circlepath")
        imageView.tintColor = .systemPurple
        imageView.contentMode = .scaleAspectFit
        
        effectView.addSubview(imageView)
        view.addSubview(effectView)
        
        return effectView
    }
    
    private func createProgressIndicator(at point: CGPoint, in view: UIView, progress: Double) -> UIView {
        let size: CGFloat = 70
        let effectView = UIView(frame: CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size))
        
        // Create progress circle
        let progressLayer = CAShapeLayer()
        let center = CGPoint(x: size/2, y: size/2)
        let radius = size/2 - 5
        
        let circlePath = UIBezierPath(arcCenter: center, radius: radius, startAngle: -CGFloat.pi/2, endAngle: CGFloat.pi * 1.5, clockwise: true)
        
        progressLayer.path = circlePath.cgPath
        progressLayer.strokeColor = UIColor.systemGreen.cgColor
        progressLayer.lineWidth = 6.0
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = CGFloat(progress)
        
        effectView.layer.addSublayer(progressLayer)
        
        if progress >= 1.0 {
            // Add checkmark
            let checkmarkLayer = CAShapeLayer()
            let checkmarkPath = UIBezierPath()
            checkmarkPath.move(to: CGPoint(x: size * 0.3, y: size * 0.5))
            checkmarkPath.addLine(to: CGPoint(x: size * 0.45, y: size * 0.65))
            checkmarkPath.addLine(to: CGPoint(x: size * 0.7, y: size * 0.35))
            
            checkmarkLayer.path = checkmarkPath.cgPath
            checkmarkLayer.strokeColor = UIColor.systemGreen.cgColor
            checkmarkLayer.lineWidth = 4.0
            checkmarkLayer.fillColor = UIColor.clear.cgColor
            checkmarkLayer.lineCap = .round
            checkmarkLayer.lineJoin = .round
            
            effectView.layer.addSublayer(checkmarkLayer)
        }
        
        view.addSubview(effectView)
        return effectView
    }
    
    private func createARPlacementIndicator(at point: CGPoint, in view: UIView, success: Bool) -> UIView {
        let size: CGFloat = 80
        let effectView = UIView(frame: CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size))
        
        let color = success ? UIColor.systemGreen : UIColor.systemRed
        let iconName = success ? "checkmark.circle.fill" : "xmark.circle.fill"
        
        effectView.backgroundColor = color.withAlphaComponent(0.2)
        effectView.layer.cornerRadius = size / 2
        effectView.layer.borderWidth = 3.0
        effectView.layer.borderColor = color.cgColor
        
        // Add icon
        let imageView = UIImageView(frame: CGRect(x: size * 0.3, y: size * 0.3, width: size * 0.4, height: size * 0.4))
        imageView.image = UIImage(systemName: iconName)
        imageView.tintColor = color
        imageView.contentMode = .scaleAspectFit
        
        effectView.addSubview(imageView)
        view.addSubview(effectView)
        
        return effectView
    }
    
    // MARK: - Haptic Feedback
    
    private func playHapticFeedback(for type: TouchType) {
        guard supportsHaptics else {
            // Fallback to system haptics
            playSystemHapticFeedback(for: type)
            return
        }
        
        do {
            let pattern = createHapticPattern(for: type)
            let player = try hapticEngine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            logError("Failed to play haptic feedback", category: .ui, error: error)
            playSystemHapticFeedback(for: type)
        }
    }
    
    private func playDragHapticFeedback(distance: CGFloat) {
        guard supportsHaptics else { return }
        
        let intensity = min(1.0, distance / 200.0) // Normalize to screen distance
        
        do {
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity * feedbackIntensity.rawValue)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ],
                relativeTime: 0,
                duration: 0.1
            )
            
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try hapticEngine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            logError("Failed to play drag haptic feedback", category: .ui, error: error)
        }
    }
    
    private func playScaleHapticFeedback(scale: CGFloat) {
        guard supportsHaptics else { return }
        
        let intensity = scale > 1.0 ? min(1.0, (scale - 1.0) * 2.0) : min(1.0, (1.0 - scale) * 2.0)
        
        do {
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity * feedbackIntensity.rawValue)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: scale > 1.0 ? 0.8 : 0.3)
                ],
                relativeTime: 0
            )
            
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try hapticEngine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            logError("Failed to play scale haptic feedback", category: .ui, error: error)
        }
    }
    
    private func playRotationHapticFeedback(rotation: CGFloat) {
        guard supportsHaptics else { return }
        
        let intensity = min(1.0, abs(rotation) / CGFloat.pi) // Normalize to full rotation
        
        do {
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity * feedbackIntensity.rawValue)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: 0
            )
            
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try hapticEngine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            logError("Failed to play rotation haptic feedback", category: .ui, error: error)
        }
    }
    
    private func createHapticPattern(for type: TouchType) throws -> CHHapticPattern {
        let intensity = feedbackIntensity.rawValue
        
        switch type {
        case .tap, .arSelection:
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: 0
            )
            return try CHHapticPattern(events: [event], parameters: [])
            
        case .longPressComplete:
            let events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity * 0.8)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ], relativeTime: 0),
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                ], relativeTime: 0.1)
            ]
            return try CHHapticPattern(events: events, parameters: [])
            
        case .success, .arPlacementSuccess:
            let events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity * 0.6)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ], relativeTime: 0),
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ], relativeTime: 0.08)
            ]
            return try CHHapticPattern(events: events, parameters: [])
            
        case .failure, .arPlacementFailure:
            let events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ], relativeTime: 0),
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity * 0.7)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
                ], relativeTime: 0.12)
            ]
            return try CHHapticPattern(events: events, parameters: [])
            
        default:
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity * 0.7)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                ],
                relativeTime: 0
            )
            return try CHHapticPattern(events: [event], parameters: [])
        }
    }
    
    private func playSystemHapticFeedback(for type: TouchType) {
        let feedbackGenerator: UIFeedbackGenerator
        
        switch type {
        case .tap, .arSelection:
            feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        case .longPressComplete, .success, .arPlacementSuccess:
            feedbackGenerator = UINotificationFeedbackGenerator()
            (feedbackGenerator as! UINotificationFeedbackGenerator).notificationOccurred(.success)
            return
        case .failure, .arPlacementFailure:
            feedbackGenerator = UINotificationFeedbackGenerator()
            (feedbackGenerator as! UINotificationFeedbackGenerator).notificationOccurred(.error)
            return
        default:
            feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        }
        
        feedbackGenerator.impactOccurred()
    }
    
    // MARK: - Cleanup
    
    private func removeIndicator(_ id: UUID) {
        activeIndicators.removeAll { $0.id == id }
    }
    
    private func removeTrail(_ id: UUID) {
        gestureTrails.removeAll { $0.id == id }
    }
    
    private func distance(from: CGPoint, to: CGPoint) -> CGFloat {
        let dx = to.x - from.x
        let dy = to.y - from.y
        return sqrt(dx*dx + dy*dy)
    }
    
    // MARK: - Settings
    
    public func setFeedbackIntensity(_ intensity: FeedbackIntensity) {
        feedbackIntensity = intensity
        logInfo("Gesture feedback intensity changed", category: .ui, context: LogContext(customData: [
            "intensity": intensity.rawValue
        ]))
    }
    
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            // Clear all active effects
            activeIndicators.removeAll()
            gestureTrails.removeAll()
        }
        
        logInfo("Gesture feedback enabled state changed", category: .ui, context: LogContext(customData: [
            "enabled": enabled
        ]))
    }
}

// MARK: - Supporting Types

public enum FeedbackIntensity: Float, CaseIterable {
    case light = 0.3
    case medium = 0.6
    case strong = 1.0
    
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }
}

public enum TouchType {
    case tap
    case longPress(Double)
    case longPressComplete
    case pinch(CGFloat)
    case rotation(CGFloat)
    case success
    case failure
    case arSelection
    case arPlacementSuccess
    case arPlacementFailure
    case arMove
    case arRotate
    case arScale
    
    var effectSize: CGFloat {
        switch self {
        case .tap, .arSelection: return 40
        case .longPress: return 60
        case .longPressComplete: return 70
        case .pinch, .rotation: return 60
        case .success, .failure: return 50
        case .arPlacementSuccess, .arPlacementFailure: return 80
        case .arMove, .arRotate, .arScale: return 50
        }
    }
    
    var effectColor: UIColor {
        switch self {
        case .tap, .arSelection: return .systemBlue
        case .longPress, .longPressComplete: return .systemGreen
        case .pinch, .arScale: return .systemOrange
        case .rotation, .arRotate: return .systemPurple
        case .success, .arPlacementSuccess: return .systemGreen
        case .failure, .arPlacementFailure: return .systemRed
        case .arMove: return .systemCyan
        }
    }
}

public enum ARManipulationType {
    case move
    case rotate
    case scale
}

private struct TouchIndicator {
    let id: UUID
    let position: CGPoint
    let type: TouchType
    let startTime: Date
    let view: UIView
}

private struct GestureTrail {
    let id: UUID
    let startPoint: CGPoint
    let endPoint: CGPoint
    let startTime: Date
    let view: UIView
}

// MARK: - SwiftUI Integration

public struct GestureFeedbackModifier: ViewModifier {
    @StateObject private var feedback = GestureVisualFeedback.shared
    
    public func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if value.translation == .zero {
                            // This is a tap
                            feedback.showTouchFeedback(
                                at: value.location,
                                in: UIView(), // Would need proper view reference
                                type: .tap
                            )
                        }
                    }
            )
    }
}

extension View {
    public func gestureFeedback() -> some View {
        modifier(GestureFeedbackModifier())
    }
}

// MARK: - UIKit Integration

public class GestureFeedbackView: UIView {
    private let feedbackManager = GestureVisualFeedback.shared
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestureRecognizers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestureRecognizers()
    }
    
    private func setupGestureRecognizers() {
        // Tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
        
        // Long press gesture
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        addGestureRecognizer(longPressGesture)
        
        // Pan gesture
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)
        
        // Pinch gesture
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinchGesture)
        
        // Rotation gesture
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        addGestureRecognizer(rotationGesture)
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        feedbackManager.showTouchFeedback(at: location, in: self, type: .tap)
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        let location = gesture.location(in: self)
        
        switch gesture.state {
        case .began:
            feedbackManager.showLongPressFeedback(at: location, in: self, progress: 0.0)
        case .ended:
            feedbackManager.showLongPressFeedback(at: location, in: self, progress: 1.0)
        default:
            break
        }
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .ended:
            let startLocation = gesture.location(in: self)
            let translation = gesture.translation(in: self)
            let endLocation = CGPoint(x: startLocation.x + translation.x, y: startLocation.y + translation.y)
            
            feedbackManager.showDragFeedback(from: startLocation, to: endLocation, in: self)
        default:
            break
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .changed {
            let location = gesture.location(in: self)
            feedbackManager.showPinchFeedback(at: location, scale: gesture.scale, in: self)
        }
    }
    
    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        if gesture.state == .changed {
            let location = gesture.location(in: self)
            feedbackManager.showRotationFeedback(at: location, rotation: gesture.rotation, in: self)
        }
    }
}