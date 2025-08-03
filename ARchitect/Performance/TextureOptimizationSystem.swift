import Foundation
import UIKit
import SceneKit
import RealityKit
import Metal
import MetalKit
import ImageIO
import Combine
import Compression

// MARK: - Texture Optimization System

@MainActor
public class TextureOptimizationSystem: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var textureStats: TextureStatistics = TextureStatistics()
    @Published public var compressionStats: CompressionStatistics = CompressionStatistics()
    @Published public var isOptimizing: Bool = false
    @Published public var currentQualityLevel: TextureQuality = .automatic
    
    // MARK: - Configuration
    public enum TextureQuality: String, CaseIterable {
        case low = "Low"
        case medium = "Medium" 
        case high = "High"
        case ultra = "Ultra"
        case automatic = "Automatic"
        
        var maxTextureSize: Int {
            switch self {
            case .low: return 512
            case .medium: return 1024
            case .high: return 2048
            case .ultra: return 4096
            case .automatic: return 0 // Will be determined dynamically
            }
        }
        
        var compressionQuality: Float {
            switch self {
            case .low: return 0.3
            case .medium: return 0.5
            case .high: return 0.7
            case .ultra: return 0.9
            case .automatic: return 0.6
            }
        }
        
        var usesMipmaps: Bool {
            switch self {
            case .low: return false
            case .medium, .high, .ultra, .automatic: return true
            }
        }
        
        var compressionFormat: TextureCompressionFormat {
            switch self {
            case .low: return .astc4x4
            case .medium: return .astc6x6
            case .high: return .astc8x8
            case .ultra: return .rgba8
            case .automatic: return .automatic
            }
        }
    }
    
    public enum TextureCompressionFormat {
        case rgba8
        case rgba4
        case astc4x4
        case astc6x6
        case astc8x8
        case bc7
        case etc2
        case automatic
        
        var metalPixelFormat: MTLPixelFormat {
            switch self {
            case .rgba8: return .rgba8Unorm
            case .rgba4: return .abgr4Unorm
            case .astc4x4: return .astc_4x4_ldr
            case .astc6x6: return .astc_6x6_ldr
            case .astc8x8: return .astc_8x8_ldr
            case .bc7: return .bc7_rgbaUnorm
            case .etc2: return .etc2_rgb8
            case .automatic: return .rgba8Unorm
            }
        }
        
        var compressionRatio: Float {
            switch self {
            case .rgba8: return 1.0
            case .rgba4: return 2.0
            case .astc4x4: return 8.0
            case .astc6x6: return 5.33
            case .astc8x8: return 4.0
            case .bc7: return 4.0
            case .etc2: return 6.0
            case .automatic: return 6.0
            }
        }
    }
    
    // MARK: - Private Properties
    private var textureCache: NSCache<NSString, OptimizedTexture> = NSCache()
    private var loadingQueue = DispatchQueue(label: "com.architectar.texture.loading", qos: .userInitiated)
    private var compressionQueue = DispatchQueue(label: "com.architectar.texture.compression", qos: .utility)
    
    private var metalDevice: MTLDevice?
    private var textureLoader: MTKTextureLoader?
    private var performanceProfiler: InstrumentsProfiler
    
    // Adaptive quality system
    private var deviceCapabilities: DeviceCapabilities
    private var memoryPressure: MemoryPressureLevel = .normal
    private var thermalState: ProcessInfo.ThermalState = .nominal
    
    // Texture streaming
    private var streamingManager: TextureStreamingManager
    private var lodManager: TextureLODManager
    
    // Statistics tracking
    private var loadedTextures: [String: TextureLoadInfo] = [:]
    private var compressionTimes: [TimeInterval] = []
    private var memoryUsage: UInt64 = 0
    
    private var cancellables = Set<AnyCancellable>()
    
    public init(performanceProfiler: InstrumentsProfiler) {
        self.performanceProfiler = performanceProfiler
        self.deviceCapabilities = DeviceCapabilities()
        self.streamingManager = TextureStreamingManager()
        self.lodManager = TextureLODManager()
        
        setupMetal()
        setupCaching()
        setupMonitoring()
        
        logDebug("Texture optimization system initialized", category: .performance)
    }
    
    // MARK: - Setup
    
    private func setupMetal() {
        metalDevice = MTLCreateSystemDefaultDevice()
        
        if let device = metalDevice {
            textureLoader = MTKTextureLoader(device: device)
            logInfo("Metal texture loading enabled", category: .performance, context: LogContext(customData: [
                "device_name": device.name
            ]))
        } else {
            logError("Failed to create Metal device", category: .performance)
        }
    }
    
    private func setupCaching() {
        textureCache.countLimit = 100
        textureCache.totalCostLimit = 500 * 1024 * 1024 // 500MB
        
        // Monitor memory warnings to clear cache
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
    }
    
    private func setupMonitoring() {
        // Monitor thermal state changes
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateThermalState()
            }
            .store(in: &cancellables)
        
        // Periodic quality adjustment
        Timer.publish(every: 30.0, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.adjustQualityBasedOnConditions()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Texture Loading
    
    public func loadTexture(
        from url: URL,
        quality: TextureQuality? = nil,
        completion: @escaping (Result<OptimizedTexture, Error>) -> Void
    ) {
        let effectiveQuality = quality ?? currentQualityLevel
        let cacheKey = generateCacheKey(url: url, quality: effectiveQuality)
        
        // Check cache first
        if let cachedTexture = textureCache.object(forKey: cacheKey as NSString) {
            completion(.success(cachedTexture))
            textureStats.incrementCacheHits()
            return
        }
        
        textureStats.incrementCacheMisses()
        
        loadingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let startTime = Date()
            self.performanceProfiler.beginModelLoading(
                modelName: "texture_\(url.lastPathComponent)",
                fileSize: self.getFileSize(url: url)
            )
            
            do {
                let optimizedTexture = try self.loadAndOptimizeTexture(
                    from: url,
                    quality: effectiveQuality
                )
                
                // Cache the optimized texture
                let cost = Int(optimizedTexture.memorySize)
                self.textureCache.setObject(optimizedTexture, forKey: cacheKey as NSString, cost: cost)
                
                // Update statistics
                let loadTime = Date().timeIntervalSince(startTime)
                self.updateLoadStatistics(url: url, loadTime: loadTime, memorySize: optimizedTexture.memorySize)
                
                self.performanceProfiler.endModelLoading(
                    modelName: "texture_\(url.lastPathComponent)",
                    success: true,
                    loadTime: loadTime
                )
                
                DispatchQueue.main.async {
                    completion(.success(optimizedTexture))
                }
                
            } catch {
                self.performanceProfiler.endModelLoading(
                    modelName: "texture_\(url.lastPathComponent)",
                    success: false,
                    loadTime: Date().timeIntervalSince(startTime)
                )
                
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    public func loadTextureAsync(
        from url: URL,
        quality: TextureQuality? = nil
    ) async throws -> OptimizedTexture {
        return try await withCheckedThrowingContinuation { continuation in
            loadTexture(from: url, quality: quality) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    // MARK: - Texture Optimization
    
    private func loadAndOptimizeTexture(from url: URL, quality: TextureQuality) throws -> OptimizedTexture {
        // Load the original image
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let originalImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw TextureError.failedToLoadImage
        }
        
        // Get original properties
        let originalWidth = originalImage.width
        let originalHeight = originalImage.height
        let originalSize = originalWidth * originalHeight * 4 // Assume RGBA
        
        logDebug("Loading texture", category: .performance, context: LogContext(customData: [
            "url": url.lastPathComponent,
            "original_size": "\(originalWidth)x\(originalHeight)",
            "quality": quality.rawValue
        ]))
        
        // Determine optimal size based on quality and device capabilities
        let optimalSize = determineOptimalTextureSize(
            originalWidth: originalWidth,
            originalHeight: originalHeight,
            quality: quality
        )
        
        // Resize if necessary
        let resizedImage = if optimalSize.width != originalWidth || optimalSize.height != originalHeight {
            try resizeImage(originalImage, to: optimalSize)
        } else {
            originalImage
        }
        
        // Apply compression
        let compressionFormat = determineCompressionFormat(quality: quality)
        let compressedData = try compressImage(resizedImage, format: compressionFormat, quality: quality)
        
        // Create optimized texture
        let optimizedTexture = OptimizedTexture(
            data: compressedData,
            width: optimalSize.width,
            height: optimalSize.height,
            format: compressionFormat,
            originalSize: originalSize,
            memorySize: compressedData.count,
            url: url,
            quality: quality,
            hasMipmaps: quality.usesMipmaps
        )
        
        // Generate mipmaps if enabled
        if quality.usesMipmaps {
            optimizedTexture.mipmaps = try generateMipmaps(for: resizedImage)
        }
        
        logInfo("Texture optimized", category: .performance, context: LogContext(customData: [
            "original_size": originalSize,
            "compressed_size": compressedData.count,
            "compression_ratio": Float(originalSize) / Float(compressedData.count),
            "format": String(describing: compressionFormat)
        ]))
        
        return optimizedTexture
    }
    
    // MARK: - Image Processing
    
    private func resizeImage(_ image: CGImage, to size: CGSize) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TextureError.failedToCreateContext
        }
        
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        
        context.draw(image, in: CGRect(origin: .zero, size: size))
        
        guard let resizedImage = context.makeImage() else {
            throw TextureError.failedToResizeImage
        }
        
        return resizedImage
    }
    
    private func compressImage(_ image: CGImage, format: TextureCompressionFormat, quality: TextureQuality) throws -> Data {
        let startTime = Date()
        
        switch format {
        case .rgba8:
            return try compressToRGBA8(image)
        case .rgba4:
            return try compressToRGBA4(image)
        case .astc4x4, .astc6x6, .astc8x8:
            return try compressToASTC(image, format: format, quality: quality.compressionQuality)
        case .bc7:
            return try compressToBC7(image, quality: quality.compressionQuality)
        case .etc2:
            return try compressToETC2(image, quality: quality.compressionQuality)
        case .automatic:
            return try compressToOptimalFormat(image, quality: quality)
        }
    }
    
    private func compressToRGBA8(_ image: CGImage) throws -> Data {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        
        var pixelData = Data(count: height * bytesPerRow)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: pixelData.withUnsafeMutableBytes { $0.baseAddress },
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TextureError.failedToCreateContext
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return pixelData
    }
    
    private func compressToRGBA4(_ image: CGImage) throws -> Data {
        // Convert RGBA8 to RGBA4 (16-bit per pixel)
        let rgba8Data = try compressToRGBA8(image)
        let width = image.width
        let height = image.height
        
        var rgba4Data = Data(count: width * height * 2) // 2 bytes per pixel
        
        rgba8Data.withUnsafeBytes { rgba8Bytes in
            rgba4Data.withUnsafeMutableBytes { rgba4Bytes in
                let rgba8Ptr = rgba8Bytes.bindMemory(to: UInt8.self)
                let rgba4Ptr = rgba4Bytes.bindMemory(to: UInt16.self)
                
                for i in 0..<(width * height) {
                    let r8 = rgba8Ptr[i * 4]
                    let g8 = rgba8Ptr[i * 4 + 1]
                    let b8 = rgba8Ptr[i * 4 + 2]
                    let a8 = rgba8Ptr[i * 4 + 3]
                    
                    let r4 = UInt16(r8 >> 4)
                    let g4 = UInt16(g8 >> 4)
                    let b4 = UInt16(b8 >> 4)
                    let a4 = UInt16(a8 >> 4)
                    
                    rgba4Ptr[i] = (a4 << 12) | (b4 << 8) | (g4 << 4) | r4
                }
            }
        }
        
        return rgba4Data
    }
    
    private func compressToASTC(_ image: CGImage, format: TextureCompressionFormat, quality: Float) throws -> Data {
        // ASTC compression using Metal Performance Shaders or external library
        // For now, we'll use a simplified approach
        
        guard let device = metalDevice,
              let commandQueue = device.makeCommandQueue() else {
            throw TextureError.metalNotAvailable
        }
        
        // Convert to Metal texture
        let rgba8Data = try compressToRGBA8(image)
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: image.width,
            height: image.height,
            mipmapped: false
        )
        
        guard let inputTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw TextureError.failedToCreateTexture
        }
        
        inputTexture.replace(
            region: MTLRegionMake2D(0, 0, image.width, image.height),
            mipmapLevel: 0,
            with: rgba8Data.withUnsafeBytes { $0.baseAddress! },
            bytesPerRow: image.width * 4
        )
        
        // For now, return RGBA8 data (actual ASTC compression would require specialized libraries)
        return rgba8Data
    }
    
    private func compressToBC7(_ image: CGImage, quality: Float) throws -> Data {
        // BC7 compression (DirectX format, mainly for Windows/Xbox)
        // On iOS, fall back to RGBA8 or use alternative compression
        return try compressToRGBA8(image)
    }
    
    private func compressToETC2(_ image: CGImage, quality: Float) throws -> Data {
        // ETC2 compression (supported on many mobile GPUs)
        // Implementation would use specialized compression library
        return try compressToRGBA8(image)
    }
    
    private func compressToOptimalFormat(_ image: CGImage, quality: TextureQuality) throws -> Data {
        // Determine the best format based on device capabilities
        let optimalFormat = deviceCapabilities.getOptimalCompressionFormat()
        return try compressImage(image, format: optimalFormat, quality: quality)
    }
    
    // MARK: - Mipmap Generation
    
    private func generateMipmaps(for image: CGImage) throws -> [Data] {
        var mipmaps: [Data] = []
        var currentImage = image
        var currentWidth = image.width
        var currentHeight = image.height
        
        // Generate mipmaps until we reach 1x1
        while currentWidth > 1 || currentHeight > 1 {
            currentWidth = max(1, currentWidth / 2)
            currentHeight = max(1, currentHeight / 2)
            
            let mipmapSize = CGSize(width: currentWidth, height: currentHeight)
            let mipmapImage = try resizeImage(currentImage, to: mipmapSize)
            let mipmapData = try compressToRGBA8(mipmapImage)
            
            mipmaps.append(mipmapData)
            currentImage = mipmapImage
        }
        
        return mipmaps
    }
    
    // MARK: - Quality Determination
    
    private func determineOptimalTextureSize(originalWidth: Int, originalHeight: Int, quality: TextureQuality) -> CGSize {
        var maxSize = quality.maxTextureSize
        
        // For automatic quality, determine based on device capabilities and conditions
        if quality == .automatic {
            maxSize = deviceCapabilities.getMaxTextureSize()
            
            // Adjust based on memory pressure
            switch memoryPressure {
            case .critical:
                maxSize = min(maxSize, 512)
            case .warning:
                maxSize = min(maxSize, 1024)
            case .normal:
                break
            }
            
            // Adjust based on thermal state
            switch thermalState {
            case .critical, .serious:
                maxSize = min(maxSize, 1024)
            default:
                break
            }
        }
        
        // Calculate optimal size maintaining aspect ratio
        let aspectRatio = Float(originalWidth) / Float(originalHeight)
        
        let optimalWidth: Int
        let optimalHeight: Int
        
        if originalWidth >= originalHeight {
            optimalWidth = min(originalWidth, maxSize)
            optimalHeight = min(originalHeight, Int(Float(optimalWidth) / aspectRatio))
        } else {
            optimalHeight = min(originalHeight, maxSize)
            optimalWidth = min(originalWidth, Int(Float(optimalHeight) * aspectRatio))
        }
        
        // Ensure power-of-two sizes for better GPU performance
        return CGSize(
            width: nextPowerOfTwo(optimalWidth),
            height: nextPowerOfTwo(optimalHeight)
        )
    }
    
    private func determineCompressionFormat(quality: TextureQuality) -> TextureCompressionFormat {
        if quality == .automatic {
            return deviceCapabilities.getOptimalCompressionFormat()
        }
        return quality.compressionFormat
    }
    
    private func nextPowerOfTwo(_ value: Int) -> Int {
        guard value > 0 else { return 1 }
        return Int(pow(2, ceil(log2(Double(value)))))
    }
    
    // MARK: - Adaptive Quality
    
    private func adjustQualityBasedOnConditions() {
        guard currentQualityLevel == .automatic else { return }
        
        var recommendedQuality: TextureQuality = .medium
        
        // Factor in memory pressure
        switch memoryPressure {
        case .critical:
            recommendedQuality = .low
        case .warning:
            recommendedQuality = .medium
        case .normal:
            recommendedQuality = .high
        }
        
        // Factor in thermal state
        switch thermalState {
        case .critical:
            recommendedQuality = .low
        case .serious:
            recommendedQuality = .medium
        case .fair:
            recommendedQuality = max(recommendedQuality, .medium)
        case .nominal:
            break
        @unknown default:
            break
        }
        
        // Factor in device capabilities
        if !deviceCapabilities.supportsHighQualityTextures {
            recommendedQuality = min(recommendedQuality, .medium)
        }
        
        logDebug("Adaptive quality adjustment", category: .performance, context: LogContext(customData: [
            "recommended_quality": recommendedQuality.rawValue,
            "memory_pressure": String(describing: memoryPressure),
            "thermal_state": String(describing: thermalState)
        ]))
    }
    
    // MARK: - Memory Management
    
    private func handleMemoryWarning() {
        logWarning("Memory warning - clearing texture cache", category: .performance)
        
        // Clear texture cache
        textureCache.removeAllObjects()
        
        // Update statistics
        textureStats.resetCacheStats()
        
        // Force garbage collection
        autoreleasepool { }
    }
    
    private func updateThermalState() {
        thermalState = ProcessInfo.processInfo.thermalState
        
        if thermalState == .critical || thermalState == .serious {
            // Reduce texture quality temporarily
            performThermalThrottling()
        }
    }
    
    private func performThermalThrottling() {
        // Clear cache to reduce memory usage
        textureCache.removeAllObjects()
        
        // Temporarily reduce quality for new textures
        logWarning("Thermal throttling - reducing texture quality", category: .performance, context: LogContext(customData: [
            "thermal_state": String(describing: thermalState)
        ]))
    }
    
    // MARK: - Statistics
    
    private func updateLoadStatistics(url: URL, loadTime: TimeInterval, memorySize: Int) {
        let loadInfo = TextureLoadInfo(
            url: url,
            loadTime: loadTime,
            memorySize: memorySize,
            timestamp: Date()
        )
        
        loadedTextures[url.lastPathComponent] = loadInfo
        memoryUsage += UInt64(memorySize)
        
        textureStats.updateStats(
            loadTime: loadTime,
            memoryUsage: memoryUsage,
            textureCount: loadedTextures.count
        )
    }
    
    // MARK: - Utility Methods
    
    private func getFileSize(url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    private func generateCacheKey(url: URL, quality: TextureQuality) -> String {
        return "\(url.lastPathComponent)_\(quality.rawValue)"
    }
    
    // MARK: - Public Interface
    
    public func setTextureQuality(_ quality: TextureQuality) {
        currentQualityLevel = quality
        
        // Clear cache if quality changed significantly
        if quality != .automatic {
            textureCache.removeAllObjects()
        }
        
        logInfo("Texture quality changed", category: .performance, context: LogContext(customData: [
            "quality": quality.rawValue
        ]))
    }
    
    public func preloadTextures(urls: [URL], quality: TextureQuality? = nil) {
        Task {
            for url in urls {
                do {
                    _ = try await loadTextureAsync(from: url, quality: quality)
                } catch {
                    logError("Failed to preload texture", category: .performance, error: error, context: LogContext(customData: [
                        "url": url.lastPathComponent
                    ]))
                }
            }
        }
    }
    
    public func clearCache() {
        textureCache.removeAllObjects()
        loadedTextures.removeAll()
        memoryUsage = 0
        textureStats.resetCacheStats()
        
        logInfo("Texture cache cleared", category: .performance)
    }
    
    public func getTextureStatistics() -> [String: Any] {
        return [
            "cache_hits": textureStats.cacheHits,
            "cache_misses": textureStats.cacheMisses,
            "hit_rate": textureStats.hitRate,
            "loaded_textures": loadedTextures.count,
            "memory_usage_mb": Double(memoryUsage) / (1024 * 1024),
            "average_load_time": textureStats.averageLoadTime,
            "current_quality": currentQualityLevel.rawValue,
            "cache_size": textureCache.totalCostLimit / (1024 * 1024)
        ]
    }
    
    public func getDetailedStatistics() -> TextureDetailedStatistics {
        return TextureDetailedStatistics(
            totalTexturesLoaded: loadedTextures.count,
            cacheHitRate: textureStats.hitRate,
            averageLoadTime: textureStats.averageLoadTime,
            totalMemoryUsage: memoryUsage,
            compressionRatios: calculateCompressionRatios(),
            qualityDistribution: calculateQualityDistribution(),
            deviceCapabilities: deviceCapabilities
        )
    }
    
    private func calculateCompressionRatios() -> [String: Float] {
        // Calculate compression ratios for different formats
        return [:]
    }
    
    private func calculateQualityDistribution() -> [String: Int] {
        // Calculate distribution of loaded texture qualities
        return [:]
    }
}

