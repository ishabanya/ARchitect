import Foundation
import Combine

// MARK: - Collaboration Permission Management System

@MainActor
public class PermissionManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var userPermissions: [UUID: CollaborationPermission] = [:]
    @Published public var sessionSettings: SessionPermissionSettings = .default
    @Published public var permissionRequests: [PermissionRequest] = []
    @Published public var isLocked: Bool = false
    
    // MARK: - Private Properties
    private let accessController: AccessController
    private let auditLogger: PermissionAuditLogger
    private let requestHandler: PermissionRequestHandler
    
    private var hostUserId: UUID?
    private var permissionCache: [String: Bool] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Configuration
    private let cacheExpirationTime: TimeInterval = 300 // 5 minutes
    private let maxPendingRequests = 10
    
    public init() {
        self.accessController = AccessController()
        self.auditLogger = PermissionAuditLogger()
        self.requestHandler = PermissionRequestHandler()
        
        setupObservers()
        
        logDebug("Permission manager initialized", category: .collaboration)
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        $sessionSettings
            .sink { [weak self] settings in
                self?.applySessionSettings(settings)
            }
            .store(in: &cancellables)
        
        $isLocked
            .sink { [weak self] locked in
                if locked {
                    self?.handleSessionLock()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Permission Management
    
    public func setHostUser(_ userId: UUID) {
        hostUserId = userId
        userPermissions[userId] = .host
        
        logInfo("Host user set", category: .collaboration, context: LogContext(customData: [
            "host_user_id": userId.uuidString
        ]))
    }
    
    public func assignPermission(_ permission: CollaborationPermission, to userId: UUID) throws {
        // Only host can assign permissions
        guard let hostId = hostUserId, 
              userPermissions[hostId] == .host else {
            throw PermissionError.insufficientPrivileges("Only host can assign permissions")
        }
        
        // Validate permission assignment
        try validatePermissionAssignment(permission, to: userId)
        
        let previousPermission = userPermissions[userId]
        userPermissions[userId] = permission
        
        // Clear permission cache for this user
        clearPermissionCache(for: userId)
        
        // Log permission change
        auditLogger.logPermissionChange(
            userId: userId,
            fromPermission: previousPermission,
            toPermission: permission,
            changedBy: hostId
        )
        
        logInfo("Permission assigned", category: .collaboration, context: LogContext(customData: [
            "user_id": userId.uuidString,
            "permission": permission.rawValue,
            "previous_permission": previousPermission?.rawValue ?? "none"
        ]))
    }
    
    public func requestPermissionElevation(
        userId: UUID,
        requestedPermission: CollaborationPermission,
        reason: String
    ) throws -> UUID {
        
        // Check if user can request this permission
        guard canRequestPermission(userId: userId, permission: requestedPermission) else {
            throw PermissionError.invalidRequest("Cannot request this permission level")
        }
        
        // Check pending request limit
        guard permissionRequests.count < maxPendingRequests else {
            throw PermissionError.tooManyRequests("Too many pending permission requests")
        }
        
        // Create permission request
        let request = PermissionRequest(
            id: UUID(),
            userId: userId,
            currentPermission: userPermissions[userId] ?? .viewOnly,
            requestedPermission: requestedPermission,
            reason: reason,
            timestamp: Date(),
            status: .pending
        )
        
        permissionRequests.append(request)
        
        // Notify host about the request
        notifyHostOfPermissionRequest(request)
        
        logInfo("Permission elevation requested", category: .collaboration, context: LogContext(customData: [
            "user_id": userId.uuidString,
            "requested_permission": requestedPermission.rawValue,
            "reason": reason
        ]))
        
        return request.id
    }
    
    public func respondToPermissionRequest(
        requestId: UUID,
        response: PermissionRequestResponse,
        respondingUserId: UUID
    ) throws {
        
        // Only host can respond to permission requests
        guard userPermissions[respondingUserId] == .host else {
            throw PermissionError.insufficientPrivileges("Only host can respond to permission requests")
        }
        
        guard var request = permissionRequests.first(where: { $0.id == requestId }) else {
            throw PermissionError.requestNotFound("Permission request not found")
        }
        
        guard request.status == .pending else {
            throw PermissionError.invalidRequest("Request already processed")
        }
        
        // Update request status
        request.status = response.approved ? .approved : .denied
        request.responseReason = response.reason
        request.respondedBy = respondingUserId
        request.responseTimestamp = Date()
        
        // Update requests array
        if let index = permissionRequests.firstIndex(where: { $0.id == requestId }) {
            permissionRequests[index] = request
        }
        
        // Apply permission change if approved
        if response.approved {
            try assignPermission(request.requestedPermission, to: request.userId)
        }
        
        // Remove from pending requests after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.permissionRequests.removeAll { $0.id == requestId }
        }
        
        auditLogger.logPermissionRequestResponse(request: request, respondingUserId: respondingUserId)
        
        logInfo("Permission request responded", category: .collaboration, context: LogContext(customData: [
            "request_id": requestId.uuidString,
            "approved": response.approved,
            "responding_user": respondingUserId.uuidString
        ]))
    }
    
    // MARK: - Permission Checking
    
    public func canPerform(_ action: CollaborationAction, userId: UUID) -> Bool {
        
        // Check session lock
        if isLocked && action.requiresEdit {
            return false
        }
        
        // Get user permission
        let userPermission = userPermissions[userId] ?? .viewOnly
        
        // Check cached result first
        let cacheKey = "\(userId.uuidString)_\(action.rawValue)"
        if let cachedResult = permissionCache[cacheKey] {
            return cachedResult
        }
        
        // Perform permission check
        let canPerform = accessController.checkPermission(
            action: action,
            userPermission: userPermission,
            sessionSettings: sessionSettings
        )
        
        // Cache result
        permissionCache[cacheKey] = canPerform
        
        // Schedule cache cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + cacheExpirationTime) {
            self.permissionCache.removeValue(forKey: cacheKey)
        }
        
        return canPerform
    }
    
    public func getPermission(for userId: UUID) -> CollaborationPermission {
        return userPermissions[userId] ?? .viewOnly
    }
    
    public func getUsersWithPermission(_ permission: CollaborationPermission) -> [UUID] {
        return userPermissions.compactMap { userId, userPermission in
            userPermission == permission ? userId : nil
        }
    }
    
    public func canUserSeeAction(_ action: CollaborationAction, performedBy actorId: UUID, viewerId: UUID) -> Bool {
        let actorPermission = userPermissions[actorId] ?? .viewOnly
        let viewerPermission = userPermissions[viewerId] ?? .viewOnly
        
        return accessController.canSeeAction(
            action: action,
            actorPermission: actorPermission,
            viewerPermission: viewerPermission,
            sessionSettings: sessionSettings
        )
    }
    
    // MARK: - Session Settings
    
    public func updateSessionSettings(_ settings: SessionPermissionSettings) throws {
        // Only host can update session settings
        guard let hostId = hostUserId,
              userPermissions[hostId] == .host else {
            throw PermissionError.insufficientPrivileges("Only host can update session settings")
        }
        
        sessionSettings = settings
        
        // Clear all permission caches when settings change
        permissionCache.removeAll()
        
        auditLogger.logSessionSettingsChange(settings: settings, changedBy: hostId)
        
        logInfo("Session settings updated", category: .collaboration, context: LogContext(customData: [
            "allow_anonymous_view": settings.allowAnonymousView,
            "require_permission_for_edit": settings.requirePermissionForEdit,
            "auto_approve_edit_requests": settings.autoApproveEditRequests
        ]))
    }
    
    public func lockSession() throws {
        guard let hostId = hostUserId,
              userPermissions[hostId] == .host else {
            throw PermissionError.insufficientPrivileges("Only host can lock session")
        }
        
        isLocked = true
        auditLogger.logSessionLock(lockedBy: hostId)
        
        logInfo("Session locked", category: .collaboration)
    }
    
    public func unlockSession() throws {
        guard let hostId = hostUserId,
              userPermissions[hostId] == .host else {
            throw PermissionError.insufficientPrivileges("Only host can unlock session")
        }
        
        isLocked = false
        auditLogger.logSessionUnlock(unlockedBy: hostId)
        
        logInfo("Session unlocked", category: .collaboration)
    }
    
    // MARK: - User Management
    
    public func addUser(_ userId: UUID, withPermission permission: CollaborationPermission = .viewOnly) {
        
        // Apply default permission based on session settings
        let finalPermission: CollaborationPermission
        if sessionSettings.allowAnonymousView && permission == .viewOnly {
            finalPermission = .viewOnly
        } else if sessionSettings.defaultJoinPermission != nil {
            finalPermission = sessionSettings.defaultJoinPermission!
        } else {
            finalPermission = permission
        }
        
        userPermissions[userId] = finalPermission
        
        auditLogger.logUserJoined(userId: userId, permission: finalPermission)
        
        logInfo("User added to session", category: .collaboration, context: LogContext(customData: [
            "user_id": userId.uuidString,
            "permission": finalPermission.rawValue
        ]))
    }
    
    public func removeUser(_ userId: UUID) {
        let removedPermission = userPermissions.removeValue(forKey: userId)
        
        // Clear permission cache for this user
        clearPermissionCache(for: userId)
        
        // Cancel any pending requests from this user
        permissionRequests.removeAll { $0.userId == userId }
        
        auditLogger.logUserLeft(userId: userId, hadPermission: removedPermission)
        
        logInfo("User removed from session", category: .collaboration, context: LogContext(customData: [
            "user_id": userId.uuidString,
            "had_permission": removedPermission?.rawValue ?? "none"
        ]))
    }
    
    // MARK: - Helper Methods
    
    private func validatePermissionAssignment(_ permission: CollaborationPermission, to userId: UUID) throws {
        // Cannot assign host permission to others
        if permission == .host && userId != hostUserId {
            throw PermissionError.invalidAssignment("Cannot assign host permission to non-host user")
        }
        
        // Check session settings
        if !sessionSettings.allowPermissionChanges && permission != .viewOnly {
            throw PermissionError.settingsViolation("Permission changes not allowed in this session")
        }
    }
    
    private func canRequestPermission(userId: UUID, permission: CollaborationPermission) -> Bool {
        let currentPermission = userPermissions[userId] ?? .viewOnly
        
        // Cannot request host permission
        if permission == .host {
            return false
        }
        
        // Cannot request lower permission
        if permission.level <= currentPermission.level {
            return false
        }
        
        // Check if user already has pending request
        if permissionRequests.contains(where: { $0.userId == userId && $0.status == .pending }) {
            return false
        }
        
        return true
    }
    
    private func clearPermissionCache(for userId: UUID) {
        let userCacheKeys = permissionCache.keys.filter { $0.hasPrefix(userId.uuidString) }
        for key in userCacheKeys {
            permissionCache.removeValue(forKey: key)
        }
    }
    
    private func applySessionSettings(_ settings: SessionPermissionSettings) {
        // Clear all caches when settings change
        permissionCache.removeAll()
        
        // Apply settings to existing users if needed
        if !settings.allowAnonymousView {
            // Remove view-only users if anonymous viewing is disabled
            let viewOnlyUsers = getUsersWithPermission(.viewOnly)
            for userId in viewOnlyUsers {
                if userId != hostUserId {
                    removeUser(userId)
                }
            }
        }
    }
    
    private func handleSessionLock() {
        // Cancel all pending permission requests when session is locked
        for i in 0..<permissionRequests.count {
            permissionRequests[i].status = .cancelled
        }
        
        // Clear permission cache
        permissionCache.removeAll()
    }
    
    private func notifyHostOfPermissionRequest(_ request: PermissionRequest) {
        // This would send a notification to the host about the permission request
        // Implementation would depend on the notification system
        logDebug("Permission request notification sent to host", category: .collaboration)
    }
    
    // MARK: - Public Interface
    
    public func getPermissionSummary() -> PermissionSummary {
        let hostCount = getUsersWithPermission(.host).count
        let editCount = getUsersWithPermission(.edit).count
        let commentCount = getUsersWithPermission(.comment).count
        let viewOnlyCount = getUsersWithPermission(.viewOnly).count
        
        return PermissionSummary(
            totalUsers: userPermissions.count,
            hostUsers: hostCount,
            editUsers: editCount,
            commentUsers: commentCount,
            viewOnlyUsers: viewOnlyCount,
            pendingRequests: permissionRequests.filter { $0.status == .pending }.count,
            isSessionLocked: isLocked
        )
    }
    
    public func getAuditLog() -> [PermissionAuditEntry] {
        return auditLogger.getAuditLog()
    }
    
    public func exportPermissions() -> PermissionExport {
        return PermissionExport(
            userPermissions: userPermissions,
            sessionSettings: sessionSettings,
            auditLog: auditLogger.getAuditLog(),
            exportTimestamp: Date()
        )
    }
    
    public func importPermissions(_ export: PermissionExport) throws {
        // Only host can import permissions
        guard let hostId = hostUserId,
              userPermissions[hostId] == .host else {
            throw PermissionError.insufficientPrivileges("Only host can import permissions")
        }
        
        userPermissions = export.userPermissions
        sessionSettings = export.sessionSettings
        
        // Clear cache after import
        permissionCache.removeAll()
        
        logInfo("Permissions imported", category: .collaboration)
    }
}

