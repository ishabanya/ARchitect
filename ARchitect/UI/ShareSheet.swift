import SwiftUI
import UIKit

// MARK: - Share Sheet View

struct ShareSheet: View {
    let item: ShareableItem
    @StateObject private var shareManager = ShareManager()
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedDestination: ShareManager.ShareDestination?
    @State private var showingProgress = false
    
    private let destinations: [ShareManager.ShareDestination] = [
        .messages, .mail, .social, .photos, .airdrop, .files, .copy, .more
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Preview Section
                sharePreview
                    .padding()
                
                Divider()
                
                // Share Options
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 20) {
                        ForEach(destinations, id: \.self) { destination in
                            ShareDestinationButton(
                                destination: destination,
                                isSelected: selectedDestination == destination
                            ) {
                                selectedDestination = destination
                                performShare(to: destination)
                            }
                        }
                    }
                    .padding()
                }
                
                // Quick Actions
                if item.type == .arSnapshot {
                    quickActionsSection
                }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .overlay {
            if showingProgress {
                ShareProgressOverlay(progress: shareManager.shareProgress)
            }
        }
    }
    
    // MARK: - Preview Section
    
    private var sharePreview: some View {
        VStack(spacing: 16) {
            // Preview Image
            if let previewImage = item.previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
            }
            
            // Content Info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: item.type.icon)
                        .foregroundColor(.accentColor)
                    
                    Text(item.type.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                
                Text(item.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(item.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Quick Actions
    
    private var quickActionsSection: some View {
        VStack(spacing: 16) {
            Divider()
            
            HStack(spacing: 20) {
                QuickActionButton(
                    icon: "photo.badge.plus",
                    title: "Save to Photos",
                    action: {
                        Task {
                            if let image = item.previewImage {
                                await shareManager.quickShareToPhotos(image)
                            }
                        }
                    }
                )
                
                QuickActionButton(
                    icon: "doc.on.clipboard",
                    title: "Copy",
                    action: {
                        shareManager.quickCopyToClipboard(item)
                    }
                )
                
                QuickActionButton(
                    icon: "square.and.arrow.up",
                    title: "Share More",
                    action: {
                        selectedDestination = .more
                        performShare(to: .more)
                    }
                )
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Actions
    
    private func performShare(to destination: ShareManager.ShareDestination) {
        showingProgress = true
        
        Task {
            switch destination {
            case .photos:
                if let image = item.previewImage {
                    await shareManager.quickShareToPhotos(image)
                }
            case .copy:
                shareManager.quickCopyToClipboard(item)
            case .more:
                // This would trigger the system share sheet
                await shareManager.shareProject(Project(name: item.title, description: item.description))
            default:
                // Handle other destinations
                break
            }
            
            showingProgress = false
            
            // Auto-dismiss after successful share
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                dismiss()
            }
        }
    }
}

// MARK: - Share Destination Button

struct ShareDestinationButton: View {
    let destination: ShareManager.ShareDestination
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color(.systemGray5))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: destination.icon)
                        .font(.system(size: 24))
                        .foregroundColor(isSelected ? .white : .primary)
                }
                
                Text(destination.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Share Progress Overlay

struct ShareProgressOverlay: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView(value: progress)
                    .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                    .scaleEffect(1.5)
                
                Text("Sharing...")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

// MARK: - UIKit Integration

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]?
    let excludedActivityTypes: [UIActivity.ActivityType]?
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        controller.excludedActivityTypes = excludedActivityTypes
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - Share Button Modifier

struct ShareButtonModifier: ViewModifier {
    let item: ShareableItem
    @State private var showingShareSheet = false
    
    func body(content: Content) -> Content {
        content
            .onTapGesture {
                showingShareSheet = true
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(item: item)
            }
    }
}

extension View {
    func shareButton(item: ShareableItem) -> some View {
        modifier(ShareButtonModifier(item: item))
    }
}

// MARK: - Custom Share Activities

class ShareToInstagramActivity: UIActivity {
    override var activityType: UIActivity.ActivityType? {
        return UIActivity.ActivityType("com.architectar.shareToInstagram")
    }
    
    override var activityTitle: String? {
        return "Instagram"
    }
    
    override var activityImage: UIImage? {
        return UIImage(systemName: "camera.circle")
    }
    
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return activityItems.contains { $0 is UIImage }
    }
    
    override func perform() {
        // Implementation would share to Instagram Stories
        activityDidFinish(true)
    }
}

class ShareToTikTokActivity: UIActivity {
    override var activityType: UIActivity.ActivityType? {
        return UIActivity.ActivityType("com.architectar.shareToTikTok")
    }
    
    override var activityTitle: String? {
        return "TikTok"
    }
    
    override var activityImage: UIImage? {
        return UIImage(systemName: "music.note.tv")
    }
    
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return activityItems.contains { $0 is URL }
    }
    
    override func perform() {
        // Implementation would share to TikTok
        activityDidFinish(true)
    }
}

// MARK: - Preview

struct ShareSheet_Previews: PreviewProvider {
    static var previews: some View {
        ShareSheet(
            item: ShareableItem(
                type: .arSnapshot,
                title: "My AR Creation",
                description: "Amazing AR experience created with ARchitect",
                previewImage: nil,
                url: nil,
                metadata: nil
            )
        )
    }
}