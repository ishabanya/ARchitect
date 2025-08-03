import SwiftUI

// MARK: - Professional Button Component

public struct ProfessionalButton: View {
    
    // MARK: - Properties
    private let title: String
    private let icon: String?
    private let action: () -> Void
    private let style: ButtonStyle
    private let size: ButtonSize
    private let isEnabled: Bool
    private let isLoading: Bool
    private let fullWidth: Bool
    
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Button Styles
    public enum ButtonStyle {
        case primary
        case secondary
        case tertiary
        case destructive
        case success
        case warning
        case ghost
        case outline
        
        var backgroundColor: Color {
            switch self {
            case .primary:
                return DesignSystem.Colors.primary
            case .secondary:
                return DesignSystem.Colors.secondary
            case .tertiary:
                return DesignSystem.Colors.tertiarySystemBackground
            case .destructive:
                return DesignSystem.Colors.error
            case .success:
                return DesignSystem.Colors.success
            case .warning:
                return DesignSystem.Colors.warning
            case .ghost:
                return Color.clear
            case .outline:
                return Color.clear
            }
        }
        
        var foregroundColor: Color {
            switch self {
            case .primary, .destructive, .success, .warning:
                return .white
            case .secondary:
                return .white
            case .tertiary:
                return DesignSystem.Colors.label
            case .ghost:
                return DesignSystem.Colors.primary
            case .outline:
                return DesignSystem.Colors.primary
            }
        }
        
        var borderColor: Color? {
            switch self {
            case .outline:
                return DesignSystem.Colors.primary
            case .tertiary:
                return DesignSystem.Colors.separator
            default:
                return nil
            }
        }
        
        var pressedBackgroundColor: Color {
            switch self {
            case .primary:
                return DesignSystem.Colors.primaryDark
            case .secondary:
                return DesignSystem.Colors.secondaryDark
            case .tertiary:
                return DesignSystem.Colors.secondarySystemBackground
            case .destructive:
                return DesignSystem.Colors.errorDark
            case .success:
                return DesignSystem.Colors.successDark
            case .warning:
                return DesignSystem.Colors.warningDark
            case .ghost:
                return DesignSystem.Colors.primary.opacity(0.1)
            case .outline:
                return DesignSystem.Colors.primary.opacity(0.1)
            }
        }
    }
    
    // MARK: - Button Sizes
    public enum ButtonSize {
        case small
        case medium
        case large
        case xlarge
        
        var height: CGFloat {
            switch self {
            case .small: return 32
            case .medium: return 44
            case .large: return 52
            case .xlarge: return 60
            }
        }
        
        var fontSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 16
            case .large: return 18
            case .xlarge: return 20
            }
        }
        
        var iconSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 16
            case .large: return 18
            case .xlarge: return 20
            }
        }
        
        var horizontalPadding: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 16
            case .large: return 20
            case .xlarge: return 24
            }
        }
        
        var cornerRadius: CGFloat {
            switch self {
            case .small: return 6
            case .medium: return 8
            case .large: return 10
            case .xlarge: return 12
            }
        }
    }
    
    // MARK: - Initializers
    public init(
        title: String,
        icon: String? = nil,
        style: ButtonStyle = .primary,
        size: ButtonSize = .medium,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        fullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.size = size
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.fullWidth = fullWidth
        self.action = action
    }
    
    // MARK: - Body
    public var body: some View {
        Button(action: {
            if !isLoading && isEnabled {
                HapticFeedbackManager.shared.impact(.light)
                action()
            }
        }) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Loading indicator
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: style.foregroundColor))
                        .scaleEffect(0.8)
                }
                
                // Icon
                if let icon = icon, !isLoading {
                    Image(systemName: icon)
                        .font(.system(size: size.iconSize, weight: .medium))
                        .foregroundColor(currentForegroundColor)
                }
                
                // Title
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: size.fontSize, weight: .semibold))
                        .foregroundColor(currentForegroundColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: size.height)
            .padding(.horizontal, size.horizontalPadding)
            .background(currentBackgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .stroke(currentBorderColor, lineWidth: style.borderColor != nil ? 1 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))
            .scaleEffect(pressedScale)
            .opacity(currentOpacity)
            .animation(DesignSystem.Animations.buttonPress, value: isPressed)
            .animation(DesignSystem.Animations.buttonPress, value: isLoading)
        }
        .disabled(!isEnabled || isLoading)
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            if isEnabled && !isLoading {
                isPressed = pressing
            }
        }, perform: {})
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isEnabled ? .isButton : [.isButton, .isNotEnabled])
    }
    
    // MARK: - Computed Properties
    private var currentBackgroundColor: Color {
        if !isEnabled {
            return style.backgroundColor.opacity(0.3)
        }
        return isPressed ? style.pressedBackgroundColor : style.backgroundColor
    }
    
    private var currentForegroundColor: Color {
        if !isEnabled {
            return style.foregroundColor.opacity(0.5)
        }
        return style.foregroundColor
    }
    
    private var currentBorderColor: Color {
        if let borderColor = style.borderColor {
            return isEnabled ? borderColor : borderColor.opacity(0.3)
        }
        return Color.clear
    }
    
    private var pressedScale: CGFloat {
        if reduceMotion || !isEnabled || isLoading {
            return 1.0
        }
        return isPressed ? 0.96 : 1.0
    }
    
    private var currentOpacity: Double {
        if !isEnabled && !isLoading {
            return 0.6
        }
        return 1.0
    }
    
    private var accessibilityLabel: String {
        if isLoading {
            return "\(title), Loading"
        }
        return title
    }
    
    private var accessibilityHint: String {
        if !isEnabled {
            return "Button is disabled"
        }
        if isLoading {
            return "Please wait, action in progress"
        }
        return "Tap to \(title.lowercased())"
    }
}

