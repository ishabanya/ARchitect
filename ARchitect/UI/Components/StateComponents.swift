import SwiftUI

// MARK: - Loading State Component

public struct LoadingStateView: View {
    private let title: String
    private let message: String?
    private let style: LoadingStyle
    private let size: LoadingSize
    private let showProgress: Bool
    private let progress: Double?
    
    public enum LoadingStyle {
        case minimal
        case standard
        case detailed
        case fullScreen
        
        var showTitle: Bool {
            switch self {
            case .minimal: return false
            case .standard, .detailed, .fullScreen: return true
            }
        }
        
        var showMessage: Bool {
            switch self {
            case .minimal, .standard: return false
            case .detailed, .fullScreen: return true
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .fullScreen: return DesignSystem.Colors.systemBackground
            default: return Color.clear
            }
        }
    }
    
    public enum LoadingSize {
        case small
        case medium
        case large
        
        var spinnerSize: CGFloat {
            switch self {
            case .small: return 20
            case .medium: return 32
            case .large: return 48
            }
        }
        
        var titleFont: Font {
            switch self {
            case .small: return DesignSystem.Typography.footnote(.medium)
            case .medium: return DesignSystem.Typography.subheadline(.semibold)
            case .large: return DesignSystem.Typography.headline(.semibold)
            }
        }
    }
    
    public init(
        title: String = "Loading",
        message: String? = nil,
        style: LoadingStyle = .standard,
        size: LoadingSize = .medium,
        showProgress: Bool = false,
        progress: Double? = nil
    ) {
        self.title = title
        self.message = message
        self.style = style
        self.size = size
        self.showProgress = showProgress
        self.progress = progress
    }
    
    public var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Loading Animation
            if showProgress && progress != nil {
                ProgressView(value: progress)
                    .progressViewStyle(CircularProgressViewStyle(tint: DesignSystem.Colors.primary))
                    .scaleEffect(size.spinnerSize / 24)
            } else {
                LoadingAnimation(
                    style: .spinning,
                    size: size.spinnerSize,
                    color: DesignSystem.Colors.primary
                )
            }
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                // Title
                if style.showTitle {
                    Text(title)
                        .font(size.titleFont)
                        .foregroundColor(DesignSystem.Colors.label)
                        .multilineTextAlignment(.center)
                }
                
                // Message
                if style.showMessage, let message = message {
                    Text(message)
                        .font(DesignSystem.Typography.body())
                        .foregroundColor(DesignSystem.Colors.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Progress Text
                if showProgress, let progress = progress {
                    Text("\(Int(progress * 100))%")
                        .font(DesignSystem.Typography.caption1(.medium))
                        .foregroundColor(DesignSystem.Colors.tertiaryLabel)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: style == .fullScreen ? .infinity : nil, 
               maxHeight: style == .fullScreen ? .infinity : nil)
        .background(style.backgroundColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }
    
    private var accessibilityLabel: String {
        var label = title
        if let message = message {
            label += ". \(message)"
        }
        if let progress = progress {
            label += ". \(Int(progress * 100)) percent complete"
        }
        return label
    }
}

// MARK: - Empty State Component

public struct EmptyStateView: View {
    private let icon: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let style: EmptyStyle
    
    public enum EmptyStyle {
        case minimal
        case standard
        case illustrated
        
        var iconSize: CGFloat {
            switch self {
            case .minimal: return 32
            case .standard: return 48
            case .illustrated: return 64
            }
        }
        
        var showAction: Bool {
            switch self {
            case .minimal: return false
            case .standard, .illustrated: return true
            }
        }
    }
    
    public init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        style: EmptyStyle = .standard,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.style = style
        self.action = action
    }
    
    public var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Icon
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.tertiarySystemBackground)
                        .frame(width: style.iconSize + 24, height: style.iconSize + 24)
                    
