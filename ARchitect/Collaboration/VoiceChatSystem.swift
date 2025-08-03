import Foundation
import AVFoundation
import MultipeerConnectivity
import Combine
import CallKit

// MARK: - Voice Chat Integration System

@MainActor
public class VoiceChatSystem: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published public var chatState: VoiceChatState = .disabled
    @Published public var activeParticipants: [VoiceParticipant] = []
    @Published public var isMuted: Bool = false
    @Published public var isSpeaking: Bool = false
    @Published public var audioLevel: Float = 0.0
    @Published public var networkQuality: AudioNetworkQuality = .good
    
    // MARK: - Private Properties
    private let audioEngine: AVAudioEngine
    private let audioSession: AVAudioSession
    private let audioManager: VoiceAudioManager
    private let streamManager: AudioStreamManager
    private let participantManager: ParticipantManager
    private let qualityMonitor: AudioQualityMonitor
    
    private var mcSession: MCSession?
    private var audioInputStream: InputStream?
    private var audioOutputStream: OutputStream?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Configuration
    private let sampleRate: Double = 44100.0
    private let bufferSize: AVAudioFrameCount = 1024
    private lazy var audioFormat: AVAudioFormat = {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
            fatalError("Failed to create audio format - this should never happen with standard parameters")
        }
        return format
    }()
    private let maxParticipants = 8
    
    public override init() {
        self.audioEngine = AVAudioEngine()
        self.audioSession = AVAudioSession.sharedInstance()
        self.audioManager = VoiceAudioManager()
        self.streamManager = AudioStreamManager()
        self.participantManager = ParticipantManager()
        self.qualityMonitor = AudioQualityMonitor()
        
        super.init()
        
        setupObservers()
        
        logDebug("Voice chat system initialized", category: .collaboration)
    }
    
    // MARK: - Chat States
    
    public enum VoiceChatState {
        case disabled
        case initializing
        case ready
        case connecting
        case connected
        case disconnecting
        case failed(Error)
        
        var description: String {
            switch self {
            case .disabled: return "Voice chat disabled"
            case .initializing: return "Initializing audio system..."
            case .ready: return "Ready for voice chat"
            case .connecting: return "Connecting to voice chat..."
            case .connected: return "Voice chat active"
            case .disconnecting: return "Disconnecting..."
            case .failed(let error): return "Voice chat failed: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        $isMuted
            .sink { [weak self] muted in
                self?.handleMuteStateChange(muted)
            }
            .store(in: &cancellables)
        
        // Monitor audio session interruptions
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                self?.handleAudioInterruption(notification)
            }
            .store(in: &cancellables)
        
        // Monitor route changes
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in
                self?.handleAudioRouteChange(notification)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Voice Chat Control
    
    public func initializeVoiceChat() async throws {
        guard chatState == .disabled else {
            throw VoiceChatError.invalidState("Voice chat already initialized")
        }
        
        chatState = .initializing
        
        do {
            // Request microphone permission
            let granted = await requestMicrophonePermission()
            guard granted else {
                throw VoiceChatError.permissionDenied("Microphone permission required")
            }
            
            // Configure audio session
            try await configureAudioSession()
            
            // Initialize audio engine
            try setupAudioEngine()
            
            // Initialize audio processing components
            try audioManager.initialize(audioFormat: audioFormat)
            try streamManager.initialize()
            
            chatState = .ready
            
            logInfo("Voice chat initialized successfully", category: .collaboration)
            
        } catch {
            chatState = .failed(error)
            throw error
        }
    }
    
    public func startVoiceChat(session: MCSession) async throws {
        guard chatState == .ready else {
            throw VoiceChatError.invalidState("Voice chat not ready")
        }
        
        chatState = .connecting
        mcSession = session
        
        do {
            // Start audio engine
            try audioEngine.start()
            
            // Initialize streams for each connected peer
            try await initializeAudioStreams(for: session.connectedPeers)
            
            // Start audio processing
            try audioManager.startProcessing()
            
            // Start quality monitoring
            qualityMonitor.startMonitoring { [weak self] quality in
                Task { @MainActor in
                    self?.networkQuality = quality
                }
            }
            
            chatState = .connected
            
            logInfo("Voice chat started", category: .collaboration, context: LogContext(customData: [
                "connected_peers": session.connectedPeers.count
            ]))
            
        } catch {
            chatState = .failed(error)
            throw error
        }
    }
    
    public func stopVoiceChat() async throws {
        guard chatState == .connected else {
            throw VoiceChatError.invalidState("Voice chat not active")
        }
        
        chatState = .disconnecting
        
        do {
            // Stop audio processing
            audioManager.stopProcessing()
            
            // Stop audio engine
            audioEngine.stop()
            
            // Close all audio streams
            try await closeAudioStreams()
            
            // Stop quality monitoring
            qualityMonitor.stopMonitoring()
            
            // Clear participants
            activeParticipants.removeAll()
            
            mcSession = nil
            chatState = .ready
            
            logInfo("Voice chat stopped", category: .collaboration)
            
        } catch {
            chatState = .failed(error)
            throw error
        }
    }
    
    // MARK: - Participant Management
    
    public func addParticipant(_ peerId: MCPeerID, userId: UUID, userName: String) throws {
        guard activeParticipants.count < maxParticipants else {
            throw VoiceChatError.maxParticipantsReached
        }
        
        let participant = VoiceParticipant(
            id: UUID(),
            userId: userId,
            userName: userName,
            peerId: peerId,
            isMuted: false,
            isSpeaking: false,
            audioLevel: 0.0,
            connectionState: .connecting,
            joinedAt: Date()
        )
        
        activeParticipants.append(participant)
        
        // Initialize audio stream for this participant
        if chatState == .connected {
            try streamManager.createStreamForPeer(peerId)
        }
        
        logInfo("Voice chat participant added", category: .collaboration, context: LogContext(customData: [
            "participant_name": userName,
            "total_participants": activeParticipants.count
        ]))
    }
    
    public func removeParticipant(_ peerId: MCPeerID) {
        activeParticipants.removeAll { $0.peerId == peerId }
        
        // Close audio stream for this participant
        streamManager.closeStreamForPeer(peerId)
        
        logInfo("Voice chat participant removed", category: .collaboration, context: LogContext(customData: [
            "remaining_participants": activeParticipants.count
        ]))
    }
    
    public func updateParticipantState(_ peerId: MCPeerID, isSpeaking: Bool, audioLevel: Float) {
        if let index = activeParticipants.firstIndex(where: { $0.peerId == peerId }) {
            activeParticipants[index].isSpeaking = isSpeaking
            activeParticipants[index].audioLevel = audioLevel
            activeParticipants[index].lastActivity = Date()
        }
    }
    
    // MARK: - Audio Control
    
    public func toggleMute() {
        isMuted.toggle()
    }
    
    public func setMuted(_ muted: Bool) {
        isMuted = muted
    }
    
    public func adjustVolume(for peerId: MCPeerID, volume: Float) {
        streamManager.setVolume(volume, for: peerId)
        
        if let index = activeParticipants.firstIndex(where: { $0.peerId == peerId }) {
            activeParticipants[index].volume = volume
        }
    }
    
    public func setSpatialAudio(enabled: Bool, for peerId: MCPeerID, position: SIMD3<Float>?) {
        streamManager.setSpatialAudio(enabled: enabled, for: peerId, position: position)
    }
    
    // MARK: - Audio Session Configuration
    
    private func requestMicrophonePermission() async -> Bool {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            return true
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
    
    private func configureAudioSession() async throws {
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth, .defaultToSpeaker]
        )
        
        try audioSession.setPreferredSampleRate(sampleRate)
        try audioSession.setPreferredIOBufferDuration(Double(bufferSize) / sampleRate)
        try audioSession.setActive(true)
    }
    
    private func setupAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let outputNode = audioEngine.outputNode
        
        // Configure input
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Install tap to capture microphone input
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioInput(buffer: buffer, time: time)
        }
        
        // Configure audio processing chain
        let mixerNode = AVAudioMixerNode()
        audioEngine.attach(mixerNode)
        audioEngine.connect(mixerNode, to: outputNode, format: audioFormat)
        
        // Prepare the engine
        audioEngine.prepare()
    }
    
    // MARK: - Audio Processing
    
    private func processAudioInput(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard !isMuted, let mcSession = mcSession else { return }
        
        // Calculate audio level
        let level = calculateAudioLevel(buffer: buffer)
        audioLevel = level
        isSpeaking = level > 0.1 // Threshold for speech detection
        
        // Process audio with noise reduction and echo cancellation
        let processedBuffer = audioManager.processAudioBuffer(buffer)
        
        // Encode and send audio to peers
        if let audioData = encodeAudioBuffer(processedBuffer) {
            streamManager.sendAudioData(audioData, to: mcSession.connectedPeers)
        }
    }
    
    private func processReceivedAudio(data: Data, from peerId: MCPeerID) {
        guard let audioBuffer = decodeAudioData(data) else { return }
        
        // Apply spatial audio effects if enabled
        let spatialBuffer = streamManager.applySpatialEffects(audioBuffer, for: peerId)
        
        // Mix into output
        audioManager.mixAudioBuffer(spatialBuffer, from: peerId)
        
        // Update participant state
        let level = calculateAudioLevel(buffer: spatialBuffer)
        updateParticipantState(peerId, isSpeaking: level > 0.1, audioLevel: level)
    }
    
    // MARK: - Audio Stream Management
    
    private func initializeAudioStreams(for peers: [MCPeerID]) async throws {
        for peer in peers {
            try await initializeAudioStream(for: peer)
        }
    }
    
    private func initializeAudioStream(for peer: MCPeerID) async throws {
        guard let session = mcSession else {
            throw VoiceChatError.sessionNotAvailable
        }
        
        // Create bidirectional audio stream
        let streamName = "voice_chat_\(peer.displayName)"
        
        do {
            let outputStream = try session.startStream(withName: streamName, toPeer: peer)
            streamManager.registerOutputStream(outputStream, for: peer)
            
            logDebug("Audio stream initialized for peer", category: .collaboration, context: LogContext(customData: [
                "peer_name": peer.displayName
            ]))
            
        } catch {
            logError("Failed to initialize audio stream for peer", category: .collaboration, error: error)
            throw VoiceChatError.streamInitializationFailed(error.localizedDescription)
        }
    }
    
    private func closeAudioStreams() async throws {
        streamManager.closeAllStreams()
    }
    
    // MARK: - Audio Encoding/Decoding
    
    private func encodeAudioBuffer(_ buffer: AVAudioPCMBuffer) -> Data? {
        return audioManager.encodeBuffer(buffer)
    }
    
    private func decodeAudioData(_ data: Data) -> AVAudioPCMBuffer? {
        return audioManager.decodeData(data)
    }
    
    private func calculateAudioLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        
        var sum: Float = 0.0
        let frameLength = Int(buffer.frameLength)
        
        for i in 0..<frameLength {
            sum += abs(channelData[i])
        }
        
        return sum / Float(frameLength)
    }
    
    // MARK: - Event Handlers
    
    private func handleMuteStateChange(_ muted: Bool) {
        audioManager.setMuted(muted)
        
        // Notify other participants about mute state
        if let session = mcSession {
            let muteMessage = VoiceChatMessage(
                type: .muteStateChanged,
                data: ["muted": muted]
            )
            streamManager.sendControlMessage(muteMessage, to: session.connectedPeers)
        }
        
        logInfo("Mute state changed", category: .collaboration, context: LogContext(customData: [
            "muted": muted
        ]))
    }
    
    private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? NSNumber else { return }
        
        let type = AVAudioSession.InterruptionType(rawValue: typeValue.uintValue)
        
        switch type {
        case .began:
            // Pause voice chat
            audioEngine.pause()
            logInfo("Audio session interrupted", category: .collaboration)
            
        case .ended:
            // Resume voice chat
            if chatState == .connected {
                try? audioEngine.start()
                logInfo("Audio session resumed", category: .collaboration)
            }
            
        default:
            break
        }
    }
    
    private func handleAudioRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? NSNumber else { return }
        
        let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue.uintValue)
        
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            // Handle headphone/speaker changes
            logInfo("Audio route changed", category: .collaboration, context: LogContext(customData: [
                "reason": String(describing: reason)
            ]))
            
        default:
            break
        }
    }
    
    // MARK: - Public Interface
    
    public func getParticipantCount() -> Int {
        return activeParticipants.count
    }
    
    public func getParticipant(by peerId: MCPeerID) -> VoiceParticipant? {
        return activeParticipants.first { $0.peerId == peerId }
    }
    
    public func getVoiceChatStatistics() -> VoiceChatStatistics {
        return VoiceChatStatistics(
            participantCount: activeParticipants.count,
            isActive: chatState == .connected,
            networkQuality: networkQuality,
            averageLatency: qualityMonitor.getAverageLatency(),
            packetLossRate: qualityMonitor.getPacketLossRate(),
            audioLevel: audioLevel,
            isMuted: isMuted
        )
    }
    
    public func enableEchoCancellation(_ enabled: Bool) {
        audioManager.setEchoCancellationEnabled(enabled)
    }
    
    public func enableNoiseSuppression(_ enabled: Bool) {
        audioManager.setNoiseSuppressionEnabled(enabled)
    }
    
    public func setAudioQuality(_ quality: AudioQuality) {
        audioManager.setAudioQuality(quality)
    }
}

