import SwiftUI

// MARK: - Professional Card Component

public struct ProfessionalCard<Content: View>: View {
    private let content: Content
    private let style: CardStyle
    private let padding: EdgeInsets
    private let onTap: (() -> Void)?
    
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public enum CardStyle {
        case plain
        case elevated
        case outlined
        case filled
        
        var backgroundColor: Color {
            switch self {
            case .plain: return Color.clear
            case .elevated: return DesignSystem.Colors.systemBackground
            case .outlined: return DesignSystem.Colors.systemBackground
            case .filled: return DesignSystem.Colors.secondarySystemBackground
            }
        }
        
        var shadow: DesignSystem.Shadows.Shadow {
            switch self {
            case .plain, .outlined, .filled: return DesignSystem.Shadows.none
            case .elevated: return DesignSystem.Shadows.md
            }
        }
        
        var borderColor: Color? {
            switch self {
            case .outlined: return DesignSystem.Colors.separator
            default: return nil
            }
        }
    }
    
    public init(
        style: CardStyle = .elevated,
        padding: EdgeInsets = DesignSystem.Spacing.cardPadding,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.style = style
        self.padding = padding
        self.onTap = onTap
    }
    
    public var body: some View {
        Group {
            if let onTap = onTap {
                Button(action: {
                    HapticFeedbackManager.shared.impact(.light)
                    onTap()
                }) {
                    cardContent
                }
                .buttonStyle(PlainButtonStyle())
                .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                    isPressed = pressing
                }, perform: {})
            } else {
                cardContent
            }
        }
    }
    
    private var cardContent: some View {
        content
            .padding(padding)
            .background(style.backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.BorderRadius.card)
                    .stroke(style.borderColor ?? Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.BorderRadius.card))
            .shadowStyle(style.shadow)
            .scaleEffect(pressedScale)
            .animation(DesignSystem.Animations.buttonPress, value: isPressed)
    }
    
    private var pressedScale: CGFloat {
        if reduceMotion || onTap == nil {
            return 1.0
        }
        return isPressed ? 0.98 : 1.0
    }
}

// MARK: - Professional List Item

public struct ProfessionalListItem: View {
    private let title: String
    private let subtitle: String?
    private let leadingIcon: String?
    private let trailingIcon: String?
    private let badge: String?
    private let isSelected: Bool
    private let onTap: (() -> Void)?
    
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init(
        title: String,
        subtitle: String? = nil,
        leadingIcon: String? = nil,
        trailingIcon: String? = "chevron.right",
        badge: String? = nil,
        isSelected: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
        self.badge = badge
        self.isSelected = isSelected
        self.onTap = onTap
    }
    
    public var body: some View {
        Button(action: {
            if let onTap = onTap {
                HapticFeedbackManager.shared.impact(.light)
                onTap()
            }
        }) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Leading Icon
                if let leadingIcon = leadingIcon {
                    ZStack {
                        Circle()
                            .fill(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.tertiarySystemBackground)
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: leadingIcon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(isSelected ? .white : DesignSystem.Colors.secondaryLabel)
                    }
                }
                
                // Content
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title)
                            .font(DesignSystem.Typography.body(.medium))
                            .foregroundColor(DesignSystem.Colors.label)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        // Badge
                        if let badge = badge {
                            Text(badge)
                                .font(DesignSystem.Typography.caption2(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(DesignSystem.Colors.primary, in: Capsule())
                        }
                    }
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(DesignSystem.Typography.footnote())
                            .foregroundColor(DesignSystem.Colors.secondaryLabel)
                            .lineLimit(2)
                    }
                }
                
                // Trailing Icon
                if let trailingIcon = trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.tertiaryLabel)
                }
            }
            .padding(.vertical, DesignSystem.Spacing.sm)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.BorderRadius.md)
                    .fill(isSelected ? DesignSystem.Colors.primaryContainer : Color.clear)
            )
            .scaleEffect(pressedScale)
            .animation(DesignSystem.Animations.buttonPress, value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(onTap == nil)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            if onTap != nil {
                isPressed = pressing
            }
        }, perform: {})
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(onTap != nil ? .isButton : [])
    }
    
    private var pressedScale: CGFloat {
        if reduceMotion || onTap == nil {
            return 1.0
        }
        return isPressed ? 0.98 : 1.0
    }
    
    private var accessibilityLabel: String {
        var label = title
        if let subtitle = subtitle {
            label += ", \(subtitle)"
        }
        if let badge = badge {
            label += ", \(badge)"
        }
        if isSelected {
            label += ", selected"
        }
        return label
    }
}

// MARK: - Professional Text Field