// MARK: - Supporting Data Structures

public class OptimizedTexture {
    public let data: Data
    public let width: Int
    public let height: Int
    public let format: TextureOptimizationSystem.TextureCompressionFormat
    public let originalSize: Int
    public let memorySize: Int
    public let url: URL
    public let quality: TextureOptimizationSystem.TextureQuality
    public let hasMipmaps: Bool
    
    public var mipmaps: [Data] = []
    
    public init(
        data: Data,
        width: Int,
        height: Int,
        format: TextureOptimizationSystem.TextureCompressionFormat,
        originalSize: Int,
        memorySize: Int,
        url: URL,
        quality: TextureOptimizationSystem.TextureQuality,
        hasMipmaps: Bool
    ) {
        self.data = data
        self.width = width
        self.height = height
        self.format = format
        self.originalSize = originalSize
        self.memorySize = memorySize
        self.url = url
        self.quality = quality
        self.hasMipmaps = hasMipmaps
    }
    
    public var compressionRatio: Float {
        guard originalSize > 0 else { return 1.0 }
        return Float(originalSize) / Float(memorySize)
    }
}

public class TextureStatistics: ObservableObject {
    @Published public var cacheHits: Int = 0
    @Published public var cacheMisses: Int = 0
    @Published public var averageLoadTime: TimeInterval = 0
    @Published public var totalMemoryUsage: UInt64 = 0
    @Published public var textureCount: Int = 0
    