// MARK: - MCSessionDelegate Extension

extension VoiceChatSystem: MCSessionDelegate {
    
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        
        if streamName.hasPrefix("voice_chat_") {
            streamManager.registerInputStream(stream, for: peerID)
            
            // Start reading from the stream
            stream.delegate = streamManager
            stream.schedule(in: .current, forMode: .default)
            stream.open()
            
            logDebug("Received voice chat stream", category: .collaboration, context: LogContext(customData: [
                "peer_name": peerID.displayName,
                "stream_name": streamName
            ]))
        }
    }
    
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                // Participant will be added via separate call
                break
            case .notConnected:
                removeParticipant(peerID)
            default:
                break
            }
        }
    }
    
    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Handle voice chat control messages
        if let message = try? JSONDecoder().decode(VoiceChatMessage.self, from: data) {
            handleControlMessage(message, from: peerID)
        } else {
            // Handle audio data
            processReceivedAudio(data: data, from: peerID)
        }
    }
    
    private func handleControlMessage(_ message: VoiceChatMessage, from peerId: MCPeerID) {
        switch message.type {
        case .muteStateChanged:
            if let muted = message.data["muted"] as? Bool,
               let index = activeParticipants.firstIndex(where: { $0.peerId == peerId }) {
                activeParticipants[index].isMuted = muted
            }
        case .volumeChanged:
            if let volume = message.data["volume"] as? Float,
               let index = activeParticipants.firstIndex(where: { $0.peerId == peerId }) {
                activeParticipants[index].volume = volume
            }
        case .qualityReport:
            // Handle quality reports from other participants
            break
        }
    }
    
    // Required delegate methods
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Supporting Data Structures

