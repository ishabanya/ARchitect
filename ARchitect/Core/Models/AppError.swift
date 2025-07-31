import Foundation
import ARKit

// MARK: - Main Error Protocol
protocol AppErrorProtocol: LocalizedError {
    var errorCode: String { get }
    var errorCategory: ErrorCategory { get }
    var severity: ErrorSeverity { get }
    var isRetryable: Bool { get }
    var userMessage: String { get }
    var recoveryAction: RecoveryAction? { get }
    var underlyingError: Error? { get }
    var metadata: [String: Any] { get }
}

// MARK: - Error Categories
enum ErrorCategory: String, CaseIterable {
    case ar = "ar"
    case network = "network"
    case modelLoading = "model_loading"
    case storage = "storage"
    case authentication = "authentication"
    case collaboration = "collaboration"
    case ai = "ai"
    case ui = "ui"
    case system = "system"
}

// MARK: - Error Severity
enum ErrorSeverity: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

// MARK: - Recovery Actions
enum RecoveryAction {
    case retry
    case retryWithDelay(TimeInterval)
    case restartSession
    case requestPermission(String)
    case goToSettings
    case contactSupport
    case none
    
    var actionTitle: String {
        switch self {
        case .retry:
            return "Try Again"
        case .retryWithDelay:
            return "Retry"
        case .restartSession:
            return "Restart Session"
        case .requestPermission:
            return "Allow Permission"
        case .goToSettings:
            return "Open Settings"
        case .contactSupport:
            return "Contact Support"
        case .none:
            return ""
        }
    }
}

// MARK: - AR Errors
enum ARError: AppErrorProtocol {
    case sessionFailed(ARError.Code)
    case trackingLost
    case insufficientFeatures
    case permissionDenied
    case unsupportedDevice
    case worldMapLoadFailed
    case worldMapSaveFailed
    case anchorPlacementFailed
    case planeDetectionFailed
    case meshGenerationFailed
    
    var errorCode: String {
        switch self {
        case .sessionFailed(let code):
            return "AR_SESSION_FAILED_\(code.rawValue)"
        case .trackingLost:
            return "AR_TRACKING_LOST"
        case .insufficientFeatures:
            return "AR_INSUFFICIENT_FEATURES"
        case .permissionDenied:
            return "AR_PERMISSION_DENIED"
        case .unsupportedDevice:
            return "AR_UNSUPPORTED_DEVICE"
        case .worldMapLoadFailed:
            return "AR_WORLD_MAP_LOAD_FAILED"
        case .worldMapSaveFailed:
            return "AR_WORLD_MAP_SAVE_FAILED"
        case .anchorPlacementFailed:
            return "AR_ANCHOR_PLACEMENT_FAILED"
        case .planeDetectionFailed:
            return "AR_PLANE_DETECTION_FAILED"
        case .meshGenerationFailed:
            return "AR_MESH_GENERATION_FAILED"
        }
    }
    
    var errorCategory: ErrorCategory { .ar }
    
    var severity: ErrorSeverity {
        switch self {
        case .unsupportedDevice, .permissionDenied:
            return .critical
        case .sessionFailed, .worldMapLoadFailed, .worldMapSaveFailed:
            return .high
        case .trackingLost, .planeDetectionFailed, .meshGenerationFailed:
            return .medium
        case .insufficientFeatures, .anchorPlacementFailed:
            return .low
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .unsupportedDevice, .permissionDenied:
            return false
        default:
            return true
        }
    }
    
    var userMessage: String {
        switch self {
        case .sessionFailed:
            return "AR session encountered an issue. Please try restarting the session."
        case .trackingLost:
            return "Lost tracking of your environment. Move your device slowly to regain tracking."
        case .insufficientFeatures:
            return "Not enough visual features detected. Point your camera at a well-lit area with textures."
        case .permissionDenied:
            return "Camera access is required for AR features. Please enable camera permission in Settings."
        case .unsupportedDevice:
            return "Your device doesn't support the required AR features for this app."
        case .worldMapLoadFailed:
            return "Failed to load the saved room layout. Starting with a new session."
        case .worldMapSaveFailed:
            return "Unable to save your room layout. Your progress may be lost."
        case .anchorPlacementFailed:
            return "Unable to place furniture at this location. Try a different spot."
        case .planeDetectionFailed:
            return "Having trouble detecting surfaces. Move your device around to scan the area."
        case .meshGenerationFailed:
            return "Failed to create room mesh. Some advanced features may not work properly."
        }
    }
    