    private var totalLoadTime: TimeInterval = 0
    private var loadCount: Int = 0
    
    public var hitRate: Double {
        let total = cacheHits + cacheMisses
        return total > 0 ? Double(cacheHits) / Double(total) : 0.0
    }
    
    public func incrementCacheHits() {
        cacheHits += 1
    }
    
    public func incrementCacheMisses() {
        cacheMisses += 1
    }
    
    public func updateStats(loadTime: TimeInterval, memoryUsage: UInt64, textureCount: Int) {
        totalLoadTime += loadTime
        loadCount += 1
        averageLoadTime = totalLoadTime / Double(loadCount)
        
        self.totalMemoryUsage = memoryUsage
        self.textureCount = textureCount
    }
    
    public func resetCacheStats() {
        cacheHits = 0
        cacheMisses = 0
    }
}

public class CompressionStatistics: ObservableObject {
    @Published public var totalCompressions: Int = 0
    @Published public var averageCompressionTime: TimeInterval = 0
    @Published public var averageCompressionRatio: Float = 0
    @Published public var bytesProcessed: UInt64 = 0
    @Published public var bytesSaved: UInt64 = 0
    
    public func updateStats(
        compressionTime: TimeInterval,
        originalSize: Int,
        compressedSize: Int
    ) {
        totalCompressions += 1
        
        let totalTime = averageCompressionTime * Double(totalCompressions - 1) + compressionTime
        averageCompressionTime = totalTime / Double(totalCompressions)
        
        let compressionRatio = Float(originalSize) / Float(compressedSize)
        let totalRatio = averageCompressionRatio * Float(totalCompressions - 1) + compressionRatio
        averageCompressionRatio = totalRatio / Float(totalCompressions)
        
        bytesProcessed += UInt64(originalSize)
        bytesSaved += UInt64(originalSize - compressedSize)
    }
}