// MARK: - Supporting Data Structures

public struct SessionPermissionSettings {
    public let allowAnonymousView: Bool
    public let requirePermissionForEdit: Bool
    public let autoApproveEditRequests: Bool
    public let allowPermissionChanges: Bool
    public let defaultJoinPermission: CollaborationPermission?
    public let maxEditUsers: Int?
    public let sessionTimeout: TimeInterval?
    
    public static let `default` = SessionPermissionSettings(
        allowAnonymousView: true,
        requirePermissionForEdit: true,
        autoApproveEditRequests: false,
        allowPermissionChanges: true,
        defaultJoinPermission: .viewOnly,
        maxEditUsers: nil,
        sessionTimeout: nil
    )
    
    public static let restrictive = SessionPermissionSettings(
        allowAnonymousView: false,
        requirePermissionForEdit: true,
        autoApproveEditRequests: false,
        allowPermissionChanges: false,
        defaultJoinPermission: .viewOnly,
        maxEditUsers: 2,
        sessionTimeout: 3600 // 1 hour
    )
}

public struct PermissionRequest: Identifiable {
    public let id: UUID
    public let userId: UUID
    public let currentPermission: CollaborationPermission
    public let requestedPermission: CollaborationPermission
    public let reason: String
    public let timestamp: Date
    public var status: RequestStatus
    public var responseReason: String?
    public var respondedBy: UUID?
    public var responseTimestamp: Date?
    
