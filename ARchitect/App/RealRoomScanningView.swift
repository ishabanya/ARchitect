import SwiftUI
import ARKit
import RealityKit

struct RealRoomScanningView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var isPlaneDetectionEnabled = true
    @State private var detectedPlanes: [DetectedPlane] = []
    @State private var measurements: [ARMeasurement] = []
    @State private var isScanning = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var scanDuration: TimeInterval = 0
    @State private var timer: Timer?
    
    var body: some View {
        ZStack {
            // AR Camera View
            ARViewContainer(
                isPlaneDetectionEnabled: $isPlaneDetectionEnabled,
                detectedPlanes: $detectedPlanes,
                measurements: $measurements
            )
            .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top Status Bar
                topStatusBar
                
                Spacer()
                
                // Instructions
                if !isScanning {
                    instructionsView
                }
                
                Spacer()
                
                // Bottom Controls
                bottomControls
            }
            .padding()
        }
        .navigationBarHidden(true)
        .onAppear {
            startScanning()
        }
        .onDisappear {
            stopScanning()
        }
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text("ARKit Error"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private var topStatusBar: some View {
        HStack {
            Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))
            .cornerRadius(20)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Planes: \(detectedPlanes.count)")
                Text("Points: \(measurements.count)")
                if isScanning {
                    Text(String(format: "%.0fs", scanDuration))
                }
            }
            .foregroundColor(.white)
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))
            .cornerRadius(12)
        }
    }
    
    private var instructionsView: some View {
        VStack(spacing: 12) {
            Text("Room Scanning")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Move your device around to detect surfaces. Tap to add measurement points.")
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(16)
        .transition(.opacity)
    }
    
    private var bottomControls: some View {
        HStack(spacing: 20) {
            // Toggle Plane Detection
            Button(action: togglePlaneDetection) {
                VStack(spacing: 8) {
                    Image(systemName: isPlaneDetectionEnabled ? "eye.fill" : "eye.slash.fill")
                        .font(.title2)
                    Text("Detect")
                        .font(.caption)
                }
                .foregroundColor(isPlaneDetectionEnabled ? .green : .gray)
            }
            .frame(width: 60, height: 60)
            .background(Color.black.opacity(0.5))
            .cornerRadius(30)
            
            Spacer()
            
            // Scan Button
            Button(action: toggleScanning) {
                VStack(spacing: 8) {
                    Image(systemName: isScanning ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                    Text(isScanning ? "Stop" : "Start")
                        .font(.caption)
                }
                .foregroundColor(isScanning ? .red : .green)
            }
            .frame(width: 80, height: 60)
            .background(Color.black.opacity(0.5))
            .cornerRadius(30)
            
            Spacer()
            
            // Clear Button
            Button(action: clearMeasurements) {
                VStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.title2)
                    Text("Clear")
                        .font(.caption)
                }
                .foregroundColor(.red)
            }
            .frame(width: 60, height: 60)
            .background(Color.black.opacity(0.5))
            .cornerRadius(30)
        }
    }
    
    private func startScanning() {
        guard ARWorldTrackingConfiguration.isSupported else {
            alertMessage = "ARKit is not supported on this device"
            showingAlert = true
            return
        }
        
        isScanning = true
        scanDuration = 0
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            scanDuration += 1
        }
    }
    
    private func stopScanning() {
        isScanning = false
        timer?.invalidate()
        timer = nil
    }
    
    private func toggleScanning() {
        if isScanning {
            stopScanning()
        } else {
            startScanning()
        }
    }
    
    private func togglePlaneDetection() {
        isPlaneDetectionEnabled.toggle()
    }
    
    private func clearMeasurements() {
        measurements.removeAll()
        detectedPlanes.removeAll()
    }
}

#Preview {
    RealRoomScanningView()
}