public struct TextureLoadInfo {
    public let url: URL
    public let loadTime: TimeInterval
    public let memorySize: Int
    public let timestamp: Date
}

public struct TextureDetailedStatistics {
    public let totalTexturesLoaded: Int
    public let cacheHitRate: Double
    public let averageLoadTime: TimeInterval
    public let totalMemoryUsage: UInt64
    public let compressionRatios: [String: Float]
    public let qualityDistribution: [String: Int]
    public let deviceCapabilities: DeviceCapabilities
}

public enum TextureError: Error {
    case failedToLoadImage
    case failedToCreateContext
    case failedToResizeImage
    case failedToCreateTexture
    case metalNotAvailable
    case compressionFailed
    case unsupportedFormat
    
    public var localizedDescription: String {
        switch self {
        case .failedToLoadImage: return "Failed to load image"
        case .failedToCreateContext: return "Failed to create graphics context"
        case .failedToResizeImage: return "Failed to resize image"
        case .failedToCreateTexture: return "Failed to create Metal texture"
        case .metalNotAvailable: return "Metal framework not available"
        case .compressionFailed: return "Texture compression failed"
        case .unsupportedFormat: return "Unsupported texture format"
        }
    }
}

// MARK: - Device Capabilities

public class DeviceCapabilities {
    private let device = UIDevice.current
    private let metalDevice = MTLCreateSystemDefaultDevice()
    