public struct VoiceParticipant: Identifiable {
    public let id: UUID
    public let userId: UUID
    public let userName: String
    public let peerId: MCPeerID
    public var isMuted: Bool
    public var isSpeaking: Bool
    public var audioLevel: Float
    public var volume: Float = 1.0
    public var connectionState: ParticipantConnectionState
    public let joinedAt: Date
    public var lastActivity: Date = Date()
    
    public enum ParticipantConnectionState {
        case connecting
        case connected
        case reconnecting
        case disconnected
    }
}

public enum AudioNetworkQuality {
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

public enum AudioQuality: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    
    var sampleRate: Double {
        switch self {
        case .low: return 22050
        case .medium: return 44100
        case .high: return 48000
        }
    }
    
    var bitRate: Int {
        switch self {
        case .low: return 32000
        case .medium: return 64000
        case .high: return 128000
        }
    }
}

public struct VoiceChatStatistics {
    public let participantCount: Int
    public let isActive: Bool
    public let networkQuality: AudioNetworkQuality
    public let averageLatency: TimeInterval
    public let packetLossRate: Float
    public let audioLevel: Float
    public let isMuted: Bool
}

public struct VoiceChatMessage: Codable {
    public let type: MessageType
    public let data: [String: Any]
    
    public enum MessageType: String, Codable {
        case muteStateChanged = "mute_state_changed"
        case volumeChanged = "volume_changed"
        case qualityReport = "quality_report"
    }
    
