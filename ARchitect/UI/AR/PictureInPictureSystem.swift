import SwiftUI
import AVKit
import Combine

// MARK: - Picture-in-Picture Manager

@MainActor
public class PictureInPictureManager: ObservableObject {
    
    // MARK: - Properties
    @Published public var isSupported = true
    @Published public var isPiPActive = false
    @Published public var isPiPVisible = true
    @Published public var currentContent: PiPContent?
    
    // Position and size
    @Published public var pipFrame: CGRect = CGRect(x: 20, y: 100, width: 280, height: 200)
    @Published public var isMinimized = false
    @Published public var isDragging = false
    
    // Content state
    @Published public var catalogItems: [FurnitureItem] = []
    @Published public var selectedCategory: FurnitureCategory?
    @Published public var searchQuery = ""
    @Published public var isLoading = false
    
    // Interaction state
    @Published public var allowsInteraction = true
    @Published public var snapToEdges = true
    @Published public var autoHide = false
    
    // Animation state
    @Published public var animationProgress: Double = 0.0
    @Published public var isTransitioning = false
    
    // Configuration
    private let minSize = CGSize(width: 200, height: 150)
    private let maxSize = CGSize(width: 350, height: 280)
    private let collapsedHeight: CGFloat = 60
    private let edgeSnapDistance: CGFloat = 20
    
    private let hapticFeedback = HapticFeedbackManager.shared
    private let accessibilityManager = AccessibilityManager.shared
    private var autoHideTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        setupObservers()
        checkPiPSupport()
        
        logDebug("Picture-in-Picture manager initialized", category: .general)
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Monitor content changes
        $currentContent
            .sink { [weak self] content in
                self?.handleContentChange(content)
            }
            .store(in: &cancellables)
        
