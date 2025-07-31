import SwiftUI

struct ContentView: View {
    @StateObject private var arSessionManager = ARSessionManager()
    @State private var showingLogViewer = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "camera.viewfinder")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                    .font(.system(size: 80))
                
                Text("Welcome to ARchitect")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your AR Interior Design Assistant")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // AR Session Status
                VStack(spacing: 8) {
                    HStack {
                        Circle()
                            .fill(arSessionManager.isSessionRunning ? .green : .red)
                            .frame(width: 8, height: 8)
                        
                        Text(arSessionManager.isSessionRunning ? "AR Ready" : "AR Not Available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Tracking: \(arSessionManager.trackingState.description)")
                        .font(.caption2)
                        .foregroundColor(.tertiary)
                }
                
                // Logging Status
                LoggingSystemStatusView()
                
                // Demo Error Buttons (for testing)
                if ProcessInfo.processInfo.environment["DEMO_MODE"] == "true" {
                    VStack(spacing: 8) {
                        Text("Demo Actions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            Button("Network Error") {
                                ErrorManager.shared.reportError(NetworkError.noConnection)
                                logError("Demo network error triggered", category: .network)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            
                            Button("AR Error") {
                                ErrorManager.shared.reportError(ARError.trackingLost)
                                logError("Demo AR error triggered", category: .ar)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        
                        Button("View Logs") {
                            showingLogViewer = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.top)
                }
            }
            .padding()
            .navigationTitle("ARchitect")
        }
        .withErrorHandling()
        .sheet(isPresented: $showingLogViewer) {
            LogViewer()
        }
        .onAppear {
            // Initialize logging system
            LoggingSystem.shared.initialize()
            
            // Initialize global error handler
            _ = GlobalErrorHandler.shared
            
            // Log app launch
            logInfo("App launched successfully", category: .general, context: LogContext(customData: [
                "launch_time": Date().timeIntervalSince1970,
                "environment": AppEnvironment.current.rawValue,
                "is_first_launch": !UserDefaults.standard.bool(forKey: "has_launched_before")
            ]))
        }
    }
}

#Preview {
    ContentView()
}