    public enum RequestStatus {
        case pending
        case approved
        case denied
        case cancelled
    }
}

public struct PermissionRequestResponse {
    public let approved: Bool
    public let reason: String?
    
    public init(approved: Bool, reason: String? = nil) {
        self.approved = approved
        self.reason = reason
    }
}

public enum CollaborationAction: String, CaseIterable {
    case viewLayout = "view_layout"
    case addObject = "add_object"
    case removeObject = "remove_object"
    case moveObject = "move_object"
    case rotateObject = "rotate_object"
    case scaleObject = "scale_object"
    case selectObject = "select_object"
    case commentOnLayout = "comment_on_layout"
    case changePermissions = "change_permissions"
    case kickUser = "kick_user"
    case lockSession = "lock_session"
    case recordSession = "record_session"
    case shareScreen = "share_screen"
    case voiceChat = "voice_chat"
    
    public var requiresEdit: Bool {
        switch self {
        case .addObject, .removeObject, .moveObject, .rotateObject, .scaleObject:
            return true
        case .changePermissions, .kickUser, .lockSession:
            return true
        default:
            return false
        }
    }
    
    public var minimumPermission: CollaborationPermission {
        switch self {
        case .viewLayout, .selectObject:
            return .viewOnly
        case .commentOnLayout, .voiceChat:
            return .comment
        case .addObject, .removeObject, .moveObject, .rotateObject, .scaleObject:
            return .edit
        case .changePermissions, .kickUser, .lockSession, .recordSession:
            return .host
        case .shareScreen:
            return .edit
        }
    }
}

