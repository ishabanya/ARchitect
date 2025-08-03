import SwiftUI
import Combine

// MARK: - Tool Palette Manager

@MainActor
public class ToolPaletteManager: ObservableObject {
    
    // MARK: - Properties
    @Published public var isExpanded = false
    @Published public var selectedTool: ARTool?
    @Published public var availableTools: [ARTool] = []
    @Published public var recentTools: [ARTool] = []
    @Published public var favoriteTtools: [ARTool] = []
    
    // Animation state
    @Published public var expansionProgress: Double = 0.0
    @Published public var isAnimating = false
    
    // Configuration
    public var maxRecentTools = 4
    public var maxVisibleTools = 8
    public var animationDuration: Double = 0.4
    
    private let hapticFeedback = HapticFeedbackManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        setupDefaultTools()
        loadUserPreferences()
        
        logDebug("Tool palette manager initialized", category: .general)
    }
    
    // MARK: - Setup
    
    private func setupDefaultTools() {
        availableTools = [
            ARTool(id: "furniture", name: "Add Furniture", icon: "sofa.fill", category: .creation, shortcut: "F"),
            ARTool(id: "light", name: "Add Light", icon: "lightbulb.fill", category: .creation, shortcut: "L"),
            ARTool(id: "decoration", name: "Add Decoration", icon: "star.fill", category: .creation, shortcut: "D"),
            ARTool(id: "move", name: "Move", icon: "move.3d", category: .manipulation, shortcut: "M"),
            ARTool(id: "rotate", name: "Rotate", icon: "rotate.3d", category: .manipulation, shortcut: "R"),
            ARTool(id: "scale", name: "Scale", icon: "scale.3d", category: .manipulation, shortcut: "S"),
            ARTool(id: "duplicate", name: "Duplicate", icon: "doc.on.doc", category: .manipulation, shortcut: "Cmd+D"),
            ARTool(id: "delete", name: "Delete", icon: "trash", category: .manipulation, shortcut: "Delete"),
            ARTool(id: "measure", name: "Measure", icon: "ruler", category: .utility, shortcut: "U"),
            ARTool(id: "camera", name: "Camera", icon: "camera", category: .utility, shortcut: "C"),
            ARTool(id: "snapshot", name: "Snapshot", icon: "camera.viewfinder", category: .utility, shortcut: "Space"),
            ARTool(id: "settings", name: "Settings", icon: "gear", category: .utility, shortcut: "Cmd+,")
        ]
    }
    
    private func loadUserPreferences() {
        // Load user's recent and favorite tools
        // This would typically load from UserDefaults or Core Data
        recentTools = Array(availableTools.prefix(maxRecentTools))
    }
    
    // MARK: - Expansion Control
    
    public func toggleExpansion() {
        withAnimation(.spring(response: animationDuration, dampingFraction: 0.8)) {
            isExpanded.toggle()
            isAnimating = true
        }
        
        // Animate expansion progress
        animateExpansionProgress()
        
        // Haptic feedback
        hapticFeedback.impact(isExpanded ? .medium : .light)
        
        // Accessibility announcement
        AccessibilityManager.shared.announce(
            isExpanded ? "Tool palette expanded" : "Tool palette collapsed",
            priority: .normal
        )
        
        logDebug("Tool palette toggled", category: .general, context: LogContext(customData: [
            "expanded": isExpanded
        ]))
    }
    
    public func expand() {
        guard !isExpanded else { return }
        toggleExpansion()
    }
    
    public func collapse() {
        guard isExpanded else { return }
        toggleExpansion()
    }
    
    private func animateExpansionProgress() {
        let targetProgress = isExpanded ? 1.0 : 0.0
        
        withAnimation(.easeInOut(duration: animationDuration)) {
            expansionProgress = targetProgress
        }
        
        // Complete animation
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            self.isAnimating = false
        }
    }
    
    // MARK: - Tool Selection
    
    public func selectTool(_ tool: ARTool) {
        selectedTool = tool
        addToRecentTools(tool)
        
        // Haptic feedback
        hapticFeedback.selectionChanged()
        
        // Accessibility announcement
        AccessibilityManager.shared.announce("Selected \(tool.name) tool", priority: .normal)
        
        // Auto-collapse after selection (optional)
        if isExpanded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.collapse()
            }
        }
        
        logDebug("Tool selected", category: .general, context: LogContext(customData: [
            "tool_id": tool.id,
            "tool_name": tool.name
        ]))
    }
    
    public func deselectTool() {
        selectedTool = nil
        
        AccessibilityManager.shared.announce("Tool deselected", priority: .normal)
        
        logDebug("Tool deselected", category: .general)
    }
    
    // MARK: - Tool Management
    
    private func addToRecentTools(_ tool: ARTool) {
        // Remove if already exists
        recentTools.removeAll { $0.id == tool.id }
        
        // Add to front
        recentTools.insert(tool, at: 0)
        
        // Limit to max recent tools
        if recentTools.count > maxRecentTools {
            recentTools.removeLast()
        }
        
        saveUserPreferences()
    }
    
    public func toggleFavorite(_ tool: ARTool) {
        if favoriteTtools.contains(where: { $0.id == tool.id }) {
            favoriteTtools.removeAll { $0.id == tool.id }
        } else {
            favoriteTtools.append(tool)
        }
        
        saveUserPreferences()
        
        hapticFeedback.impact(.light)
    }
    
    private func saveUserPreferences() {
        // Save to UserDefaults or Core Data
        // Implementation would go here
    }
    
    // MARK: - Tool Categories
    
    public func getTools(for category: ToolCategory) -> [ARTool] {
        return availableTools.filter { $0.category == category }
    }
    
    public func getVisibleTools() -> [ARTool] {
        if isExpanded {
            return availableTools
        } else {
            return Array(recentTools.prefix(4))
        }
    }
}

