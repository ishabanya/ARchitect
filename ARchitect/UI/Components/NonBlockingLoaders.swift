import SwiftUI
import Combine

// MARK: - Non-Blocking Loading System

@MainActor
public class LoadingStateManager: ObservableObject {
    @Published public var activeOperations: [LoadingOperation] = []
    @Published public var backgroundTasks: [BackgroundTask] = []
    @Published public var isAnyOperationActive: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        setupObservers()
    }
    
    private func setupObservers() {
        $activeOperations
            .map { !$0.isEmpty }
            .assign(to: \.isAnyOperationActive, on: self)
            .store(in: &cancellables)
    }
    
    public func startOperation(_ operation: LoadingOperation) {
        activeOperations.append(operation)
    }
    
    public func completeOperation(id: UUID) {
        activeOperations.removeAll { $0.id == id }
    }
    
    public func startBackgroundTask(_ task: BackgroundTask) {
        backgroundTasks.append(task)
    }
    
    public func completeBackgroundTask(id: UUID) {
        backgroundTasks.removeAll { $0.id == id }
    }
}

// MARK: - Loading Operation Model

public struct LoadingOperation: Identifiable {
    public let id: UUID = UUID()
    public let title: String
    public let subtitle: String?
    public let progress: Double?
    public let canCancel: Bool
    public let priority: Priority
    public let estimatedDuration: TimeInterval?
    public let startTime: Date = Date()
    
    public enum Priority {
        case low, normal, high, critical
    }
    
    public init(
        title: String,
        subtitle: String? = nil,
        progress: Double? = nil,
        canCancel: Bool = true,
        priority: Priority = .normal,
        estimatedDuration: TimeInterval? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.canCancel = canCancel
        self.priority = priority
        self.estimatedDuration = estimatedDuration
    }
}

// MARK: - Background Task Model

public struct BackgroundTask: Identifiable {
    public let id: UUID = UUID()
    public let name: String
    public let progress: Double
    public let isIndeterminate: Bool
    
    public init(name: String, progress: Double = 0.0, isIndeterminate: Bool = false) {
        self.name = name
        self.progress = progress
        self.isIndeterminate = isIndeterminate
    }
}

// MARK: - Non-Blocking Loading Overlay

public struct NonBlockingLoadingOverlay: View {
    @EnvironmentObject private var loadingManager: LoadingStateManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingOperations = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Background tasks indicator (minimal)
            if !loadingManager.backgroundTasks.isEmpty {
                VStack {
                    HStack {
                        Spacer()
                        BackgroundTasksIndicator()
                    }
                    Spacer()
                }
                .padding()
            }
            
            // Active operations (non-blocking)
            if !loadingManager.activeOperations.isEmpty {
                VStack {
                    Spacer()
                    
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.spring()) {
                                showingOperations.toggle()
                            }
                        }) {
                            ActiveOperationsButton(
                                count: loadingManager.activeOperations.count,
                                isExpanded: showingOperations
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 100)
                }
            }
            
            // Expanded operations panel
            if showingOperations {
                VStack {
                    Spacer()
                    
                    OperationsPanel(
                        operations: loadingManager.activeOperations,
                        onDismiss: {
                            withAnimation(.spring()) {
                                showingOperations = false
                            }
                        }
                    )
                    .padding(.bottom, 50)
                }
            }
        }
        .allowsHitTesting(showingOperations)
    }
}

// MARK: - Background Tasks Indicator

private struct BackgroundTasksIndicator: View {
    @EnvironmentObject private var loadingManager: LoadingStateManager
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        Circle()
            .fill(.blue)
            .frame(width: 12, height: 12)
            .scaleEffect(pulseScale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulseScale = 1.3
                }
            }
            .accessibilityLabel("Background tasks running")
            .accessibilityValue("\(loadingManager.backgroundTasks.count) tasks")
    }
}

// MARK: - Active Operations Button

private struct ActiveOperationsButton: View {
    let count: Int
    let isExpanded: Bool
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(lineWidth: 2)
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(lineWidth: 2)
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(rotationAngle))
            }
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    rotationAngle = 360
                }
            }
            
            if isExpanded {
                Text("\(count) operation\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .fontWeight(.medium)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .accessibilityLabel("Loading operations")
        .accessibilityValue("\(count) active")
        .accessibilityHint("Tap to expand")
    }
}

// MARK: - Operations Panel

private struct OperationsPanel: View {
    let operations: [LoadingOperation]
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Active Operations")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Close operations panel")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Operations list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(operations) { operation in
                        OperationCard(operation: operation)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: 300)
            
            Spacer(minLength: 16)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Operation Card

