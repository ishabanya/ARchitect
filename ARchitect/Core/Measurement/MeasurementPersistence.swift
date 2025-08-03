import Foundation
import Combine

// MARK: - Measurement Persistence Manager
public class MeasurementPersistence: ObservableObject {
    
    public static let shared = MeasurementPersistence()
    
    // MARK: - Published Properties
    @Published public var isLoading = false
    @Published public var lastSaveDate: Date?
    @Published public var storageSize: Int64 = 0
    
    // MARK: - Private Properties
    private let fileManager = FileManager.default
    private let persistenceQueue = DispatchQueue(label: "measurement.persistence", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // Storage paths
    private var documentsDirectory: URL {
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private var measurementsDirectory: URL {
        return documentsDirectory.appendingPathComponent("Measurements", isDirectory: true)
    }
    
    private var historyFile: URL {
        return measurementsDirectory.appendingPathComponent("measurement_history.json")
    }
    
    private var backupDirectory: URL {
        return measurementsDirectory.appendingPathComponent("Backups", isDirectory: true)
    }
    
    // Settings
    private let maxBackupCount = 5
    private let compressionEnabled = true
    private var autoSaveTimer: Timer?
    
    private init() {
        setupDirectories()
        setupEncoder()
        startAutoSave()
        calculateStorageSize()
        
        logInfo("Measurement persistence initialized", category: .measurement, context: LogContext(customData: [
            "storage_path": measurementsDirectory.path,
            "compression_enabled": compressionEnabled
        ]))
    }
    
    deinit {
        autoSaveTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// Load measurement history from storage
    public func loadMeasurementHistory() async throws -> MeasurementHistory {
        return try await withCheckedThrowingContinuation { continuation in
            persistenceQueue.async {
                do {
                    let history = try self.loadHistoryFromDisk()
                    DispatchQueue.main.async {
                        continuation.resume(returning: history)
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Save measurement history to storage
    public func saveMeasurementHistory(_ history: MeasurementHistory) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                self.isLoading = true
            }
            
            persistenceQueue.async {
                do {
                    try self.saveHistoryToDisk(history)
                    
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.lastSaveDate = Date()
                        self.calculateStorageSize()
                        continuation.resume()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Export measurement history to a file
    public func exportMeasurementHistory(_ history: MeasurementHistory, format: ExportFormat = .json) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            persistenceQueue.async {
                do {
                    let exportURL = try self.exportHistory(history, format: format)
                    DispatchQueue.main.async {
                        continuation.resume(returning: exportURL)
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Import measurement history from a file
    public func importMeasurementHistory(from url: URL) async throws -> MeasurementHistory {
        return try await withCheckedThrowingContinuation { continuation in
            persistenceQueue.async {
                do {
                    let history = try self.importHistory(from: url)
                    DispatchQueue.main.async {
                        continuation.resume(returning: history)
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Create a backup of the current measurement history
    public func createBackup(_ history: MeasurementHistory) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            persistenceQueue.async {
                do {
                    let backupURL = try self.createHistoryBackup(history)
                    DispatchQueue.main.async {
                        continuation.resume(returning: backupURL)
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Get list of available backups
    public func getAvailableBackups() async throws -> [BackupInfo] {
        return try await withCheckedThrowingContinuation { continuation in
            persistenceQueue.async {
                do {
                    let backups = try self.listBackups()
                    DispatchQueue.main.async {
                        continuation.resume(returning: backups)
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Restore from a backup
    public func restoreFromBackup(_ backup: BackupInfo) async throws -> MeasurementHistory {
        return try await withCheckedThrowingContinuation { continuation in
            persistenceQueue.async {
                do {
                    let history = try self.restoreHistoryFromBackup(backup)
                    DispatchQueue.main.async {
                        continuation.resume(returning: history)
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Clear all measurement data
    public func clearAllData() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            persistenceQueue.async {
                do {
                    try self.clearStorage()
                    DispatchQueue.main.async {
                        self.storageSize = 0
                        self.lastSaveDate = nil
                        continuation.resume()
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Get storage statistics
    public var storageStatistics: StorageStatistics {
        return StorageStatistics(
            totalSize: storageSize,
            historyFileSize: getFileSize(historyFile),
            backupCount: (try? listBackups().count) ?? 0,
            lastModified: lastSaveDate
        )
    }
    
    // MARK: - Private Methods
    
    private func setupDirectories() {
        do {
            try fileManager.createDirectory(at: measurementsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        } catch {
            logError("Failed to create directories: \(error)", category: .measurement)
        }
    }
    
    private func setupEncoder() {
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        decoder.dateDecodingStrategy = .iso8601
    }
    
    private func startAutoSave() {
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task {
                await self.calculateStorageSize()
            }
        }
    }
    
    private func loadHistoryFromDisk() throws -> MeasurementHistory {
        guard fileManager.fileExists(atPath: historyFile.path) else {
            logDebug("No measurement history file found, creating new", category: .measurement)
            return MeasurementHistory()
        }
        
        do {
            let data = try Data(contentsOf: historyFile)
            let decompressedData = compressionEnabled ? try decompress(data) : data
            let history = try decoder.decode(MeasurementHistory.self, from: decompressedData)
            
            logDebug("Loaded measurement history", category: .measurement, context: LogContext(customData: [
                "sessions_count": history.sessions.count,
                "measurements_count": history.allMeasurements.count,
                "file_size": data.count
            ]))
            
            return history
        } catch {
            logError("Failed to load measurement history: \(error)", category: .measurement)
            
            // Try to restore from backup
            if let backup = try? listBackups().first {
                logWarning("Attempting to restore from backup", category: .measurement)
                return try restoreHistoryFromBackup(backup)
            }
            
            throw PersistenceError.loadFailed(error)
        }
    }
    
    private func saveHistoryToDisk(_ history: MeasurementHistory) throws {
        do {
            let data = try encoder.encode(history)
            let finalData = compressionEnabled ? try compress(data) : data
            
            // Create backup before overwriting
            if fileManager.fileExists(atPath: historyFile.path) {
                _ = try? createHistoryBackup(history)
            }
            
            try finalData.write(to: historyFile, options: .atomic)
            
            logDebug("Saved measurement history", category: .measurement, context: LogContext(customData: [
                "sessions_count": history.sessions.count,
                "measurements_count": history.allMeasurements.count,
                "file_size": finalData.count,
                "compressed": compressionEnabled
            ]))
            
        } catch {
            logError("Failed to save measurement history: \(error)", category: .measurement)
            throw PersistenceError.saveFailed(error)
        }
    }
    
    private func exportHistory(_ history: MeasurementHistory, format: ExportFormat) throws -> URL {
        let timestamp = Date().formatted(date: .abbreviated, time: .omitted)
        let filename = "measurements_\(timestamp).\(format.fileExtension)"
        let exportURL = documentsDirectory.appendingPathComponent(filename)
        
        let data: Data
        switch format {
        case .json:
            data = try encoder.encode(history)
        case .csv:
            data = try generateCSV(from: history)
        }
        
        try data.write(to: exportURL)
        
        logInfo("Exported measurement history", category: .measurement, context: LogContext(customData: [
            "format": format.rawValue,
            "file_path": exportURL.path,
            "sessions_count": history.sessions.count
        ]))
        
        return exportURL
    }
    
    private func importHistory(from url: URL) throws -> MeasurementHistory {
        guard url.startAccessingSecurityScopedResource() else {
            throw PersistenceError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let data = try Data(contentsOf: url)
        let history = try decoder.decode(MeasurementHistory.self, from: data)
        
        logInfo("Imported measurement history", category: .measurement, context: LogContext(customData: [
            "source_path": url.path,
            "sessions_count": history.sessions.count
        ]))
        
        return history
    }
    
    private func createHistoryBackup(_ history: MeasurementHistory) throws -> URL {
        let timestamp = Date().formatted(date: .numeric, time: .standard).replacingOccurrences(of: ":", with: "-")
        let backupFilename = "measurement_backup_\(timestamp).json"
        let backupURL = backupDirectory.appendingPathComponent(backupFilename)
        
        let data = try encoder.encode(BackupData(
            version: "1.0",
            timestamp: Date(),
            history: history
        ))
        
        let finalData = compressionEnabled ? try compress(data) : data
        try finalData.write(to: backupURL)
        
        // Clean up old backups
        try cleanupOldBackups()
        
        logDebug("Created measurement backup", category: .measurement, context: LogContext(customData: [
            "backup_path": backupURL.path,
            "sessions_count": history.sessions.count
        ]))
        
        return backupURL
    }
    
    private func listBackups() throws -> [BackupInfo] {
        let backupFiles = try fileManager.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
        
        return try backupFiles
            .filter { $0.pathExtension == "json" }
            .map { url in
                let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return BackupInfo(
                    url: url,
                    filename: url.lastPathComponent,
                    timestamp: resourceValues.contentModificationDate ?? Date(),
                    size: Int64(resourceValues.fileSize ?? 0)
                )
            }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    private func restoreHistoryFromBackup(_ backup: BackupInfo) throws -> MeasurementHistory {
        let data = try Data(contentsOf: backup.url)
        let decompressedData = compressionEnabled ? try decompress(data) : data
        let backupData = try decoder.decode(BackupData.self, from: decompressedData)
        
        logInfo("Restored measurement history from backup", category: .measurement, context: LogContext(customData: [
            "backup_filename": backup.filename,
            "backup_timestamp": backup.timestamp.timeIntervalSince1970,
            "sessions_count": backupData.history.sessions.count
        ]))
        
        return backupData.history
    }
    
    private func cleanupOldBackups() throws {
        let backups = try listBackups()
        
        if backups.count > maxBackupCount {
            let backupsToDelete = Array(backups.dropFirst(maxBackupCount))
            
            for backup in backupsToDelete {
                try fileManager.removeItem(at: backup.url)
                logDebug("Deleted old backup", category: .measurement, context: LogContext(customData: [
                    "backup_filename": backup.filename
                ]))
            }
        }
    }
    
    private func clearStorage() throws {
        // Remove all measurement files
        if fileManager.fileExists(atPath: historyFile.path) {
            try fileManager.removeItem(at: historyFile)
        }
        
        // Remove all backups
        let backupContents = try fileManager.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)
        for backupFile in backupContents {
            try fileManager.removeItem(at: backupFile)
        }
        
        logInfo("Cleared all measurement storage", category: .measurement)
    }
    
    private func calculateStorageSize() {
        Task {
            let size = await withCheckedContinuation { continuation in
                persistenceQueue.async {
                    var totalSize: Int64 = 0
                    
                    // Add history file size
                    totalSize += self.getFileSize(self.historyFile)
                    
                    // Add backup files size
                    if let backupFiles = try? self.fileManager.contentsOfDirectory(at: self.backupDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
                        for backupFile in backupFiles {
                            totalSize += self.getFileSize(backupFile)
                        }
                    }
                    
                    continuation.resume(returning: totalSize)
                }
            }
            
            await MainActor.run {
                self.storageSize = size
            }
        }
    }
    
    private func getFileSize(_ url: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            return 0
        }
        return fileSize
    }
    
    private func compress(_ data: Data) throws -> Data {
        return try (data as NSData).compressed(using: .lzfse) as Data
    }
    
    private func decompress(_ data: Data) throws -> Data {
        return try (data as NSData).decompressed(using: .lzfse) as Data
    }
    
    private func generateCSV(from history: MeasurementHistory) throws -> Data {
        var csvContent = "Session Name,Measurement Name,Type,Value,Unit,Accuracy,Timestamp,Notes\n"
        
        for session in history.sessions {
            for measurement in session.measurements {
                let row = [
                    session.name,
                    measurement.name,
                    measurement.type.displayName,
                    String(measurement.value.primary),
                    measurement.value.unit.rawValue,
                    measurement.accuracy.level.rawValue,
                    measurement.timestamp.ISO8601Format(),
                    measurement.notes.replacingOccurrences(of: ",", with: ";")
                ].joined(separator: ",")
                
                csvContent += row + "\n"
            }
        }
        
        guard let data = csvContent.data(using: .utf8) else {
            throw PersistenceError.exportFailed("Failed to encode CSV data")
        }
        
        return data
    }
}

// MARK: - Supporting Types

public enum ExportFormat: String, CaseIterable {
    case json = "json"
    case csv = "csv"
    
    public var displayName: String {
        switch self {
        case .json: return "JSON"
        case .csv: return "CSV"
        }
    }
    
    public var fileExtension: String {
        return rawValue
    }
}

public struct BackupInfo: Identifiable {
    public let id = UUID()
    public let url: URL
    public let filename: String
    public let timestamp: Date
    public let size: Int64
    
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

private struct BackupData: Codable {
    let version: String
    let timestamp: Date
    let history: MeasurementHistory
}

public struct StorageStatistics {
    public let totalSize: Int64
    public let historyFileSize: Int64
    public let backupCount: Int
    public let lastModified: Date?
    
    public var formattedTotalSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }
    
    public var formattedHistoryFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: historyFileSize)
    }
}

public enum PersistenceError: LocalizedError {
    case loadFailed(Error)
    case saveFailed(Error)
    case exportFailed(String)
    case importFailed(Error)
    case accessDenied
    case corruptedData
    
    public var errorDescription: String? {
        switch self {
        case .loadFailed(let error):
            return "Failed to load measurement data: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "Failed to save measurement data: \(error.localizedDescription)"
        case .exportFailed(let reason):
            return "Failed to export measurement data: \(reason)"
        case .importFailed(let error):
            return "Failed to import measurement data: \(error.localizedDescription)"
        case .accessDenied:
            return "Access denied to measurement data file"
        case .corruptedData:
            return "Measurement data file is corrupted"
        }
    }
}