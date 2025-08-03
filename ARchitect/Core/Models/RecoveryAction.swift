import SwiftUI

// MARK: - Recovery Action Model

public enum RecoveryAction: CaseIterable {
    case retry
    case retryWithDelay
    case restartSession
    case requestPermission
    case goToSettings
    case contactSupport
    case checkConnection
    case freeUpSpace
    case updateApp
    case none
    
    public var actionTitle: String {
        switch self {
        case .retry:
            return "Try Again"
        case .retryWithDelay:
            return "Retry in a Moment"
        case .restartSession:
            return "Restart Session"
        case .requestPermission:
            return "Grant Permission"
        case .goToSettings:
            return "Open Settings"
        case .contactSupport:
            return "Contact Support"
        case .checkConnection:
            return "Check Connection"
        case .freeUpSpace:
            return "Free Up Space"
        case .updateApp:
            return "Update App"
        case .none:
            return "OK"
        }
    }
    
    public var icon: String {
        switch self {
        case .retry:
            return "arrow.clockwise"
        case .retryWithDelay:
            return "clock.arrow.circlepath"
        case .restartSession:
            return "restart.circle"
        case .requestPermission:
            return "hand.raised"
        case .goToSettings:
            return "gear"
        case .contactSupport:
            return "person.crop.circle.badge.questionmark"
        case .checkConnection:
            return "wifi.exclamationmark"
        case .freeUpSpace:
            return "externaldrive.badge.minus"
        case .updateApp:
            return "arrow.down.circle"
        case .none:
            return "checkmark"
        }
    }
    
    public var color: Color {
        switch self {
        case .retry, .retryWithDelay:
            return .blue
        case .restartSession:
            return .orange
        case .requestPermission:
            return .purple
        case .goToSettings:
            return .gray
        case .contactSupport:
            return .green
        case .checkConnection:
            return .cyan
        case .freeUpSpace:
            return .yellow
        case .updateApp:
            return .indigo
        case .none:
            return .secondary
        }
    }
    
    public var isDestructive: Bool {
        switch self {
        case .restartSession:
            return true
        default:
            return false
        }
    }
}

// MARK: - Error Extensions

extension AppError {
    public var hasHelpContent: Bool {
        switch errorCategory {
        case .ar, .modelLoading, .collaboration:
            return true
        default:
            return false
        }
    }
}