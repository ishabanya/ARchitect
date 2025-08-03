import Foundation
import Network
import MultipeerConnectivity
import Combine

// MARK: - Network Monitoring and Disconnection Handling

@MainActor
public class NetworkMonitor: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var networkQuality: NetworkQuality = .good
    @Published public var connectionState: ConnectionState = .disconnected
    @Published public var reconnectionState: ReconnectionState = .idle
    @Published public var dataTransferred: NetworkDataStats = .zero
    @Published public var activeConnections: [PeerConnection] = []
    
    // MARK: - Private Properties
    private let pathMonitor: NWPathMonitor
    private let monitorQueue: DispatchQueue
    private let reconnectionManager: ReconnectionManager
    private let connectionHealthTracker: ConnectionHealthTracker
    private let fallbackManager: FallbackConnectionManager
    
    private var cancellables = Set<AnyCancellable>()
    private var healthCheckTimer: Timer?
    private var reconnectionTimer: Timer?
    
    // MARK: - Configuration
    private let healthCheckInterval: TimeInterval = 5.0
    private let reconnectionTimeout: TimeInterval = 30.0
    private let maxReconnectionAttempts = 5
    private let qualityAssessmentInterval: TimeInterval = 10.0
    
    public init() {
        self.pathMonitor = NWPathMonitor()
        self.monitorQueue = DispatchQueue(label: "network.monitor", qos: .utility)
        self.reconnectionManager = ReconnectionManager()
        self.connectionHealthTracker = ConnectionHealthTracker()
        self.fallbackManager = FallbackConnectionManager()
        
        setupNetworkMonitoring()
        setupObservers()
        
        logDebug("Network monitor initialized", category: .networking)
    }
    
    // MARK: - Network States
    
    public enum NetworkQuality: String, CaseIterable {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        case disconnected = "Disconnected"
        
        var latencyThreshold: TimeInterval {
            switch self {
            case .excellent: return 0.05
            case .good: return 0.1
            case .fair: return 0.2
            case .poor: return 0.5
            case .disconnected: return Double.infinity
            }
        }
        
        var packetLossThreshold: Float {
            switch self {
            case .excellent: return 0.01
            case .good: return 0.05
            case .fair: return 0.1
            case .poor: return 0.2
            case .disconnected: return 1.0
            }
        }
    }
    
    public enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case degraded
        case unstable
        case reconnecting
        
        var description: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            case .degraded: return "Connection Degraded"
            case .unstable: return "Unstable Connection"
            case .reconnecting: return "Reconnecting..."
            }
        }
    }
    
    public enum ReconnectionState {
        case idle
        case attempting
        case succeeded
        case failed
        case exhausted
        
        var description: String {
            switch self {
            case .idle: return "Ready"
            case .attempting: return "Attempting reconnection..."
            case .succeeded: return "Reconnection successful"
            case .failed: return "Reconnection failed"
            case .exhausted: return "Max reconnection attempts reached"
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handleNetworkPathUpdate(path)
            }
        }
        
        pathMonitor.start(queue: monitorQueue)
        
        // Start periodic quality assessment
        Timer.scheduledTimer(withTimeInterval: qualityAssessmentInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.assessNetworkQuality()
            }
        }
    }
    
    private func setupObservers() {
        $connectionState
            .sink { [weak self] state in
                self?.handleConnectionStateChange(state)
            }
            .store(in: &cancellables)
        
        $networkQuality
            .sink { [weak self] quality in
                self?.handleNetworkQualityChange(quality)
            }  
            .store(in: &cancellables)
    }
    
    // MARK: - Network Path Monitoring
    
    private func handleNetworkPathUpdate(_ path: NWPath) {
        let previousState = connectionState
        
        switch path.status {
        case .satisfied:
            if connectionState == .disconnected || connectionState == .reconnecting {
                connectionState = .connecting
                attemptReconnection()
            }
            
        case .unsatisfied:
            connectionState = .disconnected
            handleNetworkDisconnection()
            
        case .requiresConnection:
            connectionState = .degraded
            
        @unknown default:
            connectionState = .unstable
        }
        
        // Log network interface changes
        logNetworkInterfaceChanges(path)
        
        if previousState != connectionState {
            logInfo("Network connection state changed", category: .networking, context: LogContext(customData: [
                "previous_state": String(describing: previousState),
                "new_state": String(describing: connectionState),
                "network_available": path.status == .satisfied
            ]))
        }
    }
    
    private func logNetworkInterfaceChanges(_ path: NWPath) {
        let interfaces = path.availableInterfaces.map { $0.name }.joined(separator: ", ")
        let isExpensive = path.isExpensive
        let isConstrained = path.isConstrained
        
        logDebug("Network interfaces updated", category: .networking, context: LogContext(customData: [
            "available_interfaces": interfaces,
            "is_expensive": isExpensive,
            "is_constrained": isConstrained
        ]))
    }
    
    // MARK: - Connection Management
    
    public func startMonitoring(session: MCSession?) {
        guard let session = session else { return }
        
        // Start health check monitoring
        startHealthChecks(for: session)
        
        // Track initial connections
        for peer in session.connectedPeers {
            addPeerConnection(peer, state: .connected)
        }
        
        connectionState = session.connectedPeers.isEmpty ? .disconnected : .connected
        
        logInfo("Started monitoring network connections", category: .networking, context: LogContext(customData: [
            "connected_peers": session.connectedPeers.count
        ]))
    }
    
    public func stopMonitoring() {
        stopHealthChecks()
        stopReconnectionAttempts()
        activeConnections.removeAll()
        connectionState = .disconnected
        
        logInfo("Stopped monitoring network connections", category: .networking)
    }
    
    public func addPeerConnection(_ peerId: MCPeerID, state: PeerConnectionState) {
        let connection = PeerConnection(
            id: UUID(),
            peerId: peerId,
            state: state,
            connectedAt: Date(),
            lastSeen: Date(),
            latency: 0,
            packetLoss: 0,
            dataTransferred: NetworkDataStats.zero
        )
        
        activeConnections.append(connection)
        updateConnectionState()
        
        logInfo("Peer connection added", category: .networking, context: LogContext(customData: [
            "peer_name": peerId.displayName,
            "connection_state": String(describing: state)
        ]))
    }
    
    public func removePeerConnection(_ peerId: MCPeerID) {
        activeConnections.removeAll { $0.peerId == peerId }
        updateConnectionState()
        
        logInfo("Peer connection removed", category: .networking, context: LogContext(customData: [
            "peer_name": peerId.displayName,
            "remaining_connections": activeConnections.count
        ]))
    }
    
    public func updatePeerConnectionState(_ peerId: MCPeerID, state: PeerConnectionState) {
        if let index = activeConnections.firstIndex(where: { $0.peerId == peerId }) {
            activeConnections[index].state = state
            activeConnections[index].lastSeen = Date()
            updateConnectionState()
        }
    }
    
    // MARK: - Disconnection Handling
    
    private func handleNetworkDisconnection() {
        // Mark all connections as disconnected
        for i in 0..<activeConnections.count {
            activeConnections[i].state = .disconnected
        }
        
        // Stop health checks
        stopHealthChecks()
        
        // Start reconnection process if we have connections to restore
        if !activeConnections.isEmpty {
            startReconnectionProcess()
        }
        
        logWarning("Network disconnection detected", category: .networking, context: LogContext(customData: [
            "affected_connections": activeConnections.count
        ]))
    }
    
    private func startReconnectionProcess() {
        guard reconnectionState == .idle else { return }
        
        reconnectionState = .attempting
        reconnectionManager.startReconnection(
            connections: activeConnections,
            maxAttempts: maxReconnectionAttempts,
            timeout: reconnectionTimeout
        ) { [weak self] result in
            Task { @MainActor in
                self?.handleReconnectionResult(result)
            }
        }
        
        logInfo("Started reconnection process", category: .networking)
    }
    
    private func handleReconnectionResult(_ result: ReconnectionResult) {
        switch result {
        case .success(let restoredConnections):
            reconnectionState = .succeeded
            
            // Update connection states
            for connection in restoredConnections {
                updatePeerConnectionState(connection.peerId, state: .connected)
            }
            
            // Resume health checks
            if let session = getCurrentSession() {
                startHealthChecks(for: session)
            }
            
            logInfo("Reconnection successful", category: .networking, context: LogContext(customData: [
                "restored_connections": restoredConnections.count
            ]))
            
        case .partialSuccess(let restoredConnections, let failedConnections):
            reconnectionState = .succeeded
            
            // Update successful connections
            for connection in restoredConnections {
                updatePeerConnectionState(connection.peerId, state: .connected)
            }
            
            // Remove failed connections
            for connection in failedConnections {
                removePeerConnection(connection.peerId)
            }
            
            logWarning("Partial reconnection success", category: .networking, context: LogContext(customData: [
                "restored_connections": restoredConnections.count,
                "failed_connections": failedConnections.count
            ]))
            
        case .failure(let error):
            reconnectionState = .failed
            connectionState = .disconnected
            
            logError("Reconnection failed", category: .networking, error: error)
            
        case .exhausted:
            reconnectionState = .exhausted
            connectionState = .disconnected
            
            // Try fallback connection methods
            attemptFallbackConnection()
            
            logError("Reconnection attempts exhausted", category: .networking)
        }
        
        // Reset reconnection state after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if self.reconnectionState != .attempting {
                self.reconnectionState = .idle
            }
        }
    }
    
    // MARK: - Health Monitoring
    
    private func startHealthChecks(for session: MCSession) {
        stopHealthChecks()
        
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: healthCheckInterval, repeats: true) { [weak self] _ in
            self?.performHealthCheck(session: session)
        }
    }
    
    private func stopHealthChecks() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }
    
    private func performHealthCheck(session: MCSession) {
        let healthCheck = NetworkHealthCheck(
            timestamp: Date(),
            sessionId: UUID(),
            connectedPeers: session.connectedPeers.map { $0.displayName }
        )
        
        for peer in session.connectedPeers {
            checkPeerHealth(peer, in: session)
        }
        
        // Update overall connection health
        updateConnectionHealth()
    }
    
    private func checkPeerHealth(_ peer: MCPeerID, in session: MCSession) {
        guard let connectionIndex = activeConnections.firstIndex(where: { $0.peerId == peer }) else { return }
        
        let startTime = Date()
        
        // Send health check message
        let healthCheckData = createHealthCheckMessage()
        
        do {
            try session.send(healthCheckData, toPeers: [peer], with: .reliable)
            
            // Measure latency (simplified - in real implementation you'd wait for response)
            let latency = Date().timeIntervalSince(startTime)
            activeConnections[connectionIndex].latency = latency
            activeConnections[connectionIndex].lastSeen = Date()
            
            // Update health based on latency
            updatePeerHealth(connectionIndex, latency: latency)
            
        } catch {
            // Health check failed - peer may be disconnected
            activeConnections[connectionIndex].state = .disconnected
            logWarning("Health check failed for peer", category: .networking, context: LogContext(customData: [
                "peer_name": peer.displayName
            ]), error: error)
        }
    }
    
    private func updatePeerHealth(_ connectionIndex: Int, latency: TimeInterval) {
        let quality = determineQualityFromLatency(latency)
        
        switch quality {
        case .excellent, .good:
            activeConnections[connectionIndex].state = .connected
        case .fair:
            activeConnections[connectionIndex].state = .degraded
        case .poor:
            activeConnections[connectionIndex].state = .unstable
        case .disconnected:
            activeConnections[connectionIndex].state = .disconnected
        }
    }
    
    // MARK: - Quality Assessment
    
    private func assessNetworkQuality() {
        guard !activeConnections.isEmpty else {
            networkQuality = .disconnected
            return
        }
        
        let connectedConnections = activeConnections.filter { $0.state == .connected }
        guard !connectedConnections.isEmpty else {
            networkQuality = .disconnected
            return
        }
        
        // Calculate average latency
        let avgLatency = connectedConnections.reduce(0) { $0 + $1.latency } / Double(connectedConnections.count)
        
        // Calculate average packet loss
        let avgPacketLoss = connectedConnections.reduce(0) { $0 + $1.packetLoss } / Float(connectedConnections.count)
        
        // Determine overall quality
        networkQuality = determineOverallQuality(latency: avgLatency, packetLoss: avgPacketLoss)
        
        // Update data transfer statistics
        updateDataTransferStats()
    }
    
    private func determineQualityFromLatency(_ latency: TimeInterval) -> NetworkQuality {
        switch latency {
        case 0..<NetworkQuality.excellent.latencyThreshold:
            return .excellent
        case NetworkQuality.excellent.latencyThreshold..<NetworkQuality.good.latencyThreshold:
            return .good
        case NetworkQuality.good.latencyThreshold..<NetworkQuality.fair.latencyThreshold:
            return .fair
        case NetworkQuality.fair.latencyThreshold..<NetworkQuality.poor.latencyThreshold:
            return .poor
        default:
            return .disconnected
        }
    }
    
    private func determineOverallQuality(latency: TimeInterval, packetLoss: Float) -> NetworkQuality {
        let latencyQuality = determineQualityFromLatency(latency)
        let lossQuality = determineQualityFromPacketLoss(packetLoss)
        
        // Return the worse of the two qualities
        return min(latencyQuality, lossQuality)
    }
    
    private func determineQualityFromPacketLoss(_ packetLoss: Float) -> NetworkQuality {
        switch packetLoss {
        case 0..<NetworkQuality.excellent.packetLossThreshold:
            return .excellent
        case NetworkQuality.excellent.packetLossThreshold..<NetworkQuality.good.packetLossThreshold:
            return .good
        case NetworkQuality.good.packetLossThreshold..<NetworkQuality.fair.packetLossThreshold:
            return .fair
        case NetworkQuality.fair.packetLossThreshold..<NetworkQuality.poor.packetLossThreshold:
            return .poor
        default:
            return .disconnected
        }
    }
    
    // MARK: - Fallback Connection
    
    private func attemptFallbackConnection() {
        fallbackManager.attemptFallbackConnection(
            for: activeConnections.filter { $0.state == .disconnected }
        ) { [weak self] result in
            Task { @MainActor in
                self?.handleFallbackResult(result)
            }
        }
    }
    
    private func handleFallbackResult(_ result: FallbackResult) {
        switch result {
        case .success(let method):
            logInfo("Fallback connection successful", category: .networking, context: LogContext(customData: [
                "fallback_method": method.description
            ]))
            
        case .failure(let error):
            logError("Fallback connection failed", category: .networking, error: error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateConnectionState() {
        let connectedCount = activeConnections.filter { $0.state == .connected }.count
        let degradedCount = activeConnections.filter { $0.state == .degraded }.count
        let unstableCount = activeConnections.filter { $0.state == .unstable }.count
        
        if connectedCount == 0 {
            connectionState = .disconnected
        } else if degradedCount > connectedCount / 2 {
            connectionState = .degraded
        } else if unstableCount > 0 {
            connectionState = .unstable
        } else {
            connectionState = .connected
        }
    }
    
    private func updateConnectionHealth() {
        connectionHealthTracker.updateHealth(
            connections: activeConnections,
            networkQuality: networkQuality
        )
    }
    
    private func updateDataTransferStats() {
        let totalBytesReceived = activeConnections.reduce(0) { $0 + $1.dataTransferred.bytesReceived }
        let totalBytesSent = activeConnections.reduce(0) { $0 + $1.dataTransferred.bytesSent }
        
        dataTransferred = NetworkDataStats(
            bytesReceived: totalBytesReceived,
            bytesSent: totalBytesSent,
            messagesReceived: dataTransferred.messagesReceived, // Would be updated elsewhere
            messagesSent: dataTransferred.messagesSent // Would be updated elsewhere
        )
    }
    
    private func createHealthCheckMessage() -> Data {
        let healthCheck = HealthCheckMessage(
            timestamp: Date(),
            checkId: UUID(),
            type: .ping
        )
        
        return (try? JSONEncoder().encode(healthCheck)) ?? Data()
    }
    
    private func getCurrentSession() -> MCSession? {
        // This would be provided by the collaboration manager
        return nil
    }
    
    private func attemptReconnection() {
        // This would trigger the collaboration manager to attempt reconnection
        logInfo("Attempting network reconnection", category: .networking)
    }
    
    private func handleConnectionStateChange(_ state: ConnectionState) {
        switch state {
        case .connected:
            logInfo("Network connection established", category: .networking)
        case .disconnected:
            logWarning("Network connection lost", category: .networking)
        case .degraded:
            logWarning("Network connection degraded", category: .networking)
        case .unstable:
            logWarning("Network connection unstable", category: .networking)
        default:
            break
        }
    }
    
    private func handleNetworkQualityChange(_ quality: NetworkQuality) {
        logDebug("Network quality changed", category: .networking, context: LogContext(customData: [
            "quality": quality.rawValue
        ]))
    }
    
    private func stopReconnectionAttempts() {
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
        reconnectionManager.stopReconnection()
    }
    
    // MARK: - Public Interface
    
    public func getTotalDataTransferred() -> Int64 {
        return dataTransferred.bytesReceived + dataTransferred.bytesSent
    }
    
    public func getConnectionStatistics() -> NetworkStatistics {
        return NetworkStatistics(
            connectionState: connectionState,
            networkQuality: networkQuality,
            activeConnections: activeConnections.count,
            totalDataTransferred: getTotalDataTransferred(),
            averageLatency: activeConnections.isEmpty ? 0 : activeConnections.reduce(0) { $0 + $1.latency } / Double(activeConnections.count),
            packetLossRate: activeConnections.isEmpty ? 0 : activeConnections.reduce(0) { $0 + $1.packetLoss } / Float(activeConnections.count)
        )
    }
    
    public func forceReconnection() {
        guard connectionState != .connecting && connectionState != .reconnecting else { return }
        
        stopHealthChecks()
        startReconnectionProcess()
        
        logInfo("Manual reconnection initiated", category: .networking)
    }
    
    public func getNetworkDiagnostics() -> NetworkDiagnostics {
        return NetworkDiagnostics(
            pathStatus: pathMonitor.currentPath?.status.description ?? "Unknown",
            availableInterfaces: pathMonitor.currentPath?.availableInterfaces.map { $0.name } ?? [],
            isExpensive: pathMonitor.currentPath?.isExpensive ?? false,
            isConstrained: pathMonitor.currentPath?.isConstrained ?? false,
            activeConnections: activeConnections,
            reconnectionHistory: reconnectionManager.getReconnectionHistory()
        )
    }
}

// MARK: - Supporting Data Structures

public struct PeerConnection: Identifiable {
    public let id: UUID
    public let peerId: MCPeerID
    public var state: PeerConnectionState
    public let connectedAt: Date
    public var lastSeen: Date
    public var latency: TimeInterval
    public var packetLoss: Float
    public var dataTransferred: NetworkDataStats
}

public enum PeerConnectionState {
    case connecting
    case connected
    case degraded
    case unstable
    case disconnected
    case reconnecting
}

public struct NetworkDataStats {
    public let bytesReceived: Int64
    public let bytesSent: Int64
    public let messagesReceived: Int
    public let messagesSent: Int
    
    public static let zero = NetworkDataStats(
        bytesReceived: 0,
        bytesSent: 0,
        messagesReceived: 0,
        messagesSent: 0
    )
}

public struct NetworkStatistics {
    public let connectionState: NetworkMonitor.ConnectionState
    public let networkQuality: NetworkMonitor.NetworkQuality
    public let activeConnections: Int
    public let totalDataTransferred: Int64
    public let averageLatency: TimeInterval
    public let packetLossRate: Float
}

public struct NetworkDiagnostics {
    public let pathStatus: String
    public let availableInterfaces: [String]
    public let isExpensive: Bool
    public let isConstrained: Bool
    public let activeConnections: [PeerConnection]
    public let reconnectionHistory: [ReconnectionAttempt]
}

public struct NetworkHealthCheck {
    public let timestamp: Date
    public let sessionId: UUID
    public let connectedPeers: [String]
}

public struct HealthCheckMessage: Codable {
    public let timestamp: Date
    public let checkId: UUID
    public let type: HealthCheckType
    
    public enum HealthCheckType: String, Codable {
        case ping = "ping"
        case pong = "pong"
        case status = "status"
    }
}

public enum ReconnectionResult {
    case success([PeerConnection])
    case partialSuccess([PeerConnection], [PeerConnection])
    case failure(Error)
    case exhausted
}

public enum FallbackResult {
    case success(FallbackMethod)
    case failure(Error)
}

public enum FallbackMethod {
    case bluetooth
    case hotspot
    case infrastructure
    
    var description: String {
        switch self {
        case .bluetooth: return "Bluetooth"
        case .hotspot: return "Personal Hotspot"
        case .infrastructure: return "Infrastructure WiFi"
        }
    }
}

public struct ReconnectionAttempt {
    public let id: UUID
    public let timestamp: Date
    public let targetPeers: [MCPeerID]
    public let result: ReconnectionResult?
    public let duration: TimeInterval?
}

public enum NetworkError: Error {
    case connectionLost
    case reconnectionFailed
    case healthCheckFailed
    case fallbackUnavailable
    
    public var localizedDescription: String {
        switch self {
        case .connectionLost: return "Network connection lost"
        case .reconnectionFailed: return "Failed to reconnect"
        case .healthCheckFailed: return "Health check failed"
        case .fallbackUnavailable: return "Fallback connection unavailable"
        }
    }
}

// MARK: - Supporting Classes

@MainActor
class ReconnectionManager {
    private var isReconnecting = false
    private var reconnectionAttempts: [ReconnectionAttempt] = []
    private let maxHistoryEntries = 50
    
    func startReconnection(
        connections: [PeerConnection],
        maxAttempts: Int,
        timeout: TimeInterval,
        completion: @escaping (ReconnectionResult) -> Void
    ) {
        guard !isReconnecting else { return }
        
        isReconnecting = true
        let targetPeers = connections.map { $0.peerId }
        
        let attempt = ReconnectionAttempt(
            id: UUID(),
            timestamp: Date(),
            targetPeers: targetPeers,
            result: nil,
            duration: nil
        )
        
        reconnectionAttempts.append(attempt)
        trimHistory()
        
        // Simulate reconnection process
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isReconnecting = false
            
            // Simulate partial success
            let successfulConnections = Array(connections.prefix(connections.count / 2))
            let failedConnections = Array(connections.suffix(connections.count / 2))
            
            if !successfulConnections.isEmpty {
                completion(.partialSuccess(successfulConnections, failedConnections))
            } else {
                completion(.failure(NetworkError.reconnectionFailed))
            }
        }
    }
    
    func stopReconnection() {
        isReconnecting = false
    }
    
    func getReconnectionHistory() -> [ReconnectionAttempt] {
        return reconnectionAttempts
    }
    
    private func trimHistory() {
        if reconnectionAttempts.count > maxHistoryEntries {
            reconnectionAttempts.removeFirst(reconnectionAttempts.count - maxHistoryEntries)
        }
    }
}

@MainActor
class ConnectionHealthTracker {
    private var healthHistory: [ConnectionHealthSnapshot] = []
    private let maxHistoryEntries = 100
    
    func updateHealth(connections: [PeerConnection], networkQuality: NetworkMonitor.NetworkQuality) {
        let snapshot = ConnectionHealthSnapshot(
            timestamp: Date(),
            connectionCount: connections.count,
            networkQuality: networkQuality,
            averageLatency: connections.isEmpty ? 0 : connections.reduce(0) { $0 + $1.latency } / Double(connections.count),
            packetLossRate: connections.isEmpty ? 0 : connections.reduce(0) { $0 + $1.packetLoss } / Float(connections.count)
        )
        
        healthHistory.append(snapshot)
        trimHistory()
    }
    
    func getHealthHistory() -> [ConnectionHealthSnapshot] {
        return healthHistory
    }
    
    private func trimHistory() {
        if healthHistory.count > maxHistoryEntries {
            healthHistory.removeFirst(healthHistory.count - maxHistoryEntries)
        }
    }
    
    struct ConnectionHealthSnapshot {
        let timestamp: Date
        let connectionCount: Int
        let networkQuality: NetworkMonitor.NetworkQuality
        let averageLatency: TimeInterval
        let packetLossRate: Float
    }
}

@MainActor
class FallbackConnectionManager {
    
    func attemptFallbackConnection(
        for connections: [PeerConnection],
        completion: @escaping (FallbackResult) -> Void
    ) {
        // Try different fallback methods in order of preference
        attemptBluetoothFallback(for: connections) { result in
            switch result {
            case .success:
                completion(result)
            case .failure:
                self.attemptHotspotFallback(for: connections) { hotspotResult in
                    switch hotspotResult {
                    case .success:
                        completion(hotspotResult)
                    case .failure:
                        self.attemptInfrastructureFallback(for: connections, completion: completion)
                    }
                }
            }
        }
    }
    
    private func attemptBluetoothFallback(
        for connections: [PeerConnection],
        completion: @escaping (FallbackResult) -> Void
    ) {
        // Simulate Bluetooth fallback attempt
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Bluetooth has limited range and bandwidth
            if connections.count <= 2 {
                completion(.success(.bluetooth))
            } else {
                completion(.failure(NetworkError.fallbackUnavailable))
            }
        }
    }
    
    private func attemptHotspotFallback(
        for connections: [PeerConnection],
        completion: @escaping (FallbackResult) -> Void
    ) {
        // Simulate Personal Hotspot fallback attempt
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Hotspot can handle more connections but may be expensive
            completion(.success(.hotspot))
        }
    }
    
    private func attemptInfrastructureFallback(
        for connections: [PeerConnection],
        completion: @escaping (FallbackResult) -> Void
    ) {
        // Simulate Infrastructure WiFi fallback attempt
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Infrastructure WiFi requires all devices to be on same network
            completion(.failure(NetworkError.fallbackUnavailable))
        }
    }
}

// Extensions for NetworkQuality to make it comparable
extension NetworkMonitor.NetworkQuality: Comparable {
    public static func < (lhs: NetworkMonitor.NetworkQuality, rhs: NetworkMonitor.NetworkQuality) -> Bool {
        return lhs.qualityScore < rhs.qualityScore
    }
    
    private var qualityScore: Int {
        switch self {
        case .excellent: return 5
        case .good: return 4
        case .fair: return 3
        case .poor: return 2
        case .disconnected: return 1
        }
    }
}

extension NWPath.Status {
    var description: String {
        switch self {
        case .satisfied: return "Satisfied"
        case .unsatisfied: return "Unsatisfied"
        case .requiresConnection: return "Requires Connection"
        @unknown default: return "Unknown"
        }
    }
}