extension CollaborationPermission {
    public var level: Int {
        switch self {
        case .viewOnly: return 1
        case .comment: return 2
        case .edit: return 3
        case .host: return 4
        }
    }
}

public struct PermissionSummary {
    public let totalUsers: Int
    public let hostUsers: Int
    public let editUsers: Int
    public let commentUsers: Int
    public let viewOnlyUsers: Int
    public let pendingRequests: Int
    public let isSessionLocked: Bool
}

public struct PermissionExport: Codable {
    public let userPermissions: [UUID: CollaborationPermission]
    public let sessionSettings: SessionPermissionSettings
    public let auditLog: [PermissionAuditEntry]
    public let exportTimestamp: Date
}

public enum PermissionError: Error {
    case insufficientPrivileges(String)
    case invalidRequest(String)
    case invalidAssignment(String)
    case settingsViolation(String)
    case requestNotFound(String)
    case tooManyRequests(String)
    
    public var localizedDescription: String {
        switch self {
        case .insufficientPrivileges(let message):
            return "Insufficient privileges: \(message)"
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .invalidAssignment(let message):
            return "Invalid assignment: \(message)"
        case .settingsViolation(let message):
            return "Settings violation: \(message)"
        case .requestNotFound(let message):
            return "Request not found: \(message)"
        case .tooManyRequests(let message):
            return "Too many requests: \(message)"
        }
    }
}

