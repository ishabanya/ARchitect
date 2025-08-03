import Foundation
import Network
import CryptoKit
import os.log

// MARK: - Intelligent Network Cache Optimizer

@MainActor
public class NetworkCacheOptimizer: ObservableObject {
    
    // MARK: - Cache Configuration
    public struct CacheConfiguration {
        public static let maxCacheSize: UInt64 = 100 * 1024 * 1024 // 100MB
        public static let maxMemoryCache: UInt64 = 20 * 1024 * 1024 // 20MB
        public static let defaultTTL: TimeInterval = 24 * 3600 // 24 hours
        public static let maxConcurrentRequests: Int = 10
        public static let requestTimeout: TimeInterval = 30.0
    }
    
    // MARK: - Published Properties
    @Published public var cacheMetrics = CacheMetrics()
    @Published public var networkMetrics = NetworkMetrics()
    @Published public var isOnline = true
    @Published public var networkQuality: NetworkQuality = .good
    @Published public var cacheHitRate: Double = 0.0
    
    // MARK: - Private Properties
    private let performanceLogger = Logger(subsystem: "ARchitect", category: "NetworkCache")
    private let session: URLSession
    private let cache: NetworkCache
    private let prefetcher: NetworkPrefetcher
    private let compressionManager: CompressionManager
    private let networkMonitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "network.monitor")
    
    // Request management
    private var activeRequests: [URL: URLSessionDataTask] = [:]
    private var requestQueue: [CacheRequest] = []
    private let requestSemaphore: DispatchSemaphore
    
    public static let shared = NetworkCacheOptimizer()
    
    private init() {
        // Configure URLSession for optimal performance
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = CacheConfiguration.requestTimeout
        config.timeoutIntervalForResource = CacheConfiguration.requestTimeout * 2
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        
        session = URLSession(configuration: config)
        cache = NetworkCache()
        prefetcher = NetworkPrefetcher()
        compressionManager = CompressionManager()
        networkMonitor = NWPathMonitor()
        requestSemaphore = DispatchSemaphore(value: CacheConfiguration.maxConcurrentRequests)
        
        setupNetworkOptimization()
        startNetworkMonitoring()
    }
    
    // MARK: - Network Optimization Setup
    
    private func setupNetworkOptimization() {
        cache.configure(
            maxSize: CacheConfiguration.maxCacheSize,
            maxMemorySize: CacheConfiguration.maxMemoryCache,
            defaultTTL: CacheConfiguration.defaultTTL
        )
        
        prefetcher.configure(
            cacheOptimizer: self,
            priorityThreshold: .high
        )
        
        compressionManager.configure(
            enableGzip: true,
            enableBrotli: true,
            compressionThreshold: 1024 // 1KB
        )
    }
    
    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                await self?.handleNetworkChange(path)
            }
        }
        
        networkMonitor.start(queue: monitorQueue)
        
        // Start metrics collection
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task { @MainActor in
                await self.updateMetrics()
            }
        }
    }
    
    // MARK: - Core Network Cache Interface
    
    public func fetchData(
        from url: URL,
        priority: RequestPriority = .normal,
        cachePolicy: CachePolicy = .intelligent,
        completion: @escaping (Result<Data, Error>) -> Void
    ) -> CacheRequest {
        
        let request = CacheRequest(
            url: url,
            priority: priority,
            cachePolicy: cachePolicy,
            completion: completion
        )
        
        Task {
            await executeRequest(request)
        }
        
        return request
    }
    
    public func fetchData(from url: URL, priority: RequestPriority = .normal, cachePolicy: CachePolicy = .intelligent) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            _ = fetchData(from: url, priority: priority, cachePolicy: cachePolicy) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    private func executeRequest(_ request: CacheRequest) async {
        // Check cache first based on policy
        if await shouldCheckCache(for: request) {
            if let cachedData = await cache.getData(for: request.url) {
                await updateCacheMetrics(hit: true)
                request.completion(.success(cachedData))
                return
            }
        }
        
        await updateCacheMetrics(hit: false)
        
        // Add to queue if at capacity
        requestSemaphore.wait()
        defer { requestSemaphore.signal() }
        
        await performNetworkRequest(request)
    }
    
    private func performNetworkRequest(_ request: CacheRequest) async {
        do {
            performanceLogger.debug("🌐 Fetching from network: \(request.url)")
            
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // Create optimized URLRequest
            var urlRequest = URLRequest(url: request.url)
            await configureRequest(&urlRequest, for: request)
            
            // Execute request
            let (data, response) = try await session.data(for: urlRequest)
            
            let requestTime = CFAbsoluteTimeGetCurrent() - startTime
            await updateNetworkMetrics(requestTime: requestTime, dataSize: data.count)
            
            // Process and cache response
            let processedData = await processResponse(data, response: response, for: request)
            await cache.storeData(processedData, for: request.url, response: response)
            
            request.completion(.success(processedData))
            
        } catch {
            performanceLogger.error("❌ Network request failed: \(error)")
            await updateNetworkMetrics(error: error)
            
            // Try to serve stale cache if available
            if let staleData = await cache.getStaleData(for: request.url) {
                performanceLogger.info("📦 Serving stale cache for: \(request.url)")
                request.completion(.success(staleData))
            } else {
                request.completion(.failure(error))
            }
        }
    }
    
    // MARK: - Request Configuration
    
    private func configureRequest(_ request: inout URLRequest, for cacheRequest: CacheRequest) async {
        // Add compression headers
        request.setValue("gzip, br", forHTTPHeaderField: "Accept-Encoding")
        
        // Add cache headers based on policy
        switch cacheRequest.cachePolicy {
        case .cacheFirst:
            request.cachePolicy = .returnCacheDataElseLoad
        case .networkFirst:
            request.cachePolicy = .reloadIgnoringLocalCacheData
        case .intelligent:
            // Use intelligent caching based on network conditions
            if networkQuality == .poor {
                request.cachePolicy = .returnCacheDataElseLoad
            } else {
                request.cachePolicy = .useProtocolCachePolicy
            }
        case .noCache:
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        }
        
        // Add conditional headers if we have cached data
        if let etag = await cache.getETag(for: cacheRequest.url) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        
        if let lastModified = await cache.getLastModified(for: cacheRequest.url) {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        
        // Optimize for current network conditions
        await optimizeForNetworkConditions(&request)
    }
    
    private func optimizeForNetworkConditions(_ request: inout URLRequest) async {
        switch networkQuality {
        case .excellent, .good:
            // Use default settings
            break
        case .fair:
            // Reduce timeout for faster fallback
            request.timeoutInterval = 20.0
        case .poor:
            // Aggressive timeout reduction
            request.timeoutInterval = 10.0
            // Request compressed data
            request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        case .offline:
            // This should be handled before reaching here
            break
        }
    }
    
    // MARK: - Response Processing
    
    private func processResponse(_ data: Data, response: URLResponse, for request: CacheRequest) async -> Data {
        var processedData = data
        
        // Decompress if needed
        if let httpResponse = response as? HTTPURLResponse,
           let encoding = httpResponse.value(forHTTPHeaderField: "Content-Encoding") {
            processedData = await compressionManager.decompress(data, encoding: encoding) ?? data
        }
        
        // Apply additional processing based on content type
        if let httpResponse = response as? HTTPURLResponse,
           let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
            processedData = await processContentType(processedData, contentType: contentType)
        }
        
        return processedData
    }
    
    private func processContentType(_ data: Data, contentType: String) async -> Data {
        if contentType.contains("application/json") {
            // Validate and potentially compress JSON
            return await processJSONData(data)
        } else if contentType.contains("image/") {
            // Optimize image data
            return await processImageData(data)
        } else if contentType.contains("text/") {
            // Compress text data
            return await compressTextData(data)
        }
        
        return data
    }
    
    private func processJSONData(_ data: Data) async -> Data {
        // Validate JSON and potentially minify
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            return try JSONSerialization.data(withJSONObject: jsonObject, options: .fragmentsAllowed)
        } catch {
            return data
        }
    }
    
    private func processImageData(_ data: Data) async -> Data {
        // For large images, we might want to compress them further
        if data.count > 1024 * 1024 { // 1MB
            return await compressionManager.compressImage(data) ?? data
        }
        return data
    }
    
    private func compressTextData(_ data: Data) async -> Data {
        if data.count > 10 * 1024 { // 10KB
            return await compressionManager.compress(data) ?? data
        }
        return data
    }
    
    // MARK: - Intelligent Caching Logic
    
    private func shouldCheckCache(for request: CacheRequest) async -> Bool {
        switch request.cachePolicy {
        case .cacheFirst:
            return true
        case .networkFirst:
            return false
        case .intelligent:
            return await intelligentCacheDecision(for: request)
        case .noCache:
            return false
        }
    }
    
    private func intelligentCacheDecision(for request: CacheRequest) async -> Bool {
        // Check network conditions
        if networkQuality == .poor || networkQuality == .offline {
            return true
        }
        
        // Check cache age and freshness
        if let cacheEntry = await cache.getCacheEntry(for: request.url) {
            let age = Date().timeIntervalSince(cacheEntry.timestamp)
            
            // For high priority requests, use fresher cache
            if request.priority == .high && age < 300 { // 5 minutes
                return true
            }
            
            // For normal requests, use cache within TTL
            if age < cacheEntry.ttl {
                return true
            }
        }
        
        // Check request frequency
        let frequency = await getRequestFrequency(for: request.url)
        if frequency > 5 { // Frequently requested URLs get cached more aggressively
            return true
        }
        
        return false
    }
    
    // MARK: - Prefetching
    
    public func prefetchData(urls: [URL], priority: RequestPriority = .low) async {
        await prefetcher.prefetch(urls: urls, priority: priority)
    }
    
    public func enableSmartPrefetching(for patterns: [URLPattern]) async {
        await prefetcher.enableSmartPrefetching(patterns: patterns)
    }
    
    // MARK: - Cache Management
    
    public func clearCache() async {
        await cache.clear()
        cacheMetrics.cacheClears += 1
        performanceLogger.info("🧹 Network cache cleared")
    }
    
    public func clearExpiredCache() async {
        let freed = await cache.clearExpired()
        cacheMetrics.expiredDataCleared += freed
        performanceLogger.info("🧹 Expired cache cleared: \(freed / 1024 / 1024)MB")
    }
    
    public func getCacheSize() async -> UInt64 {
        return await cache.getCurrentSize()
    }
    
    public func getCacheInfo() async -> CacheInfo {
        return await cache.getCacheInfo()
    }
    
    // MARK: - Network Monitoring
    
    private func handleNetworkChange(_ path: NWPath) async {
        let wasOnline = isOnline
        isOnline = path.status == .satisfied
        
        if isOnline != wasOnline {
            performanceLogger.info("🌐 Network status changed: \(isOnline ? "Online" : "Offline")")
            
            if isOnline {
                await handleNetworkReconnection()
            } else {
                await handleNetworkDisconnection()
            }
        }
        
        // Update network quality
        networkQuality = determineNetworkQuality(from: path)
        
        // Adjust caching strategy based on network changes
        await adjustCachingStrategy()
    }
    
    private func determineNetworkQuality(from path: NWPath) -> NetworkQuality {
        if path.status != .satisfied {
            return .offline
        }
        
        if path.isExpensive {
            return .poor
        }
        
        if path.isConstrained {
            return .fair
        }
        
        // Check interface types for quality estimation
        if path.usesInterfaceType(.wifi) {
            return .excellent
        } else if path.usesInterfaceType(.cellular) {
            return .good
        } else {
            return .fair
        }
    }
    
    private func handleNetworkReconnection() async {
        // Resume queued requests
        await processQueuedRequests()
        
        // Sync critical data
        await syncCriticalData()
        
        // Update cache with fresh data for expired entries
        await refreshExpiredCache()
    }
    
    private func handleNetworkDisconnection() async {
        // Cancel non-critical requests
        await cancelNonCriticalRequests()
        
        // Prepare for offline mode
        await prepareOfflineMode()
    }
    
    private func adjustCachingStrategy() async {
        switch networkQuality {
        case .excellent, .good:
            // Use standard caching
            await cache.setAggressiveness(.normal)
        case .fair:
            // More aggressive caching
            await cache.setAggressiveness(.aggressive)
        case .poor:
            // Very aggressive caching
            await cache.setAggressiveness(.veryAggressive)
        case .offline:
            // Rely entirely on cache
            await cache.setAggressiveness(.offlineOnly)
        }
    }
    
    // MARK: - Metrics and Analytics
    
    private func updateCacheMetrics(hit: Bool) async {
        if hit {
            cacheMetrics.hits += 1
        } else {
            cacheMetrics.misses += 1
        }
        
        let total = cacheMetrics.hits + cacheMetrics.misses
        cacheHitRate = total > 0 ? Double(cacheMetrics.hits) / Double(total) : 0.0
    }
    
    private func updateNetworkMetrics(requestTime: TimeInterval, dataSize: Int) async {
        networkMetrics.totalRequests += 1
        networkMetrics.totalDataTransferred += UInt64(dataSize)
        networkMetrics.totalRequestTime += requestTime
        networkMetrics.averageRequestTime = networkMetrics.totalRequestTime / Double(networkMetrics.totalRequests)
        
        // Calculate bandwidth
        if requestTime > 0 {
            let bandwidth = Double(dataSize) / requestTime // bytes per second
            networkMetrics.estimatedBandwidth = bandwidth
        }
    }
    
    private func updateNetworkMetrics(error: Error) async {
        networkMetrics.failedRequests += 1
    }
    
    private func updateMetrics() async {
        // Update cache metrics
        cacheMetrics.currentCacheSize = await cache.getCurrentSize()
        cacheMetrics.cachedItems = await cache.getItemCount()
        
        // Update network metrics
        let total = cacheMetrics.hits + cacheMetrics.misses
        cacheHitRate = total > 0 ? Double(cacheMetrics.hits) / Double(total) : 0.0
        
        // Calculate efficiency metrics
        calculateEfficiencyMetrics()
    }
    
    private func calculateEfficiencyMetrics() {
        let totalRequests = cacheMetrics.hits + cacheMetrics.misses
        if totalRequests > 0 {
            cacheMetrics.efficiency = Double(cacheMetrics.hits) / Double(totalRequests)
        }
        
        if networkMetrics.totalRequests > 0 {
            networkMetrics.reliability = 1.0 - (Double(networkMetrics.failedRequests) / Double(networkMetrics.totalRequests))
        }
    }
    
    // MARK: - Helper Methods
    
    private func getRequestFrequency(for url: URL) async -> Int {
        return await cache.getRequestFrequency(for: url)
    }
    
    private func processQueuedRequests() async {
        for request in requestQueue {
            Task {
                await executeRequest(request)
            }
        }
        requestQueue.removeAll()
    }
    
    private func syncCriticalData() async {
        // Sync data marked as critical
        let criticalURLs = await cache.getCriticalURLs()
        for url in criticalURLs {
            Task {
                _ = try? await fetchData(from: url, priority: .high, cachePolicy: .networkFirst)
            }
        }
    }
    
    private func refreshExpiredCache() async {
        let expiredURLs = await cache.getExpiredURLs()
        for url in expiredURLs.prefix(10) { // Limit to 10 to avoid overwhelming
            Task {
                _ = try? await fetchData(from: url, priority: .low, cachePolicy: .networkFirst)
            }
        }
    }
    
    private func cancelNonCriticalRequests() async {
        for (url, task) in activeRequests {
            if await getRequestPriority(for: url) != .high {
                task.cancel()
                activeRequests.removeValue(forKey: url)
            }
        }
    }
    
    private func prepareOfflineMode() async {
        // Extend cache TTL for offline usage
        await cache.extendTTLForOffline()
        
        // Prioritize essential data
        await cache.prioritizeEssentialData()
    }
    
    private func getRequestPriority(for url: URL) async -> RequestPriority {
        // This would check the priority of active requests
        return .normal // Placeholder
    }
    
    // MARK: - Public Interface
    
    public func getNetworkReport() -> NetworkReport {
        return NetworkReport(
            isOnline: isOnline,
            networkQuality: networkQuality,
            cacheHitRate: cacheHitRate,
            cacheMetrics: cacheMetrics,
            networkMetrics: networkMetrics
        )
    }
    
    public func optimizeForBattery() async {
        // Reduce network activity to save battery
        await cache.setAggressiveness(.veryAggressive)
        await prefetcher.pause()
    }
    
    public func optimizeForPerformance() async {
        // Optimize for maximum performance
        await cache.setAggressiveness(.normal)
        await prefetcher.resume()
    }
}