    // Custom coding to handle Any values
    private enum CodingKeys: String, CodingKey {
        case type, data
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(MessageType.self, forKey: .type)
        data = [:] // Simplified for this implementation
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        // Simplified encoding
    }
    
    public init(type: MessageType, data: [String: Any]) {
        self.type = type
        self.data = data
    }
}

public enum VoiceChatError: Error {
    case invalidState(String)
    case permissionDenied(String)
    case sessionNotAvailable
    case streamInitializationFailed(String)
    case audioProcessingError(String)
    case maxParticipantsReached
    
    public var localizedDescription: String {
        switch self {
        case .invalidState(let message):
            return "Invalid state: \(message)"
        case .permissionDenied(let message):
            return "Permission denied: \(message)"
        case .sessionNotAvailable:
            return "Session not available"
        case .streamInitializationFailed(let message):
            return "Stream initialization failed: \(message)"
        case .audioProcessingError(let message):
            return "Audio processing error: \(message)"
        case .maxParticipantsReached:
            return "Maximum participants reached"
        }
    }
}

// MARK: - Supporting Classes

@MainActor
class VoiceAudioManager {
    private var isInitialized = false
    private var audioFormat: AVAudioFormat?
    private var isMuted = false
    private var echoCancellationEnabled = true
    private var noiseSuppressionEnabled = true
    private var audioQuality: AudioQuality = .medium
    