                    Image(systemName: icon)
                        .font(.system(size: style.iconSize, weight: .light))
                        .foregroundColor(DesignSystem.Colors.tertiaryLabel)
                }
                .animateOnAppear(delay: 0.1)
                
                VStack(spacing: DesignSystem.Spacing.sm) {
                    // Title
                    Text(title)
                        .font(DesignSystem.Typography.title3(.semibold))
                        .foregroundColor(DesignSystem.Colors.label)
                        .multilineTextAlignment(.center)
                        .animateOnAppear(delay: 0.2)
                    
                    // Message
                    Text(message)
                        .font(DesignSystem.Typography.body())
                        .foregroundColor(DesignSystem.Colors.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                        .animateOnAppear(delay: 0.3)
                }
            }
            
            // Action Button
            if style.showAction, let actionTitle = actionTitle, let action = action {
                ProfessionalButton(
                    title: actionTitle,
                    style: .primary,
                    size: .medium,
                    action: action
                )
                .animateOnAppear(delay: 0.4)
            }
        }
        .padding(DesignSystem.Spacing.xxxl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
        .accessibilityHint(actionTitle != nil ? "Tap \(actionTitle!) to continue" : "")
    }
}

// MARK: - Error State Component

public struct ErrorStateView: View {
    private let error: ErrorInfo
    private let style: ErrorStyle
    private let onRetry: (() -> Void)?
    private let onDismiss: (() -> Void)?
    
    public struct ErrorInfo {
        public let title: String
        public let message: String
        public let code: String?
        public let recoverable: Bool
        
        public init(
            title: String,
            message: String,
            code: String? = nil,
            recoverable: Bool = true
        ) {
            self.title = title
            self.message = message
            self.code = code
            self.recoverable = recoverable
        }
        
        // Predefined error types
        public static let networkError = ErrorInfo(
            title: "Connection Error",
            message: "Please check your internet connection and try again.",
            code: "NET_001",
            recoverable: true
        )
        
        public static let serverError = ErrorInfo(
            title: "Server Error",
            message: "We're experiencing technical difficulties. Please try again later.",
            code: "SRV_001",
            recoverable: true
        )
        
        public static let authenticationError = ErrorInfo(
            title: "Authentication Failed",
            message: "Please sign in again to continue.",
            code: "AUTH_001",
            recoverable: true
        )
        
        public static let permissionError = ErrorInfo(
            title: "Permission Denied",
            message: "You don't have permission to access this content.",
            code: "PERM_001",
            recoverable: false
        )
        
        public static let notFoundError = ErrorInfo(
            title: "Content Not Found",
            message: "The content you're looking for is no longer available.",
            code: "404",
            recoverable: false
        )
        
        public static let arError = ErrorInfo(
            title: "AR Not Available",
            message: "This device doesn't support AR features or AR is disabled.",
            code: "AR_001",
            recoverable: false
        )
    }
    
    public enum ErrorStyle {
        case minimal
        case standard
        case detailed
        case fullScreen
        
        var showCode: Bool {
            switch self {
            case .detailed, .fullScreen: return true
            default: return false
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .fullScreen: return DesignSystem.Colors.systemBackground
            default: return Color.clear
            }
        }
    }
    