    var recoveryAction: RecoveryAction? {
        switch self {
        case .sessionFailed, .worldMapLoadFailed:
            return .restartSession
        case .trackingLost, .insufficientFeatures, .planeDetectionFailed:
            return .none
        case .permissionDenied:
            return .goToSettings
        case .unsupportedDevice:
            return .contactSupport
        case .worldMapSaveFailed, .anchorPlacementFailed:
            return .retry
        case .meshGenerationFailed:
            return .retryWithDelay(2.0)
        }
    }
    
    var underlyingError: Error? { nil }
    var metadata: [String: Any] { [:] }
    
    var errorDescription: String? { userMessage }
}

// MARK: - Network Errors
enum NetworkError: AppErrorProtocol {
    case noConnection
    case timeout
    case serverError(Int)
    case invalidResponse
    case rateLimited
    case unauthorized
    case forbidden
    case notFound
    case badRequest
    case parseFailed(Error)
    
    var errorCode: String {
        switch self {
        case .noConnection:
            return "NETWORK_NO_CONNECTION"
        case .timeout:
            return "NETWORK_TIMEOUT"
        case .serverError(let code):
            return "NETWORK_SERVER_ERROR_\(code)"
        case .invalidResponse:
            return "NETWORK_INVALID_RESPONSE"
        case .rateLimited:
            return "NETWORK_RATE_LIMITED"
        case .unauthorized:
            return "NETWORK_UNAUTHORIZED"
        case .forbidden:
            return "NETWORK_FORBIDDEN"
        case .notFound:
            return "NETWORK_NOT_FOUND"
        case .badRequest:
            return "NETWORK_BAD_REQUEST"
        case .parseFailed:
            return "NETWORK_PARSE_FAILED"
        }
    }
    
    var errorCategory: ErrorCategory { .network }
    
    var severity: ErrorSeverity {
        switch self {
        case .unauthorized, .forbidden:
            return .high
        case .serverError, .rateLimited:
            return .medium
        case .noConnection, .timeout, .notFound, .badRequest:
            return .medium
        case .invalidResponse, .parseFailed:
            return .low
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .noConnection, .timeout, .serverError, .rateLimited:
            return true
        case .unauthorized, .forbidden, .notFound, .badRequest, .invalidResponse, .parseFailed:
            return false
        }
    }
    
    var userMessage: String {
        switch self {
        case .noConnection:
            return "No internet connection. Please check your network and try again."
        case .timeout:
            return "Request timed out. Please try again."
        case .serverError:
            return "Server is experiencing issues. Please try again later."
        case .invalidResponse:
            return "Received invalid response from server."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .unauthorized:
            return "Authentication required. Please log in again."
        case .forbidden:
            return "You don't have permission to access this resource."
        case .notFound:
            return "The requested resource was not found."
        case .badRequest:
            return "Invalid request. Please try again."
        case .parseFailed:
            return "Failed to process server response."
        }
    }
    
    var recoveryAction: RecoveryAction? {
        switch self {
        case .noConnection, .timeout:
            return .retry
        case .serverError:
            return .retryWithDelay(5.0)
        case .rateLimited:
            return .retryWithDelay(10.0)
        case .unauthorized:
            return .none // Should trigger login flow
        default:
            return .none
        }
    }
    
    var underlyingError: Error? {
        switch self {
        case .parseFailed(let error):
            return error
        default:
            return nil
        }
    }
    
    var metadata: [String: Any] { [:] }
    var errorDescription: String? { userMessage }
}

// MARK: - Model Loading Errors
enum ModelLoadingError: AppErrorProtocol {
    case fileNotFound(String)
    case invalidFormat(String)
    case corruptedData(String)
    case insufficientMemory
    case loadTimeout
    case unsupportedVersion
    case dependencyMissing(String)
    
