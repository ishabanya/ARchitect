import Foundation

// MARK: - Log Storage Configuration
public struct LogStorageConfiguration {
    let maxFileSize: Int64 // in bytes
    let maxFiles: Int
    let maxAge: TimeInterval // in seconds
    let compressionEnabled: Bool
    let encryptionEnabled: Bool
    let batchSize: Int
    let flushInterval: TimeInterval
    
    static let `default` = LogStorageConfiguration(
        maxFileSize: 5 * 1024 * 1024, // 5MB
        maxFiles: 10,
        maxAge: 7 * 24 * 3600, // 7 days
        compressionEnabled: true,
        encryptionEnabled: false,
        batchSize: 50,
        flushInterval: 5.0
    )
    
    static func forEnvironment(_ environment: AppEnvironment) -> LogStorageConfiguration {
        switch environment {
        case .development:
            return LogStorageConfiguration(
                maxFileSize: 10 * 1024 * 1024, // 10MB
                maxFiles: 20,
                maxAge: 14 * 24 * 3600, // 14 days
                compressionEnabled: false,
                encryptionEnabled: false,
                batchSize: 100,
                flushInterval: 1.0
            )
        case .staging:
            return LogStorageConfiguration(
                maxFileSize: 5 * 1024 * 1024, // 5MB
                maxFiles: 15,
                maxAge: 10 * 24 * 3600, // 10 days
                compressionEnabled: true,
                encryptionEnabled: false,
                batchSize: 75,
                flushInterval: 3.0
            )
        case .production:
            return LogStorageConfiguration(
                maxFileSize: 2 * 1024 * 1024, // 2MB
                maxFiles: 5,
                maxAge: 3 * 24 * 3600, // 3 days
                compressionEnabled: true,
                encryptionEnabled: true,
                batchSize: 25,
                flushInterval: 10.0
            )
        }
    }
}

// MARK: - Log File Info
struct LogFileInfo {
    let url: URL
    let creationDate: Date
    let size: Int64
    let entryCount: Int
    let isCompressed: Bool
    let isEncrypted: Bool
    
    var isExpired: Bool {
        let maxAge = LogStorageConfiguration.forEnvironment(AppEnvironment.current).maxAge
        return Date().timeIntervalSince(creationDate) > maxAge
    }
}

// MARK: - Log Storage
class LogStorage {
    private let configuration: LogStorageConfiguration
    private let fileManager = FileManager.default
    private let logsDirectory: URL
    private let currentLogFile: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var pendingEntries: [LogEntry] = []
    private var currentFileHandle: FileHandle?
    private var currentFileSize: Int64 = 0
    private var flushTimer: Timer?
    
    private let queue = DispatchQueue(label: "com.architect.logstorage", qos: .utility)
    private let encryptor: LogEncryptor?
    
    init(configuration: LogStorageConfiguration) {
        self.configuration = configuration
        
        // Setup logs directory
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.logsDirectory = documentsDirectory.appendingPathComponent("Logs")
        
        // Create logs directory if needed
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        
        // Current log file
        let timestamp = DateFormatter.logFileTimestamp.string(from: Date())
        self.currentLogFile = logsDirectory.appendingPathComponent("log_\(timestamp).jsonl")
        
        // Setup encryption if enabled
        self.encryptor = configuration.encryptionEnabled ? LogEncryptor() : nil
        
        // Setup JSON encoder/decoder
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        
        setupCurrentLogFile()
        startFlushTimer()
        performMaintenanceIfNeeded()
    }
    
    deinit {
        flush()
        flushTimer?.invalidate()
        currentFileHandle?.closeFile()
    }
    
    // MARK: - Public Methods
    
    func store(_ entry: LogEntry) {
        queue.async {
            self.pendingEntries.append(entry)
            
            if self.pendingEntries.count >= self.configuration.batchSize {
                self.flushPendingEntries()
            }
        }
    }
    
    func flush() {
        queue.sync {
            flushPendingEntries()
        }
    }
    
