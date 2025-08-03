import Foundation
import CoreData
import Combine

// MARK: - Scan Data Manager
public class ScanDataManager: ObservableObject {
    public static let shared = ScanDataManager()
    
    @Published public var savedScans: [RoomScan] = []
    @Published public var isLoading = false
    @Published public var storageInfo: StorageInfo?
    
    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    private let scansDirectory: URL
    private let cacheDirectory: URL
    
    private var cancellables = Set<AnyCancellable>()
    
    // Storage configuration
    private let maxStorageSize: Int64 = 1024 * 1024 * 1024 // 1GB
    private let maxScansCount = 100
    private let compressionEnabled = true
    
    // MARK: - Initialization
    private init() {
        self.documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.scansDirectory = documentsDirectory.appendingPathComponent("RoomScans")
        self.cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RoomScans")
        
        setupDirectories()
        loadSavedScans()
        calculateStorageInfo()
        
        logInfo("Scan data manager initialized", category: .storage, context: LogContext(customData: [
            "scans_directory": scansDirectory.path,
            "cache_directory": cacheDirectory.path
        ]))
    }
    
    // MARK: - Public Methods
    
    /// Save a room scan to persistent storage
    public func saveScan(_ scan: RoomScan) async throws {
        logInfo("Saving room scan", category: .storage, context: LogContext(customData: [
            "scan_id": scan.id.uuidString,
            "scan_name": scan.name,
            "scan_quality": scan.scanQuality.overallScore
        ]))
        
        await MainActor.run {
            isLoading = true
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        do {
            // Check storage limits
            try await checkStorageLimits()
            
            // Create scan file
            let scanURL = scanFileURL(for: scan.id)
            let scanData = try encodeScan(scan)
            
            // Write to disk
            try scanData.write(to: scanURL)
            
            // Update metadata
            try await updateScanMetadata(scan)
            
            // Update in-memory collection
            await MainActor.run {
                if let index = savedScans.firstIndex(where: { $0.id == scan.id }) {
                    savedScans[index] = scan
                } else {
                    savedScans.append(scan)
                }
                savedScans.sort { $0.timestamp > $1.timestamp }
            }
            
            // Update storage info
            await calculateStorageInfo()
            
            logInfo("Room scan saved successfully", category: .storage, context: LogContext(customData: [
                "scan_id": scan.id.uuidString,
                "file_size": scanData.count
            ]))
            
        } catch {
            logError("Failed to save room scan: \(error)", category: .storage)
            throw ScanDataError.saveFailed(error.localizedDescription)
        }
    }
    
    /// Load a specific room scan from storage
    public func loadScan(id: UUID) async throws -> RoomScan {
        logDebug("Loading room scan", category: .storage, context: LogContext(customData: [
            "scan_id": id.uuidString
        ]))
        
        let scanURL = scanFileURL(for: id)
        
        guard fileManager.fileExists(atPath: scanURL.path) else {
            throw ScanDataError.scanNotFound("Scan file not found")
        }
        
        do {
            let scanData = try Data(contentsOf: scanURL)
            let scan = try decodeScan(from: scanData)
            
            logDebug("Room scan loaded successfully", category: .storage, context: LogContext(customData: [
                "scan_id": id.uuidString,
                "scan_name": scan.name
            ]))
            
            return scan
            
        } catch {
            logError("Failed to load room scan: \(error)", category: .storage)
            throw ScanDataError.loadFailed(error.localizedDescription)
        }
    }
    
    /// Delete a room scan from storage
    public func deleteScan(id: UUID) async throws {
        logInfo("Deleting room scan", category: .storage, context: LogContext(customData: [
            "scan_id": id.uuidString
        ]))
        
        let scanURL = scanFileURL(for: id)
        
        do {
            // Remove file
            if fileManager.fileExists(atPath: scanURL.path) {
                try fileManager.removeItem(at: scanURL)
            }
            
            // Remove from metadata
            try await removeScanMetadata(id)
            
            // Update in-memory collection
            await MainActor.run {
                savedScans.removeAll { $0.id == id }
            }
            
            // Update storage info
            await calculateStorageInfo()
            
            logInfo("Room scan deleted successfully", category: .storage)
            
        } catch {
            logError("Failed to delete room scan: \(error)", category: .storage)
            throw ScanDataError.deleteFailed(error.localizedDescription)
        }
    }
    
    /// Get a list of all saved scans (metadata only)
    public func getScanList() async -> [ScanMetadataInfo] {
        do {
            let metadataURL = scansDirectory.appendingPathComponent("metadata.json")
            
            guard fileManager.fileExists(atPath: metadataURL.path) else {
                return []
            }
            
            let data = try Data(contentsOf: metadataURL)
            let metadata = try JSONDecoder().decode([ScanMetadataInfo].self, from: data)
            
            return metadata.sorted { $0.timestamp > $1.timestamp }
            
        } catch {
            logError("Failed to load scan metadata: \(error)", category: .storage)
            return []
        }
    }
    
    /// Export a scan to a shareable format
    public func exportScan(id: UUID, format: ExportFormat) async throws -> URL {
        logInfo("Exporting room scan", category: .storage, context: LogContext(customData: [
            "scan_id": id.uuidString,
            "format": format.rawValue
        ]))
        
        let scan = try await loadScan(id: id)
        let exportURL = cacheDirectory.appendingPathComponent("exports")
            .appendingPathComponent("\(scan.name)_\(id.uuidString.prefix(8)).\(format.fileExtension)")
        
        // Create export directory if needed
        try fileManager.createDirectory(at: exportURL.deletingLastPathComponent(), 
                                       withIntermediateDirectories: true)
        
        let exportData: Data
        
        switch format {
        case .json:
            exportData = try JSONEncoder().encode(scan)
        case .csv:
            exportData = try exportToCSV(scan: scan)
        case .obj:
            exportData = try exportToOBJ(scan: scan)
        }
        
        try exportData.write(to: exportURL)
        
        logInfo("Room scan exported successfully", category: .storage, context: LogContext(customData: [
            "export_url": exportURL.path,
            "file_size": exportData.count
        ]))
        
        return exportURL
    }
    
    /// Import a scan from file
    public func importScan(from url: URL) async throws -> RoomScan {
        logInfo("Importing room scan", category: .storage, context: LogContext(customData: [
            "import_url": url.path
        ]))
        
        guard url.startAccessingSecurityScopedResource() else {
            throw ScanDataError.importFailed("Cannot access file")
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        do {
            let data = try Data(contentsOf: url)
            let scan = try decodeScan(from: data)
            
            // Save imported scan
            try await saveScan(scan)
            
            logInfo("Room scan imported successfully", category: .storage, context: LogContext(customData: [
                "scan_id": scan.id.uuidString,
                "scan_name": scan.name
            ]))
            
            return scan
            
        } catch {
            logError("Failed to import room scan: \(error)", category: .storage)
            throw ScanDataError.importFailed(error.localizedDescription)
        }
    }
    
    /// Clear all cached data
    public func clearCache() async throws {
        logInfo("Clearing scan cache", category: .storage)
        
        do {
            if fileManager.fileExists(atPath: cacheDirectory.path) {
                try fileManager.removeItem(at: cacheDirectory)
            }
            
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            
            await calculateStorageInfo()
            
            logInfo("Scan cache cleared successfully", category: .storage)
            
        } catch {
            logError("Failed to clear cache: \(error)", category: .storage)
            throw ScanDataError.clearFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupDirectories() {
        let directories = [scansDirectory, cacheDirectory]
        
        for directory in directories {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                logError("Failed to create directory \(directory.path): \(error)", category: .storage)
            }
        }
    }
    
    private func loadSavedScans() {
        Task {
            let scanList = await getScanList()
            
            await MainActor.run {
                self.savedScans = scanList.compactMap { metadata in
                    // Create minimal RoomScan objects for listing
                    // Full data will be loaded on demand
                    RoomScan(
                        id: metadata.id,
                        name: metadata.name,
                        timestamp: metadata.timestamp,
                        scanDuration: metadata.scanDuration,
                        scanQuality: ScanQuality(
                            overallScore: metadata.qualityScore,
                            completeness: 0.8, // Placeholder values
                            accuracy: 0.8,
                            coverage: 0.8,
                            planeQuality: 0.8,
                            trackingStability: 0.8,
                            issues: [],
                            recommendations: []
                        ),
                        roomDimensions: RoomDimensions(
                            width: metadata.dimensions.width,
                            length: metadata.dimensions.length,
                            height: metadata.dimensions.height
                        ),
                        detectedPlanes: [], // Will be loaded on demand
                        mergedPlanes: [],
                        roomBounds: RoomBounds(min: simd_float3(0,0,0), max: simd_float3(0,0,0)),
                        scanMetadata: ScanMetadata(
                            startTime: metadata.timestamp,
                            scanSettings: ScanSettings.default
                        )
                    )
                }
            }
        }
    }
    
    private func scanFileURL(for id: UUID) -> URL {
        return scansDirectory.appendingPathComponent("\(id.uuidString).scan")
    }
    
    private func encodeScan(_ scan: RoomScan) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(scan)
        
        if compressionEnabled {
            return try compressData(data)
        } else {
            return data
        }
    }
    
    private func decodeScan(from data: Data) throws -> RoomScan {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let decodingData: Data
        if compressionEnabled {
            decodingData = try decompressData(data)
        } else {
            decodingData = data
        }
        
        return try decoder.decode(RoomScan.self, from: decodingData)
    }
    
    private func compressData(_ data: Data) throws -> Data {
        // Simple compression using NSData compression
        let compressedData = try (data as NSData).compressed(using: .lzfse)
        return compressedData as Data
    }
    
    private func decompressData(_ data: Data) throws -> Data {
        let decompressedData = try (data as NSData).decompressed(using: .lzfse)
        return decompressedData as Data
    }
    
    private func updateScanMetadata(_ scan: RoomScan) async throws {
        let metadataURL = scansDirectory.appendingPathComponent("metadata.json")
        
        var metadata = await getScanList()
        
        let newMetadata = ScanMetadataInfo(
            id: scan.id,
            name: scan.name,
            timestamp: scan.timestamp,
            scanDuration: scan.scanDuration,
            qualityScore: scan.scanQuality.overallScore,
            dimensions: scan.roomDimensions,
            fileSize: try fileSize(for: scan.id)
        )
        
        // Update or add metadata
        if let index = metadata.firstIndex(where: { $0.id == scan.id }) {
            metadata[index] = newMetadata
        } else {
            metadata.append(newMetadata)
        }
        
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL)
    }
    
    private func removeScanMetadata(_ id: UUID) async throws {
        let metadataURL = scansDirectory.appendingPathComponent("metadata.json")
        
        var metadata = await getScanList()
        metadata.removeAll { $0.id == id }
        
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL)
    }
    
