import Foundation
import SwiftUI
import UIKit
import Photos
import PhotosUI
import LinkPresentation

// MARK: - Share Manager

@MainActor
public class ShareManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published public var isSharing: Bool = false
    @Published public var shareProgress: Double = 0.0
    @Published public var lastSharedItem: ShareableItem?
    
    // MARK: - Share Types
    public enum ShareType {
        case project
        case arSnapshot
        case video
        case model3D
        case customization
        case achievement
        
        public var displayName: String {
            switch self {
            case .project: return "Project"
            case .arSnapshot: return "AR Snapshot"
            case .video: return "Video"
            case .model3D: return "3D Model"
            case .customization: return "Design"
            case .achievement: return "Achievement"
            }
        }
        
        public var icon: String {
            switch self {
            case .project: return "folder.fill"
            case .arSnapshot: return "camera.fill"
            case .video: return "video.fill"
            case .model3D: return "cube.fill"
            case .customization: return "paintbrush.fill"
            case .achievement: return "trophy.fill"
            }
        }
    }
    
    public enum ShareDestination {
        case messages
        case mail
        case social
        case files
        case photos
        case airdrop
        case copy
        case more
        
        public var displayName: String {
            switch self {
            case .messages: return "Messages"
            case .mail: return "Mail"
            case .social: return "Social"
            case .files: return "Files"
            case .photos: return "Photos"
            case .airdrop: return "AirDrop"
            case .copy: return "Copy"
            case .more: return "More"
            }
        }
        
        public var icon: String {
            switch self {
            case .messages: return "message.fill"
            case .mail: return "envelope.fill"
            case .social: return "network"
            case .files: return "folder.fill"
            case .photos: return "photo.fill"
            case .airdrop: return "wifi"
            case .copy: return "doc.on.clipboard.fill"
            case .more: return "ellipsis.circle.fill"
            }
        }
    }
    
    // MARK: - Private Properties
    private var previewGenerator: SharePreviewGenerator
    private var soundManager = SoundEffectsManager()
    
    public override init() {
        self.previewGenerator = SharePreviewGenerator()
        super.init()
        
        logInfo("Share Manager initialized", category: .sharing)
    }
    
    // MARK: - Share Methods
    
    public func shareProject(_ project: Project, from sourceView: UIView? = nil) async {
        await performShare {
            let shareableItem = try await createProjectShareableItem(project)
            await presentShareSheet(for: shareableItem, from: sourceView)
        }
    }
    
    public func shareARSnapshot(_ image: UIImage, metadata: ARSnapshotMetadata, from sourceView: UIView? = nil) async {
        await performShare {
            let shareableItem = try await createARSnapshotShareableItem(image, metadata: metadata)
            await presentShareSheet(for: shareableItem, from: sourceView)
        }
    }
    
    public func shareVideo(_ videoURL: URL, metadata: VideoMetadata, from sourceView: UIView? = nil) async {
        await performShare {
            let shareableItem = try await createVideoShareableItem(videoURL, metadata: metadata)
            await presentShareSheet(for: shareableItem, from: sourceView)
        }
    }
    
    public func share3DModel(_ modelURL: URL, metadata: Model3DMetadata, from sourceView: UIView? = nil) async {
        await performShare {
            let shareableItem = try await create3DModelShareableItem(modelURL, metadata: metadata)
            await presentShareSheet(for: shareableItem, from: sourceView)
        }
    }
    
    public func shareAchievement(_ achievement: Achievement, from sourceView: UIView? = nil) async {
        await performShare {
            let shareableItem = try await createAchievementShareableItem(achievement)
            await presentShareSheet(for: shareableItem, from: sourceView)
        }
    }
    
    private func performShare(_ shareAction: @escaping () async throws -> Void) async {
        guard !isSharing else { return }
        
        isSharing = true
        shareProgress = 0.0
        
        do {
            try await shareAction()
            soundManager.playSound(.projectShare, withHaptic: true)
        } catch {
            logError("Share failed", category: .sharing, error: error)
            await showShareError(error)
        }
        
        isSharing = false
        shareProgress = 1.0
    }
    
    // MARK: - Shareable Item Creation
    
    private func createProjectShareableItem(_ project: Project) async throws -> ShareableItem {
        updateProgress(0.2)
        
        // Generate preview image
        let previewImage = try await previewGenerator.generateProjectPreview(project)
        updateProgress(0.5)
        
        // Create project bundle
        let projectBundle = try await createProjectBundle(project)
        updateProgress(0.8)
        
        let shareableItem = ShareableItem(
            type: .project,
            title: project.name,
            description: project.description ?? "Created with ARchitect",
            previewImage: previewImage,
            url: projectBundle,
            metadata: ProjectShareMetadata(
                project: project,
                createdDate: Date(),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            )
        )
        
        updateProgress(1.0)
        lastSharedItem = shareableItem
        
        return shareableItem
    }
    
    private func createARSnapshotShareableItem(_ image: UIImage, metadata: ARSnapshotMetadata) async throws -> ShareableItem {
        updateProgress(0.3)
        
        // Generate enhanced preview with AR branding
        let enhancedImage = try await previewGenerator.generateARSnapshotPreview(image, metadata: metadata)
        updateProgress(0.7)
        
        // Save to temporary file
        let imageURL = try await saveImageToTemporaryFile(enhancedImage)
        updateProgress(0.9)
        
        let shareableItem = ShareableItem(
            type: .arSnapshot,
            title: "AR Creation",
            description: "Created with ARchitect - Augmented Reality Designer",
            previewImage: enhancedImage,
            url: imageURL,
            metadata: metadata
        )
        
        updateProgress(1.0)
        lastSharedItem = shareableItem
        
        return shareableItem
    }
    
    private func createVideoShareableItem(_ videoURL: URL, metadata: VideoMetadata) async throws -> ShareableItem {
        updateProgress(0.2)
        
        // Generate video thumbnail
        let thumbnail = try await previewGenerator.generateVideoThumbnail(videoURL)
        updateProgress(0.5)
        
        // Add watermark to video if needed
        let processedVideoURL = try await addWatermarkToVideo(videoURL)
        updateProgress(0.9)
        
        let shareableItem = ShareableItem(
            type: .video,
            title: metadata.title ?? "AR Video",
            description: "AR experience captured with ARchitect",
            previewImage: thumbnail,
            url: processedVideoURL,
            metadata: metadata
        )
        
        updateProgress(1.0)
        lastSharedItem = shareableItem
        
        return shareableItem
    }
    
    private func create3DModelShareableItem(_ modelURL: URL, metadata: Model3DMetadata) async throws -> ShareableItem {
        updateProgress(0.3)
        
        // Generate 3D model preview
        let previewImage = try await previewGenerator.generate3DModelPreview(modelURL)
        updateProgress(0.7)
        
        // Create model package with metadata
        let modelPackage = try await createModelPackage(modelURL, metadata: metadata)
        updateProgress(0.9)
        
        let shareableItem = ShareableItem(
            type: .model3D,
            title: metadata.name,
            description: "3D model created with ARchitect",
            previewImage: previewImage,
            url: modelPackage,
            metadata: metadata
        )
        
        updateProgress(1.0)
        lastSharedItem = shareableItem
        
        return shareableItem
    }
    
    private func createAchievementShareableItem(_ achievement: Achievement) async throws -> ShareableItem {
        updateProgress(0.3)
        
        // Generate achievement card
        let achievementCard = try await previewGenerator.generateAchievementCard(achievement)
        updateProgress(0.8)
        
        // Save achievement card
        let cardURL = try await saveImageToTemporaryFile(achievementCard)
        updateProgress(0.9)
        
        let shareableItem = ShareableItem(
            type: .achievement,
            title: "Achievement Unlocked!",
            description: "\(achievement.title) - \(achievement.description)",
            previewImage: achievementCard,
            url: cardURL,
            metadata: achievement
        )
        
        updateProgress(1.0)
        lastSharedItem = shareableItem
        
        return shareableItem
    }
    
    // MARK: - Share Presentation
    
    private func presentShareSheet(for item: ShareableItem, from sourceView: UIView?) async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw ShareError.noViewController
        }
        
        let activityViewController = UIActivityViewController(
            activityItems: [ShareActivityItemSource(item: item)],
            applicationActivities: [SaveToPhotosActivity(), CopyLinkActivity()]
        )
        
        // Configure for iPad
        if let popover = activityViewController.popoverPresentationController {
            if let sourceView = sourceView {
                popover.sourceView = sourceView
                popover.sourceRect = sourceView.bounds
            } else {
                popover.sourceView = rootViewController.view
                popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
            }
        }
        
        // Exclude certain activities for specific content types
        activityViewController.excludedActivityTypes = getExcludedActivities(for: item.type)
        
        // Present the share sheet
        await withCheckedContinuation { continuation in
            activityViewController.completionWithItemsHandler = { activityType, completed, returnedItems, error in
                if let error = error {
                    logError("Share completion error", category: .sharing, error: error)
                } else if completed {
                    logInfo("Share completed successfully", category: .sharing, context: LogContext(customData: [
                        "activity_type": activityType?.rawValue ?? "unknown",
                        "item_type": item.type.displayName
                    ]))
                }
                continuation.resume()
            }
            
            rootViewController.present(activityViewController, animated: true)
        }
    }
    
    private func getExcludedActivities(for type: ShareType) -> [UIActivity.ActivityType] {
        switch type {
        case .project:
            return [.assignToContact, .addToReadingList]
        case .arSnapshot:
            return [.assignToContact]
        case .video:
            return [.assignToContact, .addToReadingList]
        case .model3D:
            return [.assignToContact, .addToReadingList, .postToFacebook, .postToTwitter]
        case .customization:
            return [.assignToContact]
        case .achievement:
            return [.assignToContact, .addToReadingList]
        }
    }
    
    // MARK: - Utility Methods
    
    private func updateProgress(_ progress: Double) {
        shareProgress = progress
    }
    
    private func createProjectBundle(_ project: Project) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let bundleURL = tempDir.appendingPathComponent("\(project.name).arproject")
        
        // Create project bundle with all assets
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        
        // Add project data
        let projectData = try JSONEncoder().encode(project)
        try projectData.write(to: bundleURL.appendingPathComponent("project.json"))
        
        // Add preview image
        if let previewImage = try? await previewGenerator.generateProjectPreview(project),
           let imageData = previewImage.pngData() {
            try imageData.write(to: bundleURL.appendingPathComponent("preview.png"))
        }
        
        return bundleURL
    }
    
    private func saveImageToTemporaryFile(_ image: UIImage) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let imageURL = tempDir.appendingPathComponent("\(UUID().uuidString).png")
        
        guard let imageData = image.pngData() else {
            throw ShareError.imageConversionFailed
        }
        
        try imageData.write(to: imageURL)
        return imageURL
    }
    
    private func addWatermarkToVideo(_ videoURL: URL) async throws -> URL {
        // For now, return the original URL
        // In a full implementation, you would add watermark using AVFoundation
        return videoURL
    }
    
    private func createModelPackage(_ modelURL: URL, metadata: Model3DMetadata) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let packageURL = tempDir.appendingPathComponent("\(metadata.name).armodel")
        
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        
        // Copy model file
        let modelFileName = modelURL.lastPathComponent
        try FileManager.default.copyItem(at: modelURL, to: packageURL.appendingPathComponent(modelFileName))
        
        // Add metadata
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: packageURL.appendingPathComponent("metadata.json"))
        
        return packageURL
    }
    
    private func showShareError(_ error: Error) async {
        // In a full implementation, you would show an error alert
        logError("Share error occurred", category: .sharing, error: error)
    }
    
    // MARK: - Quick Share Methods
    
    public func quickShareToPhotos(_ image: UIImage) async {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            }
            soundManager.playSound(.successSound, withHaptic: true)
        } catch {
            logError("Failed to save to photos", category: .sharing, error: error)
            soundManager.playSound(.errorSound, withHaptic: true)
        }
    }
    
    public func quickCopyToClipboard(_ item: ShareableItem) {
        if let image = item.previewImage {
            UIPasteboard.general.image = image
        } else if let url = item.url {
            UIPasteboard.general.url = url
        } else {
            UIPasteboard.general.string = "\(item.title) - \(item.description)"
        }
        
        soundManager.playSound(.successSound, withHaptic: true)
    }
}

