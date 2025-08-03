import Foundation
import UIKit
import SwiftUI
import CoreImage
import Combine
import PencilKit

// MARK: - Screenshot Annotation System
@MainActor
public class ScreenshotAnnotationSystem: ObservableObject {
    public static let shared = ScreenshotAnnotationSystem()
    
    @Published public var isAnnotating = false
    @Published public var currentScreenshot: UIImage?
    @Published public var annotatedScreenshot: UIImage?
    @Published public var annotationTools: [AnnotationTool] = AnnotationTool.allCases
    @Published public var selectedTool: AnnotationTool = .arrow
    @Published public var selectedColor: Color = .red
    @Published public var strokeWidth: CGFloat = 3.0
    
    private let hapticManager = HapticFeedbackManager.shared
    private let analyticsManager = AnalyticsManager.shared
    
    private var canvasView: PKCanvasView?
    private var originalScreenshot: UIImage?
    
    private init() {}
    
    // MARK: - Public Methods
    
    public func startAnnotation(with screenshot: UIImage) {
        originalScreenshot = screenshot
        currentScreenshot = screenshot
        isAnnotating = true
        
        hapticManager.impact(.medium)
        
        analyticsManager.trackCustomEvent(
            name: "screenshot_annotation_started",
            parameters: [
                "screenshot_size": "\(Int(screenshot.size.width))x\(Int(screenshot.size.height))"
            ]
        )
    }
    
    public func finishAnnotation() -> UIImage? {
        defer {
            resetAnnotation()
        }
        
        guard let screenshot = currentScreenshot else { return nil }
        
        let finalImage = annotatedScreenshot ?? screenshot
        
        analyticsManager.trackCustomEvent(
            name: "screenshot_annotation_completed",
            parameters: [
                "has_annotations": annotatedScreenshot != nil,
                "tools_used": getUsedTools()
            ]
        )
        
        hapticManager.operationSuccess()
        
        return finalImage
    }
    
    public func cancelAnnotation() {
        resetAnnotation()
        hapticManager.impact(.light)
        
        analyticsManager.trackCustomEvent(name: "screenshot_annotation_cancelled")
    }
    
    public func addTextAnnotation(at point: CGPoint, text: String) {
        guard let screenshot = currentScreenshot else { return }
        
        let annotatedImage = addText(to: screenshot, text: text, at: point)
        annotatedScreenshot = annotatedImage
        currentScreenshot = annotatedImage
        
        hapticManager.impact(.light)
        
        analyticsManager.trackCustomEvent(
            name: "text_annotation_added",
            parameters: [
                "text_length": text.count,
                "position_x": point.x,
                "position_y": point.y
            ]
        )
    }
    
    public func addArrowAnnotation(from startPoint: CGPoint, to endPoint: CGPoint) {
        guard let screenshot = currentScreenshot else { return }
        
        let annotatedImage = addArrow(to: screenshot, from: startPoint, to: endPoint)
        annotatedScreenshot = annotatedImage
        currentScreenshot = annotatedImage
        
        hapticManager.impact(.light)
        
        analyticsManager.trackCustomEvent(
            name: "arrow_annotation_added",
            parameters: [
                "start_x": startPoint.x,
                "start_y": startPoint.y,
                "end_x": endPoint.x,
                "end_y": endPoint.y
            ]
        )
    }
    
    public func addHighlightAnnotation(rect: CGRect) {
        guard let screenshot = currentScreenshot else { return }
        
        let annotatedImage = addHighlight(to: screenshot, rect: rect)
        annotatedScreenshot = annotatedImage
        currentScreenshot = annotatedImage
        
        hapticManager.impact(.light)
        
        analyticsManager.trackCustomEvent(
            name: "highlight_annotation_added",
            parameters: [
                "rect_x": rect.origin.x,
                "rect_y": rect.origin.y,
                "rect_width": rect.width,
                "rect_height": rect.height
            ]
        )
    }
    
    public func addCircleAnnotation(center: CGPoint, radius: CGFloat) {
        guard let screenshot = currentScreenshot else { return }
        
        let annotatedImage = addCircle(to: screenshot, center: center, radius: radius)
        annotatedScreenshot = annotatedImage
        currentScreenshot = annotatedImage
        
        hapticManager.impact(.light)
        
        analyticsManager.trackCustomEvent(
            name: "circle_annotation_added",
            parameters: [
                "center_x": center.x,
                "center_y": center.y,
                "radius": radius
            ]
        )
    }
    
