import Foundation

// MARK: - App Environment
enum AppEnvironment: String, CaseIterable {
    case development = "dev"
    case staging = "staging"
    case production = "prod"
    
    var displayName: String {
        switch self {
        case .development:
            return "Development"
        case .staging:
            return "Staging"
        case .production:
            return "Production"
        }
    }
    
    var isDebugEnvironment: Bool {
        return self != .production
    }
    
    static var current: AppEnvironment {
        #if DEBUG
        return ProcessInfo.processInfo.environment["APP_ENVIRONMENT"]
            .flatMap(AppEnvironment.init) ?? .development
        #else
        return .production
        #endif
    }
}

// MARK: - Environment Configuration
struct EnvironmentConfiguration {
    let environment: AppEnvironment
    let apiConfiguration: APIConfiguration
    let analyticsConfiguration: AnalyticsConfiguration
    let arConfiguration: ARConfiguration
    let aiConfiguration: AIConfiguration
    let debugConfiguration: DebugConfiguration
    let performanceConfiguration: PerformanceConfiguration
    let networkConfiguration: NetworkConfiguration
}

// MARK: - API Configuration
struct APIConfiguration {
    let baseURL: URL
    let timeout: TimeInterval
    let maxRetries: Int
    let rateLimitPerMinute: Int
    let authEndpoint: String
    let modelEndpoint: String
    let analyticsEndpoint: String
    
    static func forEnvironment(_ environment: AppEnvironment) -> APIConfiguration {
        switch environment {
        case .development:
            return APIConfiguration(
                baseURL: URL(string: "https://api-dev.architect.com/v1")!,
                timeout: 30.0,
                maxRetries: 3,
                rateLimitPerMinute: 1000,
                authEndpoint: "/auth",
                modelEndpoint: "/models",
                analyticsEndpoint: "/analytics"
            )
        case .staging:
            return APIConfiguration(
                baseURL: URL(string: "https://api-staging.architect.com/v1")!,
                timeout: 20.0,
                maxRetries: 2,
                rateLimitPerMinute: 500,
                authEndpoint: "/auth",
                modelEndpoint: "/models",
                analyticsEndpoint: "/analytics"
            )
        case .production:
            return APIConfiguration(
                baseURL: URL(string: "https://api.architect.com/v1")!,
                timeout: 15.0,
                maxRetries: 2,
                rateLimitPerMinute: 200,
                authEndpoint: "/auth",
                modelEndpoint: "/models",
                analyticsEndpoint: "/analytics"
            )
        }
    }
}

// MARK: - Analytics Configuration
struct AnalyticsConfiguration {
    let isEnabled: Bool
    let samplingRate: Double
    let batchSize: Int
    let flushInterval: TimeInterval
    let maxLocalEvents: Int
    let privacyMode: AnalyticsPrivacyMode
    
    enum AnalyticsPrivacyMode {
        case full
        case limited
        case minimal
    }
    
    static func forEnvironment(_ environment: AppEnvironment) -> AnalyticsConfiguration {
        switch environment {
        case .development:
            return AnalyticsConfiguration(
                isEnabled: true,
                samplingRate: 1.0,
                batchSize: 10,
                flushInterval: 30.0,
                maxLocalEvents: 1000,
                privacyMode: .full
            )
        case .staging:
            return AnalyticsConfiguration(
                isEnabled: true,
                samplingRate: 0.5,
                batchSize: 25,
                flushInterval: 60.0,
                maxLocalEvents: 500,
                privacyMode: .limited
            )
        case .production:
            return AnalyticsConfiguration(
                isEnabled: true,
                samplingRate: 0.1,
                batchSize: 50,
                flushInterval: 300.0,
                maxLocalEvents: 200,
                privacyMode: .minimal
            )
        }
    }
}

// MARK: - AR Configuration
struct ARConfiguration {
    let maxTrackingLossTime: TimeInterval
    let meshGenerationEnabled: Bool
    let sceneReconstructionQuality: SceneReconstructionQuality
    let planeDetectionTypes: [PlaneDetectionType]
    let lightEstimationEnabled: Bool
    let peopleOcclusionEnabled: Bool
    let maxAnchorsPerSession: Int
    
    enum SceneReconstructionQuality {
        case high
        case medium
        case low
        case disabled
    }
    
    enum PlaneDetectionType {
        case horizontal
        case vertical
    }
    
    static func forEnvironment(_ environment: AppEnvironment) -> ARConfiguration {
        switch environment {
        case .development:
            return ARConfiguration(
                maxTrackingLossTime: 10.0,
                meshGenerationEnabled: true,
                sceneReconstructionQuality: .high,
                planeDetectionTypes: [.horizontal, .vertical],
                lightEstimationEnabled: true,
                peopleOcclusionEnabled: true,
                maxAnchorsPerSession: 100
            )
        case .staging:
            return ARConfiguration(
                maxTrackingLossTime: 8.0,
                meshGenerationEnabled: true,
                sceneReconstructionQuality: .medium,
                planeDetectionTypes: [.horizontal, .vertical],
                lightEstimationEnabled: true,
                peopleOcclusionEnabled: false,
                maxAnchorsPerSession: 75
            )
        case .production:
            return ARConfiguration(
                maxTrackingLossTime: 5.0,
                meshGenerationEnabled: false,
                sceneReconstructionQuality: .low,
                planeDetectionTypes: [.horizontal],
                lightEstimationEnabled: false,
                peopleOcclusionEnabled: false,
                maxAnchorsPerSession: 50
            )
        }
    }
}