    private func fileSize(for id: UUID) throws -> Int64 {
        let url = scanFileURL(for: id)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    private func calculateStorageInfo() async {
        let info = await withTaskGroup(of: (Int64, Int).self) { group in
            var totalSize: Int64 = 0
            var totalFiles = 0
            
            group.addTask {
                let scansSize = self.directorySize(self.scansDirectory)
                let scansCount = self.fileCount(self.scansDirectory)
                return (scansSize, scansCount)
            }
            
            group.addTask {
                let cacheSize = self.directorySize(self.cacheDirectory)
                let cacheCount = self.fileCount(self.cacheDirectory)
                return (cacheSize, cacheCount)
            }
            
            for await (size, count) in group {
                totalSize += size
                totalFiles += count
            }
            
            return StorageInfo(
                totalSize: totalSize,
                maxSize: maxStorageSize,
                totalFiles: totalFiles,
                scansCount: savedScans.count,
                cacheSize: directorySize(cacheDirectory),
                availableSpace: maxStorageSize - totalSize
            )
        }
        
        await MainActor.run {
            storageInfo = info
        }
    }
    
    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(resourceValues.fileSize ?? 0)
            } catch {
                continue
            }
        }
        
        return totalSize
    }
    
    private func fileCount(_ url: URL) -> Int {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) else {
            return 0
        }
        
        var count = 0
        for _ in enumerator {
            count += 1
        }
        
        return count
    }
    
    private func checkStorageLimits() async throws {
        let currentSize = directorySize(scansDirectory)
        
        if currentSize >= maxStorageSize {
            // Clean up old scans
            try await cleanupOldScans()
        }
        
        if savedScans.count >= maxScansCount {
            // Remove oldest scan
            if let oldestScan = savedScans.min(by: { $0.timestamp < $1.timestamp }) {
                try await deleteScan(id: oldestScan.id)
            }
        }
    }
    
    private func cleanupOldScans() async throws {
        // Remove scans older than 30 days with poor quality
        let cutoffDate = Date().addingTimeInterval(-30 * 24 * 3600) // 30 days ago
        
        let scansToRemove = savedScans.filter { scan in
            scan.timestamp < cutoffDate && scan.scanQuality.overallScore < 0.5
        }
        
        for scan in scansToRemove.prefix(5) { // Remove up to 5 old poor-quality scans
            try await deleteScan(id: scan.id)
        }
    }
    
    // MARK: - Export Methods
    
    private func exportToCSV(scan: RoomScan) throws -> Data {
        var csv = "Type,Area,Width,Length,Height,Center_X,Center_Y,Center_Z,Confidence\n"
        
        for plane in scan.mergedPlanes {
            let row = [
                plane.type.rawValue,
                String(format: "%.2f", plane.area),
                String(format: "%.2f", plane.bounds.size.x),
                String(format: "%.2f", plane.bounds.size.y),
                String(format: "%.2f", plane.bounds.size.z),
                String(format: "%.3f", plane.center.x),
                String(format: "%.3f", plane.center.y),
                String(format: "%.3f", plane.center.z),
                String(format: "%.2f", plane.confidence)
            ].joined(separator: ",")
            
            csv += row + "\n"
        }
        
        return csv.data(using: .utf8) ?? Data()
    }
    
    private func exportToOBJ(scan: RoomScan) throws -> Data {
        var obj = "# Room Scan Export\n"
        obj += "# Generated by ARchitect\n\n"
        
        var vertexIndex = 1
        
        for (planeIndex, plane) in scan.mergedPlanes.enumerated() {
            obj += "# Plane \(planeIndex + 1): \(plane.type.rawValue)\n"
            obj += "g plane_\(planeIndex + 1)\n"
            
            // Add vertices
            for vertex in plane.geometry {
                obj += "v \(vertex.x) \(vertex.y) \(vertex.z)\n"
            }
            
            // Add face (assuming planar polygon)
            if plane.geometry.count >= 3 {
                obj += "f"
                for i in 0..<plane.geometry.count {
                    obj += " \(vertexIndex + i)"
                }
                obj += "\n"
            }
            
            vertexIndex += plane.geometry.count
            obj += "\n"
        }
        
        return obj.data(using: .utf8) ?? Data()
    }
}