// MARK: - Supporting Types

public enum RequestPriority {
    case low, normal, high, critical
}

public enum CachePolicy {
    case cacheFirst    // Check cache first, fallback to network
    case networkFirst  // Always try network first, fallback to cache
    case intelligent   // Intelligent decision based on conditions
    case noCache      // Never use cache
}

public enum NetworkQuality {
    case excellent, good, fair, poor, offline
    
    var description: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .offline: return "Offline"
        }
    }
}

public enum CacheAggressiveness {
    case normal, aggressive, veryAggressive, offlineOnly
}

public class CacheRequest {
    public let url: URL
    public let priority: RequestPriority
    public let cachePolicy: CachePolicy
    public let completion: (Result<Data, Error>) -> Void
    public let timestamp: Date
    
    public init(url: URL, priority: RequestPriority, cachePolicy: CachePolicy, completion: @escaping (Result<Data, Error>) -> Void) {
        self.url = url
        self.priority = priority
        self.cachePolicy = cachePolicy
        self.completion = completion
        self.timestamp = Date()
    }
}

public struct CacheMetrics {
    public var hits: Int = 0
    public var misses: Int = 0
    public var currentCacheSize: UInt64 = 0
    public var cachedItems: Int = 0
    public var efficiency: Double = 0.0
    public var cacheClears: Int = 0
    public var expiredDataCleared: UInt64 = 0
}