    public func addRectangleAnnotation(rect: CGRect) {
        guard let screenshot = currentScreenshot else { return }
        
        let annotatedImage = addRectangle(to: screenshot, rect: rect)
        annotatedScreenshot = annotatedImage
        currentScreenshot = annotatedImage
        
        hapticManager.impact(.light)
        
        analyticsManager.trackCustomEvent(
            name: "rectangle_annotation_added",
            parameters: [
                "rect_x": rect.origin.x,
                "rect_y": rect.origin.y,
                "rect_width": rect.width,
                "rect_height": rect.height
            ]
        )
    }
    
    public func undoLastAnnotation() {
        // Reset to original screenshot
        currentScreenshot = originalScreenshot
        annotatedScreenshot = nil
        
        hapticManager.impact(.light)
        
        analyticsManager.trackCustomEvent(name: "annotation_undone")
    }
    
    public func clearAllAnnotations() {
        currentScreenshot = originalScreenshot
        annotatedScreenshot = nil
        
        hapticManager.impact(.medium)
        
        analyticsManager.trackCustomEvent(name: "all_annotations_cleared")
    }
    
    // MARK: - Drawing Methods
    
    private func addText(to image: UIImage, text: String, at point: CGPoint) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        
        return renderer.image { context in
            image.draw(at: CGPoint.zero)
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: UIColor(selectedColor),
                .strokeColor: UIColor.white,
                .strokeWidth: -2.0
            ]
            
            let attributedString = NSAttributedString(string: text, attributes: attributes)
            let textSize = attributedString.size()
            
            let textRect = CGRect(
                x: point.x - textSize.width / 2,
                y: point.y - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            attributedString.draw(in: textRect)
        }
    }
    
    private func addArrow(to image: UIImage, from startPoint: CGPoint, to endPoint: CGPoint) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        
        return renderer.image { context in
            image.draw(at: CGPoint.zero)
            
            let cgContext = context.cgContext
            
            // Configure drawing
            cgContext.setStrokeColor(UIColor(selectedColor).cgColor)
            cgContext.setLineWidth(strokeWidth)
            cgContext.setLineCap(.round)
            
            // Draw arrow line
            cgContext.move(to: startPoint)
            cgContext.addLine(to: endPoint)
            cgContext.strokePath()
            
            // Calculate arrow head
            let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
            let arrowLength: CGFloat = 20
            let arrowAngle: CGFloat = .pi / 6
            
            let arrowPoint1 = CGPoint(
                x: endPoint.x - arrowLength * cos(angle - arrowAngle),
                y: endPoint.y - arrowLength * sin(angle - arrowAngle)
            )
            
            let arrowPoint2 = CGPoint(
                x: endPoint.x - arrowLength * cos(angle + arrowAngle),
                y: endPoint.y - arrowLength * sin(angle + arrowAngle)
            )
            
            // Draw arrow head
            cgContext.move(to: endPoint)
            cgContext.addLine(to: arrowPoint1)
            cgContext.move(to: endPoint)
            cgContext.addLine(to: arrowPoint2)
            cgContext.strokePath()
        }
    }
    
    private func addHighlight(to image: UIImage, rect: CGRect) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        
        return renderer.image { context in
            image.draw(at: CGPoint.zero)
            
            let cgContext = context.cgContext
            
            // Configure highlight
            cgContext.setFillColor(UIColor(selectedColor).withAlphaComponent(0.3).cgColor)
            cgContext.setStrokeColor(UIColor(selectedColor).cgColor)
            cgContext.setLineWidth(strokeWidth)
            
            // Draw highlight
            cgContext.fillEllipse(in: rect)
            cgContext.strokeEllipse(in: rect)
        }
    }
    
    private func addCircle(to image: UIImage, center: CGPoint, radius: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        
        return renderer.image { context in
            image.draw(at: CGPoint.zero)
            
            let cgContext = context.cgContext
            
            // Configure circle
            cgContext.setStrokeColor(UIColor(selectedColor).cgColor)
            cgContext.setLineWidth(strokeWidth)
            
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            
            cgContext.strokeEllipse(in: rect)
        }
    }
    
    private func addRectangle(to image: UIImage, rect: CGRect) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        
        return renderer.image { context in
            image.draw(at: CGPoint.zero)
            
            let cgContext = context.cgContext
            
            // Configure rectangle
            cgContext.setStrokeColor(UIColor(selectedColor).cgColor)
            cgContext.setLineWidth(strokeWidth)
            
            cgContext.stroke(rect)
        }
    }
    
    // MARK: - Helper Methods
    
    private func resetAnnotation() {
        isAnnotating = false
        currentScreenshot = nil
        annotatedScreenshot = nil
        originalScreenshot = nil
        selectedTool = .arrow
        selectedColor = .red
        strokeWidth = 3.0
    }
    
    private func getUsedTools() -> [String] {
        // This would track which tools were actually used during the session
        // For now, return the selected tool
        return [selectedTool.rawValue]
    }
}