// MARK: - Supporting Types

public struct ScanMetadataInfo: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let timestamp: Date
    public let scanDuration: TimeInterval
    public let qualityScore: Float
    public let dimensions: RoomDimensions
    public let fileSize: Int64
}

public struct StorageInfo {
    public let totalSize: Int64
    public let maxSize: Int64
    public let totalFiles: Int
    public let scansCount: Int
    public let cacheSize: Int64
    public let availableSpace: Int64
    
    public var usagePercentage: Double {
        return Double(totalSize) / Double(maxSize) * 100
    }
    
    public var totalSizeMB: Double {
        return Double(totalSize) / (1024 * 1024)
    }
    
    public var availableSpaceMB: Double {
        return Double(availableSpace) / (1024 * 1024)
    }
}

public enum ExportFormat: String, CaseIterable {
    case json = "json"
    case csv = "csv"
    case obj = "obj"
    
    public var displayName: String {
        switch self {
        case .json: return "JSON"
        case .csv: return "CSV"
        case .obj: return "OBJ"
        }
    }
    
    public var fileExtension: String {
        return rawValue
    }
}

// MARK: - Error Types
public enum ScanDataError: Error, LocalizedError {
    case saveFailed(String)
    case loadFailed(String)
    case deleteFailed(String)
    case importFailed(String)
    case exportFailed(String)
    case clearFailed(String)
    case scanNotFound(String)
    case storageFull
    
    public var errorDescription: String? {
        switch self {
        case .saveFailed(let reason):
            return "Failed to save scan: \(reason)"
        case .loadFailed(let reason):
            return "Failed to load scan: \(reason)"
        case .deleteFailed(let reason):
            return "Failed to delete scan: \(reason)"
        case .importFailed(let reason):
            return "Failed to import scan: \(reason)"
        case .exportFailed(let reason):
            return "Failed to export scan: \(reason)"
        case .clearFailed(let reason):
            return "Failed to clear data: \(reason)"
        case .scanNotFound(let reason):
            return "Scan not found: \(reason)"
        case .storageFull:
            return "Storage is full"
        }
    }
}