    func initialize(audioFormat: AVAudioFormat) throws {
        self.audioFormat = audioFormat
        isInitialized = true
    }
    
    func startProcessing() throws {
        guard isInitialized else {
            throw VoiceChatError.invalidState("Audio manager not initialized")
        }
    }
    
    func stopProcessing() {
        // Stop audio processing
    }
    
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        var processedBuffer = buffer
        
        if noiseSuppressionEnabled {
            processedBuffer = applyNoiseSuppression(processedBuffer)
        }
        
        if echoCancellationEnabled {
            processedBuffer = applyEchoCancellation(processedBuffer)
        }
        
        return processedBuffer
    }
    
    func mixAudioBuffer(_ buffer: AVAudioPCMBuffer, from peerId: MCPeerID) {
        // Mix audio buffer into output
    }
    
    func encodeBuffer(_ buffer: AVAudioPCMBuffer) -> Data? {
        // Encode audio buffer to data
        return Data() // Placeholder
    }
    
    func decodeData(_ data: Data) -> AVAudioPCMBuffer? {
        // Decode data to audio buffer
        return nil // Placeholder
    }
    
    func setMuted(_ muted: Bool) {
        isMuted = muted
    }
    
    func setEchoCancellationEnabled(_ enabled: Bool) {
        echoCancellationEnabled = enabled
    }
    
    func setNoiseSuppressionEnabled(_ enabled: Bool) {
        noiseSuppressionEnabled = enabled
    }
    
    func setAudioQuality(_ quality: AudioQuality) {
        audioQuality = quality
    }
    
    private func applyNoiseSuppression(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        // Apply noise suppression algorithms
        return buffer
    }
    
    private func applyEchoCancellation(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        // Apply echo cancellation algorithms
        return buffer
    }
}

@MainActor
class AudioStreamManager: NSObject {
    private var inputStreams: [MCPeerID: InputStream] = [:]
    private var outputStreams: [MCPeerID: OutputStream] = [:]
    private var spatialAudioEnabled: [MCPeerID: Bool] = [:]
    private var participantPositions: [MCPeerID: SIMD3<Float>] = [:]
    private var participantVolumes: [MCPeerID: Float] = [:]
    
    func initialize() throws {
        // Initialize stream manager
    }
    
    func createStreamForPeer(_ peerId: MCPeerID) throws {
        // Create audio stream for peer
    }
    
    func registerInputStream(_ stream: InputStream, for peerId: MCPeerID) {
        inputStreams[peerId] = stream
    }
    
    func registerOutputStream(_ stream: OutputStream, for peerId: MCPeerID) {
        outputStreams[peerId] = stream
    }
    
    func closeStreamForPeer(_ peerId: MCPeerID) {
        inputStreams[peerId]?.close()
        outputStreams[peerId]?.close()
        inputStreams.removeValue(forKey: peerId)
        outputStreams.removeValue(forKey: peerId)
        spatialAudioEnabled.removeValue(forKey: peerId)
        participantPositions.removeValue(forKey: peerId)
        participantVolumes.removeValue(forKey: peerId)
    }
    