    public init(
        error: ErrorInfo,
        style: ErrorStyle = .standard,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.error = error
        self.style = style
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Error Icon
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.errorLight)
                        .frame(width: 72, height: 72)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.error)
                }
                .animateOnAppear(delay: 0.1)
                
                VStack(spacing: DesignSystem.Spacing.sm) {
                    // Title
                    Text(error.title)
                        .font(DesignSystem.Typography.title3(.semibold))
                        .foregroundColor(DesignSystem.Colors.label)
                        .multilineTextAlignment(.center)
                        .animateOnAppear(delay: 0.2)
                    
                    // Message
                    Text(error.message)
                        .font(DesignSystem.Typography.body())
                        .foregroundColor(DesignSystem.Colors.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .animateOnAppear(delay: 0.3)
                    
                    // Error Code
                    if style.showCode, let code = error.code {
                        Text("Error Code: \(code)")
                            .font(DesignSystem.Typography.caption1(.medium))
                            .foregroundColor(DesignSystem.Colors.tertiaryLabel)
                            .padding(.top, DesignSystem.Spacing.xs)
                            .animateOnAppear(delay: 0.4)
                    }
                }
            }
            
            // Action Buttons
            VStack(spacing: DesignSystem.Spacing.md) {
                if error.recoverable, let onRetry = onRetry {
                    ProfessionalButton(
                        title: "Try Again",
                        icon: "arrow.clockwise",
                        style: .primary,
                        size: .medium,
                        fullWidth: true,
                        action: onRetry
                    )
                    .animateOnAppear(delay: 0.5)
                }
                
                if let onDismiss = onDismiss {
                    ProfessionalButton(
                        title: error.recoverable ? "Cancel" : "OK",
                        style: .tertiary,
                        size: .medium,
                        fullWidth: true,
                        action: onDismiss
                    )
                    .animateOnAppear(delay: 0.6)
                }
            }
        }
        .padding(DesignSystem.Spacing.xxxl)
        .frame(maxWidth: .infinity)
        .background(style.backgroundColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(error.title). \(error.message)")
        .accessibilityHint(error.recoverable ? "Tap Try Again to retry the operation" : "")
    }
}

// MARK: - Success State Component

public struct SuccessStateView: View {
    private let title: String
    private let message: String?
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let style: SuccessStyle
    private let autoDismiss: Bool
    private let dismissDelay: TimeInterval
    
    @State private var isVisible = true
    
    public enum SuccessStyle {
        case toast
        case card
        case fullScreen
        
        var iconSize: CGFloat {
            switch self {
            case .toast: return 20
            case .card: return 32
            case .fullScreen: return 48
            }
        }
        
        var showAction: Bool {
            switch self {
            case .toast: return false
            case .card, .fullScreen: return true
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .toast: return DesignSystem.Colors.successLight
            case .card: return DesignSystem.Colors.systemBackground
            case .fullScreen: return DesignSystem.Colors.systemBackground
            }
        }
    }
    
    public init(
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        style: SuccessStyle = .card,
        autoDismiss: Bool = false,
        dismissDelay: TimeInterval = 3.0,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.style = style
        self.autoDismiss = autoDismiss
        self.dismissDelay = dismissDelay
        self.action = action
    }
    
