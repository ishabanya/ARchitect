# ARchitect API Documentation

## Overview

ARchitect follows modern iOS architecture best practices including MVVM with Combine, dependency injection, protocol-oriented programming, async/await, proper memory management, and single responsibility principle.

## Architecture Patterns

### MVVM with Combine

The app uses Model-View-ViewModel pattern with Combine for reactive programming:

- **Models**: Data structures and business logic (`FurnitureItem`, `Room`, etc.)
- **Views**: SwiftUI views that observe ViewModels
- **ViewModels**: Combine ObservableObjects that manage state and business logic

### Dependency Injection

All dependencies are managed through `DIContainer` for testability and loose coupling:

```swift
// Register dependencies
DIContainer.shared.registerSingleton(ARSessionManagerProtocol.self) {
    ARSessionManager()
}

// Resolve dependencies
let sessionManager = DIContainer.shared.resolve(ARSessionManagerProtocol.self)
```

### Protocol-Oriented Design

Core functionality is defined through protocols for flexibility and testability:

- `ARSessionManagerProtocol`: AR session management
- `AnalyticsManagerProtocol`: Analytics tracking  
- `ErrorManagerProtocol`: Error handling and reporting
- `LoggingSystemProtocol`: Logging and diagnostics

## Core Protocols

### ARSessionManagerProtocol

Manages ARKit sessions with async/await support and reactive updates.

#### Key Features
- Async session lifecycle management
- Real-time state monitoring through Combine publishers
- Automatic error handling and recovery
- Memory-efficient plane detection

#### Usage Example

```swift
@StateObject private var sessionManager = DIContainer.shared.resolve(ARSessionManagerProtocol.self)

// Start AR session
Task {
    try await sessionManager.startSession()
}

// Monitor session state
sessionManager.sessionStatePublisher
    .sink { state in
        print("Session state: \(state)")
    }
    .store(in: &cancellables)
```

#### Methods

##### `startSession() async throws`
Starts the AR session with default configuration.
- **Throws**: `ARError` if session fails to start
- **Thread**: Must be called from main thread

##### `pauseSession() async`
Pauses the currently running AR session.
- **Note**: Session can be resumed later

##### `resetSession() async throws`
Resets the AR session, clearing all tracking data.
- **Throws**: `ARError` if reset fails
- **Note**: Removes all anchors and restarts tracking

##### `updateConfiguration(_:) async throws`
Updates the AR session with a new configuration.
- **Parameter**: `ARWorldTrackingConfiguration` to apply
- **Throws**: `ARError` if configuration update fails

#### Publishers

##### `sessionStatePublisher: AnyPublisher<ARSessionState, Never>`
Emits AR session state changes on the main thread.

##### `trackingQualityPublisher: AnyPublisher<ARTrackingQuality, Never>`
Emits tracking quality updates on the main thread.

##### `detectedPlanesPublisher: AnyPublisher<[ARPlaneAnchor], Never>`
Emits detected plane updates on the main thread.

### AnalyticsManagerProtocol

Handles user analytics and performance tracking.

#### Features
- Event tracking with custom parameters
- Performance metric collection
- User property management
- Debug mode support

#### Usage Example

```swift
let analytics = DIContainer.shared.resolve(AnalyticsManagerProtocol.self)

// Track user events
analytics.trackUserEngagement(.featureUsed, parameters: [
    "feature": "ar_scanning",
    "duration": 30.5
])

// Track performance metrics
analytics.trackPerformanceMetric(.appLaunchTime, value: 2.1, context: [
    "device_model": "iPhone 15 Pro"
])
```

### ErrorManagerProtocol

Centralized error handling and reporting system.

#### Features
- Error categorization and severity levels
- Error history and statistics
- Recovery strategies
- Real-time error monitoring

#### Usage Example

```swift
let errorManager = DIContainer.shared.resolve(ErrorManagerProtocol.self)

// Report errors with context
errorManager.reportError(error, context: ErrorContext(
    feature: "ar_session",
    customData: ["user_action": "start_scanning"]
))

// Monitor errors
errorManager.errorPublisher
    .sink { error in
        // Handle error UI updates
    }
    .store(in: &cancellables)
```

### LoggingSystemProtocol

Comprehensive logging system with multiple levels and categories.

#### Features
- Multiple log levels (debug, info, warning, error, critical)
- Category-based filtering
- Async initialization
- Log export functionality

#### Usage Example

```swift
// Initialize logging
let logging = DIContainer.shared.resolve(LoggingSystemProtocol.self)
try await logging.initialize()

// Log messages
logging.logInfo("AR session started", category: .ar, context: LogContext())
logging.logError("Failed to load model", category: .performance, context: LogContext())

// Export logs
let logData = try await logging.exportLogs()
```

## Memory Management

### MemoryManager

Centralized memory monitoring and cleanup system.

#### Features
- Real-time memory usage monitoring
- Memory pressure detection
- Automatic cleanup on warnings
- Memory statistics and trends

#### Usage Example

