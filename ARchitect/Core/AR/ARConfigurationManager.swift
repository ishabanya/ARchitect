import Foundation
import ARKit

/// Manages AR configuration creation and validation following single responsibility principle
final class ARConfigurationManager {
    
    // MARK: - Configuration Creation
    
    /// Creates an AR configuration based on provided options
    /// - Parameter options: Configuration options to apply
    /// - Returns: Configured ARWorldTrackingConfiguration
    /// - Throws: ARConfigurationError if configuration is invalid
    func createConfiguration(with options: ARConfigurationOptions) throws -> ARWorldTrackingConfiguration {
        guard ARWorldTrackingConfiguration.isSupported else {
            throw ARConfigurationError.deviceNotSupported
        }
        
        let config = ARWorldTrackingConfiguration()
        
        try applyPlaneDetection(options.planeDetection, to: config)
        try applySceneReconstruction(options.sceneReconstruction, to: config)
        try applyEnvironmentTexturing(options.environmentTexturing, to: config)
        try applyFrameSemantics(options.frameSemantics, to: config)
        try applyDetectionImages(options.detectionImages, maxImages: options.maximumNumberOfTrackedImages, to: config)
        
        config.providesAudioData = options.providesAudioData
        config.isLightEstimationEnabled = options.isLightEstimationEnabled
        config.isCollaborationEnabled = options.isCollaborationEnabled
        
        return config
    }
    
    /// Validates if the given configuration options are supported on the current device
    /// - Parameter options: Configuration options to validate
    /// - Returns: ValidationResult with supported/unsupported features
    func validateConfiguration(_ options: ARConfigurationOptions) -> ConfigurationValidationResult {
        var supportedFeatures: [String] = []
        var unsupportedFeatures: [String] = []
        var warnings: [String] = []
        
        // Check basic AR support
        if !ARWorldTrackingConfiguration.isSupported {
            unsupportedFeatures.append("ARWorldTracking")
            return ConfigurationValidationResult(
                isValid: false,
                supportedFeatures: supportedFeatures,
                unsupportedFeatures: unsupportedFeatures,
                warnings: warnings
            )
        }
        
        supportedFeatures.append("ARWorldTracking")
        
        // Check scene reconstruction
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(options.sceneReconstruction) {
            supportedFeatures.append("SceneReconstruction: \(options.sceneReconstruction)")
        } else if options.sceneReconstruction != .none {
            unsupportedFeatures.append("SceneReconstruction: \(options.sceneReconstruction)")
            warnings.append("Scene reconstruction will be disabled")
        }
        
        // Check frame semantics
        if ARWorldTrackingConfiguration.supportsFrameSemantics(options.frameSemantics) {
            supportedFeatures.append("FrameSemantics: \(options.frameSemantics)")
        } else if !options.frameSemantics.isEmpty {
            unsupportedFeatures.append("FrameSemantics: \(options.frameSemantics)")
            warnings.append("Frame semantics will be disabled")
        }
        
        // Check plane detection
        supportedFeatures.append("PlaneDetection: \(options.planeDetection)")
        
        // Check collaboration
        if options.isCollaborationEnabled {
            supportedFeatures.append("Collaboration")
        }
        
        // Check light estimation
        if options.isLightEstimationEnabled {
            supportedFeatures.append("LightEstimation")
        }
        
        return ConfigurationValidationResult(
            isValid: unsupportedFeatures.isEmpty,
            supportedFeatures: supportedFeatures,
            unsupportedFeatures: unsupportedFeatures,
            warnings: warnings
        )
    }
    
    /// Creates a fallback configuration for devices with limited AR capabilities
    /// - Returns: Basic AR configuration that should work on most devices
    func createFallbackConfiguration() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.sceneReconstruction = .none
        config.environmentTexturing = .none
        config.frameSemantics = []
        config.providesAudioData = false
        config.isLightEstimationEnabled = false
        config.isCollaborationEnabled = false
        return config
    }
    
    // MARK: - Private Methods
    
    private func applyPlaneDetection(_ planeDetection: ARWorldTrackingConfiguration.PlaneDetection, to config: ARWorldTrackingConfiguration) throws {
        config.planeDetection = planeDetection
    }
    
    private func applySceneReconstruction(_ sceneReconstruction: ARWorldTrackingConfiguration.SceneReconstruction, to config: ARWorldTrackingConfiguration) throws {
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(sceneReconstruction) {
            config.sceneReconstruction = sceneReconstruction
        } else if sceneReconstruction != .none {
            logWarning("Scene reconstruction not supported, falling back to none", category: .ar)
            config.sceneReconstruction = .none
        }
    }
    
    private func applyEnvironmentTexturing(_ environmentTexturing: ARWorldTrackingConfiguration.EnvironmentTexturing, to config: ARWorldTrackingConfiguration) throws {
        config.environmentTexturing = environmentTexturing
    }
    
    private func applyFrameSemantics(_ frameSemantics: ARConfiguration.FrameSemantics, to config: ARWorldTrackingConfiguration) throws {
        if ARWorldTrackingConfiguration.supportsFrameSemantics(frameSemantics) {
            config.frameSemantics = frameSemantics
        } else if !frameSemantics.isEmpty {
            logWarning("Frame semantics not supported, disabling", category: .ar)
            config.frameSemantics = []
        }
    }
    
    private func applyDetectionImages(_ detectionImages: Set<ARReferenceImage>?, maxImages: Int, to config: ARWorldTrackingConfiguration) throws {
        if let images = detectionImages, !images.isEmpty {
            config.detectionImages = images
            config.maximumNumberOfTrackedImages = maxImages
        }
    }
}

// MARK: - Supporting Types

struct ConfigurationValidationResult {
    let isValid: Bool
    let supportedFeatures: [String]
    let unsupportedFeatures: [String]
    let warnings: [String]
    
    var summary: String {
        var lines: [String] = []
        
        if isValid {
            lines.append("✅ Configuration is valid")
        } else {
            lines.append("❌ Configuration has issues")
        }
        
        if !supportedFeatures.isEmpty {
            lines.append("Supported: \(supportedFeatures.joined(separator: ", "))")
        }
        
        if !unsupportedFeatures.isEmpty {
            lines.append("Unsupported: \(unsupportedFeatures.joined(separator: ", "))")
        }
        
        if !warnings.isEmpty {
            lines.append("Warnings: \(warnings.joined(separator: ", "))")
        }
        
        return lines.joined(separator: "\n")
    }
}

enum ARConfigurationError: LocalizedError {
    case deviceNotSupported
    case invalidPlaneDetection
    case invalidSceneReconstruction
    case invalidFrameSemantics
    case invalidDetectionImages
    
    var errorDescription: String? {
        switch self {
        case .deviceNotSupported:
            return "AR is not supported on this device"
        case .invalidPlaneDetection:
            return "Invalid plane detection configuration"
        case .invalidSceneReconstruction:
            return "Invalid scene reconstruction configuration"
        case .invalidFrameSemantics:
            return "Invalid frame semantics configuration"
        case .invalidDetectionImages:
            return "Invalid detection images configuration"
        }
    }
}