// MARK: - AI Configuration
struct AIConfiguration {
    let modelCacheSize: Int
    let inferenceTimeout: TimeInterval
    let maxConcurrentInferences: Int
    let fallbackToLocalModel: Bool
    let modelUpdateCheckInterval: TimeInterval
    let compressionEnabled: Bool
    
    static func forEnvironment(_ environment: AppEnvironment) -> AIConfiguration {
        switch environment {
        case .development:
            return AIConfiguration(
                modelCacheSize: 500 * 1024 * 1024, // 500MB
                inferenceTimeout: 30.0,
                maxConcurrentInferences: 5,
                fallbackToLocalModel: true,
                modelUpdateCheckInterval: 3600.0, // 1 hour
                compressionEnabled: false
            )
        case .staging:
            return AIConfiguration(
                modelCacheSize: 300 * 1024 * 1024, // 300MB
                inferenceTimeout: 20.0,
                maxConcurrentInferences: 3,
                fallbackToLocalModel: true,
                modelUpdateCheckInterval: 7200.0, // 2 hours
                compressionEnabled: true
            )
        case .production:
            return AIConfiguration(
                modelCacheSize: 200 * 1024 * 1024, // 200MB
                inferenceTimeout: 10.0,
                maxConcurrentInferences: 2,
                fallbackToLocalModel: false,
                modelUpdateCheckInterval: 14400.0, // 4 hours
                compressionEnabled: true
            )
        }
    }
}

// MARK: - Debug Configuration
struct DebugConfiguration {
    let loggingEnabled: Bool
    let logLevel: LogLevel
    let crashReportingEnabled: Bool
    let performanceMonitoringEnabled: Bool
    let networkLoggingEnabled: Bool
    let arDebuggingEnabled: Bool
    let showErrorDetails: Bool
    
    enum LogLevel: String, CaseIterable {
        case verbose = "verbose"
        case debug = "debug"
        case info = "info"
        case warning = "warning"
        case error = "error"
        case critical = "critical"
    }
    
    static func forEnvironment(_ environment: AppEnvironment) -> DebugConfiguration {
        switch environment {
        case .development:
            return DebugConfiguration(
                loggingEnabled: true,
                logLevel: .verbose,
                crashReportingEnabled: false,
                performanceMonitoringEnabled: true,
                networkLoggingEnabled: true,
                arDebuggingEnabled: true,
                showErrorDetails: true
            )
        case .staging:
            return DebugConfiguration(
                loggingEnabled: true,
                logLevel: .debug,
                crashReportingEnabled: true,
                performanceMonitoringEnabled: true,
                networkLoggingEnabled: false,
                arDebuggingEnabled: false,
                showErrorDetails: true
            )
        case .production:
            return DebugConfiguration(
                loggingEnabled: false,
                logLevel: .error,
                crashReportingEnabled: true,
                performanceMonitoringEnabled: false,
                networkLoggingEnabled: false,
                arDebuggingEnabled: false,
                showErrorDetails: false
            )
        }
    }
}

// MARK: - Performance Configuration
struct PerformanceConfiguration {
    let maxMemoryUsageMB: Int
    let targetFrameRate: Int
    let thermalThrottlingEnabled: Bool
    let backgroundProcessingEnabled: Bool
    let cacheExpirationTime: TimeInterval
    let maxCacheSize: Int
    
    static func forEnvironment(_ environment: AppEnvironment) -> PerformanceConfiguration {
        switch environment {
        case .development:
            return PerformanceConfiguration(
                maxMemoryUsageMB: 1024,
                targetFrameRate: 60,
                thermalThrottlingEnabled: false,
                backgroundProcessingEnabled: true,
                cacheExpirationTime: 3600.0,
                maxCacheSize: 100 * 1024 * 1024
            )
        case .staging:
            return PerformanceConfiguration(
                maxMemoryUsageMB: 512,
                targetFrameRate: 60,
                thermalThrottlingEnabled: true,
                backgroundProcessingEnabled: true,
                cacheExpirationTime: 1800.0,
                maxCacheSize: 50 * 1024 * 1024
            )
        case .production:
            return PerformanceConfiguration(
                maxMemoryUsageMB: 256,
                targetFrameRate: 30,
                thermalThrottlingEnabled: true,
                backgroundProcessingEnabled: false,
                cacheExpirationTime: 900.0,
                maxCacheSize: 25 * 1024 * 1024
            )
        }
    }
}

// MARK: - Network Configuration
struct NetworkConfiguration {
    let connectionTimeout: TimeInterval
    let readTimeout: TimeInterval
    let allowsCellularAccess: Bool
    let requiresSecureConnection: Bool
    let cachePolicy: URLRequest.CachePolicy
    let maxConcurrentConnections: Int
    
    static func forEnvironment(_ environment: AppEnvironment) -> NetworkConfiguration {
        switch environment {
        case .development:
            return NetworkConfiguration(
                connectionTimeout: 30.0,
                readTimeout: 60.0,
                allowsCellularAccess: true,
                requiresSecureConnection: false,
                cachePolicy: .reloadIgnoringLocalCacheData,
                maxConcurrentConnections: 10
            )
        case .staging:
            return NetworkConfiguration(
                connectionTimeout: 20.0,
                readTimeout: 40.0,
                allowsCellularAccess: true,
                requiresSecureConnection: true,
                cachePolicy: .useProtocolCachePolicy,
                maxConcurrentConnections: 6
            )
        case .production:
            return NetworkConfiguration(
                connectionTimeout: 15.0,
                readTimeout: 30.0,
                allowsCellularAccess: false,
                requiresSecureConnection: true,
                cachePolicy: .returnCacheDataElseLoad,
                maxConcurrentConnections: 4
            )
        }
    }
}