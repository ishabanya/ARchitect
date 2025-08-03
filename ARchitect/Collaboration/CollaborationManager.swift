import Foundation
import MultipeerConnectivity
import Combine
import ARKit

// MARK: - Collaboration Manager

@MainActor
public class CollaborationManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published public var sessionState: CollaborationState = .disconnected
    @Published public var connectedPeers: [CollaborationPeer] = []
    @Published public var localPeer: CollaborationPeer
    @Published public var sessionMetadata: SessionMetadata?
    @Published public var isHost: Bool = false
    @Published public var networkQuality: NetworkQuality = .good
    
    // MARK: - Private Properties
    private let serviceType = "architectar"
    private let peerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    private let messageProcessor: CollaborationMessageProcessor
    private let conflictResolver: ConflictResolver
    private let permissionManager: PermissionManager
    private let sessionRecorder: SessionRecorder
    private let networkMonitor: NetworkMonitor
    
    private var cancellables = Set<AnyCancellable>()
    private var heartbeatTimer: Timer?
    private var reconnectionTimer: Timer?
    
    // MARK: - Configuration
    private let maxPeers = 6
    private let heartbeatInterval: TimeInterval = 5.0
    private let reconnectionDelay: TimeInterval = 2.0
    private let messageTimeout: TimeInterval = 10.0
    
    public override init() {
        // Create local peer identity
        let deviceName = UIDevice.current.name
        self.peerID = MCPeerID(displayName: deviceName)
        self.localPeer = CollaborationPeer(
            id: UUID(),
            peerID: peerID,
            displayName: deviceName,
            permission: .host,
            status: .connected,
            deviceType: .iOS
        )
        
        // Initialize session
        self.session = MCSession(
            peer: peerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        
        // Initialize supporting components
        self.messageProcessor = CollaborationMessageProcessor()
        self.conflictResolver = ConflictResolver()
        self.permissionManager = PermissionManager()
        self.sessionRecorder = SessionRecorder()
        self.networkMonitor = NetworkMonitor()
        
        super.init()
        
        setupSession()
        setupObservers()
        
        logDebug("Collaboration manager initialized", category: .collaboration)
    }
    
    // MARK: - Collaboration States
    
    public enum CollaborationState {
        case disconnected
        case searching
        case connecting
        case connected
        case hosting
        case reconnecting
        case error(Error)
        
        var description: String {
            switch self {
            case .disconnected: return "Not connected"
            case .searching: return "Searching for sessions..."
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            case .hosting: return "Hosting session"
            case .reconnecting: return "Reconnecting..."
            case .error(let error): return "Error: \(error.localizedDescription)"
            }
        }
    }
    
    public enum NetworkQuality {
        case excellent
        case good
        case fair
        case poor
        case disconnected
        
        var description: String {
            switch self {
            case .excellent: return "Excellent"
            case .good: return "Good"
            case .fair: return "Fair"
            case .poor: return "Poor"
            case .disconnected: return "Disconnected"
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupSession() {
        session.delegate = self
    }
    
    private func setupObservers() {
        // Monitor network quality
        networkMonitor.$networkQuality
            .sink { [weak self] quality in
                self?.networkQuality = quality
                self?.handleNetworkQualityChange(quality)
            }
            .store(in: &cancellables)
        
        // Monitor session state changes
        $sessionState
            .sink { [weak self] state in
                self?.handleSessionStateChange(state)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Session Management
    
    public func startHosting(sessionName: String, roomData: ARRoomData? = nil) throws {
        guard sessionState == .disconnected else {
            throw CollaborationError.invalidState("Already in session")
        }
        
        isHost = true
        sessionState = .hosting
        
        // Create session metadata
        sessionMetadata = SessionMetadata(
            id: UUID(),
            name: sessionName,
            hostPeer: localPeer,
            createdAt: Date(),
            roomData: roomData,
            maxParticipants: maxPeers
        )
        
        // Start advertising
        let discoveryInfo = createDiscoveryInfo()
        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        
        // Start session recording if enabled
        sessionRecorder.startRecording(sessionId: sessionMetadata!.id, isHost: true)
        
        // Start heartbeat
        startHeartbeat()
        
        logInfo("Started hosting collaboration session", category: .collaboration, context: LogContext(customData: [
            "session_name": sessionName,
            "session_id": sessionMetadata!.id.uuidString
        ]))
    }
    
    public func joinSession(_ peer: MCPeerID, invitation: Data?) throws {
        guard sessionState == .disconnected else {
            throw CollaborationError.invalidState("Already in session")
        }
        
        isHost = false
        sessionState = .connecting
        
        // Parse invitation data
        if let invitationData = invitation,
           let metadata = try? JSONDecoder().decode(SessionMetadata.self, from: invitationData) {
            sessionMetadata = metadata
        }
        
        // Start browsing and connect
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        
        logInfo("Joining collaboration session", category: .collaboration, context: LogContext(customData: [
            "host_peer": peer.displayName
        ]))
    }
    
    public func leaveSession() {
        stopAdvertising()
        stopBrowsing()
        stopHeartbeat()
        
        // Disconnect from all peers
        session.disconnect()
        
        // Clear state
        connectedPeers.removeAll()
        sessionMetadata = nil
        isHost = false
        sessionState = .disconnected
        
        // Stop recording
        sessionRecorder.stopRecording()
        
        logInfo("Left collaboration session", category: .collaboration)
    }
    
    public func searchForSessions() {
        guard sessionState == .disconnected else { return }
        
        sessionState = .searching
        
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        
        // Auto-stop searching after timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            if self.sessionState == .searching {
                self.stopSearching()
            }
        }
    }
    
    public func stopSearching() {
        stopBrowsing()
        if sessionState == .searching {
            sessionState = .disconnected
        }
    }
    
    // MARK: - Message Handling
    
    public func sendMessage(_ message: CollaborationMessage, to peers: [MCPeerID]? = nil) throws {
        let targetPeers = peers ?? session.connectedPeers
        guard !targetPeers.isEmpty else {
            throw CollaborationError.noPeersConnected
        }
        
        // Add message metadata
        var messageWithMetadata = message
        messageWithMetadata.id = UUID()
        messageWithMetadata.timestamp = Date()
        messageWithMetadata.senderId = localPeer.id
        
        // Serialize message
        let data = try JSONEncoder().encode(messageWithMetadata)
        
        // Send to peers
        try session.send(data, toPeers: targetPeers, with: .reliable)
        
        // Record message
        sessionRecorder.recordMessage(messageWithMetadata, direction: .outgoing)
        
        logDebug("Sent collaboration message", category: .collaboration, context: LogContext(customData: [
            "message_type": message.type.rawValue,
            "peers_count": targetPeers.count
        ]))
    }
    
    public func broadcastMessage(_ message: CollaborationMessage) throws {
        try sendMessage(message, to: nil)
    }
    
    // MARK: - User Actions
    
    public func updateUserCursor(position: SIMD3<Float>, target: String?) throws {
        let message = CollaborationMessage(
            type: .cursorUpdate,
            payload: CursorUpdatePayload(
                position: position,
                target: target,
                timestamp: Date()
            )
        )
        try broadcastMessage(message)
    }
    
    public func selectObject(_ objectId: UUID) throws {
        let message = CollaborationMessage(
            type: .objectSelection,
            payload: ObjectSelectionPayload(
                objectId: objectId,
                userId: localPeer.id,
                selectionType: .select
            )
        )
        try broadcastMessage(message)
    }
    
    public func deselectObject(_ objectId: UUID) throws {
        let message = CollaborationMessage(
            type: .objectSelection,
            payload: ObjectSelectionPayload(
                objectId: objectId,
                userId: localPeer.id,
                selectionType: .deselect
            )
        )
        try broadcastMessage(message)
    }
    
    public func moveObject(_ objectId: UUID, to position: SIMD3<Float>, rotation: Float) throws {
        let message = CollaborationMessage(
            type: .objectTransform,
            payload: ObjectTransformPayload(
                objectId: objectId,
                position: position,
                rotation: rotation,
                scale: SIMD3<Float>(1, 1, 1),
                transformType: .move
            )
        )
        try broadcastMessage(message)
    }
    
    public func addObject(_ furniture: FurnitureItem, at position: SIMD3<Float>) throws {
        let message = CollaborationMessage(
            type: .objectAdd,
            payload: ObjectAddPayload(
                objectId: furniture.id,
                furnitureType: furniture.category.rawValue,
                position: position,
                rotation: 0.0,
                metadata: furniture.metadata
            )
        )
        try broadcastMessage(message)
    }
    
    public func removeObject(_ objectId: UUID) throws {
        let message = CollaborationMessage(
            type: .objectRemove,
            payload: ObjectRemovePayload(
                objectId: objectId,
                userId: localPeer.id
            )
        )
        try broadcastMessage(message)
    }
    
    // MARK: - Permission Management
    
    public func updatePeerPermission(_ peerId: UUID, permission: CollaborationPermission) throws {
        guard isHost else {
            throw CollaborationError.insufficientPermissions("Only host can change permissions")
        }
        
        guard var peer = connectedPeers.first(where: { $0.id == peerId }) else {
            throw CollaborationError.peerNotFound
        }
        
        peer.permission = permission
        
        if let index = connectedPeers.firstIndex(where: { $0.id == peerId }) {
            connectedPeers[index] = peer
        }
        
        // Notify peer of permission change
        let message = CollaborationMessage(
            type: .permissionUpdate,
            payload: PermissionUpdatePayload(
                userId: peerId,
                newPermission: permission,
                updatedBy: localPeer.id
            )
        )
        
        if let mcPeer = session.connectedPeers.first(where: { 
            connectedPeers.first(where: { $0.peerID == $0 })?.id == peerId 
        }) {
            try sendMessage(message, to: [mcPeer])
        }
        
        logInfo("Updated peer permission", category: .collaboration, context: LogContext(customData: [
            "peer_id": peerId.uuidString,
            "new_permission": permission.rawValue
        ]))
    }
    
    public func kickPeer(_ peerId: UUID) throws {
        guard isHost else {
            throw CollaborationError.insufficientPermissions("Only host can kick peers")
        }
        
        guard let peer = connectedPeers.first(where: { $0.id == peerId }) else {
            throw CollaborationError.peerNotFound
        }
        
        // Send kick notification
        let message = CollaborationMessage(
            type: .peerKick,
            payload: PeerKickPayload(
                kickedUserId: peerId,
                reason: "Removed by host"
            )
        )
        
        try sendMessage(message, to: [peer.peerID])
        
        // Disconnect the peer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Forcibly disconnect after giving them a chance to leave gracefully
            if self.session.connectedPeers.contains(peer.peerID) {
                self.session.cancelConnectPeer(peer.peerID)
            }
        }
        
        logInfo("Kicked peer from session", category: .collaboration, context: LogContext(customData: [
            "peer_id": peerId.uuidString,
            "peer_name": peer.displayName
        ]))
    }
    
    // MARK: - Network Monitoring
    
    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }
    
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    private func sendHeartbeat() {
        let heartbeat = CollaborationMessage(
            type: .heartbeat,
            payload: HeartbeatPayload(
                timestamp: Date(),
                networkQuality: networkQuality.rawValue
            )
        )
        
        do {
            try broadcastMessage(heartbeat)
        } catch {
            logWarning("Failed to send heartbeat", category: .collaboration, error: error)
        }
    }
    
    private func handleNetworkQualityChange(_ quality: NetworkQuality) {
        switch quality {
        case .poor, .disconnected:
            if sessionState == .connected || sessionState == .hosting {
                startReconnectionProcess()
            }
        case .fair:
            // Reduce message frequency or quality
            break
        case .good, .excellent:
            // Resume normal operations
            if sessionState == .reconnecting {
                sessionState = isHost ? .hosting : .connected
            }
        }
    }
    
    private func startReconnectionProcess() {
        guard sessionState != .reconnecting else { return }
        
        sessionState = .reconnecting
        
        reconnectionTimer = Timer.scheduledTimer(withTimeInterval: reconnectionDelay, repeats: true) { [weak self] timer in
            self?.attemptReconnection()
        }
    }
    
    private func attemptReconnection() {
        // Try to send a test message to verify connectivity
        let testMessage = CollaborationMessage(
            type: .connectionTest,
            payload: ConnectionTestPayload(timestamp: Date())
        )
        
        do {
            try broadcastMessage(testMessage)
            // If successful, we're back online
            reconnectionTimer?.invalidate()
            reconnectionTimer = nil
            sessionState = isHost ? .hosting : .connected
        } catch {
            logDebug("Reconnection attempt failed", category: .collaboration, error: error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createDiscoveryInfo() -> [String: String] {
        var info: [String: String] = [:]
        
        if let metadata = sessionMetadata {
            info["sessionName"] = metadata.name
            info["sessionId"] = metadata.id.uuidString
            info["maxPeers"] = String(metadata.maxParticipants)
            info["currentPeers"] = String(connectedPeers.count + 1) // +1 for host
            
            if let roomData = metadata.roomData {
                info["hasRoomData"] = "true"
                info["roomType"] = roomData.roomType.rawValue
            }
        }
        
        info["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        info["deviceType"] = UIDevice.current.userInterfaceIdiom.rawValue
        
        return info
    }
    
    private func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
    }
    
    private func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
    }
    
    private func handleSessionStateChange(_ state: CollaborationState) {
        switch state {
        case .connected, .hosting:
            HapticFeedbackManager.shared.operationSuccess()
            AccessibilityManager.shared.announceSuccess("Connected to collaboration session")
        case .disconnected:
            AccessibilityManager.shared.announce("Disconnected from collaboration session", priority: .normal)
        case .error:
            HapticFeedbackManager.shared.operationError()
            AccessibilityManager.shared.announceError("Collaboration session error")
        default:
            break
        }
    }
    
    // MARK: - Public Interface
    
    public func getAvailableSessions() -> [DiscoveredSession] {
        // This would be populated by the browser delegate
        return []
    }
    
    public func canPerformAction(_ action: CollaborationAction) -> Bool {
        return permissionManager.canPerform(action, with: localPeer.permission)
    }
    
    public func getPeerByPeerID(_ peerID: MCPeerID) -> CollaborationPeer? {
        return connectedPeers.first { $0.peerID == peerID }
    }
    
    public func getSessionStatistics() -> SessionStatistics {
        return SessionStatistics(
            sessionDuration: sessionMetadata?.createdAt.timeIntervalSinceNow ?? 0,
            totalMessages: sessionRecorder.getMessageCount(),
            connectedPeersCount: connectedPeers.count,
            networkQuality: networkQuality,
            dataTransferred: networkMonitor.getTotalDataTransferred()
        )
    }
}

// MARK: - MCSessionDelegate

extension CollaborationManager: MCSessionDelegate {
    
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.handlePeerConnected(peerID)
            case .connecting:
                self.handlePeerConnecting(peerID)
            case .notConnected:
                self.handlePeerDisconnected(peerID)
            @unknown default:
                logWarning("Unknown peer state", category: .collaboration)
            }
        }
    }
    
    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.handleReceivedData(data, from: peerID)
        }
    }
    
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Handle incoming streams (for voice chat)
        logDebug("Received stream from peer", category: .collaboration, context: LogContext(customData: [
            "stream_name": streamName,
            "peer": peerID.displayName
        ]))
    }
    
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        logDebug("Started receiving resource", category: .collaboration, context: LogContext(customData: [
            "resource_name": resourceName,
            "peer": peerID.displayName
        ]))
    }
    
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        if let error = error {
            logError("Failed to receive resource", category: .collaboration, error: error)
        } else {
            logDebug("Finished receiving resource", category: .collaboration, context: LogContext(customData: [
                "resource_name": resourceName,
                "peer": peerID.displayName
            ]))
        }
    }
    
    // MARK: - Peer Management
    
    private func handlePeerConnected(_ peerID: MCPeerID) {
        let newPeer = CollaborationPeer(
            id: UUID(),
            peerID: peerID,
            displayName: peerID.displayName,
            permission: .edit, // Default permission
            status: .connected,
            deviceType: .iOS // Would be detected from discovery info
        )
        
        connectedPeers.append(newPeer)
        
        if sessionState != .hosting && sessionState != .connected {
            sessionState = .connected
        }
        
        // Send welcome message with session info
        if isHost {
            sendWelcomeMessage(to: newPeer)
        }
        
        logInfo("Peer connected", category: .collaboration, context: LogContext(customData: [
            "peer_name": peerID.displayName,
            "total_peers": connectedPeers.count
        ]))
    }
    
    private func handlePeerConnecting(_ peerID: MCPeerID) {
        logDebug("Peer connecting", category: .collaboration, context: LogContext(customData: [
            "peer_name": peerID.displayName
        ]))
    }
    
    private func handlePeerDisconnected(_ peerID: MCPeerID) {
        connectedPeers.removeAll { $0.peerID == peerID }
        
        if connectedPeers.isEmpty && !isHost {
            sessionState = .disconnected
        }
        
        logInfo("Peer disconnected", category: .collaboration, context: LogContext(customData: [
            "peer_name": peerID.displayName,
            "remaining_peers": connectedPeers.count
        ]))
    }
    
    private func sendWelcomeMessage(to peer: CollaborationPeer) {
        let welcomeMessage = CollaborationMessage(
            type: .welcome,
            payload: WelcomePayload(
                sessionMetadata: sessionMetadata,
                connectedPeers: connectedPeers,
                yourPermission: peer.permission
            )
        )
        
        do {
            try sendMessage(welcomeMessage, to: [peer.peerID])
        } catch {
            logWarning("Failed to send welcome message", category: .collaboration, error: error)
        }
    }
    
    private func handleReceivedData(_ data: Data, from peerID: MCPeerID) {
        do {
            let message = try JSONDecoder().decode(CollaborationMessage.self, from: data)
            
            // Record received message
            sessionRecorder.recordMessage(message, direction: .incoming)
            
            // Process message
            try messageProcessor.processMessage(message, from: peerID, in: self)
            
        } catch {
            logError("Failed to process received message", category: .collaboration, error: error)
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension CollaborationManager: MCNearbyServiceAdvertiserDelegate {
    
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        
        // Check if we can accept more peers
        guard connectedPeers.count < maxPeers else {
            invitationHandler(false, nil)
            return
        }
        
        // Auto-accept for now (could add user confirmation later)
        invitationHandler(true, session)
        
        logInfo("Accepted invitation from peer", category: .collaboration, context: LogContext(customData: [
            "peer_name": peerID.displayName
        ]))
    }
    
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        sessionState = .error(error)
        logError("Failed to start advertising", category: .collaboration, error: error)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension CollaborationManager: MCNearbyServiceBrowserDelegate {
    
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        
        // Create discovered session info
        let discoveredSession = DiscoveredSession(
            hostPeerID: peerID,
            sessionName: info?["sessionName"] ?? peerID.displayName,
            sessionId: UUID(uuidString: info?["sessionId"] ?? "") ?? UUID(),
            currentParticipants: Int(info?["currentPeers"] ?? "1") ?? 1,
            maxParticipants: Int(info?["maxPeers"] ?? "6") ?? 6,
            hasRoomData: info?["hasRoomData"] == "true",
            discoveryInfo: info ?? [:]
        )
        
        // Auto-join if we were specifically looking for this session
        // Otherwise, present to user for selection
        
        logInfo("Found collaboration session", category: .collaboration, context: LogContext(customData: [
            "session_name": discoveredSession.sessionName,
            "host_peer": peerID.displayName
        ]))
    }
    
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        logDebug("Lost peer", category: .collaboration, context: LogContext(customData: [
            "peer_name": peerID.displayName
        ]))
    }
    
    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        sessionState = .error(error)
        logError("Failed to start browsing", category: .collaboration, error: error)
    }
}