    func getLogs(category: LogCategory? = nil, 
                level: LogLevel? = nil, 
                since: Date? = nil, 
                limit: Int = 100) -> [LogEntry] {
        return queue.sync {
            var entries: [LogEntry] = []
            let logFiles = getLogFiles().sorted { $0.creationDate > $1.creationDate }
            
            for fileInfo in logFiles {
                let fileEntries = readLogFile(fileInfo.url)
                entries.append(contentsOf: fileEntries)
                
                if entries.count >= limit {
                    break
                }
            }
            
            // Apply filters
            var filteredEntries = entries
            
            if let category = category {
                filteredEntries = filteredEntries.filter { $0.category == category }
            }
            
            if let level = level {
                filteredEntries = filteredEntries.filter { $0.level >= level }
            }
            
            if let since = since {
                filteredEntries = filteredEntries.filter { $0.timestamp >= since }
            }
            
            // Sort by timestamp (newest first) and apply limit
            return Array(filteredEntries.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
        }
    }
    
    func clearLogs() {
        queue.async {
            self.pendingEntries.removeAll()
            self.currentFileHandle?.closeFile()
            self.currentFileHandle = nil
            
            let logFiles = self.getLogFiles()
            for fileInfo in logFiles {
                try? self.fileManager.removeItem(at: fileInfo.url)
            }
            
            self.setupCurrentLogFile()
        }
    }
    
    func exportLogs() -> Data? {
        return queue.sync {
            let allEntries = getLogs(limit: Int.max)
            
            let exportData: [String: Any] = [
                "exportDate": ISO8601DateFormatter().string(from: Date()),
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "Unknown",
                "logCount": allEntries.count,
                "logs": allEntries.map { entry in
                    [
                        "id": entry.id.uuidString,
                        "timestamp": ISO8601DateFormatter().string(from: entry.timestamp),
                        "level": entry.level.displayName,
                        "category": entry.category.rawValue,
                        "message": entry.message,
                        "file": entry.file,
                        "function": entry.function,
                        "line": entry.line,
                        "sessionId": entry.sessionId,
                        "threadInfo": [
                            "isMainThread": entry.threadInfo.isMainThread,
                            "name": entry.threadInfo.name ?? "",
                            "queueLabel": entry.threadInfo.queueLabel ?? ""
                        ],
                        "deviceInfo": [
                            "deviceModel": entry.context.deviceInfo.deviceModel,
                            "systemVersion": entry.context.deviceInfo.systemVersion,
                            "appVersion": entry.context.deviceInfo.appVersion,
                            "isSimulator": entry.context.deviceInfo.isSimulator
                        ],
                        "customData": entry.context.customData
                    ]
                }
            ]
            
            return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
        }
    }
    
    func getStorageInfo() -> LogStorageInfo {
        return queue.sync {
            let logFiles = getLogFiles()
            let totalSize = logFiles.reduce(0) { $0 + $1.size }
            let totalEntries = logFiles.reduce(0) { $0 + $1.entryCount }
            
            return LogStorageInfo(
                totalFiles: logFiles.count,
                totalSize: totalSize,
                totalEntries: totalEntries,
                oldestLogDate: logFiles.map { $0.creationDate }.min(),
                newestLogDate: logFiles.map { $0.creationDate }.max(),
                pendingEntries: pendingEntries.count
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func setupCurrentLogFile() {
        do {
            if !fileManager.fileExists(atPath: currentLogFile.path) {
                fileManager.createFile(atPath: currentLogFile.path, contents: nil)
            }
            
            currentFileHandle = try FileHandle(forWritingTo: currentLogFile)
            currentFileHandle?.seekToEndOfFile()
            
            let attributes = try fileManager.attributesOfItem(atPath: currentLogFile.path)
            currentFileSize = attributes[.size] as? Int64 ?? 0
            
        } catch {
            print("Failed to setup current log file: \(error)")
        }
    }
    
    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: configuration.flushInterval, repeats: true) { [weak self] _ in
            self?.queue.async {
                self?.flushPendingEntries()
            }
        }
    }
    
    private func flushPendingEntries() {
        guard !pendingEntries.isEmpty else { return }
        
        let entriesToFlush = pendingEntries
        pendingEntries.removeAll()
        
        for entry in entriesToFlush {
            writeLogEntry(entry)
        }
        
        currentFileHandle?.synchronizeFile()
    }
    
    private func writeLogEntry(_ entry: LogEntry) {
        do {
            var data = try encoder.encode(entry)
            
            // Encrypt if needed
            if let encryptor = encryptor {
                data = try encryptor.encrypt(data)
            }
            
            // Add newline for JSONL format
            data.append("\n".data(using: .utf8)!)
            
            // Check if we need to rotate the log file
            if currentFileSize + Int64(data.count) > configuration.maxFileSize {
                rotateLogFile()
            }
            
            currentFileHandle?.write(data)
            currentFileSize += Int64(data.count)
            
        } catch {
            print("Failed to write log entry: \(error)")
        }
    }
    
    private func rotateLogFile() {
        // Close current file
        currentFileHandle?.closeFile()
        currentFileHandle = nil
        
        // Compress current file if enabled
        if configuration.compressionEnabled {
            compressLogFile(currentLogFile)
        }
        
        // Create new log file
        let timestamp = DateFormatter.logFileTimestamp.string(from: Date())
        let newLogFile = logsDirectory.appendingPathComponent("log_\(timestamp).jsonl")
        
        // Update current file reference
        let oldCurrentFile = currentLogFile
        let newCurrentFile = newLogFile
        
        // Setup new file
        fileManager.createFile(atPath: newCurrentFile.path, contents: nil)
        
        do {
            currentFileHandle = try FileHandle(forWritingTo: newCurrentFile)
            currentFileSize = 0
        } catch {
            print("Failed to create new log file: \(error)")
        }
        
        // Perform maintenance
        performMaintenance()
    }
    
    private func compressLogFile(_ fileURL: URL) {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        
        do {
            let compressedData = try data.compressed(using: .lzfse)
            let compressedURL = fileURL.appendingPathExtension("lzfse")
            
            try compressedData.write(to: compressedURL)
            try fileManager.removeItem(at: fileURL)
            
        } catch {
            print("Failed to compress log file: \(error)")
        }
    }
    
    private func readLogFile(_ fileURL: URL) -> [LogEntry] {
        var entries: [LogEntry] = []
        
        do {
            var data = try Data(contentsOf: fileURL)
            
            // Check if file is compressed
            if fileURL.pathExtension == "lzfse" {
                data = try data.decompressed(using: .lzfse)
            }
            
            // Decrypt if needed
            if let encryptor = encryptor {
                data = try encryptor.decrypt(data)
            }
            
            let content = String(data: data, encoding: .utf8) ?? ""
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            
            for line in lines {
                if let lineData = line.data(using: .utf8),
                   let entry = try? decoder.decode(LogEntry.self, from: lineData) {
                    entries.append(entry)
                }
            }
            
        } catch {
            print("Failed to read log file \(fileURL): \(error)")
        }
        
        return entries
    }
    
    private func getLogFiles() -> [LogFileInfo] {
        guard let files = try? fileManager.contentsOfDirectory(at: logsDirectory, 
                                                              includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                                                              options: []) else {
            return []
        }
        
        var logFiles: [LogFileInfo] = []
        
        for file in files {
            guard file.pathExtension == "jsonl" || file.pathExtension == "lzfse" else { continue }
            
            do {
                let resourceValues = try file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                let creationDate = resourceValues.creationDate ?? Date()
                let size = Int64(resourceValues.fileSize ?? 0)
                let entryCount = estimateEntryCount(for: file)
                let isCompressed = file.pathExtension == "lzfse"
                
                let fileInfo = LogFileInfo(
                    url: file,
                    creationDate: creationDate,
                    size: size,
                    entryCount: entryCount,
                    isCompressed: isCompressed,
                    isEncrypted: configuration.encryptionEnabled
                )
                
                logFiles.append(fileInfo)
                
            } catch {
                print("Failed to get file info for \(file): \(error)")
            }
        }
        
        return logFiles
    }
    
    private func estimateEntryCount(for fileURL: URL) -> Int {
        // Rough estimation based on average entry size
        let averageEntrySize = 512 // bytes
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return max(1, fileSize / averageEntrySize)
    }
    
    private func performMaintenanceIfNeeded() {
        // Perform maintenance every hour
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.queue.async {
                self?.performMaintenance()
            }
        }
        
        // Perform initial maintenance
        queue.async {
            self.performMaintenance()
        }
    }
    
    private func performMaintenance() {
        let logFiles = getLogFiles()
        
        // Remove expired files
        let expiredFiles = logFiles.filter { $0.isExpired }
        for fileInfo in expiredFiles {
            try? fileManager.removeItem(at: fileInfo.url)
        }
        
        // Remove excess files (keep only maxFiles)
        let currentFiles = getLogFiles().sorted { $0.creationDate > $1.creationDate }
        if currentFiles.count > configuration.maxFiles {
            let filesToRemove = Array(currentFiles.dropFirst(configuration.maxFiles))
            for fileInfo in filesToRemove {
                try? fileManager.removeItem(at: fileInfo.url)
            }
        }
        
        // Compress old files if not already compressed
        if configuration.compressionEnabled {
            let uncompressedFiles = currentFiles.filter { !$0.isCompressed && $0.url != currentLogFile }
            for fileInfo in uncompressedFiles {
                compressLogFile(fileInfo.url)
            }
        }
    }
}

// MARK: - Log Storage Info
struct LogStorageInfo {
    let totalFiles: Int
    let totalSize: Int64
    let totalEntries: Int
    let oldestLogDate: Date?
    let newestLogDate: Date?
    let pendingEntries: Int
    