public struct ProfessionalTextField: View {
    @Binding private var text: String
    private let placeholder: String
    private let label: String?
    private let helperText: String?
    private let errorMessage: String?
    private let isSecure: Bool
    private let keyboardType: UIKeyboardType
    private let maxLength: Int?
    private let style: TextFieldStyle
    
    @State private var isFocused = false
    @State private var isSecureVisible = false
    @FocusState private var fieldIsFocused: Bool
    
    public enum TextFieldStyle {
        case standard
        case outlined
        case filled
        
        var backgroundColor: Color {
            switch self {
            case .standard: return Color.clear
            case .outlined: return Color.clear
            case .filled: return DesignSystem.Colors.tertiarySystemBackground
            }
        }
        
        var borderColor: Color {
            switch self {
            case .standard: return Color.clear
            case .outlined: return DesignSystem.Colors.separator
            case .filled: return Color.clear
            }
        }
    }
    
    public init(
        text: Binding<String>,
        placeholder: String,
        label: String? = nil,
        helperText: String? = nil,
        errorMessage: String? = nil,
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default,
        maxLength: Int? = nil,
        style: TextFieldStyle = .outlined
    ) {
        self._text = text
        self.placeholder = placeholder
        self.label = label
        self.helperText = helperText
        self.errorMessage = errorMessage
        self.isSecure = isSecure
        self.keyboardType = keyboardType
        self.maxLength = maxLength
        self.style = style
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // Label
            if let label = label {
                Text(label)
                    .font(DesignSystem.Typography.footnote(.medium))
                    .foregroundColor(labelColor)
                    .animation(DesignSystem.Animations.fast, value: isFocused)
            }
            
            // Text Field Container
            HStack {
                textField
                
                // Secure toggle button
                if isSecure {
                    Button(action: {
                        isSecureVisible.toggle()
                        HapticFeedbackManager.shared.impact(.light)
                    }) {
                        Image(systemName: isSecureVisible ? "eye.slash" : "eye")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.tertiaryLabel)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(style.backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.BorderRadius.md)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.BorderRadius.md))
            .animation(DesignSystem.Animations.fast, value: isFocused)
            .animation(DesignSystem.Animations.fast, value: hasError)
            
            // Helper/Error Text
            if let message = errorMessage ?? helperText {
                HStack {
                    Text(message)
                        .font(DesignSystem.Typography.caption2())
                        .foregroundColor(hasError ? DesignSystem.Colors.error : DesignSystem.Colors.secondaryLabel)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    // Character count
                    if let maxLength = maxLength {
                        Text("\(text.count)/\(maxLength)")
                            .font(DesignSystem.Typography.caption2())
                            .foregroundColor(text.count > maxLength ? DesignSystem.Colors.error : DesignSystem.Colors.tertiaryLabel)
                            .monospacedDigit()
                    }
                }
            }
        }
        .onChange(of: fieldIsFocused) { _, focused in
            isFocused = focused
        }
        .onChange(of: text) { _, newValue in
            if let maxLength = maxLength, newValue.count > maxLength {
                text = String(newValue.prefix(maxLength))
            }
        }
    }
    
    @ViewBuilder
    private var textField: some View {
        if isSecure && !isSecureVisible {
            SecureField(placeholder, text: $text)
                .textFieldStyle()
                .focused($fieldIsFocused)
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle()
                .keyboardType(keyboardType)
                .focused($fieldIsFocused)
        }
    }
    
    private var hasError: Bool {
        return errorMessage != nil
    }
    
    private var labelColor: Color {
        if hasError {
            return DesignSystem.Colors.error
        } else if isFocused {
            return DesignSystem.Colors.primary
        } else {
            return DesignSystem.Colors.secondaryLabel
        }
    }
    
    private var borderColor: Color {
        if hasError {
            return DesignSystem.Colors.error
        } else if isFocused {
            return DesignSystem.Colors.primary
        } else {
            return style.borderColor
        }
    }
    
    private var borderWidth: CGFloat {
        return (isFocused || hasError) ? 2 : 1
    }
}

// MARK: - Professional Segmented Control

public struct ProfessionalSegmentedControl: View {
    @Binding private var selection: Int
    private let items: [String]
    private let style: SegmentedStyle
    
    @Namespace private var selectionNamespace
    
    public enum SegmentedStyle {
        case standard
        case pills
        case underline
        
        var backgroundColor: Color {
            switch self {
            case .standard, .pills: return DesignSystem.Colors.tertiarySystemBackground
            case .underline: return Color.clear
            }
        }
        
        var selectionBackgroundColor: Color {
            switch self {
            case .standard, .pills: return DesignSystem.Colors.systemBackground
            case .underline: return Color.clear
            }
        }
    }
    