// MARK: - Shareable Item

public struct ShareableItem {
    public let type: ShareManager.ShareType
    public let title: String
    public let description: String
    public let previewImage: UIImage?
    public let url: URL?
    public let metadata: Any?
    
    public init(type: ShareManager.ShareType, title: String, description: String, previewImage: UIImage?, url: URL?, metadata: Any?) {
        self.type = type
        self.title = title
        self.description = description
        self.previewImage = previewImage
        self.url = url
        self.metadata = metadata
    }
}

// MARK: - Share Metadata Types

public struct ProjectShareMetadata: Codable {
    public let project: Project
    public let createdDate: Date
    public let appVersion: String
}

public struct ARSnapshotMetadata: Codable {
    public let captureDate: Date
    public let cameraPosition: [Float]
    public let lightingEstimate: Float?
    public let deviceModel: String
    public let appVersion: String
}

public struct VideoMetadata: Codable {
    public let title: String?
    public let duration: TimeInterval
    public let resolution: CGSize
    public let captureDate: Date
    public let deviceModel: String
}

public struct Model3DMetadata: Codable {
    public let name: String
    public let format: String
    public let fileSize: Int64
    public let vertexCount: Int?
    public let triangleCount: Int?
    public let createdDate: Date
}

// MARK: - Share Activity Item Source

