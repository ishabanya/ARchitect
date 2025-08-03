import Foundation
import AVFoundation
import AudioToolbox
import SwiftUI

// MARK: - Sound Effects Manager

@MainActor
public class SoundEffectsManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var isEnabled: Bool = true
    @Published public var volume: Float = 0.7
    @Published public var currentlyPlaying: [String] = []
    
    // MARK: - Sound Categories
    public enum SoundEffect: String, CaseIterable {
        // UI Interactions
        case buttonTap = "button_tap"
        case buttonPress = "button_press"
        case switchToggle = "switch_toggle"
        case modalPresent = "modal_present"
        case modalDismiss = "modal_dismiss"
        case swipeGesture = "swipe_gesture"
        
        // AR Interactions
        case objectPlace = "object_place"
        case objectSelect = "object_select"
        case objectMove = "object_move"
        case objectDelete = "object_delete"
        case arSessionStart = "ar_session_start"
        case arSessionStop = "ar_session_stop"
        case planeDetected = "plane_detected"
        case anchorPlaced = "anchor_placed"
        
        // Project Management
        case projectSave = "project_save"
        case projectLoad = "project_load"
        case projectExport = "project_export"
        case projectShare = "project_share"
        case projectDelete = "project_delete"
        
        // Achievements & Celebrations
        case achievement = "achievement"
        case levelUp = "level_up"
        case celebration = "celebration"
        case milestone = "milestone"
        case unlock = "unlock"
        
        // Notifications & Alerts
        case notificationPop = "notification_pop"
        case alertShow = "alert_show"
        case errorSound = "error_sound"
        case successSound = "success_sound"
        case warningSound = "warning_sound"
        
        // Special Effects
        case whoosh = "whoosh"
        case sparkle = "sparkle"
        case pop = "pop"
        case chime = "chime"
        case tick = "tick"
        
        public var fileName: String {
            return "\(rawValue).wav"
        }
        
        public var displayName: String {
            switch self {
            case .buttonTap: return "Button Tap"
            case .buttonPress: return "Button Press"
            case .switchToggle: return "Switch Toggle"
            case .modalPresent: return "Modal Present"
            case .modalDismiss: return "Modal Dismiss"
            case .swipeGesture: return "Swipe Gesture"
            case .objectPlace: return "Object Place"
            case .objectSelect: return "Object Select"
            case .objectMove: return "Object Move"
            case .objectDelete: return "Object Delete"
            case .arSessionStart: return "AR Session Start"
            case .arSessionStop: return "AR Session Stop"
            case .planeDetected: return "Plane Detected"
            case .anchorPlaced: return "Anchor Placed"
            case .projectSave: return "Project Save"
            case .projectLoad: return "Project Load"
            case .projectExport: return "Project Export"
            case .projectShare: return "Project Share"
            case .projectDelete: return "Project Delete"
            case .achievement: return "Achievement"
            case .levelUp: return "Level Up"
            case .celebration: return "Celebration"
            case .milestone: return "Milestone"
            case .unlock: return "Unlock"
            case .notificationPop: return "Notification Pop"
            case .alertShow: return "Alert Show"
            case .errorSound: return "Error"
            case .successSound: return "Success"
            case .warningSound: return "Warning"
            case .whoosh: return "Whoosh"
            case .sparkle: return "Sparkle"
            case .pop: return "Pop"
            case .chime: return "Chime"
            case .tick: return "Tick"
            }
        }
        
        public var category: SoundCategory {
            switch self {
            case .buttonTap, .buttonPress, .switchToggle, .modalPresent, .modalDismiss, .swipeGesture:
                return .ui
            case .objectPlace, .objectSelect, .objectMove, .objectDelete, .arSessionStart, .arSessionStop, .planeDetected, .anchorPlaced:
                return .ar
            case .projectSave, .projectLoad, .projectExport, .projectShare, .projectDelete:
                return .project
            case .achievement, .levelUp, .celebration, .milestone, .unlock:
                return .celebration
            case .notificationPop, .alertShow, .errorSound, .successSound, .warningSound:
                return .notification
            case .whoosh, .sparkle, .pop, .chime, .tick:
                return .effect
            }
        }
        
        public var defaultVolume: Float {
            switch category {
            case .ui: return 0.5
            case .ar: return 0.7
            case .project: return 0.6
            case .celebration: return 0.8
            case .notification: return 0.7
            case .effect: return 0.6
            }
        }
        
        public var priority: SoundPriority {
            switch self {
            case .achievement, .levelUp, .celebration, .milestone: return .high
            case .errorSound, .warningSound, .alertShow: return .high
            case .projectSave, .projectExport, .projectShare: return .medium
            case .arSessionStart, .arSessionStop, .objectPlace: return .medium
            default: return .low
            }
        }
    }
    
    public enum SoundCategory: String, CaseIterable {
        case ui = "UI"
        case ar = "AR"
        case project = "Project"
        case celebration = "Celebration"
        case notification = "Notification"
        case effect = "Effect"
        
        public var displayName: String {
            return rawValue
        }
    }
    
    public enum SoundPriority {
        case low, medium, high
    }
    
    // MARK: - Private Properties
    private var audioPlayers: [String: AVAudioPlayer] = [:]
    private var soundQueue: [(SoundEffect, Float, Bool)] = []
    private var audioSession: AVAudioSession
    private var userDefaults = UserDefaults.standard
    
    // Configuration
    private var categoryVolumes: [SoundCategory: Float] = [:]
    private var maxConcurrentSounds = 5
    private var soundCooldowns: [SoundEffect: Date] = [:]
    private var minimumCooldownInterval: TimeInterval = 0.1
    
    // Haptic feedback integration
    private var hapticGenerator = UIImpactFeedbackGenerator(style: .light)
    
    public init() {
        self.audioSession = AVAudioSession.sharedInstance()
        
        setupAudioSession()
        loadSettings()
        preloadSounds()
        
        logInfo("Sound Effects Manager initialized", category: .audio)
    }
    
    // MARK: - Setup
    
    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            
            logInfo("Audio session configured", category: .audio)
        } catch {
            logError("Failed to setup audio session", category: .audio, error: error)
        }
    }
    
    private func loadSettings() {
        isEnabled = userDefaults.bool(forKey: "sound_effects_enabled") 
        if userDefaults.object(forKey: "sound_effects_enabled") == nil {
            isEnabled = true // Default to enabled
        }
        
        volume = userDefaults.float(forKey: "sound_effects_volume")
        if volume == 0 && userDefaults.object(forKey: "sound_effects_volume") == nil {
            volume = 0.7 // Default volume
        }
        
        // Load category volumes
        for category in SoundCategory.allCases {
            let key = "sound_category_volume_\(category.rawValue)"
            let savedVolume = userDefaults.float(forKey: key)
            categoryVolumes[category] = savedVolume == 0 && userDefaults.object(forKey: key) == nil ? 1.0 : savedVolume
        }
    }
    
    private func saveSettings() {
        userDefaults.set(isEnabled, forKey: "sound_effects_enabled")
        userDefaults.set(volume, forKey: "sound_effects_volume")
        
        for (category, volume) in categoryVolumes {
            userDefaults.set(volume, forKey: "sound_category_volume_\(category.rawValue)")
        }
    }
    
    private func preloadSounds() {
        Task.detached { [weak self] in
            await self?.loadEssentialSounds()
        }
    }
    
    private func loadEssentialSounds() async {
        let essentialSounds: [SoundEffect] = [
            .buttonTap, .buttonPress, .objectPlace, .objectSelect,
            .successSound, .errorSound, .achievement
        ]
        
        for sound in essentialSounds {
            await loadSound(sound)
        }
        
        logInfo("Essential sounds preloaded", category: .audio, context: LogContext(customData: [
            "sounds_loaded": essentialSounds.count
        ]))
    }
    
    private func loadSound(_ sound: SoundEffect) async {
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") else {
            // Generate synthesized sound if audio file doesn't exist
            await synthesizeSound(sound)
            return
        }
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.volume = 0 // Will be set when playing
            
            await MainActor.run {
                audioPlayers[sound.rawValue] = player
            }
        } catch {
            logError("Failed to load sound", category: .audio, error: error, context: LogContext(customData: [
                "sound": sound.rawValue
            ]))
            
            // Fallback to synthesized sound
            await synthesizeSound(sound)
        }
    }
    
    private func synthesizeSound(_ sound: SoundEffect) async {
        // Create synthesized sounds for missing audio files
        let synthesizedPlayer = createSynthesizedSound(for: sound)
        
        await MainActor.run {
            audioPlayers[sound.rawValue] = synthesizedPlayer
        }
    }
    
    private func createSynthesizedSound(for sound: SoundEffect) -> AVAudioPlayer? {
        // Generate simple synthesized sounds using AudioToolbox
        switch sound.category {
        case .ui:
            return createUISound(for: sound)
        case .ar:
            return createARSound(for: sound)
        case .celebration:
            return createCelebrationSound(for: sound)
        default:
            return createGenericSound(for: sound)
        }
    }
    
    private func createUISound(for sound: SoundEffect) -> AVAudioPlayer? {
        // Create simple UI sounds with different frequencies
        let frequency: Float = switch sound {
        case .buttonTap: 800
        case .buttonPress: 600
        case .switchToggle: 1000
        default: 700
        }
        
        return createTonePlayer(frequency: frequency, duration: 0.1)
    }
    
    private func createARSound(for sound: SoundEffect) -> AVAudioPlayer? {
        let frequency: Float = switch sound {
        case .objectPlace: 400
        case .objectSelect: 600
        case .planeDetected: 300
        default: 500
        }
        
        return createTonePlayer(frequency: frequency, duration: 0.2)
    }
    
    private func createCelebrationSound(for sound: SoundEffect) -> AVAudioPlayer? {
        // Create multi-tone celebration sounds
        return createChordPlayer(frequencies: [523, 659, 784], duration: 0.5) // C major chord
    }
    
    private func createGenericSound(for sound: SoundEffect) -> AVAudioPlayer? {
        return createTonePlayer(frequency: 440, duration: 0.15) // A4 note
    }
    
    private func createTonePlayer(frequency: Float, duration: TimeInterval) -> AVAudioPlayer? {
        let sampleRate = 44100.0
        let samples = Int(sampleRate * duration)
        
        var audioData = Data()
        
        for i in 0..<samples {
            let time = Double(i) / sampleRate
            let amplitude = sin(2.0 * Double.pi * Double(frequency) * time)
            let sample = Int16(amplitude * 32767.0 * 0.3) // 30% volume
            
            audioData.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }
        
        // Create temporary file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString).wav")
        
        do {
            try createWAVFile(data: audioData, sampleRate: Int(sampleRate), channels: 1, to: tempURL)
            let player = try AVAudioPlayer(contentsOf: tempURL)
            player.prepareToPlay()
            return player
        } catch {
            logError("Failed to create synthesized sound", category: .audio, error: error)
            return nil
        }
    }
    
    private func createChordPlayer(frequencies: [Float], duration: TimeInterval) -> AVAudioPlayer? {
        let sampleRate = 44100.0
        let samples = Int(sampleRate * duration)
        
        var audioData = Data()
        
        for i in 0..<samples {
            let time = Double(i) / sampleRate
            var combinedAmplitude = 0.0
            
            for frequency in frequencies {
                combinedAmplitude += sin(2.0 * Double.pi * Double(frequency) * time)
            }
            
            combinedAmplitude /= Double(frequencies.count) // Normalize
            let sample = Int16(combinedAmplitude * 32767.0 * 0.2) // 20% volume
            
            audioData.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }
        
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString).wav")
        
        do {
            try createWAVFile(data: audioData, sampleRate: Int(sampleRate), channels: 1, to: tempURL)
            let player = try AVAudioPlayer(contentsOf: tempURL)
            player.prepareToPlay()
            return player
        } catch {
            return nil
        }
    }
    
    private func createWAVFile(data: Data, sampleRate: Int, channels: Int, to url: URL) throws {
        let bitsPerSample = 16
        let bytesPerSample = bitsPerSample / 8
        let blockAlign = channels * bytesPerSample
        let byteRate = sampleRate * blockAlign
        
        var wavData = Data()
        
        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(36 + data.count).littleEndian) { Array($0) })
        wavData.append("WAVE".data(using: .ascii)!)
        
        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })
        
        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(data.count).littleEndian) { Array($0) })
        wavData.append(data)
        
        try wavData.write(to: url)
    }
    
    // MARK: - Sound Playback
    
    public func playSound(_ sound: SoundEffect, volume: Float? = nil, withHaptic: Bool = false) {
        guard isEnabled else { return }
        
        // Check cooldown
        if let lastPlayed = soundCooldowns[sound],
           Date().timeIntervalSince(lastPlayed) < minimumCooldownInterval {
            return
        }
        
        soundCooldowns[sound] = Date()
        
        // Calculate final volume
        let categoryVolume = categoryVolumes[sound.category] ?? 1.0
        let soundVolume = volume ?? sound.defaultVolume
        let finalVolume = self.volume * categoryVolume * soundVolume
        
        // Add haptic feedback if requested
        if withHaptic {
            playHapticFeedback(for: sound)
        }
        
        // Play sound
        Task {
            await performSoundPlayback(sound, volume: finalVolume)
        }
    }
    
    private func performSoundPlayback(_ sound: SoundEffect, volume: Float) async {
        // Load sound if not already loaded
        if audioPlayers[sound.rawValue] == nil {
            await loadSound(sound)
        }
        
        await MainActor.run {
            guard let player = audioPlayers[sound.rawValue] else {
                logWarning("Sound player not available", category: .audio, context: LogContext(customData: [
                    "sound": sound.rawValue
                ]))
                return
            }
            
            // Manage concurrent sounds
            if currentlyPlaying.count >= maxConcurrentSounds {
                // Stop the oldest lower priority sound
                stopOldestLowPrioritySound()
            }
            
            player.volume = volume
            player.currentTime = 0
            
            if player.play() {
                currentlyPlaying.append(sound.rawValue)
                
                // Remove from currently playing after duration
                let duration = player.duration
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                    self?.currentlyPlaying.removeAll { $0 == sound.rawValue }
                }
                
                logDebug("Playing sound", category: .audio, context: LogContext(customData: [
                    "sound": sound.rawValue,
                    "volume": volume,
                    "currently_playing": currentlyPlaying.count
                ]))
            } else {
                logWarning("Failed to play sound", category: .audio, context: LogContext(customData: [
                    "sound": sound.rawValue
                ]))
            }
        }
    }
    
    private func stopOldestLowPrioritySound() {
        for soundName in currentlyPlaying {
            if let sound = SoundEffect(rawValue: soundName),
               sound.priority == .low,
               let player = audioPlayers[soundName] {
                player.stop()
                currentlyPlaying.removeAll { $0 == soundName }
                break
            }
        }
    }
    
    private func playHapticFeedback(for sound: SoundEffect) {
        switch sound.category {
        case .ui:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .ar:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .celebration:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .notification:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        default:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
    
    // MARK: - Configuration
    
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        
        if !enabled {
            stopAllSounds()
        }
        
        saveSettings()
        
        logInfo("Sound effects \(enabled ? "enabled" : "disabled")", category: .audio)
    }
    
    public func setVolume(_ newVolume: Float) {
        volume = max(0.0, min(1.0, newVolume))
        saveSettings()
    }
    
    public func setCategoryVolume(_ category: SoundCategory, volume: Float) {
        categoryVolumes[category] = max(0.0, min(1.0, volume))
        saveSettings()
    }
    
    public func getCategoryVolume(_ category: SoundCategory) -> Float {
        return categoryVolumes[category] ?? 1.0
    }
    
    public func stopAllSounds() {
        for player in audioPlayers.values {
            player.stop()
        }
        currentlyPlaying.removeAll()
    }
    
    public func preloadSounds(_ sounds: [SoundEffect]) {
        Task {
            for sound in sounds {
                await loadSound(sound)
            }
        }
    }
    
    // MARK: - Convenience Methods
    
    public func playUISound(_ sound: SoundEffect = .buttonTap) {
        guard sound.category == .ui else { return }
        playSound(sound, withHaptic: true)
    }
    
    public func playARSound(_ sound: SoundEffect) {
        guard sound.category == .ar else { return }
        playSound(sound, withHaptic: false)
    }
    
    public func playCelebrationSound(_ sound: SoundEffect = .achievement) {
        guard sound.category == .celebration else { return }
        playSound(sound, volume: 0.9, withHaptic: true)
    }
    
    public func playNotificationSound(_ sound: SoundEffect) {
        guard sound.category == .notification else { return }
        playSound(sound, withHaptic: true)
    }
    
    // MARK: - Sound Testing
    
    public func testSound(_ sound: SoundEffect) {
        playSound(sound, volume: 0.8, withHaptic: true)
    }
    
    public func testAllSounds() {
        Task {
            for (index, sound) in SoundEffect.allCases.enumerated() {
                await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                await MainActor.run {
                    playSound(sound, volume: 0.5)
                }
            }
        }
    }
}

// MARK: - SwiftUI Integration

public struct SoundEffectModifier: ViewModifier {
    let sound: SoundEffectsManager.SoundEffect
    let trigger: Bool
    @StateObject private var soundManager = SoundEffectsManager()
    
    public func body(content: Content) -> Content {
        content
            .onChange(of: trigger) { shouldPlay in
                if shouldPlay {
                    soundManager.playSound(sound)
                }
            }
    }
}

extension View {
    public func soundEffect(_ sound: SoundEffectsManager.SoundEffect, trigger: Bool) -> some View {
        modifier(SoundEffectModifier(sound: sound, trigger: trigger))
    }
    
    public func buttonSound(_ sound: SoundEffectsManager.SoundEffect = .buttonTap) -> some View {
        simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    SoundEffectsManager().playUISound(sound)
                }
        )
    }
}