    public var body: some View {
        Group {
            if isVisible {
                content
                    .transition(AnimationSystem.Transitions.modalScale)
                    .onAppear {
                        HapticFeedbackManager.shared.operationSuccess()
                        
                        if autoDismiss {
                            DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
                                withAnimation(AnimationSystem.Springs.gentle) {
                                    isVisible = false
                                }
                            }
                        }
                    }
            }
        }
        .animation(AnimationSystem.Springs.gentle, value: isVisible)
    }
    
    @ViewBuilder
    private var content: some View {
        switch style {
        case .toast:
            toastContent
        case .card:
            cardContent
        case .fullScreen:
            fullScreenContent
        }
    }
    
    private var toastContent: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: style.iconSize, weight: .medium))
                .foregroundColor(DesignSystem.Colors.success)
            
            Text(title)
                .font(DesignSystem.Typography.subheadline(.medium))
                .foregroundColor(DesignSystem.Colors.label)
                .lineLimit(2)
            
            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .background(style.backgroundColor, in: RoundedRectangle(cornerRadius: DesignSystem.BorderRadius.md))
        .shadowStyle(DesignSystem.Shadows.sm)
    }
    
    private var cardContent: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Success animation
            SuccessAnimation(size: style.iconSize + 16)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(title)
                    .font(DesignSystem.Typography.headline(.semibold))
                    .foregroundColor(DesignSystem.Colors.label)
                    .multilineTextAlignment(.center)
                
                if let message = message {
                    Text(message)
                        .font(DesignSystem.Typography.body())
                        .foregroundColor(DesignSystem.Colors.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            if style.showAction, let actionTitle = actionTitle, let action = action {
                ProfessionalButton(
                    title: actionTitle,
                    style: .primary,
                    size: .medium,
                    fullWidth: true,
                    action: action
                )
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .background(style.backgroundColor, in: RoundedRectangle(cornerRadius: DesignSystem.BorderRadius.lg))
        .shadowStyle(DesignSystem.Shadows.md)
    }
    
    private var fullScreenContent: some View {
        VStack(spacing: DesignSystem.Spacing.xxxl) {
            Spacer()
            
            VStack(spacing: DesignSystem.Spacing.xl) {
                SuccessAnimation(size: style.iconSize + 32)
                
                VStack(spacing: DesignSystem.Spacing.md) {
                    Text(title)
                        .font(DesignSystem.Typography.title1(.bold))
                        .foregroundColor(DesignSystem.Colors.label)
                        .multilineTextAlignment(.center)
                    
                    if let message = message {
                        Text(message)
                            .font(DesignSystem.Typography.title3())
                            .foregroundColor(DesignSystem.Colors.secondaryLabel)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            
            Spacer()
            
            if let actionTitle = actionTitle, let action = action {
                ProfessionalButton(
                    title: actionTitle,
                    style: .primary,
                    size: .large,
                    fullWidth: true,
                    action: action
                )
                .padding(.horizontal, DesignSystem.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(style.backgroundColor)
    }
}

// MARK: - State Container

public struct StateContainer<Content: View>: View {
    private let content: Content
    private let state: ViewState
    
    public enum ViewState {
        case loading(LoadingStateView)
        case empty(EmptyStateView)
        case error(ErrorStateView)
        case success(SuccessStateView)
        case content
    }
    
    public init(
        state: ViewState,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.state = state
    }
    
    public var body: some View {
        ZStack {
            switch state {
            case .loading(let loadingView):
                loadingView
            case .empty(let emptyView):
                emptyView
            case .error(let errorView):
                errorView
            case .success(let successView):
                successView
            case .content:
                content
            }
        }
        .animation(AnimationSystem.Springs.gentle, value: stateIdentifier)
    }
    
    private var stateIdentifier: String {
        switch state {
        case .loading: return "loading"
        case .empty: return "empty"
        case .error: return "error"
        case .success: return "success"
        case .content: return "content"
        }
    }
}

// MARK: - Convenience Extensions

extension View {
    public func loadingState(
        isLoading: Bool,
        title: String = "Loading",
        message: String? = nil
    ) -> some View {
        StateContainer(
            state: isLoading ? 
                .loading(LoadingStateView(title: title, message: message)) : 
                .content
        ) {
            self
        }
    }
    
    public func emptyState(
        isEmpty: Bool,
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        StateContainer(
            state: isEmpty ? 
                .empty(EmptyStateView(
                    icon: icon,
                    title: title,
                    message: message,
                    actionTitle: actionTitle,
                    action: action
                )) : 
                .content
        ) {
            self
        }
    }
    
    public func errorState(
        error: ErrorStateView.ErrorInfo?,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        StateContainer(
            state: error != nil ? 
                .error(ErrorStateView(
                    error: error!,
                    onRetry: onRetry,
                    onDismiss: onDismiss
                )) : 
                .content
        ) {
            self
        }
    }
}

// MARK: - Preview

struct StateComponents_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            LoadingStateView(title: "Loading", message: "Please wait...")
            
            EmptyStateView(
                icon: "tray",
                title: "No Items",
                message: "Add some furniture to get started",
                actionTitle: "Browse Catalog"
            ) {}
            
            SuccessStateView(
                title: "Success!",
                message: "Your room has been saved",
                actionTitle: "Continue"
            ) {}
        }
        .previewLayout(.sizeThatFits)
    }
}