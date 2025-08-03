import Foundation
import UIKit
import SceneKit
import RealityKit
import ARKit
import Metal
import Combine

// MARK: - Dynamic Quality Management System

@MainActor
public class DynamicQualityManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var currentQualityProfile: QualityProfile = .balanced
    @Published public var adaptiveQualityEnabled: Bool = true
    @Published public var performanceMetrics: PerformanceMetrics = PerformanceMetrics()
    @Published public var qualityAdjustments: [QualityAdjustment] = []
    @Published public var deviceCapabilities: DeviceCapabilities = DeviceCapabilities()
    
    // MARK: - Quality Profiles
    public enum QualityProfile: String, CaseIterable {
        case performance = "Performance"
        case balanced = "Balanced"
        case quality = "Quality"
        case adaptive = "Adaptive"
        
        var renderSettings: RenderSettings {
            switch self {
            case .performance:
                return RenderSettings(
                    maxFrameRate: 30,
                    renderScale: 0.7,
                    shadowQuality: .low,
                    lightingQuality: .low,
                    antiAliasing: .none,
                    postProcessing: .minimal,
                    particleCount: .low,
                    geometryLOD: .aggressive,
                    textureQuality: .low,
                    enableOcclusion: false
                )
            case .balanced:
                return RenderSettings(
                    maxFrameRate: 60,
                    renderScale: 0.9,
                    shadowQuality: .medium,
                    lightingQuality: .medium,
                    antiAliasing: .fxaa,
                    postProcessing: .standard,
                    particleCount: .medium,
                    geometryLOD: .balanced,
                    textureQuality: .medium,
                    enableOcclusion: true
                )
            case .quality:
                return RenderSettings(
                    maxFrameRate: 60,
                    renderScale: 1.0,
                    shadowQuality: .high,
                    lightingQuality: .high,
                    antiAliasing: .msaa4x,
                    postProcessing: .full,
                    particleCount: .high,
                    geometryLOD: .conservative,
                    textureQuality: .high,
                    enableOcclusion: true
                )
            case .adaptive:
                return RenderSettings(
                    maxFrameRate: 60,
                    renderScale: 1.0,
                    shadowQuality: .medium,
                    lightingQuality: .medium,
                    antiAliasing: .fxaa,
                    postProcessing: .standard,
                    particleCount: .medium,
                    geometryLOD: .balanced,
                    textureQuality: .automatic,
                    enableOcclusion: true
                )
            }
        }
    }
    
    // MARK: - Quality Settings
    public struct RenderSettings {
        public let maxFrameRate: Int
        public let renderScale: Float
        public let shadowQuality: ShadowQuality
        public let lightingQuality: LightingQuality
        public let antiAliasing: AntiAliasingMode
        public let postProcessing: PostProcessingLevel
        public let particleCount: ParticleCountLevel
        public let geometryLOD: GeometryLODLevel
        public let textureQuality: TextureOptimizationSystem.TextureQuality
        public let enableOcclusion: Bool
    }
    
    public enum ShadowQuality: String, CaseIterable {
        case disabled = "Disabled"
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case ultra = "Ultra"
        
        var shadowMapSize: Int {
            switch self {
            case .disabled: return 0
            case .low: return 512
            case .medium: return 1024
            case .high: return 2048
            case .ultra: return 4096
            }
        }
        
        var cascadeCount: Int {
            switch self {
            case .disabled: return 0
            case .low: return 1
            case .medium: return 2
            case .high: return 3
            case .ultra: return 4
            }
        }
    }
    
    public enum LightingQuality: String, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case ultra = "Ultra"
        
        var maxLights: Int {
            switch self {
            case .low: return 4
            case .medium: return 8
            case .high: return 16
            case .ultra: return 32
            }
        }
        
        var enablePBR: Bool {
            switch self {
            case .low: return false
            case .medium, .high, .ultra: return true
            }
        }
    }
    
    public enum AntiAliasingMode: String, CaseIterable {
        case none = "None"
        case fxaa = "FXAA"
        case msaa2x = "MSAA 2x"
        case msaa4x = "MSAA 4x"
        case msaa8x = "MSAA 8x"
        
        var sampleCount: Int {
            switch self {
            case .none: return 1
            case .fxaa: return 1
            case .msaa2x: return 2
            case .msaa4x: return 4
            case .msaa8x: return 8
            }
        }
    }
    
    public enum PostProcessingLevel: String, CaseIterable {
        case minimal = "Minimal"
        case standard = "Standard"
        case full = "Full"
        case ultra = "Ultra"
        
        var enabledEffects: [PostProcessEffect] {
            switch self {
            case .minimal: return [.tonemapping]
            case .standard: return [.tonemapping, .bloom, .colorGrading]
            case .full: return [.tonemapping, .bloom, .colorGrading, .ssao, .motionBlur]
            case .ultra: return [.tonemapping, .bloom, .colorGrading, .ssao, .motionBlur, .ssr, .dof]
            }
        }
    }
    
    public enum PostProcessEffect: String, CaseIterable {
        case tonemapping = "Tone Mapping"
        case bloom = "Bloom"
        case colorGrading = "Color Grading"
        case ssao = "SSAO"
        case motionBlur = "Motion Blur"
        case ssr = "Screen Space Reflections"
        case dof = "Depth of Field"
    }
    
    public enum ParticleCountLevel: String, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case ultra = "Ultra"
        
        var maxParticles: Int {
            switch self {
            case .low: return 100
            case .medium: return 500
            case .high: return 1000
            case .ultra: return 2000
            }
        }
    }
    
    public enum GeometryLODLevel: String, CaseIterable {
        case aggressive = "Aggressive"
        case balanced = "Balanced"
        case conservative = "Conservative"
        
        var lodBias: Float {
            switch self {
            case .aggressive: return 2.0
            case .balanced: return 1.0
            case .conservative: return 0.5
            }
        }
        
        var cullingDistance: Float {
            switch self {
            case .aggressive: return 20.0
            case .balanced: return 50.0
            case .conservative: return 100.0
            }
        }
    }
    
    // MARK: - Private Properties
    private var performanceProfiler: InstrumentsProfiler
    private var textureOptimizer: TextureOptimizationSystem
    private var frustumCuller: FrustumCullingSystem
    private var objectPooling: ObjectPoolingSystem
    
    // Adaptive system
    private var adaptiveController: AdaptiveQualityController
    private var performanceMonitor: PerformanceMonitor
    private var deviceProfiler: DeviceProfiler
    
    // Quality adjustment tracking
    private var adjustmentHistory: [QualityAdjustmentRecord] = []
    private var lastAdjustmentTime: Date = Date()
    private let minAdjustmentInterval: TimeInterval = 2.0
    
    // External systems integration
    private weak var sceneKitRenderer: SCNRenderer?
    private weak var realityKitARView: ARView?
    
    private var cancellables = Set<AnyCancellable>()
    
    public init(
        performanceProfiler: InstrumentsProfiler,
        textureOptimizer: TextureOptimizationSystem,
        frustumCuller: FrustumCullingSystem,
        objectPooling: ObjectPoolingSystem
    ) {
        self.performanceProfiler = performanceProfiler
        self.textureOptimizer = textureOptimizer
        self.frustumCuller = frustumCuller
        self.objectPooling = objectPooling
        
        self.adaptiveController = AdaptiveQualityController()
        self.performanceMonitor = PerformanceMonitor(profiler: performanceProfiler)
        self.deviceProfiler = DeviceProfiler()
        
        setupQualityManagement()
        
        logDebug("Dynamic quality manager initialized", category: .performance)
    }
    
    // MARK: - Setup
    
    private func setupQualityManagement() {
        // Profile device capabilities
        profileDeviceCapabilities()
        
        // Set initial quality profile based on device
        setOptimalInitialQuality()
        
        // Setup performance monitoring
        setupPerformanceMonitoring()
        
        // Setup adaptive quality control
        setupAdaptiveControl()
        
        logInfo("Quality management setup completed", category: .performance, context: LogContext(customData: [
            "initial_profile": currentQualityProfile.rawValue,
            "device_tier": deviceCapabilities.deviceTier.rawValue
        ]))
    }
    
    private func profileDeviceCapabilities() {
        deviceCapabilities = deviceProfiler.profileDevice()
        
        logInfo("Device profiled", category: .performance, context: LogContext(customData: [
            "device_tier": deviceCapabilities.deviceTier.rawValue,
            "gpu_family": deviceCapabilities.gpuFamily.rawValue,
            "memory_gb": deviceCapabilities.availableMemoryGB,
            "thermal_design": deviceCapabilities.thermalDesignPower
        ]))
    }
    
    private func setOptimalInitialQuality() {
        let optimalProfile = determineOptimalQualityProfile()
        setQualityProfile(optimalProfile, reason: "Initial device-based optimization")
    }
    
    private func setupPerformanceMonitoring() {
        // Monitor frame rate
        performanceMonitor.$currentFPS
            .sink { [weak self] fps in
                self?.handleFrameRateChange(fps)
            }
            .store(in: &cancellables)
        
        // Monitor memory pressure
        performanceMonitor.$memoryPressure
            .sink { [weak self] pressure in
                self?.handleMemoryPressureChange(pressure)
            }
            .store(in: &cancellables)
        
        // Monitor thermal state
        performanceMonitor.$thermalState
            .sink { [weak self] state in
                self?.handleThermalStateChange(state)
            }
            .store(in: &cancellables)
        
        // Monitor battery level
        performanceMonitor.$batteryLevel
            .sink { [weak self] level in
                self?.handleBatteryLevelChange(level)
            }
            .store(in: &cancellables)
    }
    
    private func setupAdaptiveControl() {
        guard adaptiveQualityEnabled else { return }
        
        // Start adaptive quality adjustment timer
        Timer.publish(every: 1.0, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.performAdaptiveQualityCheck()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Quality Profile Management
    
    public func setQualityProfile(_ profile: QualityProfile, reason: String = "Manual adjustment") {
        let previousProfile = currentQualityProfile
        currentQualityProfile = profile
        
        // Apply quality settings
        applyQualitySettings(profile.renderSettings)
        
        // Record adjustment
        recordQualityAdjustment(
            from: previousProfile,
            to: profile,
            reason: reason,
            isAutomatic: reason != "Manual adjustment"
        )
        
        logInfo("Quality profile changed", category: .performance, context: LogContext(customData: [
            "from": previousProfile.rawValue,
            "to": profile.rawValue,
            "reason": reason
        ]))
    }
    
    private func applyQualitySettings(_ settings: RenderSettings) {
        // Apply to SceneKit renderer
        if let scnRenderer = sceneKitRenderer {
            applySceneKitSettings(scnRenderer, settings: settings)
        }
        
        // Apply to RealityKit ARView
        if let arView = realityKitARView {
            applyRealityKitSettings(arView, settings: settings)
        }
        
        // Apply to subsystems
        applySubsystemSettings(settings)
    }
    
    private func applySceneKitSettings(_ renderer: SCNRenderer, settings: RenderSettings) {
        // Frame rate
        if let scnView = renderer as? SCNView {
            scnView.preferredFramesPerSecond = settings.maxFrameRate
        }
        
        // Render scale
        renderer.renderingAPI = .metal
        
        // Antialiasing
        renderer.antialiasingMode = convertAntiAliasingMode(settings.antiAliasing)
        
        // Shadows
        renderer.showsStatistics = false // Disable for performance
        
        logDebug("Applied SceneKit quality settings", category: .performance, context: LogContext(customData: [
            "frame_rate": settings.maxFrameRate,
            "render_scale": settings.renderScale,
            "aa_mode": settings.antiAliasing.rawValue
        ]))
    }
    
    private func applyRealityKitSettings(_ arView: ARView, settings: RenderSettings) {
        // Frame rate
        arView.renderOptions.insert(.disableHDR)
        
        if settings.renderScale < 1.0 {
            arView.renderOptions.insert(.disableMotionBlur)
        }
        
        // Antialiasing
        if settings.antiAliasing == .none {
            arView.renderOptions.insert(.disableAREnvironmentLighting)
        }
        
        logDebug("Applied RealityKit quality settings", category: .performance, context: LogContext(customData: [
            "render_scale": settings.renderScale,
            "hdr_disabled": true
        ]))
    }
    
    private func applySubsystemSettings(_ settings: RenderSettings) {
        // Texture quality
        textureOptimizer.setTextureQuality(settings.textureQuality)
        
        // Frustum culling
        let cullingMode: FrustumCullingSystem.CullingMode
        switch settings.geometryLOD {
        case .aggressive:
            cullingMode = .aggressive
        case .balanced:
            cullingMode = .normal
        case .conservative:
            cullingMode = .conservative
        }
        frustumCuller.setCullingMode(cullingMode)
        
        logDebug("Applied subsystem quality settings", category: .performance, context: LogContext(customData: [
            "texture_quality": settings.textureQuality.rawValue,
            "culling_mode": String(describing: cullingMode)
        ]))
    }
    
    // MARK: - Adaptive Quality Control
    
    private func performAdaptiveQualityCheck() {
        guard adaptiveQualityEnabled && currentQualityProfile == .adaptive else { return }
        guard Date().timeIntervalSince(lastAdjustmentTime) >= minAdjustmentInterval else { return }
        
        let currentMetrics = performanceMonitor.getCurrentMetrics()
        let recommendation = adaptiveController.analyzePerformance(
            metrics: currentMetrics,
            deviceCapabilities: deviceCapabilities,
            currentSettings: currentQualityProfile.renderSettings
        )
        
        if let adjustment = recommendation {
            applyAdaptiveAdjustment(adjustment)
        }
    }
    
    private func applyAdaptiveAdjustment(_ adjustment: QualityAdjustment) {
        switch adjustment.type {
        case .increaseQuality:
            adjustQualityUpward(adjustment)
        case .decreaseQuality:
            adjustQualityDownward(adjustment)
        case .optimizeSpecific:
            applySpecificOptimization(adjustment)
        }
        
        qualityAdjustments.append(adjustment)
        lastAdjustmentTime = Date()
        
        logInfo("Applied adaptive quality adjustment", category: .performance, context: LogContext(customData: [
            "adjustment_type": adjustment.type.rawValue,
            "reason": adjustment.reason,
            "impact": adjustment.expectedImpact
        ]))
    }
    
    private func adjustQualityUpward(_ adjustment: QualityAdjustment) {
        var newSettings = currentQualityProfile.renderSettings
        
        // Gradually increase quality settings
        if adjustment.affectedSettings.contains(.shadows) {
            newSettings = increaseShadowQuality(newSettings)
        }
        
        if adjustment.affectedSettings.contains(.lighting) {
            newSettings = increaseLightingQuality(newSettings)
        }
        
        if adjustment.affectedSettings.contains(.textures) {
            newSettings = increaseTextureQuality(newSettings)
        }
        
        if adjustment.affectedSettings.contains(.postProcessing) {
            newSettings = increasePostProcessingQuality(newSettings)
        }
        
        applyQualitySettings(newSettings)
    }
    
    private func adjustQualityDownward(_ adjustment: QualityAdjustment) {
        var newSettings = currentQualityProfile.renderSettings
        
        // Decrease quality settings to improve performance
        if adjustment.affectedSettings.contains(.shadows) {
            newSettings = decreaseShadowQuality(newSettings)
        }
        
        if adjustment.affectedSettings.contains(.lighting) {
            newSettings = decreaseLightingQuality(newSettings)
        }
        
        if adjustment.affectedSettings.contains(.textures) {
            newSettings = decreaseTextureQuality(newSettings)
        }
        
        if adjustment.affectedSettings.contains(.postProcessing) {
            newSettings = decreasePostProcessingQuality(newSettings)
        }
        
        applyQualitySettings(newSettings)
    }
    
    private func applySpecificOptimization(_ adjustment: QualityAdjustment) {
        // Apply specific optimizations based on the adjustment
        switch adjustment.specificOptimization {
        case .reduceLODDistance:
            frustumCuller.setCullingMode(.aggressive)
        case .enableAggressiveCulling:
            frustumCuller.setCullingMode(.aggressive)
        case .reduceParticleCount:
            // Reduce particle count
            break
        case .disableExpensiveEffects:
            // Disable expensive post-processing effects
            break
        case .none:
            break
        }
    }
    
    // MARK: - Quality Adjustment Helpers
    
    private func increaseShadowQuality(_ settings: RenderSettings) -> RenderSettings {
        let newShadowQuality: ShadowQuality
        switch settings.shadowQuality {
        case .disabled: newShadowQuality = .low
        case .low: newShadowQuality = .medium
        case .medium: newShadowQuality = .high
        case .high: newShadowQuality = .ultra
        case .ultra: newShadowQuality = .ultra
        }
        
        return RenderSettings(
            maxFrameRate: settings.maxFrameRate,
            renderScale: settings.renderScale,
            shadowQuality: newShadowQuality,
            lightingQuality: settings.lightingQuality,
            antiAliasing: settings.antiAliasing,
            postProcessing: settings.postProcessing,
            particleCount: settings.particleCount,
            geometryLOD: settings.geometryLOD,
            textureQuality: settings.textureQuality,
            enableOcclusion: settings.enableOcclusion
        )
    }
    
    private func decreaseShadowQuality(_ settings: RenderSettings) -> RenderSettings {
        let newShadowQuality: ShadowQuality
        switch settings.shadowQuality {
        case .disabled: newShadowQuality = .disabled
        case .low: newShadowQuality = .disabled
        case .medium: newShadowQuality = .low
        case .high: newShadowQuality = .medium
        case .ultra: newShadowQuality = .high
        }
        
        return RenderSettings(
            maxFrameRate: settings.maxFrameRate,
            renderScale: settings.renderScale,
            shadowQuality: newShadowQuality,
            lightingQuality: settings.lightingQuality,
            antiAliasing: settings.antiAliasing,
            postProcessing: settings.postProcessing,
            particleCount: settings.particleCount,
            geometryLOD: settings.geometryLOD,
            textureQuality: settings.textureQuality,
            enableOcclusion: settings.enableOcclusion
        )
    }
    
    private func increaseLightingQuality(_ settings: RenderSettings) -> RenderSettings {
        let newLightingQuality: LightingQuality
        switch settings.lightingQuality {
        case .low: newLightingQuality = .medium
        case .medium: newLightingQuality = .high
        case .high: newLightingQuality = .ultra
        case .ultra: newLightingQuality = .ultra
        }
        
        return RenderSettings(
            maxFrameRate: settings.maxFrameRate,
            renderScale: settings.renderScale,
            shadowQuality: settings.shadowQuality,
            lightingQuality: newLightingQuality,
            antiAliasing: settings.antiAliasing,
            postProcessing: settings.postProcessing,
            particleCount: settings.particleCount,
            geometryLOD: settings.geometryLOD,
            textureQuality: settings.textureQuality,
            enableOcclusion: settings.enableOcclusion
        )
    }
    
    private func decreaseLightingQuality(_ settings: RenderSettings) -> RenderSettings {
        let newLightingQuality: LightingQuality
        switch settings.lightingQuality {
        case .low: newLightingQuality = .low
        case .medium: newLightingQuality = .low
        case .high: newLightingQuality = .medium
        case .ultra: newLightingQuality = .high
        }
        
        return RenderSettings(
            maxFrameRate: settings.maxFrameRate,
            renderScale: settings.renderScale,
            shadowQuality: settings.shadowQuality,
            lightingQuality: newLightingQuality,
            antiAliasing: settings.antiAliasing,
            postProcessing: settings.postProcessing,
            particleCount: settings.particleCount,
            geometryLOD: settings.geometryLOD,
            textureQuality: settings.textureQuality,
            enableOcclusion: settings.enableOcclusion
        )
    }
    
    private func increaseTextureQuality(_ settings: RenderSettings) -> RenderSettings {
        let newTextureQuality: TextureOptimizationSystem.TextureQuality
        switch settings.textureQuality {
        case .low: newTextureQuality = .medium
        case .medium: newTextureQuality = .high
        case .high: newTextureQuality = .ultra
        case .ultra, .automatic: newTextureQuality = settings.textureQuality
        }
        
        return RenderSettings(
            maxFrameRate: settings.maxFrameRate,
            renderScale: settings.renderScale,
            shadowQuality: settings.shadowQuality,
            lightingQuality: settings.lightingQuality,
            antiAliasing: settings.antiAliasing,
            postProcessing: settings.postProcessing,
            particleCount: settings.particleCount,
            geometryLOD: settings.geometryLOD,
            textureQuality: newTextureQuality,
            enableOcclusion: settings.enableOcclusion
        )
    }
    
    private func decreaseTextureQuality(_ settings: RenderSettings) -> RenderSettings {
        let newTextureQuality: TextureOptimizationSystem.TextureQuality
        switch settings.textureQuality {
        case .low: newTextureQuality = .low
        case .medium: newTextureQuality = .low
        case .high: newTextureQuality = .medium
        case .ultra: newTextureQuality = .high
        case .automatic: newTextureQuality = .medium
        }
        
        return RenderSettings(
            maxFrameRate: settings.maxFrameRate,
            renderScale: settings.renderScale,
            shadowQuality: settings.shadowQuality,
            lightingQuality: settings.lightingQuality,
            antiAliasing: settings.antiAliasing,
            postProcessing: settings.postProcessing,
            particleCount: settings.particleCount,
            geometryLOD: settings.geometryLOD,
            textureQuality: newTextureQuality,
            enableOcclusion: settings.enableOcclusion
        )
    }
    
    private func increasePostProcessingQuality(_ settings: RenderSettings) -> RenderSettings {
        let newPostProcessing: PostProcessingLevel
        switch settings.postProcessing {
        case .minimal: newPostProcessing = .standard
        case .standard: newPostProcessing = .full
        case .full: newPostProcessing = .ultra
        case .ultra: newPostProcessing = .ultra
        }
        
        return RenderSettings(
            maxFrameRate: settings.maxFrameRate,
            renderScale: settings.renderScale,
            shadowQuality: settings.shadowQuality,
            lightingQuality: settings.lightingQuality,
            antiAliasing: settings.antiAliasing,
            postProcessing: newPostProcessing,
            particleCount: settings.particleCount,
            geometryLOD: settings.geometryLOD,
            textureQuality: settings.textureQuality,
            enableOcclusion: settings.enableOcclusion
        )
    }
    
    private func decreasePostProcessingQuality(_ settings: RenderSettings) -> RenderSettings {
        let newPostProcessing: PostProcessingLevel
        switch settings.postProcessing {
        case .minimal: newPostProcessing = .minimal
        case .standard: newPostProcessing = .minimal
        case .full: newPostProcessing = .standard
        case .ultra: newPostProcessing = .full
        }
        
        return RenderSettings(
            maxFrameRate: settings.maxFrameRate,
            renderScale: settings.renderScale,
            shadowQuality: settings.shadowQuality,
            lightingQuality: settings.lightingQuality,
            antiAliasing: settings.antiAliasing,
            postProcessing: newPostProcessing,
            particleCount: settings.particleCount,
            geometryLOD: settings.geometryLOD,
            textureQuality: settings.textureQuality,
            enableOcclusion: settings.enableOcclusion
        )
    }
    
    // MARK: - Event Handlers
    
    private func handleFrameRateChange(_ fps: Double) {
        guard adaptiveQualityEnabled else { return }
        
        if fps < 25 && currentQualityProfile != .performance {
            // Frame rate too low, reduce quality
            setQualityProfile(.performance, reason: "Low frame rate: \(fps) FPS")
        } else if fps > 55 && currentQualityProfile == .performance {
            // Frame rate good, can increase quality
            setQualityProfile(.balanced, reason: "Frame rate recovered: \(fps) FPS")
        }
    }
    
    private func handleMemoryPressureChange(_ pressure: MemoryPressureLevel) {
        guard adaptiveQualityEnabled else { return }
        
        switch pressure {
        case .critical:
            setQualityProfile(.performance, reason: "Critical memory pressure")
        case .warning:
            if currentQualityProfile == .quality {
                setQualityProfile(.balanced, reason: "Memory pressure warning")
            }
        case .normal:
            // Can potentially increase quality if performance allows
            break
        }
    }
    
    private func handleThermalStateChange(_ state: ProcessInfo.ThermalState) {
        guard adaptiveQualityEnabled else { return }
        
        switch state {
        case .critical:
            setQualityProfile(.performance, reason: "Critical thermal state")
        case .serious:
            if currentQualityProfile == .quality {
                setQualityProfile(.balanced, reason: "Serious thermal state")
            }
        case .fair:
            if currentQualityProfile == .quality {
                setQualityProfile(.balanced, reason: "Fair thermal state")
            }
        case .nominal:
            // Normal state, no immediate changes needed
            break
        @unknown default:
            break
        }
    }
    
    private func handleBatteryLevelChange(_ level: Float) {
        guard adaptiveQualityEnabled else { return }
        
        if level < 0.2 && currentQualityProfile != .performance {
            // Low battery, reduce quality to save power
            setQualityProfile(.performance, reason: "Low battery: \(Int(level * 100))%")
        }
    }
    
    // MARK: - Quality Profile Determination
    
    private func determineOptimalQualityProfile() -> QualityProfile {
        switch deviceCapabilities.deviceTier {
        case .low:
            return .performance
        case .medium:
            return .balanced
        case .high:
            return .quality
        case .flagship:
            return .adaptive
        }
    }
    
    // MARK: - Utility Methods
    
    private func convertAntiAliasingMode(_ mode: AntiAliasingMode) -> SCNAntialiasingMode {
        switch mode {
        case .none: return .none
        case .fxaa: return .none // SceneKit doesn't have FXAA, use none
        case .msaa2x: return .multisampling2X
        case .msaa4x: return .multisampling4X
        case .msaa8x: return .multisampling4X // SceneKit max is 4x
        }
    }
    
    private func recordQualityAdjustment(from: QualityProfile, to: QualityProfile, reason: String, isAutomatic: Bool) {
        let record = QualityAdjustmentRecord(
            id: UUID(),
            timestamp: Date(),
            fromProfile: from,
            toProfile: to,
            reason: reason,
            isAutomatic: isAutomatic,
            performanceMetrics: performanceMonitor.getCurrentMetrics()
        )
        
        adjustmentHistory.append(record)
        
        // Keep only recent history
        if adjustmentHistory.count > 100 {
            adjustmentHistory.removeFirst(adjustmentHistory.count - 100)
        }
    }
    
    // MARK: - Public Interface
    
    public func setRenderer(_ renderer: SCNRenderer) {
        sceneKitRenderer = renderer
        applyQualitySettings(currentQualityProfile.renderSettings)
    }
    
    public func setARView(_ arView: ARView) {
        realityKitARView = arView
        applyQualitySettings(currentQualityProfile.renderSettings)
    }
    
    public func enableAdaptiveQuality(_ enabled: Bool) {
        adaptiveQualityEnabled = enabled
        
        if enabled {
            setupAdaptiveControl()
            setQualityProfile(.adaptive, reason: "Adaptive quality enabled")
        }
        
        logInfo("Adaptive quality \(enabled ? "enabled" : "disabled")", category: .performance)
    }
    
    public func forceQualityCheck() {
        performAdaptiveQualityCheck()
    }
    
    public func getQualityStatistics() -> [String: Any] {
        return [
            "current_profile": currentQualityProfile.rawValue,
            "adaptive_enabled": adaptiveQualityEnabled,
            "total_adjustments": adjustmentHistory.count,
            "automatic_adjustments": adjustmentHistory.filter { $0.isAutomatic }.count,
            "device_tier": deviceCapabilities.deviceTier.rawValue,
            "current_fps": performanceMetrics.currentFPS,
            "memory_usage_mb": performanceMetrics.memoryUsage / (1024 * 1024),
            "thermal_state": String(describing: performanceMetrics.thermalState)
        ]
    }
    
    public func getQualityHistory() -> [QualityAdjustmentRecord] {
        return adjustmentHistory
    }
    
    public func resetQualityToOptimal() {
        let optimalProfile = determineOptimalQualityProfile()
        setQualityProfile(optimalProfile, reason: "Reset to optimal")
        
        // Clear adjustment history
        adjustmentHistory.removeAll()
        qualityAdjustments.removeAll()
    }
    
    deinit {
        logDebug("Dynamic quality manager deinitialized", category: .performance)
    }
}

// MARK: - Supporting Data Structures

public struct QualityAdjustment {
    public let id: UUID
    public let timestamp: Date
    public let type: AdjustmentType
    public let reason: String
    public let expectedImpact: String
    public let affectedSettings: Set<QualitySetting>
    public let specificOptimization: SpecificOptimization
    
    public enum AdjustmentType: String {
        case increaseQuality = "Increase Quality"
        case decreaseQuality = "Decrease Quality"
        case optimizeSpecific = "Optimize Specific"
    }
    
    public enum QualitySetting: String, CaseIterable {
        case shadows = "Shadows"
        case lighting = "Lighting"
        case textures = "Textures"
        case postProcessing = "Post Processing"
        case antiAliasing = "Anti-Aliasing"
        case renderScale = "Render Scale"
        case particleCount = "Particle Count"
        case geometryLOD = "Geometry LOD"
    }
    
    public enum SpecificOptimization {
        case none
        case reduceLODDistance
        case enableAggressiveCulling
        case reduceParticleCount
        case disableExpensiveEffects
    }
    
    public init(
        type: AdjustmentType,
        reason: String,
        expectedImpact: String,
        affectedSettings: Set<QualitySetting> = [],
        specificOptimization: SpecificOptimization = .none
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.reason = reason
        self.expectedImpact = expectedImpact
        self.affectedSettings = affectedSettings
        self.specificOptimization = specificOptimization
    }
}

public struct QualityAdjustmentRecord {
    public let id: UUID
    public let timestamp: Date
    public let fromProfile: DynamicQualityManager.QualityProfile
    public let toProfile: DynamicQualityManager.QualityProfile
    public let reason: String
    public let isAutomatic: Bool
    public let performanceMetrics: PerformanceSnapshot
}

public struct PerformanceSnapshot {
    public let fps: Double
    public let memoryUsage: UInt64
    public let thermalState: ProcessInfo.ThermalState
    public let batteryLevel: Float
    public let cpuUsage: Double
    public let gpuUsage: Double
}

// MARK: - Device Capabilities Extended

extension DeviceCapabilities {
    public enum DeviceTier: String {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case flagship = "Flagship"
    }
    
    public enum GPUFamily: String {
        case apple1 = "Apple GPU Family 1"
        case apple2 = "Apple GPU Family 2"
        case apple3 = "Apple GPU Family 3"
        case apple4 = "Apple GPU Family 4"
        case apple5 = "Apple GPU Family 5"
        case apple6 = "Apple GPU Family 6"
        case apple7 = "Apple GPU Family 7"
        case apple8 = "Apple GPU Family 8"
        case unknown = "Unknown"
    }
    
    public var deviceTier: DeviceTier {
        let totalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        
        if totalMemoryGB >= 8 {
            return .flagship
        } else if totalMemoryGB >= 6 {
            return .high
        } else if totalMemoryGB >= 4 {
            return .medium
        } else {
            return .low
        }
    }
    
    public var gpuFamily: GPUFamily {
        guard let device = MTLCreateSystemDefaultDevice() else { return .unknown }
        
        if device.supportsFeatureSet(.iOS_GPUFamily5_v1) {
            return .apple8
        } else if device.supportsFeatureSet(.iOS_GPUFamily4_v1) {
            return .apple7
        } else if device.supportsFeatureSet(.iOS_GPUFamily3_v1) {
            return .apple6
        } else if device.supportsFeatureSet(.iOS_GPUFamily2_v1) {
            return .apple5
        } else if device.supportsFeatureSet(.iOS_GPUFamily1_v1) {
            return .apple4
        } else {
            return .unknown
        }
    }
    
    public var availableMemoryGB: Double {
        return Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }
    
    public var thermalDesignPower: Double {
        // Estimate based on device tier
        switch deviceTier {
        case .low: return 3.0
        case .medium: return 5.0
        case .high: return 7.0
        case .flagship: return 10.0
        }
    }
}

// MARK: - Adaptive Quality Controller

class AdaptiveQualityController {
    private var performanceHistory: [PerformanceSnapshot] = []
    private let historyLimit = 60 // Keep 1 minute of history at 1 FPS sampling
    
    func analyzePerformance(
        metrics: PerformanceSnapshot,
        deviceCapabilities: DeviceCapabilities,
        currentSettings: DynamicQualityManager.RenderSettings
    ) -> QualityAdjustment? {
        
        // Add to performance history
        performanceHistory.append(metrics)
        if performanceHistory.count > historyLimit {
            performanceHistory.removeFirst()
        }
        
        // Analyze trends
        let recentAvgFPS = getRecentAverageFPS()
        let fpsStability = getFPSStability()
        
        // Determine if adjustment is needed
        if recentAvgFPS < 25 && fpsStability < 0.8 {
            // Performance is poor and unstable, reduce quality
            return QualityAdjustment(
                type: .decreaseQuality,
                reason: "Poor performance: \(Int(recentAvgFPS)) FPS",
                expectedImpact: "Improve frame rate by 15-25%",
                affectedSettings: [.shadows, .postProcessing, .textures]
            )
        } else if recentAvgFPS > 55 && fpsStability > 0.95 && deviceCapabilities.deviceTier != .low {
            // Performance is excellent and stable, can increase quality
            return QualityAdjustment(
                type: .increaseQuality,
                reason: "Excellent performance: \(Int(recentAvgFPS)) FPS",
                expectedImpact: "Improve visual quality with minimal performance impact",
                affectedSettings: [.lighting, .textures]
            )
        }
        
        return nil
    }
    
    private func getRecentAverageFPS() -> Double {
        guard !performanceHistory.isEmpty else { return 60.0 }
        
        let recentSamples = performanceHistory.suffix(10)
        return recentSamples.map { $0.fps }.reduce(0, +) / Double(recentSamples.count)
    }
    
    private func getFPSStability() -> Double {
        guard performanceHistory.count >= 10 else { return 1.0 }
        
        let recentSamples = performanceHistory.suffix(10).map { $0.fps }
        let average = recentSamples.reduce(0, +) / Double(recentSamples.count)
        let variance = recentSamples.map { pow($0 - average, 2) }.reduce(0, +) / Double(recentSamples.count)
        let standardDeviation = sqrt(variance)
        
        // Normalize stability score (lower deviation = higher stability)
        return max(0, 1.0 - (standardDeviation / average))
    }
}

// MARK: - Performance Monitor

class PerformanceMonitor: ObservableObject {
    @Published var currentFPS: Double = 60.0
    @Published var memoryPressure: MemoryPressureLevel = .normal
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var batteryLevel: Float = 1.0
    
    private let profiler: InstrumentsProfiler
    private var displayLink: CADisplayLink?
    private var frameCount: Int = 0
    private var lastTimestamp: CFTimeInterval = 0
    
    init(profiler: InstrumentsProfiler) {
        self.profiler = profiler
        startMonitoring()
    }
    
    private func startMonitoring() {
        // Monitor frame rate
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkCallback))
        displayLink?.add(to: .main, forMode: .common)
        
        // Monitor other metrics
        Timer.publish(every: 1.0, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateMetrics()
            }
            .store(in: &profiler.cancellables)
    }
    
    @objc private func displayLinkCallback(displayLink: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = displayLink.timestamp
            return
        }
        
        frameCount += 1
        let elapsed = displayLink.timestamp - lastTimestamp
        
        if elapsed >= 1.0 {
            currentFPS = Double(frameCount) / elapsed
            frameCount = 0
            lastTimestamp = displayLink.timestamp
        }
    }
    
    private func updateMetrics() {
        // Update thermal state
        thermalState = ProcessInfo.processInfo.thermalState
        
        // Update battery level
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel
        
        // Update memory pressure (simplified)
        let memoryInfo = getMemoryInfo()
        let usagePercentage = Double(memoryInfo.used) / Double(ProcessInfo.processInfo.physicalMemory)
        
        if usagePercentage > 0.9 {
            memoryPressure = .critical
        } else if usagePercentage > 0.7 {
            memoryPressure = .warning
        } else {
            memoryPressure = .normal
        }
    }
    
    func getCurrentMetrics() -> PerformanceSnapshot {
        return PerformanceSnapshot(
            fps: currentFPS,
            memoryUsage: getMemoryInfo().used,
            thermalState: thermalState,
            batteryLevel: batteryLevel,
            cpuUsage: 0.0, // Would need additional implementation
            gpuUsage: 0.0  // Would need additional implementation
        )
    }
    
    private func getMemoryInfo() -> (used: UInt64, available: UInt64) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let used = UInt64(info.resident_size)
            let total = ProcessInfo.processInfo.physicalMemory
            return (used, total - used)
        }
        
        return (0, 0)
    }
    
    deinit {
        displayLink?.invalidate()
    }
}

// MARK: - Device Profiler

class DeviceProfiler {
    func profileDevice() -> DeviceCapabilities {
        let capabilities = DeviceCapabilities()
        
        // Additional device profiling logic would go here
        // This would include GPU benchmarking, memory bandwidth tests, etc.
        
        return capabilities
    }
}