        // Monitor search query changes
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query in
                self?.performSearch(query)
            }
            .store(in: &cancellables)
    }
    
    private func checkPiPSupport() {
        // Check if device supports PiP functionality
        isSupported = UIDevice.current.userInterfaceIdiom != .phone || 
                     UIScreen.main.bounds.width >= 375 // Minimum width for PiP
        
        if !isSupported {
            logWarning("Picture-in-Picture not supported on this device", category: .general)
        }
    }
    
    // MARK: - PiP Control
    
    public func showCatalogPiP() {
        guard isSupported else {
            // Fallback to full-screen catalog
            showFullScreenCatalog()
            return
        }
        
        currentContent = .furnitureCatalog
        isPiPActive = true
        isPiPVisible = true
        isMinimized = false
        
        loadCatalogContent()
        setupAutoHide()
        
        hapticFeedback.impact(.medium)
        accessibilityManager.announce("Picture-in-picture catalog opened", priority: .normal)
        
        logDebug("PiP catalog shown", category: .general)
    }
    
    public func showItemDetailPiP(_ item: FurnitureItem) {
        guard isSupported else {
            showFullScreenItemDetail(item)
            return
        }
        
        currentContent = .itemDetail(item)
        isPiPActive = true
        isPiPVisible = true
        isMinimized = false
        
        setupAutoHide()
        
        hapticFeedback.impact(.light)
        accessibilityManager.announce("Item details shown in picture-in-picture", priority: .normal)
        
        logDebug("PiP item detail shown", category: .general, context: LogContext(customData: [
            "item_id": item.id.uuidString,
            "item_name": item.name
        ]))
    }
    
    public func hidePiP() {
        guard isPiPActive else { return }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isPiPVisible = false
            isTransitioning = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isPiPActive = false
            self.currentContent = nil
            self.isTransitioning = false
        }
        
        cancelAutoHide()
        
        hapticFeedback.impact(.light)
        accessibilityManager.announce("Picture-in-picture closed", priority: .normal)
        
        logDebug("PiP hidden", category: .general)
    }
    
    public func minimizePiP() {
        guard isPiPActive && !isMinimized else { return }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isMinimized = true
            animationProgress = 1.0
        }
        
        // Update frame for minimized state
        let minimizedFrame = CGRect(
            x: pipFrame.minX,
            y: pipFrame.minY,
            width: pipFrame.width,
            height: collapsedHeight
        )
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            pipFrame = minimizedFrame
        }
        
        hapticFeedback.impact(.light)
        accessibilityManager.announce("Picture-in-picture minimized", priority: .normal)
        
        logDebug("PiP minimized", category: .general)
    }
    
    public func expandPiP() {
        guard isPiPActive && isMinimized else { return }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isMinimized = false
            animationProgress = 0.0
        }
        
        // Update frame for expanded state
        let expandedFrame = CGRect(
            x: pipFrame.minX,
            y: pipFrame.minY,
            width: pipFrame.width,
            height: maxSize.height
        )
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            pipFrame = expandedFrame
        }
        
        setupAutoHide()
        
        hapticFeedback.impact(.light)
        accessibilityManager.announce("Picture-in-picture expanded", priority: .normal)
        
        logDebug("PiP expanded", category: .general)
    }
    
    // MARK: - Content Management
    
    private func handleContentChange(_ content: PiPContent?) {
        guard let content = content else { return }
        
        switch content {
        case .furnitureCatalog:
            loadCatalogContent()
        case .itemDetail(let item):
            loadItemDetail(item)
        case .roomBrowser:
            loadRoomBrowser()
        case .settings:
            loadSettings()
        }
    }
    
    private func loadCatalogContent() {
        isLoading = true
        
        // Simulate loading catalog items
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.catalogItems = self.generateSampleCatalogItems()
            self.isLoading = false
        }
    }
    
    private func loadItemDetail(_ item: FurnitureItem) {
        // Load detailed item information
        logDebug("Loading item detail in PiP", category: .general, context: LogContext(customData: [
            "item_id": item.id.uuidString
        ]))
    }
    
    private func loadRoomBrowser() {
        // Load room browser content
        logDebug("Loading room browser in PiP", category: .general)
    }
    
    private func loadSettings() {
        // Load settings content
        logDebug("Loading settings in PiP", category: .general)
    }
    
    private func generateSampleCatalogItems() -> [FurnitureItem] {
        // Generate sample items for demonstration
        return [
            FurnitureItem(id: UUID(), name: "Modern Sofa", category: .seating, model3D: "sofa_modern", metadata: FurnitureMetadata()),
            FurnitureItem(id: UUID(), name: "Dining Table", category: .tables, model3D: "table_dining", metadata: FurnitureMetadata()),
            FurnitureItem(id: UUID(), name: "Floor Lamp", category: .lighting, model3D: "lamp_floor", metadata: FurnitureMetadata()),
            FurnitureItem(id: UUID(), name: "Bookshelf", category: .storage, model3D: "bookshelf", metadata: FurnitureMetadata())
        ]
    }
    
    // MARK: - Search and Filter
    
    private func performSearch(_ query: String) {
        guard !query.isEmpty else {
            loadCatalogContent()
            return
        }
        
        isLoading = true
        
        // Simulate search delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.catalogItems = self.catalogItems.filter { item in
                item.name.lowercased().contains(query.lowercased())
            }
            self.isLoading = false
        }
        
        logDebug("Search performed in PiP", category: .general, context: LogContext(customData: [
            "query": query
        ]))
    }
    
    public func filterByCategory(_ category: FurnitureCategory) {
        selectedCategory = category
        isLoading = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.catalogItems = self.generateSampleCatalogItems().filter { item in
                item.category == category
            }
            self.isLoading = false
        }
        
        hapticFeedback.selectionChanged()
        accessibilityManager.announce("Filtered by \(category.displayName)", priority: .normal)
        
        logDebug("Category filter applied in PiP", category: .general, context: LogContext(customData: [
            "category": category.rawValue
        ]))
    }
    
    public func clearFilters() {
        selectedCategory = nil
        searchQuery = ""
        loadCatalogContent()
        
        accessibilityManager.announce("Filters cleared", priority: .normal)
    }
    
    // MARK: - Position Management
    
    public func updatePosition(_ position: CGPoint) {
        let screenBounds = UIScreen.main.bounds
        let constrainedPosition = constrainPosition(position, in: screenBounds)
        
        pipFrame.origin = constrainedPosition
        
        if snapToEdges {
            snapToEdgesIfNeeded(screenBounds)
        }
    }
    
    private func constrainPosition(_ position: CGPoint, in bounds: CGRect) -> CGPoint {
        let minX = bounds.minX + edgeSnapDistance
        let maxX = bounds.maxX - pipFrame.width - edgeSnapDistance
        let minY = bounds.minY + 100 // Account for status bar and safe area
        let maxY = bounds.maxY - pipFrame.height - 100 // Account for home indicator
        
        return CGPoint(
            x: max(minX, min(position.x, maxX)),
            y: max(minY, min(position.y, maxY))
        )
    }
    
    private func snapToEdgesIfNeeded(_ bounds: CGRect) {
        let center = CGPoint(x: pipFrame.midX, y: pipFrame.midY)
        let screenCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        
        var newOrigin = pipFrame.origin
        
        // Snap to left or right edge
        if center.x < screenCenter.x {
            // Snap to left
            if pipFrame.minX < edgeSnapDistance * 2 {
                newOrigin.x = edgeSnapDistance
            }
        } else {
            // Snap to right
            if pipFrame.maxX > bounds.maxX - edgeSnapDistance * 2 {
                newOrigin.x = bounds.maxX - pipFrame.width - edgeSnapDistance
            }
        }
        
        if newOrigin != pipFrame.origin {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                pipFrame.origin = newOrigin
            }
            
            hapticFeedback.impact(.light)
        }
    }
    
    public func handleDragGesture(_ value: DragGesture.Value) {
        isDragging = true
        
        let newPosition = CGPoint(
            x: pipFrame.minX + value.translation.x,
            y: pipFrame.minY + value.translation.y
        )
        
        updatePosition(newPosition)
        
        // Reset auto-hide timer while dragging
        resetAutoHideTimer()
    }
    
    public func handleDragEnd(_ value: DragGesture.Value) {
        isDragging = false
        
        // Final position adjustment
        let screenBounds = UIScreen.main.bounds
        snapToEdgesIfNeeded(screenBounds)
        
        // Resume auto-hide if enabled
        setupAutoHide()
        
        hapticFeedback.impact(.light)
        
        logDebug("PiP drag ended", category: .general, context: LogContext(customData: [
            "final_position": ["x": pipFrame.minX, "y": pipFrame.minY]
        ]))
    }
    
    // MARK: - Auto-hide Management
    
    private func setupAutoHide() {
        guard autoHide && !isMinimized else { return }
        
        resetAutoHideTimer()
    }
    
    private func resetAutoHideTimer() {
        cancelAutoHide()
        
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.minimizePiP()
            }
        }
    }
    
    private func cancelAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }
    
    // MARK: - Fallback Methods
    
    private func showFullScreenCatalog() {
        // Fallback to full-screen catalog when PiP is not supported
        logInfo("Showing full-screen catalog (PiP not supported)", category: .general)
    }
    
    private func showFullScreenItemDetail(_ item: FurnitureItem) {
        // Fallback to full-screen item detail
        logInfo("Showing full-screen item detail (PiP not supported)", category: .general, context: LogContext(customData: [
            "item_id": item.id.uuidString
        ]))
    }
    
    // MARK: - Item Selection
    
    public func selectItem(_ item: FurnitureItem) {
        hapticFeedback.selectionChanged()
        accessibilityManager.announce("Selected \(item.name)", priority: .normal)
        
        // Add item to AR scene
        addItemToARScene(item)
        
        logDebug("Item selected from PiP", category: .general, context: LogContext(customData: [
            "item_id": item.id.uuidString,
            "item_name": item.name
        ]))
    }
    
    private func addItemToARScene(_ item: FurnitureItem) {
        // Interface with AR system to add the selected item
        logInfo("Adding item to AR scene", category: .general, context: LogContext(customData: [
            "item_id": item.id.uuidString,
            "item_name": item.name
        ]))
    }
}