```swift
let memoryManager = MemoryManager.shared

// Start monitoring
memoryManager.startMonitoring()

// Monitor memory usage
memoryManager.$currentMemoryUsage
    .sink { usage in
        print("Memory usage: \(usage / 1024 / 1024) MB")
    }
    .store(in: &cancellables)

// Force cleanup
memoryManager.performMemoryCleanup()
```

### Memory-Safe Patterns

#### WeakRef<T>
Utility for holding weak references to prevent retain cycles:

```swift
let weakRef = WeakRef(someObject)
if let object = weakRef.value {
    // Use object safely
}
```

#### WeakCollection<T>
Collection that automatically removes nil weak references:

```swift
var weakCollection = WeakCollection<SomeClass>()
weakCollection.add(someInstance)
let allObjects = weakCollection.allObjects // Returns only live objects
```

## Architecture Components

### Single Responsibility Classes

#### ARConfigurationManager
Dedicated to AR configuration creation and validation:

```swift
let configManager = ARConfigurationManager()
let config = try configManager.createConfiguration(with: options)
let validation = configManager.validateConfiguration(options)
```

#### ARTrackingQualityAnalyzer  
Analyzes tracking quality and provides recommendations:

```swift
let analyzer = ARTrackingQualityAnalyzer()
let quality = analyzer.analyzeTrackingQuality(
    trackingState: .normal,
    planeCount: 3,
    sessionDuration: 15.0
)
let trends = analyzer.getQualityTrends(for: 60)
```

## Data Models

### FurnitureItem
Represents furniture objects in AR space:

```swift
struct FurnitureItem {
    let id: UUID
    let name: String
    let category: FurnitureCategory
    let dimensions: FurnitureDimensions
    let modelResource: String
    let position: SIMD3<Float>
    let rotation: SIMD3<Float>
    let scale: SIMD3<Float>
    let isPlaced: Bool
    let createdAt: Date
}
```

### Supporting Enums

#### ARSessionState
```swift
enum ARSessionState {
    case unknown
    case initializing  
    case running
    case paused
    case interrupted
    case failed
}
```

#### ARTrackingQuality
```swift
enum ARTrackingQuality {
    case unknown
    case poor
    case fair
    case good
    case excellent
}
```

## Error Handling

### Error Types

#### NetworkError
```swift
enum NetworkError: LocalizedError {
    case noConnection
    case timeout
    case invalidResponse
    case serverError(Int)
    case invalidURL
    case decodingError
}
```

#### ARError
```swift
enum ARError: LocalizedError {
    case trackingLost
    case sessionFailed
    case configurationNotSupported
    case planeDetectionFailed
    case anchorPlacementFailed
    case modelLoadingFailed
}
```

### Error Context
```swift
struct ErrorContext {
    let timestamp: Date
    let userID: String?
    let sessionID: String
    let feature: String?
    let customData: [String: Any]
}
```

## Performance Considerations

### Async/Await Usage
All asynchronous operations use async/await for better performance and readability:

```swift
// Good: Modern async/await
try await sessionManager.startSession()

// Avoid: Completion handlers
sessionManager.startSession { result in
    // Handle result
}
```

### Memory Management
- All ViewModels properly clean up Combine subscriptions in `deinit`
- Weak references used in closures to prevent retain cycles
- Memory monitoring with automatic cleanup on pressure
- Efficient object pooling for frequently created objects

### Publisher Optimization
- Publishers use `eraseToAnyPublisher()` for type erasure
- Subscriptions stored in `Set<AnyCancellable>` for automatic cleanup
- Main thread dispatch handled automatically

## Testing

### Dependency Injection Benefits
All protocols can be easily mocked for testing:

```swift
class MockARSessionManager: ARSessionManagerProtocol {
    var mockSessionState: ARSessionState = .unknown
    var sessionState: ARSessionState { mockSessionState }
    
    func startSession() async throws {
        mockSessionState = .running
    }
}

// In tests
DIContainer.shared.register(ARSessionManagerProtocol.self) {
    MockARSessionManager()
}
```

### Test Utilities
- `DIContainer.reset()` for clean test environment
- Memory leak detection with `WeakRef`
- Performance testing with `MemoryManager` statistics

## Best Practices

### Code Organization
- Protocol definitions in `Core/Protocols/`
- Implementations in feature-specific folders
- ViewModels in `UI/ViewModels/`
- Shared utilities in `Core/Utilities/`

### Naming Conventions
- Protocols end with `Protocol` suffix
- Manager classes end with `Manager` suffix
- ViewModels end with `ViewModel` suffix
- Published properties use descriptive names

### Documentation
- All public APIs documented with Swift DocC format
- Usage examples provided for complex APIs
- Thread safety requirements clearly stated
- Error conditions documented

### Performance
- Lazy initialization for expensive resources
- Object pooling for frequently created objects
- Memory monitoring and automatic cleanup
- Efficient Combine publisher chains

This architecture provides a solid foundation for a scalable, testable, and maintainable iOS application following all modern best practices.