    var errorCode: String {
        switch self {
        case .fileNotFound:
            return "MODEL_FILE_NOT_FOUND"
        case .invalidFormat:
            return "MODEL_INVALID_FORMAT"
        case .corruptedData:
            return "MODEL_CORRUPTED_DATA"
        case .insufficientMemory:
            return "MODEL_INSUFFICIENT_MEMORY"
        case .loadTimeout:
            return "MODEL_LOAD_TIMEOUT"
        case .unsupportedVersion:
            return "MODEL_UNSUPPORTED_VERSION"
        case .dependencyMissing:
            return "MODEL_DEPENDENCY_MISSING"
        }
    }
    
    var errorCategory: ErrorCategory { .modelLoading }
    
    var severity: ErrorSeverity {
        switch self {
        case .insufficientMemory:
            return .high
        case .fileNotFound, .invalidFormat, .corruptedData, .unsupportedVersion:
            return .medium
        case .loadTimeout, .dependencyMissing:
            return .low
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .loadTimeout, .insufficientMemory:
            return true
        default:
            return false
        }
    }
    
    var userMessage: String {
        switch self {
        case .fileNotFound(let fileName):
            return "Model file '\(fileName)' not found. Please try downloading it again."
        case .invalidFormat(let fileName):
            return "Model file '\(fileName)' has an invalid format."
        case .corruptedData(let fileName):
            return "Model file '\(fileName)' appears to be corrupted."
        case .insufficientMemory:
            return "Not enough memory to load the model. Try closing other apps."
        case .loadTimeout:
            return "Model loading timed out. Please try again."
        case .unsupportedVersion:
            return "This model requires a newer version of the app."
        case .dependencyMissing(let dependency):
            return "Missing required dependency: \(dependency)"
        }
    }
    
    var recoveryAction: RecoveryAction? {
        switch self {
        case .loadTimeout:
            return .retry
        case .insufficientMemory:
            return .none // User should close apps
        case .fileNotFound, .corruptedData:
            return .retry // Could trigger re-download
        default:
            return .contactSupport
        }
    }
    
    var underlyingError: Error? { nil }
    var metadata: [String: Any] { [:] }
    var errorDescription: String? { userMessage }
}

// MARK: - Storage Errors
enum StorageError: AppErrorProtocol {
    case diskFull
    case permissionDenied
    case fileCorrupted(String)
    case writeFailure
    case readFailure
    case deletionFailure
    case backupFailure
    case syncFailure
    
    var errorCode: String {
        switch self {
        case .diskFull: return "STORAGE_DISK_FULL"
        case .permissionDenied: return "STORAGE_PERMISSION_DENIED"
        case .fileCorrupted: return "STORAGE_FILE_CORRUPTED"
        case .writeFailure: return "STORAGE_WRITE_FAILURE"
        case .readFailure: return "STORAGE_READ_FAILURE"
        case .deletionFailure: return "STORAGE_DELETION_FAILURE"
        case .backupFailure: return "STORAGE_BACKUP_FAILURE"
        case .syncFailure: return "STORAGE_SYNC_FAILURE"
        }
    }
    
    var errorCategory: ErrorCategory { .storage }
    var severity: ErrorSeverity {
        switch self {
        case .diskFull, .permissionDenied: return .high
        case .writeFailure, .backupFailure, .syncFailure: return .medium
        case .readFailure, .fileCorrupted, .deletionFailure: return .low
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .diskFull, .permissionDenied: return false
        default: return true
        }
    }
    
    var userMessage: String {
        switch self {
        case .diskFull:
            return "Not enough storage space. Please free up space and try again."
        case .permissionDenied:
            return "Permission denied. Please check app permissions in Settings."
        case .fileCorrupted(let fileName):
            return "File '\(fileName)' is corrupted and cannot be opened."
        case .writeFailure:
            return "Failed to save data. Please try again."
        case .readFailure:
            return "Failed to load data. The file may be corrupted."
        case .deletionFailure:
            return "Failed to delete the file. Please try again."
        case .backupFailure:
            return "Failed to backup your data. Please try again later."
        case .syncFailure:
            return "Failed to sync data. Please check your connection."
        }
    }
    
    var recoveryAction: RecoveryAction? {
        switch self {
        case .diskFull: return .none
        case .permissionDenied: return .goToSettings
        case .syncFailure: return .retryWithDelay(5.0)
        default: return .retry
        }
    }
    
    var underlyingError: Error? { nil }
    var metadata: [String: Any] { [:] }
    var errorDescription: String? { userMessage }
}