    public var supportsHighQualityTextures: Bool {
        // Check device memory and GPU capabilities
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        return totalMemory >= 4 * 1024 * 1024 * 1024 // 4GB+
    }
    
    public func getMaxTextureSize() -> Int {
        if let device = metalDevice {
            // Use Metal device capabilities
            if device.supportsFeatureSet(.iOS_GPUFamily5_v1) {
                return 4096
            } else if device.supportsFeatureSet(.iOS_GPUFamily4_v1) {
                return 2048
            } else {
                return 1024
            }
        }
        
        // Fallback based on device model
        let modelName = device.model
        if modelName.contains("iPad Pro") || modelName.contains("iPhone 12") || modelName.contains("iPhone 13") || modelName.contains("iPhone 14") {
            return 4096
        } else if modelName.contains("iPhone 11") || modelName.contains("iPhone X") {
            return 2048
        } else {
            return 1024
        }
    }
    
    public func getOptimalCompressionFormat() -> TextureOptimizationSystem.TextureCompressionFormat {
        guard let device = metalDevice else {
            return .rgba8
        }
        
        // Check for ASTC support
        if device.supportsFeatureSet(.iOS_GPUFamily3_v1) {
            return .astc6x6
        }
        
        // Check for ETC2 support
        if device.supportsFeatureSet(.iOS_GPUFamily2_v1) {
            return .etc2
        }
        
        // Fallback to basic formats
        return .rgba8
    }
    
    public func getMemoryBudgetForTextures() -> UInt64 {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        // Reserve 20% of total memory for textures
        return totalMemory / 5
    }
}

// MARK: - Texture Streaming Manager

class TextureStreamingManager {
    private var streamingQueue = DispatchQueue(label: "com.architectar.texture.streaming", qos: .utility)
    private var activeStreams: [String: StreamingInfo] = [:]
    
    func startStreaming(for texture: OptimizedTexture, distance: Float) {
        // Implementation for progressive texture loading based on distance
    }
    
    func stopStreaming(for textureId: String) {
        activeStreams.removeValue(forKey: textureId)
    }
}

struct StreamingInfo {
    let textureId: String
    let currentLOD: Int
    let targetLOD: Int
    let distance: Float
}

// MARK: - Texture LOD Manager

class TextureLODManager {
    private var lodLevels: [String: [Data]] = [:]
    
    func generateLODLevels(for texture: OptimizedTexture) -> [Data] {
        // Generate different LOD levels for the texture
        return []
    }
    
    func getLODLevel(for textureId: String, distance: Float) -> Data? {
        // Return appropriate LOD level based on distance
        return nil
    }
}