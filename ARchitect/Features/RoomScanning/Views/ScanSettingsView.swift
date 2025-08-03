import SwiftUI

// MARK: - Scan Settings View
struct ScanSettingsView: View {
    let settings: ScanSettings
    @Environment(\.dismiss) private var dismiss
    
    @State private var qualityMode: ScanSettings.QualityMode
    @State private var timeoutDuration: Double
    @State private var minPlaneArea: Double
    @State private var maxPlanesCount: Double
    @State private var mergingThreshold: Double
    @State private var planeDetection: Set<String>
    @State private var sceneReconstruction: String
    @State private var environmentTexturing: String
    
    init(settings: ScanSettings) {
        self.settings = settings
        self._qualityMode = State(initialValue: settings.qualityMode)
        self._timeoutDuration = State(initialValue: settings.timeoutDuration)
        self._minPlaneArea = State(initialValue: Double(settings.minPlaneArea))
        self._maxPlanesCount = State(initialValue: Double(settings.maxPlanesCount))
        self._mergingThreshold = State(initialValue: Double(settings.mergingThreshold))
        self._planeDetection = State(initialValue: Set(settings.planeDetection))
        self._sceneReconstruction = State(initialValue: settings.sceneReconstruction)
        self._environmentTexturing = State(initialValue: settings.environmentTexturing)
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Quality Settings
                Section("Scan Quality") {
                    Picker("Quality Mode", selection: $qualityMode) {
                        ForEach(ScanSettings.QualityMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Timeout Duration")
                            Spacer()
                            Text("\(Int(timeoutDuration / 60)) min")
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $timeoutDuration, in: 60...600, step: 30)
                    }
                }
                
                // Plane Detection Settings
                Section("Plane Detection") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Detection Types")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Toggle("Horizontal", isOn: Binding(
                                get: { planeDetection.contains("horizontal") },
                                set: { isOn in
                                    if isOn {
                                        planeDetection.insert("horizontal")
                                    } else {
                                        planeDetection.remove("horizontal")
                                    }
                                }
                            ))
                            
                            Toggle("Vertical", isOn: Binding(
                                get: { planeDetection.contains("vertical") },
                                set: { isOn in
                                    if isOn {
                                        planeDetection.insert("vertical")
                                    } else {
                                        planeDetection.remove("vertical")
                                    }
                                }
                            ))
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Minimum Plane Area")
                            Spacer()
                            Text("\(String(format: "%.1f", minPlaneArea)) m²")
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $minPlaneArea, in: 0.1...2.0, step: 0.1)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Maximum Planes")
                            Spacer()
                            Text("\(Int(maxPlanesCount))")
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $maxPlanesCount, in: 10...100, step: 5)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Merging Threshold")
                            Spacer()
                            Text("\(String(format: "%.1f", mergingThreshold * 100)) cm")
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $mergingThreshold, in: 0.05...0.5, step: 0.05)
                    }
                }
                
                // Advanced Settings
                Section("Advanced") {
                    Picker("Scene Reconstruction", selection: $sceneReconstruction) {
                        Text("None").tag("none")
                        Text("Mesh").tag("mesh")
                        Text("Mesh with Classification").tag("meshWithClassification")
                    }
                    
                    Picker("Environment Texturing", selection: $environmentTexturing) {
                        Text("None").tag("none")
                        Text("Manual").tag("manual")
                        Text("Automatic").tag("automatic")
                    }
                }
                
                // Presets
                Section("Presets") {
                    Button("Fast Scan") {
                        applyFastPreset()
                    }
                    
                    Button("Balanced") {
                        applyBalancedPreset()
                    }
                    
                    Button("High Accuracy") {
                        applyAccuratePreset()
                    }
                    
                    Button("Reset to Default") {
                        resetToDefault()
                    }
                    .foregroundColor(.red)
                }
                
                // Information
                Section("Information") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quality Mode Guide")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("• **Fast**: Quick scans with basic accuracy")
                        Text("• **Balanced**: Good balance of speed and quality")
                        Text("• **Accurate**: Slower but highly detailed scans")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Scan Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Preset Methods
    
    private func applyFastPreset() {
        qualityMode = .fast
        timeoutDuration = 120 // 2 minutes
        minPlaneArea = 0.2
        maxPlanesCount = 25
        mergingThreshold = 0.15
        sceneReconstruction = "none"
        environmentTexturing = "none"
    }
    
    private func applyBalancedPreset() {
        qualityMode = .balanced
        timeoutDuration = 300 // 5 minutes
        minPlaneArea = 0.1
        maxPlanesCount = 50
        mergingThreshold = 0.1
        sceneReconstruction = "mesh"
        environmentTexturing = "automatic"
    }
    
    private func applyAccuratePreset() {
        qualityMode = .accurate
        timeoutDuration = 600 // 10 minutes
        minPlaneArea = 0.05
        maxPlanesCount = 100
        mergingThreshold = 0.05
        sceneReconstruction = "meshWithClassification"
        environmentTexturing = "automatic"
    }
    
    private func resetToDefault() {
        let defaultSettings = ScanSettings.default
        qualityMode = defaultSettings.qualityMode
        timeoutDuration = defaultSettings.timeoutDuration
        minPlaneArea = Double(defaultSettings.minPlaneArea)
        maxPlanesCount = Double(defaultSettings.maxPlanesCount)
        mergingThreshold = Double(defaultSettings.mergingThreshold)
        planeDetection = Set(defaultSettings.planeDetection)
        sceneReconstruction = defaultSettings.sceneReconstruction
        environmentTexturing = defaultSettings.environmentTexturing
    }
    
    private func saveSettings() {
        // In a real implementation, you would save these settings
        // This is just a demonstration of the settings interface
        logInfo("Scan settings updated", category: .ar, context: LogContext(customData: [
            "quality_mode": qualityMode.rawValue,
            "timeout_duration": timeoutDuration,
            "min_plane_area": minPlaneArea,
            "max_planes_count": maxPlanesCount,
            "merging_threshold": mergingThreshold
        ]))
    }
}

// MARK: - Preview
#if DEBUG
struct ScanSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ScanSettingsView(settings: .default)
    }
}
#endif