public struct NetworkMetrics {
    public var totalRequests: Int = 0
    public var failedRequests: Int = 0
    public var totalDataTransferred: UInt64 = 0
    public var totalRequestTime: TimeInterval = 0
    public var averageRequestTime: TimeInterval = 0
    public var estimatedBandwidth: Double = 0
    public var reliability: Double = 1.0
}

public struct NetworkReport {
    public let isOnline: Bool
    public let networkQuality: NetworkQuality
    public let cacheHitRate: Double
    public let cacheMetrics: CacheMetrics
    public let networkMetrics: NetworkMetrics
}

public struct URLPattern {
    public let pattern: String
    public let priority: RequestPriority
    
    public init(pattern: String, priority: RequestPriority) {
        self.pattern = pattern
        self.priority = priority
    }
}

public struct CacheInfo {
    public let totalSize: UInt64
    public let itemCount: Int
    public let oldestItem: Date?
    public let newestItem: Date?
    public let hitRate: Double
}

// MARK: - Network Cache Implementation

actor NetworkCache {
    private var cache: [URL: CacheEntry] = [:]
    private var requestFrequency: [URL: Int] = [:]
    private var maxSize: UInt64 = 0
    private var maxMemorySize: UInt64 = 0
    private var defaultTTL: TimeInterval = 0
    private var aggressiveness: CacheAggressiveness = .normal
    
    func configure(maxSize: UInt64, maxMemorySize: UInt64, defaultTTL: TimeInterval) {
        self.maxSize = maxSize
        self.maxMemorySize = maxMemorySize
        self.defaultTTL = defaultTTL
    }
    
    func getData(for url: URL) -> Data? {
        guard let entry = cache[url], !entry.isExpired else {
            return nil
        }
        
        // Update access time
        cache[url]?.lastAccessed = Date()
        requestFrequency[url, default: 0] += 1
        
        return entry.data
    }
    
    func storeData(_ data: Data, for url: URL, response: URLResponse) {
        let ttl = calculateTTL(for: response)
        let entry = CacheEntry(
            data: data,
            timestamp: Date(),
            ttl: ttl,
            etag: extractETag(from: response),
            lastModified: extractLastModified(from: response),
            contentType: extractContentType(from: response)
        )
        
        cache[url] = entry
        
        // Cleanup if needed
        if getCurrentSize() > maxSize {
            performCleanup()
        }
    }
    
    func getStaleData(for url: URL) -> Data? {
        return cache[url]?.data
    }
    
    func getCacheEntry(for url: URL) -> CacheEntry? {
        return cache[url]
    }
    
    func getETag(for url: URL) -> String? {
        return cache[url]?.etag
    }
    
    func getLastModified(for url: URL) -> String? {
        return cache[url]?.lastModified
    }
    
    func clear() {
        cache.removeAll()
        requestFrequency.removeAll()
    }
    
    func clearExpired() -> UInt64 {
        let expiredEntries = cache.filter { $0.value.isExpired }
        let freedSize = expiredEntries.reduce(0) { $0 + UInt64($1.value.data.count) }
        
        for (url, _) in expiredEntries {
            cache.removeValue(forKey: url)
        }
        
        return freedSize
    }
    
    func getCurrentSize() -> UInt64 {
        return cache.values.reduce(0) { $0 + UInt64($1.data.count) }
    }
    
    func getItemCount() -> Int {
        return cache.count
    }
    
    func getCacheInfo() -> CacheInfo {
        let totalSize = getCurrentSize()
        let itemCount = cache.count
        let timestamps = cache.values.map { $0.timestamp }
        
        return CacheInfo(
            totalSize: totalSize,
            itemCount: itemCount,
            oldestItem: timestamps.min(),
            newestItem: timestamps.max(),
            hitRate: 0.0 // This would be calculated elsewhere
        )
    }
    
    func getRequestFrequency(for url: URL) -> Int {
        return requestFrequency[url, default: 0]
    }
    
    func setAggressiveness(_ level: CacheAggressiveness) {
        aggressiveness = level
        adjustCachePolicy()
    }
    
    func getCriticalURLs() -> [URL] {
        // Return URLs marked as critical
        return cache.compactMap { (url, entry) in
            requestFrequency[url, default: 0] > 10 ? url : nil
        }
    }
    
    func getExpiredURLs() -> [URL] {
        return cache.compactMap { (url, entry) in
            entry.isExpired ? url : nil
        }
    }
    
    func extendTTLForOffline() {
        for (url, entry) in cache {
            var updatedEntry = entry
            updatedEntry.ttl *= 2 // Double TTL for offline usage
            cache[url] = updatedEntry
        }
    }
    
    func prioritizeEssentialData() {
        // Keep only most frequently accessed data
        let threshold = 5
        let nonEssential = cache.filter { requestFrequency[$0.key, default: 0] < threshold }
        
        for (url, _) in nonEssential {
            cache.removeValue(forKey: url)
        }
    }
    
    private func calculateTTL(for response: URLResponse) -> TimeInterval {
        // Extract TTL from cache headers or use default
        if let httpResponse = response as? HTTPURLResponse {
            if let cacheControl = httpResponse.value(forHTTPHeaderField: "Cache-Control") {
                // Parse max-age directive
                if let maxAge = extractMaxAge(from: cacheControl) {
                    return TimeInterval(maxAge)
                }
            }
            
            if let expires = httpResponse.value(forHTTPHeaderField: "Expires") {
                // Parse Expires header
                if let expiryDate = parseHTTPDate(expires) {
                    return expiryDate.timeIntervalSinceNow
                }
            }
        }
        
        return defaultTTL
    }
    
    private func extractETag(from response: URLResponse) -> String? {
        return (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag")
    }
    
    private func extractLastModified(from response: URLResponse) -> String? {
        return (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Last-Modified")
    }
    
    private func extractContentType(from response: URLResponse) -> String? {
        return (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
    }
    
    private func extractMaxAge(from cacheControl: String) -> Int? {
        let components = cacheControl.components(separatedBy: ",")
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("max-age=") {
                let value = String(trimmed.dropFirst(8))
                return Int(value)
            }
        }
        return nil
    }
    
    private func parseHTTPDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: dateString)
    }
    
    private func performCleanup() {
        // Remove least recently used items
        let sortedEntries = cache.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
        let removeCount = max(1, cache.count / 4) // Remove 25%
        
        for i in 0..<min(removeCount, sortedEntries.count) {
            let (url, _) = sortedEntries[i]
            cache.removeValue(forKey: url)
        }
    }
    
    private func adjustCachePolicy() {
        switch aggressiveness {
        case .normal:
            // Standard caching behavior
            break
        case .aggressive:
            // Increase TTL by 50%
            for (url, entry) in cache {
                var updatedEntry = entry
                updatedEntry.ttl *= 1.5
                cache[url] = updatedEntry
            }
        case .veryAggressive:
            // Double TTL
            for (url, entry) in cache {
                var updatedEntry = entry
                updatedEntry.ttl *= 2.0
                cache[url] = updatedEntry
            }
        case .offlineOnly:
            // Never expire cache
            for (url, entry) in cache {
                var updatedEntry = entry
                updatedEntry.ttl = .infinity
                cache[url] = updatedEntry
            }
        }
    }
}