// MARK: - Supporting Data Structures

public struct CollaborationPeer: Identifiable, Codable {
    public let id: UUID
    public let peerID: MCPeerID
    public let displayName: String
    public var permission: CollaborationPermission
    public var status: PeerStatus
    public let deviceType: DeviceType
    public var lastSeen: Date = Date()
    
    public enum PeerStatus: String, Codable, CaseIterable {
        case connected = "Connected"
        case connecting = "Connecting"
        case disconnected = "Disconnected"
        case reconnecting = "Reconnecting"
    }
    
    public enum DeviceType: String, Codable, CaseIterable {
        case iOS = "iOS"
        case iPad = "iPad"
        case mac = "Mac"
        case unknown = "Unknown"
    }
    
    // Custom coding to handle MCPeerID
    private enum CodingKeys: String, CodingKey {
        case id, displayName, permission, status, deviceType, lastSeen
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        permission = try container.decode(CollaborationPermission.self, forKey: .permission)
        status = try container.decode(PeerStatus.self, forKey: .status)
        deviceType = try container.decode(DeviceType.self, forKey: .deviceType)
        lastSeen = try container.decode(Date.self, forKey: .lastSeen)
        
        // Reconstruct MCPeerID
        peerID = MCPeerID(displayName: displayName)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(permission, forKey: .permission)
        try container.encode(status, forKey: .status)
        try container.encode(deviceType, forKey: .deviceType)
        try container.encode(lastSeen, forKey: .lastSeen)
    }
    