// MARK: - Supporting Classes

@MainActor
class AccessController {
    
    func checkPermission(
        action: CollaborationAction,
        userPermission: CollaborationPermission,
        sessionSettings: SessionPermissionSettings
    ) -> Bool {
        
        // Check if user has minimum required permission
        guard userPermission.level >= action.minimumPermission.level else {
            return false
        }
        
        // Apply session-specific rules
        switch action {
        case .addObject, .removeObject, .moveObject, .rotateObject, .scaleObject:
            if sessionSettings.requirePermissionForEdit && userPermission == .viewOnly {
                return false
            }
        case .commentOnLayout:
            if !sessionSettings.allowAnonymousView && userPermission == .viewOnly {
                return false
            }
        default:
            break
        }
        
        return true
    }
    
    func canSeeAction(
        action: CollaborationAction,
        actorPermission: CollaborationPermission,
        viewerPermission: CollaborationPermission,
        sessionSettings: SessionPermissionSettings
    ) -> Bool {
        
        // Host can see all actions
        if viewerPermission == .host {
            return true
        }
        
        // Users can see actions performed by users with equal or lower permissions
        if actorPermission.level <= viewerPermission.level {
            return true
        }
        
        // View-only users can see basic actions if anonymous viewing is allowed
        if viewerPermission == .viewOnly && sessionSettings.allowAnonymousView {
            return !action.requiresEdit
        }
        
        return false
    }
}

@MainActor
class PermissionAuditLogger {
    private var auditLog: [PermissionAuditEntry] = []
    private let maxLogEntries = 1000
    