// MARK: - Annotation Tools
public enum AnnotationTool: String, CaseIterable {
    case arrow = "arrow"
    case text = "text"
    case highlight = "highlight"
    case circle = "circle"
    case rectangle = "rectangle"
    case freehand = "freehand"
    
    var title: String {
        switch self {
        case .arrow: return "Arrow"
        case .text: return "Text"
        case .highlight: return "Highlight"
        case .circle: return "Circle"
        case .rectangle: return "Rectangle"
        case .freehand: return "Freehand"
        }
    }
    
    var icon: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .circle: return "circle"
        case .rectangle: return "rectangle"
        case .freehand: return "pencil"
        }
    }
}

// MARK: - Screenshot Manager
@MainActor
public class ScreenshotManager: ObservableObject {
    public static let shared = ScreenshotManager()
    
    private let analyticsManager = AnalyticsManager.shared
    private let fileManager = FileManager.default
    
    private var screenshotsDirectory: URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = documentsDirectory.appendingPathComponent("Screenshots")
        
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        
        return directory
    }
    
    private init() {}
    
    public func captureCurrentScreen() async -> String? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else {
            return nil
        }
        
        let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
        let screenshot = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        
        return await saveScreenshot(screenshot)
    }
    
    public func captureView(_ view: UIView) async -> String? {
        let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
        let screenshot = renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        
        return await saveScreenshot(screenshot)
    }
    
    public func saveScreenshot(_ image: UIImage) async -> String? {
        let filename = "screenshot_\(Int(Date().timeIntervalSince1970)).png"
        let url = screenshotsDirectory.appendingPathComponent(filename)
        
        guard let data = image.pngData() else { return nil }
        
        do {
            try data.write(to: url)
            
            analyticsManager.trackCustomEvent(
                name: "screenshot_saved",
                parameters: [
                    "filename": filename,
                    "size_bytes": data.count,
                    "image_size": "\(Int(image.size.width))x\(Int(image.size.height))"
                ]
            )
            
            return url.path
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "save_screenshot",
                "filename": filename
            ])
            
            return nil
        }
    }
    
    public func loadScreenshot(from path: String) -> UIImage? {
        return UIImage(contentsOfFile: path)
    }
    
    public func deleteScreenshot(at path: String) {
        let url = URL(fileURLWithPath: path)
        try? fileManager.removeItem(at: url)
        
        analyticsManager.trackCustomEvent(
            name: "screenshot_deleted",
            parameters: ["path": path]
        )
    }
    
    public func getAllScreenshots() -> [String] {
        do {
            let contents = try fileManager.contentsOfDirectory(at: screenshotsDirectory, 
                                                              includingPropertiesForKeys: [.creationDateKey],
                                                              options: [])
            
            return contents
                .filter { $0.pathExtension.lowercased() == "png" }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return date1 > date2
                }
                .map { $0.path }
            
        } catch {
            return []
        }
    }
    
    public func cleanupOldScreenshots(olderThan days: Int = 30) {
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(days * 24 * 3600))
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: screenshotsDirectory,
                                                              includingPropertiesForKeys: [.creationDateKey],
                                                              options: [])
            
            for url in contents {
                if let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey]),
                   let creationDate = resourceValues.creationDate,
                   creationDate < cutoffDate {
                    try? fileManager.removeItem(at: url)
                }
            }
            
            analyticsManager.trackCustomEvent(
                name: "screenshots_cleaned_up",
                parameters: ["cutoff_days": days]
            )
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "action": "cleanup_screenshots"
            ])
        }
    }
}