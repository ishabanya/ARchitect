import SwiftUI

// MARK: - Sound Settings View

struct SoundSettingsView: View {
    @StateObject private var soundManager = SoundEffectsManager()
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingTestSounds = false
    
    var body: some View {
        NavigationView {
            List {
                // Master Controls
                Section {
                    HStack {
                        Image(systemName: soundManager.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .foregroundColor(soundManager.isEnabled ? .accentColor : .secondary)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sound Effects")
                                .font(.headline)
                            Text(soundManager.isEnabled ? "Enabled" : "Disabled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { soundManager.isEnabled },
                            set: { soundManager.setEnabled($0) }
                        ))
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                    
                    if soundManager.isEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Master Volume")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(Int(soundManager.volume * 100))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(
                                value: Binding(
                                    get: { soundManager.volume },
                                    set: { soundManager.setVolume($0) }
                                ),
                                in: 0...1
                            ) {
                                Text("Volume")
                            } minimumValueLabel: {
                                Image(systemName: "speaker.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } maximumValueLabel: {
                                Image(systemName: "speaker.wave.3.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .disabled(!soundManager.isEnabled)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("General")
                } footer: {
                    if soundManager.isEnabled {
                        Text("Control the volume and availability of sound effects throughout the app.")
                    } else {
                        Text("Sound effects are disabled. Toggle above to enable audio feedback.")
                    }
                }
                
                // Category Controls
                if soundManager.isEnabled {
                    Section {
                        ForEach(SoundEffectsManager.SoundCategory.allCases, id: \.rawValue) { category in
                            CategoryVolumeRow(
                                category: category,
                                volume: soundManager.getCategoryVolume(category),
                                onVolumeChange: { volume in
                                    soundManager.setCategoryVolume(category, volume: volume)
                                },
                                onTest: {
                                    testCategorySound(category)
                                }
                            )
                        }
                    } header: {
                        Text("Categories")
                    } footer: {
                        Text("Adjust volume for different types of sound effects. Tap the play button to test each category.")
                    }
                }
                
                // Sound Testing
                Section {
                    Button {
                        showingTestSounds = true
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("Test All Sounds")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(!soundManager.isEnabled)
                    
                    Button {
                        playRandomSounds()
                    } label: {
                        HStack {
                            Image(systemName: "shuffle.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("Play Random Sounds")
                            Spacer()
                        }
                    }
                    .disabled(!soundManager.isEnabled)
                } header: {
                    Text("Testing")
                } footer: {
                    Text("Test sounds to preview how they'll sound in the app.")
                }
                
                // Currently Playing
                if !soundManager.currentlyPlaying.isEmpty {
                    Section {
                        ForEach(soundManager.currentlyPlaying, id: \.self) { soundName in
                            HStack {
                                Image(systemName: "waveform")
                                    .foregroundColor(.accentColor)
                                    .font(.caption)
                                
                                if let sound = SoundEffectsManager.SoundEffect(rawValue: soundName) {
                                    Text(sound.displayName)
                                } else {
                                    Text(soundName)
                                        .font(.caption.monospacedDigit())
                                }
                                
                                Spacer()
                                
                                Text("Playing")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } header: {
                        Text("Currently Playing")
                    }
                }
            }
            .navigationTitle("Sound Effects")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingTestSounds) {
            SoundTestingView()
        }
    }
    
    private func testCategorySound(_ category: SoundEffectsManager.SoundCategory) {
        let categorySounds = SoundEffectsManager.SoundEffect.allCases.filter { $0.category == category }
        
        if let sound = categorySounds.first {
            soundManager.testSound(sound)
        }
    }
    
    private func playRandomSounds() {
        let sounds = SoundEffectsManager.SoundEffect.allCases.shuffled().prefix(5)
        
        Task {
            for (index, sound) in sounds.enumerated() {
                if index > 0 {
                    await Task.sleep(nanoseconds: 800_000_000) // 0.8 second delay
                }
                await MainActor.run {
                    soundManager.testSound(sound)
                }
            }
        }
    }
}

// MARK: - Category Volume Row

struct CategoryVolumeRow: View {
    let category: SoundEffectsManager.SoundCategory
    let volume: Float
    let onVolumeChange: (Float) -> Void
    let onTest: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: categoryIcon)
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
                
                Text(category.displayName)
                    .font(.subheadline)
                
                Spacer()
                
                Button {
                    onTest()
                } label: {
                    Image(systemName: "play.circle")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                
                Text("\(Int(volume * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 35, alignment: .trailing)
            }
            
            Slider(
                value: Binding(
                    get: { volume },
                    set: onVolumeChange
                ),
                in: 0...1
            ) {
                Text("Volume")
            }
        }
        .padding(.vertical, 2)
    }
    
    private var categoryIcon: String {
        switch category {
        case .ui: return "hand.tap.fill"
        case .ar: return "arkit"
        case .project: return "folder.fill"
        case .celebration: return "party.popper.fill"
        case .notification: return "bell.fill"
        case .effect: return "sparkles"
        }
    }
}

// MARK: - Sound Testing View

struct SoundTestingView: View {
    @StateObject private var soundManager = SoundEffectsManager()
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedCategory: SoundEffectsManager.SoundCategory?
    @State private var isPlayingAll = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Category Filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        CategoryFilterButton(
                            title: "All",
                            isSelected: selectedCategory == nil,
                            action: { selectedCategory = nil }
                        )
                        
                        ForEach(SoundEffectsManager.SoundCategory.allCases, id: \.rawValue) { category in
                            CategoryFilterButton(
                                title: category.displayName,
                                isSelected: selectedCategory == category,
                                action: { selectedCategory = category }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
                .background(Color(.systemGroupedBackground))
                
                // Sound List
                List {
                    ForEach(filteredSounds, id: \.rawValue) { sound in
                        SoundTestRow(
                            sound: sound,
                            onTest: {
                                soundManager.testSound(sound)
                            }
                        )
                    }
                }
            }
            .navigationTitle("Test Sounds")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isPlayingAll.toggle()
                        if isPlayingAll {
                            playAllSounds()
                        }
                    } label: {
                        Text(isPlayingAll ? "Stop" : "Play All")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var filteredSounds: [SoundEffectsManager.SoundEffect] {
        if let category = selectedCategory {
            return SoundEffectsManager.SoundEffect.allCases.filter { $0.category == category }
        } else {
            return SoundEffectsManager.SoundEffect.allCases
        }
    }
    
    private func playAllSounds() {
        Task {
            for sound in filteredSounds {
                if !isPlayingAll { break }
                
                await MainActor.run {
                    soundManager.testSound(sound)
                }
                
                await Task.sleep(nanoseconds: 600_000_000) // 0.6 second delay
            }
            
            await MainActor.run {
                isPlayingAll = false
            }
        }
    }
}

// MARK: - Category Filter Button

struct CategoryFilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color(.systemGray5))
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Sound Test Row

struct SoundTestRow: View {
    let sound: SoundEffectsManager.SoundEffect
    let onTest: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(sound.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Text(sound.category.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.2))
                        )
                        .foregroundColor(.accentColor)
                    
                    Text("Priority: \(priorityText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                onTest()
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }
    
    private var priorityText: String {
        switch sound.priority {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

// MARK: - Preview

struct SoundSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SoundSettingsView()
    }
}