    func logPermissionChange(
        userId: UUID,
        fromPermission: CollaborationPermission?,
        toPermission: CollaborationPermission,
        changedBy: UUID
    ) {
        let entry = PermissionAuditEntry(
            id: UUID(),
            timestamp: Date(),
            action: .permissionChanged,
            userId: userId,
            details: [
                "from_permission": fromPermission?.rawValue ?? "none",
                "to_permission": toPermission.rawValue,
                "changed_by": changedBy.uuidString
            ]
        )
        addEntry(entry)
    }
    
    func logPermissionRequestResponse(request: PermissionRequest, respondingUserId: UUID) {
        let entry = PermissionAuditEntry(
            id: UUID(),
            timestamp: Date(),
            action: .permissionRequestResponded,
            userId: request.userId,
            details: [
                "request_id": request.id.uuidString,
                "requested_permission": request.requestedPermission.rawValue,
                "approved": String(request.status == .approved),
                "responded_by": respondingUserId.uuidString
            ]
        )
        addEntry(entry)
    }
    
    func logSessionSettingsChange(settings: SessionPermissionSettings, changedBy: UUID) {
        let entry = PermissionAuditEntry(
            id: UUID(),
            timestamp: Date(),
            action: .sessionSettingsChanged,
            userId: changedBy,
            details: [
                "allow_anonymous_view": String(settings.allowAnonymousView),
                "require_permission_for_edit": String(settings.requirePermissionForEdit),
                "auto_approve_edit_requests": String(settings.autoApproveEditRequests)
            ]
        )
        addEntry(entry)
    }
    
    func logSessionLock(lockedBy: UUID) {
        let entry = PermissionAuditEntry(
            id: UUID(),
            timestamp: Date(),
            action: .sessionLocked,
            userId: lockedBy,
            details: [:]
        )
        addEntry(entry)
    }
    
    func logSessionUnlock(unlockedBy: UUID) {
        let entry = PermissionAuditEntry(
            id: UUID(),
            timestamp: Date(),
            action: .sessionUnlocked,
            userId: unlockedBy,
            details: [:]
        )
        addEntry(entry)
    }
    
    func logUserJoined(userId: UUID, permission: CollaborationPermission) {
        let entry = PermissionAuditEntry(
            id: UUID(),
            timestamp: Date(),
            action: .userJoined,
            userId: userId,
            details: [
                "permission": permission.rawValue
            ]
        )
        addEntry(entry)
    }
    
    func logUserLeft(userId: UUID, hadPermission: CollaborationPermission?) {
        let entry = PermissionAuditEntry(
            id: UUID(),
            timestamp: Date(),
            action: .userLeft,
            userId: userId,
            details: [
                "had_permission": hadPermission?.rawValue ?? "none"
            ]
        )
        addEntry(entry)
    }
    
    private func addEntry(_ entry: PermissionAuditEntry) {
        auditLog.append(entry)
        
        // Trim log if it gets too long
        if auditLog.count > maxLogEntries {
            auditLog.removeFirst(auditLog.count - maxLogEntries)
        }
    }
    
    func getAuditLog() -> [PermissionAuditEntry] {
        return auditLog
    }
}

@MainActor
class PermissionRequestHandler {
    // Handles automatic approval/denial based on rules
    
    func shouldAutoApprove(
        request: PermissionRequest,
        settings: SessionPermissionSettings
    ) -> Bool {
        
        if settings.autoApproveEditRequests && request.requestedPermission == .edit {
            return true
        }
        
        // Add more auto-approval rules as needed
        
        return false
    }
}

public struct PermissionAuditEntry: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let action: AuditAction
    public let userId: UUID
    public let details: [String: String]
    
    public enum AuditAction: String, Codable {
        case permissionChanged = "permission_changed"
        case permissionRequestResponded = "permission_request_responded"
        case sessionSettingsChanged = "session_settings_changed"
        case sessionLocked = "session_locked"
        case sessionUnlocked = "session_unlocked"
        case userJoined = "user_joined"
        case userLeft = "user_left"
    }
}

extension SessionPermissionSettings: Codable {}
extension PermissionRequest: Codable {}
extension PermissionRequest.RequestStatus: Codable {}