    public init(id: UUID, peerID: MCPeerID, displayName: String, permission: CollaborationPermission, status: PeerStatus, deviceType: DeviceType) {
        self.id = id
        self.peerID = peerID
        self.displayName = displayName
        self.permission = permission
        self.status = status
        self.deviceType = deviceType
    }
}

public enum CollaborationPermission: String, Codable, CaseIterable {
    case host = "Host"
    case edit = "Edit"
    case comment = "Comment"
    case viewOnly = "View Only"
    
    var description: String {
        return rawValue
    }
    
    var canEdit: Bool {
        return self == .host || self == .edit
    }
    
    var canComment: Bool {
        return self != .viewOnly
    }
    
    var isHost: Bool {
        return self == .host
    }
}

public struct SessionMetadata: Codable {
    public let id: UUID
    public let name: String
    public let hostPeer: CollaborationPeer
    public let createdAt: Date
    public let roomData: ARRoomData?
    public let maxParticipants: Int
    
    public init(id: UUID, name: String, hostPeer: CollaborationPeer, createdAt: Date, roomData: ARRoomData?, maxParticipants: Int) {
        self.id = id
        self.name = name
        self.hostPeer = hostPeer
        self.createdAt = createdAt
        self.roomData = roomData
        self.maxParticipants = maxParticipants
    }
}