// MARK: - Tool Palette View

public struct ToolPalette: View {
    @StateObject private var paletteManager = ToolPaletteManager()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            if paletteManager.isExpanded {
                ExpandedPalette()
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                CollapsedPalette()
                    .transition(.identity)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .environmentObject(paletteManager)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tool Palette")
        .accessibilityHint("Contains tool selection buttons")
    }
}

// MARK: - Collapsed Palette

private struct CollapsedPalette: View {
    @EnvironmentObject private var paletteManager: ToolPaletteManager
    
    var body: some View {
        HStack(spacing: 8) {
            // Recent tools
            ForEach(paletteManager.recentTools.prefix(4), id: \.id) { tool in
                ToolButton(tool: tool, size: .compact)
            }
            
            // Expand button
            Button(action: { paletteManager.expand() }) {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Expand tool palette")
            .accessibilityHint("Shows all available tools")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Expanded Palette

private struct ExpandedPalette: View {
    @EnvironmentObject private var paletteManager: ToolPaletteManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var columns: [GridItem] {
        let columnCount = horizontalSizeClass == .compact ? 4 : 6
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with collapse button
            HStack {
                Text("Tools")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { paletteManager.collapse() }) {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)
                }
                .accessibilityLabel("Collapse tool palette")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // Tool categories
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 20) {
                    ForEach(ToolCategory.allCases, id: \.self) { category in
                        ToolCategorySection(category: category)
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: 300)
            
            // Quick actions
            QuickToolActions()
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }
}

// MARK: - Tool Category Section

private struct ToolCategorySection: View {
    let category: ToolCategory
    @EnvironmentObject private var paletteManager: ToolPaletteManager
    
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category header
            HStack {
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(category.color)
                
                Text(category.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            // Tools grid
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(paletteManager.getTools(for: category), id: \.id) { tool in
                    ToolButton(tool: tool, size: .regular)
                }
            }
        }
    }
}

// MARK: - Tool Button

private struct ToolButton: View {
    let tool: ARTool
    let size: ButtonSize
    
    @EnvironmentObject private var paletteManager: ToolPaletteManager
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    enum ButtonSize {
        case compact, regular
        
        var dimension: CGFloat {
            switch self {
            case .compact: return 32
            case .regular: return 44
            }
        }
        
        var iconSize: CGFloat {
            switch self {
            case .compact: return 16
            case .regular: return 20
            }
        }
    }
    
    private var isSelected: Bool {
        paletteManager.selectedTool?.id == tool.id
    }
    
    private var isFavorite: Bool {
        paletteManager.favoriteTtools.contains { $0.id == tool.id }
    }
    
    var body: some View {
        Button(action: { paletteManager.selectTool(tool) }) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: size == .compact ? 8 : 12)
                    .fill(isSelected ? tool.category.color.opacity(0.2) : .clear)
                    .stroke(isSelected ? tool.category.color : Color.clear, lineWidth: 2)
                
                // Icon
                Image(systemName: tool.icon)
                    .font(.system(size: size.iconSize, weight: .medium))
                    .foregroundColor(isSelected ? tool.category.color : .primary)
                
                // Favorite indicator
                if isFavorite {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(.yellow)
                                .frame(width: 6, height: 6)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: size.dimension, height: size.dimension)
            .scaleEffect(isPressed && !reduceMotion ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(tool.name)
        .accessibilityHint("Selects \(tool.name) tool")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            ToolContextMenu(tool: tool)
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Tool Context Menu

private struct ToolContextMenu: View {
    let tool: ARTool
    @EnvironmentObject private var paletteManager: ToolPaletteManager
    
    var body: some View {
        VStack {
            Button(action: { paletteManager.toggleFavorite(tool) }) {
                Label(
                    paletteManager.favoriteTtools.contains { $0.id == tool.id } ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: paletteManager.favoriteTtools.contains { $0.id == tool.id } ? "star.fill" : "star"
                )
            }
            
            if !tool.shortcut.isEmpty {
                Button(action: {}) {
                    Label("Shortcut: \(tool.shortcut)", systemImage: "keyboard")
                }
                .disabled(true)
            }
        }
    }
}

// MARK: - Quick Tool Actions

private struct QuickToolActions: View {
    @EnvironmentObject private var paletteManager: ToolPaletteManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Clear selection
            if paletteManager.selectedTool != nil {
                Button("Clear Selection") {
                    paletteManager.deselectTool()
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }
            
            Spacer()
            
            // Keyboard shortcuts hint
            Button("Shortcuts") {
                showKeyboardShortcuts()
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }
    
    private func showKeyboardShortcuts() {
        // Show keyboard shortcuts help
        AccessibilityManager.shared.announce("Keyboard shortcuts available for all tools", priority: .normal)
    }
}

// MARK: - Supporting Types

public struct ARTool: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let icon: String
    public let category: ToolCategory
    public let shortcut: String
    public let isEnabled: Bool
    
    public init(id: String, name: String, icon: String, category: ToolCategory, shortcut: String = "", isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.icon = icon
        self.category = category
        self.shortcut = shortcut
        self.isEnabled = isEnabled
    }
    
    public static func == (lhs: ARTool, rhs: ARTool) -> Bool {
        return lhs.id == rhs.id
    }
}

public enum ToolCategory: String, CaseIterable {
    case creation = "creation"
    case manipulation = "manipulation"
    case utility = "utility"
    
    public var displayName: String {
        switch self {
        case .creation: return "Create"
        case .manipulation: return "Edit"
        case .utility: return "Tools"
        }
    }
    
    public var icon: String {
        switch self {
        case .creation: return "plus.circle"
        case .manipulation: return "slider.horizontal.3"
        case .utility: return "wrench.and.screwdriver"
        }
    }
    
    public var color: Color {
        switch self {
        case .creation: return .green
        case .manipulation: return .blue
        case .utility: return .orange
        }
    }
}

// MARK: - Animation Extensions

extension AnyTransition {
    static var toolPaletteExpansion: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
            removal: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 1.05))
        )
    }
}