    var totalSizeMB: Double {
        return Double(totalSize) / (1024 * 1024)
    }
}

// MARK: - Log Encryptor
class LogEncryptor {
    private let key: Data
    
    init() {
        // In a real implementation, you would use a proper key derivation function
        // and store the key securely in the keychain
        self.key = "YourSecretLogEncryptionKey32Bytes".data(using: .utf8)?.prefix(32) ?? Data()
    }
    
    func encrypt(_ data: Data) throws -> Data {
        // Simple XOR encryption for demonstration
        // In production, use proper encryption like AES
        var encrypted = Data()
        for (index, byte) in data.enumerated() {
            let keyByte = key[index % key.count]
            encrypted.append(byte ^ keyByte)
        }
        return encrypted
    }
    
    func decrypt(_ data: Data) throws -> Data {
        // XOR encryption is symmetric
        return try encrypt(data)
    }
}

// MARK: - Extensions
extension DateFormatter {
    static let logFileTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

extension Data {
    func compressed(using algorithm: NSData.CompressionAlgorithm) throws -> Data {
        return try (self as NSData).compressed(using: algorithm) as Data
    }
    
    func decompressed(using algorithm: NSData.CompressionAlgorithm) throws -> Data {
        return try (self as NSData).decompressed(using: algorithm) as Data
    }
}

// MARK: - LogEntry Codable Extension
extension LogEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, timestamp, level, category, message, file, function, line
        case context, threadInfo, sessionId
    }
    