// MARK: - Button Presets

extension ProfessionalButton {
    
    // MARK: - Primary Actions
    public static func primaryAction(
        title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> ProfessionalButton {
        ProfessionalButton(
            title: title,
            icon: icon,
            style: .primary,
            size: .large,
            isLoading: isLoading,
            fullWidth: true,
            action: action
        )
    }
    
    // MARK: - Secondary Actions
    public static func secondaryAction(
        title: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) -> ProfessionalButton {
        ProfessionalButton(
            title: title,
            icon: icon,
            style: .secondary,
            size: .medium,
            action: action
        )
    }
    
    // MARK: - Destructive Actions
    public static func destructiveAction(
        title: String,
        icon: String? = "trash",
        action: @escaping () -> Void
    ) -> ProfessionalButton {
        ProfessionalButton(
            title: title,
            icon: icon,
            style: .destructive,
            size: .medium,
            action: action
        )
    }
    
    // MARK: - Icon Only Buttons
    public static func iconButton(
        icon: String,
        style: ButtonStyle = .tertiary,
        size: ButtonSize = .medium,
        action: @escaping () -> Void
    ) -> ProfessionalButton {
        ProfessionalButton(
            title: "",
            icon: icon,
            style: style,
            size: size,
            action: action
        )
    }
    
    // MARK: - Navigation Buttons
    public static func backButton(action: @escaping () -> Void) -> ProfessionalButton {
        ProfessionalButton(
            title: "Back",
            icon: "chevron.left",
            style: .ghost,
            size: .medium,
            action: action
        )
    }
    
    public static func closeButton(action: @escaping () -> Void) -> ProfessionalButton {
        ProfessionalButton(
            title: "",
            icon: "xmark",
            style: .tertiary,
            size: .medium,
            action: action
        )
    }
    
    // MARK: - Loading States
    public static func loadingButton(
        title: String,
        style: ButtonStyle = .primary
    ) -> ProfessionalButton {
        ProfessionalButton(
            title: title,
            style: style,
            size: .large,
            isLoading: true,
            fullWidth: true,
            action: {}
        )
    }
}

// MARK: - Button Group Component

public struct ButtonGroup: View {
    private let buttons: [ProfessionalButton]
    private let axis: Axis
    private let spacing: CGFloat
    
    public init(
        buttons: [ProfessionalButton],
        axis: Axis = .horizontal,
        spacing: CGFloat = DesignSystem.Spacing.md
    ) {
        self.buttons = buttons
        self.axis = axis
        self.spacing = spacing
    }
    
    public var body: some View {
        Group {
            if axis == .horizontal {
                HStack(spacing: spacing) {
                    ForEach(0..<buttons.count, id: \.self) { index in
                        buttons[index]
                    }
                }
            } else {
                VStack(spacing: spacing) {
                    ForEach(0..<buttons.count, id: \.self) { index in
                        buttons[index]
                    }
                }
            }
        }
    }
}

// MARK: - Floating Action Button

public struct FloatingActionButton: View {
    private let icon: String
    private let action: () -> Void
    private let style: FloatingStyle
    
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public enum FloatingStyle {
        case primary
        case secondary
        case accent
        
        var backgroundColor: Color {
            switch self {
            case .primary: return DesignSystem.Colors.primary
            case .secondary: return DesignSystem.Colors.secondary
            case .accent: return DesignSystem.Colors.arAccent
            }
        }
        
        var shadowColor: Color {
            return backgroundColor.opacity(0.3)
        }
    }
    
    public init(
        icon: String,
        style: FloatingStyle = .primary,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.style = style
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            HapticFeedbackManager.shared.impact(.medium)
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(style.backgroundColor)
                .clipShape(Circle())
                .shadow(
                    color: style.shadowColor,
                    radius: isPressed ? 4 : 8,
                    x: 0,
                    y: isPressed ? 2 : 4
                )
                .scaleEffect(isPressed && !reduceMotion ? 0.95 : 1.0)
                .animation(DesignSystem.Animations.buttonPress, value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .accessibilityLabel("Floating action button")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Preview

struct ProfessionalButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ProfessionalButton.primaryAction(title: "Primary Action", icon: "plus") {}
            ProfessionalButton.secondaryAction(title: "Secondary", icon: "heart") {}
            ProfessionalButton.destructiveAction(title: "Delete", icon: "trash") {}
            ProfessionalButton.loadingButton(title: "Loading...")
            
            HStack {
                ProfessionalButton.iconButton(icon: "star") {}
                ProfessionalButton.iconButton(icon: "heart") {}
                ProfessionalButton.iconButton(icon: "bookmark") {}
            }
            
            FloatingActionButton(icon: "plus") {}
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}