class ShareActivityItemSource: NSObject, UIActivityItemSource {
    private let item: ShareableItem
    
    init(item: ShareableItem) {
        self.item = item
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return item.url ?? item.previewImage ?? item.title
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        switch activityType {
        case .message, .mail:
            return item.url ?? item.previewImage
        case .copyToPasteboard:
            return item.url ?? item.previewImage
        case .saveToCameraRoll:
            return item.previewImage
        default:
            return item.url ?? item.previewImage ?? item.title
        }
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return item.title
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        if let url = item.url {
            return url.pathExtension == "png" ? "public.png" : "public.data"
        } else if item.previewImage != nil {
            return "public.png"
        } else {
            return "public.plain-text"
        }
    }
}

// MARK: - Custom Activities

class SaveToPhotosActivity: UIActivity {
    override var activityType: UIActivity.ActivityType? {
        return UIActivity.ActivityType("com.architectar.saveToPhotos")
    }
    
    override var activityTitle: String? {
        return "Save to Photos"
    }
    
    override var activityImage: UIImage? {
        return UIImage(systemName: "photo.on.rectangle.angled")
    }
    
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return activityItems.contains { $0 is UIImage }
    }
    
    override func perform() {
        // Implementation would save to photos
        activityDidFinish(true)
    }
}

class CopyLinkActivity: UIActivity {
    override var activityType: UIActivity.ActivityType? {
        return UIActivity.ActivityType("com.architectar.copyLink")
    }
    
    override var activityTitle: String? {
        return "Copy Link"
    }
    
    override var activityImage: UIImage? {
        return UIImage(systemName: "link")
    }
    
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return activityItems.contains { $0 is URL }
    }
    
    override func perform() {
        // Implementation would copy link
        activityDidFinish(true)
    }
}

// MARK: - Share Errors

public enum ShareError: Error, LocalizedError {
    case noViewController
    case imageConversionFailed
    case fileCreationFailed
    case permissionDenied
    
    public var errorDescription: String? {
        switch self {
        case .noViewController:
            return "Could not find a view controller to present sharing interface"
        case .imageConversionFailed:
            return "Failed to convert image for sharing"
        case .fileCreationFailed:
            return "Failed to create file for sharing"
        case .permissionDenied:
            return "Permission denied for sharing operation"
        }
    }
}