    func closeAllStreams() {
        for peerId in inputStreams.keys {
            closeStreamForPeer(peerId)
        }
    }
    
    func sendAudioData(_ data: Data, to peers: [MCPeerID]) {
        for peerId in peers {
            if let outputStream = outputStreams[peerId] {
                data.withUnsafeBytes { bytes in
                    outputStream.write(bytes.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count)
                }
            }
        }
    }
    
    func sendControlMessage(_ message: VoiceChatMessage, to peers: [MCPeerID]) {
        if let data = try? JSONEncoder().encode(message) {
            sendAudioData(data, to: peers)
        }
    }
    
    func setVolume(_ volume: Float, for peerId: MCPeerID) {
        participantVolumes[peerId] = volume
    }
    
    func setSpatialAudio(enabled: Bool, for peerId: MCPeerID, position: SIMD3<Float>?) {
        spatialAudioEnabled[peerId] = enabled
        if let pos = position {
            participantPositions[peerId] = pos
        }
    }
    
    func applySpatialEffects(_ buffer: AVAudioPCMBuffer, for peerId: MCPeerID) -> AVAudioPCMBuffer {
        // Apply spatial audio effects based on participant position
        return buffer
    }
}

extension AudioStreamManager: StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            if let inputStream = aStream as? InputStream {
                readAudioData(from: inputStream)
            }
        case .hasSpaceAvailable:
            // Ready to write more data
            break
        case .errorOccurred:
            logWarning("Audio stream error", category: .collaboration)
        case .endEncountered:
            // Stream ended
            break
        default:
            break
        }
    }
    
    private func readAudioData(from stream: InputStream) {
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        let bytesRead = stream.read(buffer, maxLength: bufferSize)
        if bytesRead > 0 {
            let data = Data(bytes: buffer, count: bytesRead)
            // Process received audio data
        }
    }
}

@MainActor
class ParticipantManager {
    private var participants: [UUID: VoiceParticipant] = [:]
    
    func addParticipant(_ participant: VoiceParticipant) {
        participants[participant.id] = participant
    }
    
    func removeParticipant(_ id: UUID) {
        participants.removeValue(forKey: id)
    }
    
    func getParticipant(_ id: UUID) -> VoiceParticipant? {
        return participants[id]
    }
    
    func getAllParticipants() -> [VoiceParticipant] {
        return Array(participants.values)
    }
}

@MainActor
class AudioQualityMonitor {
    private var latencyMeasurements: [TimeInterval] = []
    private var packetLossCount = 0
    private var totalPackets = 0
    private var qualityCallback: ((AudioNetworkQuality) -> Void)?
    
    func startMonitoring(qualityCallback: @escaping (AudioNetworkQuality) -> Void) {
        self.qualityCallback = qualityCallback
        
        // Start periodic quality assessment
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.assessNetworkQuality()
        }
    }
    
    func stopMonitoring() {
        qualityCallback = nil
    }
    
    func recordLatency(_ latency: TimeInterval) {
        latencyMeasurements.append(latency)
        
        // Keep only recent measurements
        if latencyMeasurements.count > 10 {
            latencyMeasurements.removeFirst()
        }
    }
    
    func recordPacketLoss() {
        packetLossCount += 1
        totalPackets += 1
    }
    
    func recordPacketReceived() {
        totalPackets += 1
    }
    
    func getAverageLatency() -> TimeInterval {
        guard !latencyMeasurements.isEmpty else { return 0 }
        return latencyMeasurements.reduce(0, +) / Double(latencyMeasurements.count)
    }
    
    func getPacketLossRate() -> Float {
        guard totalPackets > 0 else { return 0 }
        return Float(packetLossCount) / Float(totalPackets)
    }
    
    private func assessNetworkQuality() {
        let avgLatency = getAverageLatency()
        let lossRate = getPacketLossRate()
        
        let quality: AudioNetworkQuality
        if avgLatency < 0.05 && lossRate < 0.01 {
            quality = .excellent
        } else if avgLatency < 0.1 && lossRate < 0.05 {
            quality = .good
        } else if avgLatency < 0.2 && lossRate < 0.1 {
            quality = .fair
        } else if avgLatency < 0.5 && lossRate < 0.2 {
            quality = .poor
        } else {
            quality = .disconnected
        }
        
        qualityCallback?(quality)
    }
}