// MARK: - Picture-in-Picture View

public struct PictureInPictureView: View {
    @EnvironmentObject private var pipManager: PictureInPictureManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init() {}
    
    public var body: some View {
        Group {
            if pipManager.isPiPActive && pipManager.isPiPVisible {
                PiPWindow()
                    .frame(width: pipManager.pipFrame.width, height: pipManager.pipFrame.height)
                    .position(
                        x: pipManager.pipFrame.midX,
                        y: pipManager.pipFrame.midY
                    )
                    .scaleEffect(pipManager.isMinimized ? 0.9 : 1.0)
                    .opacity(pipManager.isDragging ? 0.9 : 1.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: pipManager.isMinimized)
                    .animation(.easeInOut(duration: 0.2), value: pipManager.isDragging)
                    .zIndex(1000) // Ensure PiP is always on top
            }
        }
    }
}

// MARK: - PiP Window

private struct PiPWindow: View {
    @EnvironmentObject private var pipManager: PictureInPictureManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            PiPHeader()
            
            // Content
            if !pipManager.isMinimized {
                PiPContent()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .gesture(
            DragGesture()
                .onChanged { value in
                    pipManager.handleDragGesture(value)
                }
                .onEnded { value in
                    pipManager.handleDragEnd(value)
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Picture-in-picture window")
    }
}

// MARK: - PiP Header

private struct PiPHeader: View {
    @EnvironmentObject private var pipManager: PictureInPictureManager
    
    var body: some View {
        HStack {
            // Title
            Text(headerTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Controls
            HStack(spacing: 8) {
                if !pipManager.isMinimized {
                    Button(action: { pipManager.minimizePiP() }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .accessibilityLabel("Minimize")
                } else {
                    Button(action: { pipManager.expandPiP() }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .accessibilityLabel("Expand")
                }
                
                Button(action: { pipManager.hidePiP() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.red)
                }
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    private var headerTitle: String {
        guard let content = pipManager.currentContent else { return "Picture-in-Picture" }
        
        switch content {
        case .furnitureCatalog:
            return "Furniture Catalog"
        case .itemDetail(let item):
            return item.name
        case .roomBrowser:
            return "Room Browser"
        case .settings:
            return "Settings"
        }
    }
}

// MARK: - PiP Content

private struct PiPContent: View {
    @EnvironmentObject private var pipManager: PictureInPictureManager
    
    var body: some View {
        Group {
            if let content = pipManager.currentContent {
                switch content {
                case .furnitureCatalog:
                    FurnitureCatalogPiP()
                case .itemDetail(let item):
                    ItemDetailPiP(item: item)
                case .roomBrowser:
                    RoomBrowserPiP()
                case .settings:
                    SettingsPiP()
                }
            } else {
                EmptyPiPContent()
            }
        }
        .padding(12)
    }
}

// MARK: - Furniture Catalog PiP

private struct FurnitureCatalogPiP: View {
    @EnvironmentObject private var pipManager: PictureInPictureManager
    
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            // Search and filter
            HStack(spacing: 8) {
                TextField("Search furniture...", text: $pipManager.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                
                Menu("Filter") {
                    Button("All") {
                        pipManager.clearFilters()
                    }
                    
                    ForEach(FurnitureCategory.allCases, id: \.self) { category in
                        Button(category.displayName) {
                            pipManager.filterByCategory(category)
                        }
                    }
                }
                .font(.caption)
            }
            
            // Items grid
            if pipManager.isLoading {
                ProgressView("Loading...")
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(pipManager.catalogItems, id: \.id) { item in
                            CatalogItemCard(item: item)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Catalog Item Card

private struct CatalogItemCard: View {
    let item: FurnitureItem
    @EnvironmentObject private var pipManager: PictureInPictureManager
    
    var body: some View {
        Button(action: { pipManager.selectItem(item) }) {
            VStack(spacing: 4) {
                // Placeholder image
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.3))
                    .frame(height: 60)
                    .overlay(
                        Image(systemName: "sofa.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    )
                
                Text(item.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel("Add \(item.name) to room")
    }
}

// MARK: - Item Detail PiP

private struct ItemDetailPiP: View {
    let item: FurnitureItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Item image placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(.gray.opacity(0.3))
                .frame(height: 80)
                .overlay(
                    Image(systemName: "sofa.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                )
            
            // Item details
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(item.category.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Action buttons
                HStack(spacing: 8) {
                    Button("Add to Room") {
                        // Add item to room
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.blue, in: Capsule())
                    .foregroundColor(.white)
                    
                    Button("Details") {
                        // Show full details
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.gray.opacity(0.2), in: Capsule())
                }
            }
            
            Spacer()
        }
    }
}

// MARK: - Room Browser PiP

private struct RoomBrowserPiP: View {
    var body: some View {
        VStack {
            Text("Room Browser")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text("Browse saved room designs")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}

// MARK: - Settings PiP

private struct SettingsPiP: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Settings")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            // Quick toggles
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Auto-place objects", isOn: .constant(true))
                    .font(.caption)
                
                Toggle("Show measurements", isOn: .constant(false))
                    .font(.caption)
                
                Toggle("Snap to surfaces", isOn: .constant(true))
                    .font(.caption)
            }
            
            Spacer()
        }
    }
}

// MARK: - Empty PiP Content

private struct EmptyPiPContent: View {
    var body: some View {
        VStack {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 30))
                .foregroundColor(.gray)
            
            Text("No content loaded")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Supporting Types

public enum PiPContent: Equatable {
    case furnitureCatalog
    case itemDetail(FurnitureItem)
    case roomBrowser
    case settings
    
    public static func == (lhs: PiPContent, rhs: PiPContent) -> Bool {
        switch (lhs, rhs) {
        case (.furnitureCatalog, .furnitureCatalog),
             (.roomBrowser, .roomBrowser),
             (.settings, .settings):
            return true
        case (.itemDetail(let lhsItem), .itemDetail(let rhsItem)):
            return lhsItem.id == rhsItem.id
        default:
            return false
        }
    }
}

// MARK: - Placeholder Types

public struct FurnitureItem: Identifiable {
    public let id: UUID
    public let name: String
    public let category: FurnitureCategory
    public let model3D: String
    public let metadata: FurnitureMetadata
    
    public init(id: UUID, name: String, category: FurnitureCategory, model3D: String, metadata: FurnitureMetadata) {
        self.id = id
        self.name = name
        self.category = category
        self.model3D = model3D
        self.metadata = metadata
    }
}

public enum FurnitureCategory: String, CaseIterable {
    case seating = "seating"
    case tables = "tables"
    case storage = "storage"
    case lighting = "lighting"
    case decor = "decor"
    case bedroom = "bedroom"
    
    public var displayName: String {
        return rawValue.capitalized
    }
}

public struct FurnitureMetadata {
    public init() {}
}