private struct OperationCard: View {
    let operation: LoadingOperation
    @EnvironmentObject private var loadingManager: LoadingStateManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(operation.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if let subtitle = operation.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if operation.canCancel {
                    Button(action: {
                        loadingManager.completeOperation(id: operation.id)
                        HapticFeedbackManager.shared.impact(.light)
                    }) {
                        Image(systemName: "xmark.circle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Cancel operation")
                }
            }
            
            // Progress indicator
            if let progress = operation.progress {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .scaleEffect(y: 0.8)
            } else {
                ProgressView()
                    .progressViewStyle(LinearProgressViewStyle())
                    .scaleEffect(y: 0.8)
            }
            
            // Estimated time remaining
            if let estimatedDuration = operation.estimatedDuration {
                let elapsed = Date().timeIntervalSince(operation.startTime)
                let remaining = max(0, estimatedDuration - elapsed)
                
                if remaining > 0 {
                    Text("About \(Int(remaining))s remaining")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(operation.title)
        .accessibilityValue(operation.subtitle ?? "")
    }
}

// MARK: - Inline Loading Components

public struct InlineLoadingButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void
    
    public init(title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                        .transition(.opacity.combined(with: .scale))
                }
                
                Text(isLoading ? "Loading..." : title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(LoadingButtonStyle(isLoading: isLoading))
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? "Loading" : title)
        .accessibilityHint(isLoading ? "Please wait" : "")
    }
}

// MARK: - Loading Button Style

private struct LoadingButtonStyle: ButtonStyle {
    let isLoading: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isLoading ? .secondary : .blue)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .foregroundColor(.white)
            .animation(.easeInOut(duration: 0.2), value: isLoading)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Skeleton Loading View

public struct SkeletonLoadingView: View {
    let height: CGFloat
    let cornerRadius: CGFloat
    @State private var shimmerOffset: CGFloat = -1.0
    
    public init(height: CGFloat = 20, cornerRadius: CGFloat = 4) {
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary)
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.3), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: shimmerOffset * UIScreen.main.bounds.width)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.0
                }
            }
            .accessibilityLabel("Loading content")
    }
}

// MARK: - Progressive Image Loader

public struct ProgressiveImageView: View {
    let url: URL?
    let placeholder: String?
    @State private var loadingState: ImageLoadingState = .loading
    @State private var loadedImage: UIImage?
    
    public enum ImageLoadingState {
        case loading, loaded, failed
    }
    
    public init(url: URL?, placeholder: String? = nil) {
        self.url = url
        self.placeholder = placeholder
    }
    
    public var body: some View {
        Group {
            switch loadingState {
            case .loading:
                SkeletonLoadingView(height: 200, cornerRadius: 8)
                    .overlay(
                        if let placeholder = placeholder {
                            Image(systemName: placeholder)
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                        }
                    )
                
            case .loaded:
                if let image = loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                
            case .failed:
                VStack {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    
                    Text("Failed to load image")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 200)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: url) { _, _ in
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url = url else {
            loadingState = .failed
            return
        }
        
        loadingState = .loading
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                
                await MainActor.run {
                    if let image = UIImage(data: data) {
                        loadedImage = image
                        loadingState = .loaded
                    } else {
                        loadingState = .failed
                    }
                }
            } catch {
                await MainActor.run {
                    loadingState = .failed
                }
            }
        }
    }
}

// MARK: - View Extensions

extension View {
    public func nonBlockingLoading(
        isActive: Bool,
        title: String,
        subtitle: String? = nil,
        progress: Double? = nil
    ) -> some View {
        self.modifier(NonBlockingLoadingModifier(
            isActive: isActive,
            title: title,
            subtitle: subtitle,
            progress: progress
        ))
    }
}

// MARK: - Non-Blocking Loading Modifier

private struct NonBlockingLoadingModifier: ViewModifier {
    let isActive: Bool
    let title: String
    let subtitle: String?
    let progress: Double?
    
    @EnvironmentObject private var loadingManager: LoadingStateManager
    @State private var operationId: UUID?
    
    func body(content: Content) -> some View {
        content
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    let operation = LoadingOperation(
                        title: title,
                        subtitle: subtitle,
                        progress: progress
                    )
                    operationId = operation.id
                    loadingManager.startOperation(operation)
                } else if let id = operationId {
                    loadingManager.completeOperation(id: id)
                    operationId = nil
                }
            }
            .onDisappear {
                if let id = operationId {
                    loadingManager.completeOperation(id: id)
                }
            }
    }
}