    private enum ContextCodingKeys: String, CodingKey {
        case userInfo, deviceInfo, appInfo, customData
    }
    
    private enum ThreadInfoCodingKeys: String, CodingKey {
        case name, isMainThread, queueLabel
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        level = try container.decode(LogLevel.self, forKey: .level)
        category = try container.decode(LogCategory.self, forKey: .category)
        message = try container.decode(String.self, forKey: .message)
        file = try container.decode(String.self, forKey: .file)
        function = try container.decode(String.self, forKey: .function)
        line = try container.decode(Int.self, forKey: .line)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        
        // Decode thread info
        let threadContainer = try container.nestedContainer(keyedBy: ThreadInfoCodingKeys.self, forKey: .threadInfo)
        threadInfo = ThreadInfo(
            name: try threadContainer.decodeIfPresent(String.self, forKey: .name),
            isMainThread: try threadContainer.decode(Bool.self, forKey: .isMainThread),
            queueLabel: try threadContainer.decodeIfPresent(String.self, forKey: .queueLabel)
        )
        
        // Decode context
        let contextContainer = try container.nestedContainer(keyedBy: ContextCodingKeys.self, forKey: .context)
        let deviceInfo = try contextContainer.decode(LogContext.DeviceInfo.self, forKey: .deviceInfo)
        let appInfo = try contextContainer.decode(LogContext.AppInfo.self, forKey: .appInfo)
        let userInfo = try contextContainer.decodeIfPresent(LogContext.UserInfo.self, forKey: .userInfo)
        let customData = try contextContainer.decode([String: AnyCodableValue].self, forKey: .customData)
        
        context = LogContext(
            userInfo: userInfo,
            deviceInfo: deviceInfo,
            appInfo: appInfo,
            customData: customData.mapValues { $0.value }
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(level, forKey: .level)
        try container.encode(category, forKey: .category)
        try container.encode(message, forKey: .message)
        try container.encode(file, forKey: .file)
        try container.encode(function, forKey: .function)
        try container.encode(line, forKey: .line)
        try container.encode(sessionId, forKey: .sessionId)
        
        // Encode thread info
        var threadContainer = container.nestedContainer(keyedBy: ThreadInfoCodingKeys.self, forKey: .threadInfo)
        try threadContainer.encodeIfPresent(threadInfo.name, forKey: .name)
        try threadContainer.encode(threadInfo.isMainThread, forKey: .isMainThread)
        try threadContainer.encodeIfPresent(threadInfo.queueLabel, forKey: .queueLabel)
        
        // Encode context
        var contextContainer = container.nestedContainer(keyedBy: ContextCodingKeys.self, forKey: .context)
        try contextContainer.encode(context.deviceInfo, forKey: .deviceInfo)
        try contextContainer.encode(context.appInfo, forKey: .appInfo)
        try contextContainer.encodeIfPresent(context.userInfo, forKey: .userInfo)
        
        let customDataCodable = context.customData.mapValues { AnyCodableValue($0) }
        try contextContainer.encode(customDataCodable, forKey: .customData)
    }
}

// Helper for encoding Any values
struct AnyCodableValue: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else {
            value = ""
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else {
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - Context Extensions Codable
extension LogContext.DeviceInfo: Codable {}
extension LogContext.AppInfo: Codable {}
extension LogContext.UserInfo: Codable {}
extension LogLevel: Codable {}
extension LogCategory: Codable {}