    public init(
        selection: Binding<Int>,
        items: [String],
        style: SegmentedStyle = .standard
    ) {
        self._selection = selection
        self.items = items
        self.style = style
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<items.count, id: \.self) { index in
                segmentButton(for: index)
            }
        }
        .background(style.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: segmentCornerRadius))
    }
    
    private func segmentButton(for index: Int) -> some View {
        Button(action: {
            withAnimation(DesignSystem.Animations.spring) {
                selection = index
            }
            HapticFeedbackManager.shared.selectionChanged()
        }) {
            Text(items[index])
                .font(DesignSystem.Typography.footnote(.medium))
                .foregroundColor(selection == index ? selectedTextColor : unselectedTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    Group {
                        if selection == index {
                            if style == .underline {
                                VStack {
                                    Spacer()
                                    Rectangle()
                                        .fill(DesignSystem.Colors.primary)
                                        .frame(height: 2)
                                }
                            } else {
                                RoundedRectangle(cornerRadius: segmentCornerRadius - 2)
                                    .fill(style.selectionBackgroundColor)
                                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                            }
                        }
                    }
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var segmentCornerRadius: CGFloat {
        switch style {
        case .standard: return DesignSystem.BorderRadius.md
        case .pills: return 20
        case .underline: return 0
        }
    }
    
    private var selectedTextColor: Color {
        switch style {
        case .standard, .pills: return DesignSystem.Colors.label
        case .underline: return DesignSystem.Colors.primary
        }
    }
    
    private var unselectedTextColor: Color {
        return DesignSystem.Colors.secondaryLabel
    }
}

// MARK: - Professional Toggle

public struct ProfessionalToggle: View {
    @Binding private var isOn: Bool
    private let title: String
    private let subtitle: String?
    private let style: ToggleStyle
    
    public enum ToggleStyle {
        case standard
        case prominent
        case minimal
        
        var showLabels: Bool {
            switch self {
            case .standard, .prominent: return true
            case .minimal: return false
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .prominent: return DesignSystem.Colors.tertiarySystemBackground
            default: return Color.clear
            }
        }
    }
    
    public init(
        isOn: Binding<Bool>,
        title: String,
        subtitle: String? = nil,
        style: ToggleStyle = .standard
    ) {
        self._isOn = isOn
        self.title = title
        self.subtitle = subtitle
        self.style = style
    }
    
    public var body: some View {
        Button(action: {
            withAnimation(DesignSystem.Animations.spring) {
                isOn.toggle()
            }
            HapticFeedbackManager.shared.selectionChanged()
        }) {
            HStack {
                if style.showLabels {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(DesignSystem.Typography.body(.medium))
                            .foregroundColor(DesignSystem.Colors.label)
                        
                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(DesignSystem.Typography.footnote())
                                .foregroundColor(DesignSystem.Colors.secondaryLabel)
                        }
                    }
                    
                    Spacer()
                }
                
                // Custom Toggle Switch
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isOn ? DesignSystem.Colors.primary : DesignSystem.Colors.separator)
                        .frame(width: 50, height: 30)
                    
                    Circle()
                        .fill(.white)
                        .frame(width: 26, height: 26)
                        .offset(x: isOn ? 10 : -10)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                }
                .animation(DesignSystem.Animations.spring, value: isOn)
            }
            .padding(style == .prominent ? DesignSystem.Spacing.md : 0)
            .background(style.backgroundColor, in: RoundedRectangle(cornerRadius: DesignSystem.BorderRadius.md))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to toggle")
    }
}

// MARK: - View Extensions

extension View {
    fileprivate func textFieldStyle() -> some View {
        self
            .font(DesignSystem.Typography.body())
            .foregroundColor(DesignSystem.Colors.label)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
    }
}

// MARK: - Preview

struct ProfessionalComponents_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                ProfessionalCard {
                    VStack {
                        Text("Card Title")
                            .font(DesignSystem.Typography.headline())
                        Text("Card content goes here")
                            .font(DesignSystem.Typography.body())
                    }
                }
                
                ProfessionalListItem(
                    title: "List Item",
                    subtitle: "Subtitle",
                    leadingIcon: "star",
                    badge: "New"
                ) {}
                
                ProfessionalTextField(
                    text: .constant(""),
                    placeholder: "Enter text",
                    label: "Label"
                )
                
                ProfessionalSegmentedControl(
                    selection: .constant(0),
                    items: ["First", "Second", "Third"]
                )
                
                ProfessionalToggle(
                    isOn: .constant(true),
                    title: "Toggle Option",
                    subtitle: "Enable this feature"
                )
            }
            .padding()
        }
        .previewLayout(.sizeThatFits)
    }
}