struct CacheEntry {
    let data: Data
    let timestamp: Date
    var ttl: TimeInterval
    var lastAccessed: Date
    let etag: String?
    let lastModified: String?
    let contentType: String?
    
    init(data: Data, timestamp: Date, ttl: TimeInterval, etag: String?, lastModified: String?, contentType: String?) {
        self.data = data
        self.timestamp = timestamp
        self.ttl = ttl
        self.lastAccessed = timestamp
        self.etag = etag
        self.lastModified = lastModified
        self.contentType = contentType
    }
    
    var isExpired: Bool {
        return Date().timeIntervalSince(timestamp) > ttl
    }
}

// MARK: - Network Prefetcher

actor NetworkPrefetcher {
    private var isPaused = false
    private var smartPatterns: [URLPattern] = []
    private weak var cacheOptimizer: NetworkCacheOptimizer?
    
    func configure(cacheOptimizer: NetworkCacheOptimizer, priorityThreshold: RequestPriority) {
        self.cacheOptimizer = cacheOptimizer
    }
    
    func prefetch(urls: [URL], priority: RequestPriority) async {
        guard !isPaused else { return }
        
        for url in urls {
            Task {
                _ = try? await cacheOptimizer?.fetchData(from: url, priority: priority, cachePolicy: .intelligent)
            }
        }
    }
    
    func enableSmartPrefetching(patterns: [URLPattern]) async {
        smartPatterns = patterns
    }
    
    func pause() {
        isPaused = true
    }
    
    func resume() {
        isPaused = false
    }
}