public struct DiscoveredSession {
    public let hostPeerID: MCPeerID
    public let sessionName: String
    public let sessionId: UUID
    public let currentParticipants: Int
    public let maxParticipants: Int
    public let hasRoomData: Bool
    public let discoveryInfo: [String: String]
}

public struct SessionStatistics {
    public let sessionDuration: TimeInterval
    public let totalMessages: Int
    public let connectedPeersCount: Int
    public let networkQuality: NetworkQuality
    public let dataTransferred: Int64
}

public enum CollaborationAction {
    case addObject
    case removeObject
    case moveObject
    case selectObject
    case changePermissions
    case kickPeer
    case recordSession
}

public enum CollaborationError: Error {
    case invalidState(String)
    case noPeersConnected
    case insufficientPermissions(String)
    case peerNotFound
    case messageEncodingFailed
    case sessionFull
    case networkError(Error)
    
    var localizedDescription: String {
        switch self {
        case .invalidState(let message): return "Invalid state: \(message)"
        case .noPeersConnected: return "No peers connected"
        case .insufficientPermissions(let message): return "Insufficient permissions: \(message)"
        case .peerNotFound: return "Peer not found"
        case .messageEncodingFailed: return "Failed to encode message"
        case .sessionFull: return "Session is full"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        }
    }
}

// Supporting extensions
extension UIUserInterfaceIdiom {
    var rawValue: String {
        switch self {
        case .phone: return "iPhone"
        case .pad: return "iPad"
        case .mac: return "Mac"
        case .tv: return "Apple TV"
        case .carPlay: return "CarPlay"
        case .vision: return "Vision Pro"
        default: return "Unknown"
        }
    }
}

extension NetworkQuality {
    var rawValue: String {
        return description
    }
}