import Foundation
import UIKit
import SwiftUI
import SceneKit
import RealityKit

// MARK: - Share Preview Generator

@MainActor
public class SharePreviewGenerator {
    
    // MARK: - Configuration
    private let previewSize = CGSize(width: 1200, height: 1200)
    private let socialMediaSize = CGSize(width: 1080, height: 1080)
    private let videoThumbnailSize = CGSize(width: 1920, height: 1080)
    
    // MARK: - Preview Generation
    
    public func generateProjectPreview(_ project: Project) async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            let previewView = ProjectPreviewView(project: project)
            
            let hostingController = UIHostingController(rootView: previewView)
            hostingController.view.frame = CGRect(origin: .zero, size: previewSize)
            
            // Render the view
            let renderer = UIGraphicsImageRenderer(size: previewSize)
            let image = renderer.image { context in
                hostingController.view.layer.render(in: context.cgContext)
            }
            
            continuation.resume(returning: image)
        }
    }
    
    public func generateARSnapshotPreview(_ image: UIImage, metadata: ARSnapshotMetadata) async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            let previewView = ARSnapshotPreviewView(image: image, metadata: metadata)
            
            let hostingController = UIHostingController(rootView: previewView)
            hostingController.view.frame = CGRect(origin: .zero, size: socialMediaSize)
            
            let renderer = UIGraphicsImageRenderer(size: socialMediaSize)
            let enhancedImage = renderer.image { context in
                hostingController.view.layer.render(in: context.cgContext)
            }
            
            continuation.resume(returning: enhancedImage)
        }
    }
    
    public func generateVideoThumbnail(_ videoURL: URL) async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            let asset = AVAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            
            let time = CMTime(seconds: 1.0, preferredTimescale: 600)
            
            imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let cgImage = cgImage else {
                    continuation.resume(throwing: ShareError.imageConversionFailed)
                    return
                }
                
                let thumbnail = UIImage(cgImage: cgImage)
                continuation.resume(returning: thumbnail)
            }
        }
    }
    
    public func generate3DModelPreview(_ modelURL: URL) async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            // Create a SceneKit scene for 3D model preview
            let scene = SCNScene()
            
            // Load the 3D model
            guard let modelScene = try? SCNScene(url: modelURL) else {
                continuation.resume(throwing: ShareError.fileCreationFailed)
                return
            }
            
            // Add model to scene
            if let modelNode = modelScene.rootNode.childNodes.first {
                scene.rootNode.addChildNode(modelNode)
                
                // Position camera
                let cameraNode = SCNNode()
                cameraNode.camera = SCNCamera()
                cameraNode.position = SCNVector3(0, 0, 5)
                scene.rootNode.addChildNode(cameraNode)
                
                // Add lighting
                let lightNode = SCNNode()
                lightNode.light = SCNLight()
                lightNode.light?.type = .omni
                lightNode.position = SCNVector3(0, 10, 10)
                scene.rootNode.addChildNode(lightNode)
                
                // Render the scene
                let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
                renderer.scene = scene
                
                let image = renderer.snapshot(atTime: 0, with: previewSize, antialiasingMode: .multisampling4X)
                continuation.resume(returning: image)
            } else {
                continuation.resume(throwing: ShareError.fileCreationFailed)
            }
        }
    }
    
    public func generateAchievementCard(_ achievement: Achievement) async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            let cardView = AchievementCardView(achievement: achievement)
            
            let hostingController = UIHostingController(rootView: cardView)
            hostingController.view.frame = CGRect(origin: .zero, size: socialMediaSize)
            
            let renderer = UIGraphicsImageRenderer(size: socialMediaSize)
            let cardImage = renderer.image { context in
                hostingController.view.layer.render(in: context.cgContext)
            }
            
            continuation.resume(returning: cardImage)
        }
    }
}

// MARK: - Preview Views

struct ProjectPreviewView: View {
    let project: Project
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 20) {
                Spacer()
                
                // Project title
                Text(project.name)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(radius: 2)
                
                // Project description
                if let description = project.description {
                    Text(description)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 40)
                }
                
                Spacer()
                
                // App branding
                HStack(spacing: 16) {
                    Image(systemName: "arkit")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                    
                    Text("ARchitect")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 40)
            }
            
            // Decorative elements
            GeometryReader { geometry in
                ForEach(0..<20, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: CGFloat.random(in: 10...30))
                        .position(
                            x: CGFloat.random(in: 0...geometry.size.width),
                            y: CGFloat.random(in: 0...geometry.size.height)
                        )
                }
            }
        }
    }
}

struct ARSnapshotPreviewView: View {
    let image: UIImage
    let metadata: ARSnapshotMetadata
    
    var body: some View {
        ZStack {
            // Main image
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 1080, height: 1080)
                .clipped()
            
            // Overlay gradient
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            VStack {
                Spacer()
                
                // AR badge
                HStack {
                    Image(systemName: "arkit")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("AR")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.accentColor)
                )
                .shadow(radius: 4)
                
                Spacer().frame(height: 20)
                
                // Branding
                HStack(spacing: 12) {
                    Text("Created with")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("ARchitect")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 40)
            }
            
            // Corner watermark
            VStack {
                HStack {
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text(formatDate(metadata.captureDate))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct AchievementCardView: View {
    let achievement: Achievement
    
    var body: some View {
        ZStack {
            // Background
            RadialGradient(
                colors: [Color.yellow.opacity(0.3), Color.orange.opacity(0.8), Color.red.opacity(0.6)],
                center: .center,
                startRadius: 0,
                endRadius: 400
            )
            
            // Sparkle effects
            GeometryReader { geometry in
                ForEach(0..<30, id: \.self) { index in
                    Image(systemName: "sparkle")
                        .font(.system(size: CGFloat.random(in: 8...20)))
                        .foregroundColor(.yellow.opacity(0.8))
                        .position(
                            x: CGFloat.random(in: 0...geometry.size.width),
                            y: CGFloat.random(in: 0...geometry.size.height)
                        )
                        .rotationEffect(.degrees(Double.random(in: 0...360)))
                }
            }
            
            VStack(spacing: 30) {
                Spacer()
                
                // Achievement icon
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.yellow, Color.orange],
                                center: .center,
                                startRadius: 0,
                                endRadius: 60
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(radius: 10)
                    
                    Image(systemName: achievement.iconName)
                        .font(.system(size: 50, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Achievement title
                Text("Achievement Unlocked!")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
                
                Text(achievement.title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(radius: 2)
                
                // Achievement description
                Text(achievement.description)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 60)
                
                Spacer()
                
                // App branding
                HStack(spacing: 16) {
                    Image(systemName: "arkit")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                    
                    Text("ARchitect")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Supporting Types

public struct Achievement {
    public let title: String
    public let description: String
    public let iconName: String
    public let unlockedDate: Date
    
    public init(title: String, description: String, iconName: String, unlockedDate: Date = Date()) {
        self.title = title
        self.description = description
        self.iconName = iconName
        self.unlockedDate = unlockedDate
    }
}

// MARK: - Import Requirements

import AVFoundation