// MARK: - Compression Manager

actor CompressionManager {
    private var enableGzip = true
    private var enableBrotli = true
    private var compressionThreshold = 1024
    
    func configure(enableGzip: Bool, enableBrotli: Bool, compressionThreshold: Int) {
        self.enableGzip = enableGzip
        self.enableBrotli = enableBrotli
        self.compressionThreshold = compressionThreshold
    }
    
    func decompress(_ data: Data, encoding: String) -> Data? {
        switch encoding.lowercased() {
        case "gzip":
            return decompressGzip(data)
        case "br", "brotli":
            return decompressBrotli(data)
        default:
            return data
        }
    }
    
    func compress(_ data: Data) -> Data? {
        guard data.count > compressionThreshold else { return data }
        
        if enableBrotli {
            return compressBrotli(data)
        } else if enableGzip {
            return compressGzip(data)
        }
        
        return data
    }
    
    func compressImage(_ data: Data) -> Data? {
        // Implement image compression
        return data
    }
    
    private func decompressGzip(_ data: Data) -> Data? {
        return try? (data as NSData).decompressed(using: .zlib) as Data
    }
    
    private func decompressBrotli(_ data: Data) -> Data? {
        // Implement Brotli decompression
        return data
    }
    
    private func compressGzip(_ data: Data) -> Data? {
        return try? (data as NSData).compressed(using: .zlib) as Data
    }
    
    private func compressBrotli(_ data: Data) -> Data? {
        // Implement Brotli compression
        return data
    }
}