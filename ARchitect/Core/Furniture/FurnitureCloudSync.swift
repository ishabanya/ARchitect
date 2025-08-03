import Foundation
import CloudKit
import Combine

// MARK: - Furniture Cloud Sync Manager

@MainActor
public class FurnitureCloudSyncManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var syncStatus: CloudSyncStatus = .idle
    @Published public var lastSyncDate: Date?
    @Published public var syncProgress: Float = 0.0
    
    // MARK: - Private Properties
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let publicDatabase: CKDatabase
    private let syncQueue = DispatchQueue(label: "furniture.cloud.sync", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // CloudKit record types
    private let furnitureItemRecordType = "FurnitureItem"
    private let userFavoritesRecordType = "UserFavorites"
    private let userRecentsRecordType = "UserRecents"
    private let customItemRecordType = "CustomFurnitureItem"
    
    // Sync configuration
    private let batchSize = 50
    private let maxRetries = 3
    private let syncInterval: TimeInterval = 300 // 5 minutes
    private var syncTimer: Timer?
    
    public init() {
        self.container = CKContainer(identifier: "iCloud.com.architect.furniture")
        self.privateDatabase = container.privateCloudDatabase
        self.publicDatabase = container.publicCloudDatabase
        
        setupEncoder()
        startPeriodicSync()
        
        logInfo("Furniture cloud sync manager initialized", category: .general)
    }
    
    deinit {
        syncTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// Sync entire catalog with cloud
    public func syncCatalog() async throws -> CatalogData {
        syncStatus = .syncing
        syncProgress = 0.0
        
        do {
            // Check CloudKit availability
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                throw CloudSyncError.accountUnavailable
            }
            
            syncProgress = 0.1
            
            // Sync public furniture items
            let publicItems = try await syncPublicFurnitureItems()
            syncProgress = 0.4
            
            // Sync user's custom items
            let customItems = try await syncCustomItems()
            syncProgress = 0.6
            
            // Sync user preferences
            let favorites = try await syncFavorites()
            syncProgress = 0.8
            
            let recents = try await syncRecents()
            syncProgress = 0.9
            
            let catalogData = CatalogData(
                items: publicItems + customItems,
                favorites: favorites,
                recent: recents
            )
            
            lastSyncDate = Date()
            syncStatus = .success
            syncProgress = 1.0
            
            logInfo("Catalog sync completed successfully", category: .general, context: LogContext(customData: [
                "public_items": publicItems.count,
                "custom_items": customItems.count,
                "favorites": favorites.count,
                "recents": recents.count
            ]))
            
            return catalogData
            
        } catch {
            syncStatus = .failed(error.localizedDescription)
            logError("Catalog sync failed: \(error)", category: .general)
            throw error
        }
    }
    
    /// Sync user favorites
    public func syncFavorites(_ favoriteIDs: [UUID]) async {
        do {
            let record = try await getUserFavoritesRecord()
            record["favoriteIDs"] = favoriteIDs.map { $0.uuidString }
            record["lastModified"] = Date()
            
            _ = try await privateDatabase.save(record)
            
            logDebug("Synced favorites to cloud", category: .general, context: LogContext(customData: [
                "favorites_count": favoriteIDs.count
            ]))
            
        } catch {
            logError("Failed to sync favorites: \(error)", category: .general)
        }
    }
    
    /// Sync user recent items
    public func syncRecents(_ recentIDs: [UUID]) async {
        do {
            let record = try await getUserRecentsRecord()
            record["recentIDs"] = recentIDs.map { $0.uuidString }
            record["lastModified"] = Date()
            
            _ = try await privateDatabase.save(record)
            
            logDebug("Synced recents to cloud", category: .general, context: LogContext(customData: [
                "recents_count": recentIDs.count
            ]))
            
        } catch {
            logError("Failed to sync recents: \(error)", category: .general)
        }
    }
    
    /// Sync custom furniture item
    public func syncCustomItem(_ item: FurnitureItem) async {
        do {
            let record = createCustomItemRecord(from: item)
            _ = try await privateDatabase.save(record)
            
            logInfo("Synced custom item to cloud", category: .general, context: LogContext(customData: [
                "item_id": item.id.uuidString,
                "item_name": item.name
            ]))
            
        } catch {
            logError("Failed to sync custom item: \(error)", category: .general)
        }
    }
    
    /// Delete custom item from cloud
    public func deleteCustomItem(_ itemID: UUID) async {
        do {
            let recordID = CKRecord.ID(recordName: itemID.uuidString)
            _ = try await privateDatabase.deleteRecord(withID: recordID)
            
            logInfo("Deleted custom item from cloud", category: .general, context: LogContext(customData: [
                "item_id": itemID.uuidString
            ]))
            
        } catch {
            logError("Failed to delete custom item from cloud: \(error)", category: .general)
        }
    }
    
    /// Upload furniture item to public database (admin function)
    public func uploadPublicFurnitureItem(_ item: FurnitureItem) async throws {
        let record = createPublicItemRecord(from: item)
        _ = try await publicDatabase.save(record)
        
        logInfo("Uploaded public furniture item", category: .general, context: LogContext(customData: [
            "item_id": item.id.uuidString,
            "item_name": item.name
        ]))
    }
    
    /// Check for catalog updates
    public func checkForUpdates() async -> Bool {
        do {
            let query = CKQuery(recordType: furnitureItemRecordType, predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
            
            let (records, _) = try await publicDatabase.records(matching: query, resultsLimit: 1)
            
            guard let latestRecord = records.first?.1 else { return false }
            
            if let lastSync = lastSyncDate {
                return latestRecord.modificationDate ?? Date() > lastSync
            }
            
            return true
            
        } catch {
            logError("Failed to check for updates: \(error)", category: .general)
            return false
        }
    }
    
    /// Force full sync
    public func forceSyncCatalog() async throws -> CatalogData {
        lastSyncDate = nil // Clear last sync date to force full sync
        return try await syncCatalog()
    }
    
    // MARK: - Private Methods
    
    private func setupEncoder() {
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        
        decoder.dateDecodingStrategy = .iso8601
    }
    
    private func startPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { _ in
            Task { @MainActor in
                if await self.shouldPerformAutomaticSync() {
                    do {
                        _ = try await self.syncCatalog()
                    } catch {
                        logWarning("Automatic sync failed: \(error)", category: .general)
                    }
                }
            }
        }
    }
    
    private func shouldPerformAutomaticSync() async -> Bool {
        // Don't sync if already syncing
        if case .syncing = syncStatus {
            return false
        }
        
        // Check if enough time has passed since last sync
        if let lastSync = lastSyncDate {
            let timeSinceLastSync = Date().timeIntervalSince(lastSync)
            if timeSinceLastSync < syncInterval {
                return false
            }
        }
        
        // Check for updates
        return await checkForUpdates()
    }
    
    private func syncPublicFurnitureItems() async throws -> [FurnitureItem] {
        var allItems: [FurnitureItem] = []
        var cursor: CKQueryOperation.Cursor?
        
        repeat {
            let (items, nextCursor) = try await fetchPublicItemsBatch(cursor: cursor)
            allItems.append(contentsOf: items)
            cursor = nextCursor
            
            // Update progress
            let progress = 0.1 + (Float(allItems.count) / 1000.0) * 0.3 // Estimate 1000 items max
            syncProgress = min(progress, 0.4)
            
        } while cursor != nil
        
        return allItems
    }
    
    private func fetchPublicItemsBatch(cursor: CKQueryOperation.Cursor?) async throws -> ([FurnitureItem], CKQueryOperation.Cursor?) {
        let query = CKQuery(recordType: furnitureItemRecordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = batchSize
        operation.cursor = cursor
        
        return try await withCheckedThrowingContinuation { continuation in
            var items: [FurnitureItem] = []
            var error: Error?
            
            operation.recordMatchedBlock = { recordID, result in
                switch result {
                case .success(let record):
                    if let item = self.createFurnitureItem(from: record) {
                        items.append(item)
                    }
                case .failure(let err):
                    error = err
                }
            }
            
            operation.queryResultBlock = { result in
                switch result {
                case .success(let cursor):
                    continuation.resume(returning: (items, cursor))
                case .failure(let err):
                    continuation.resume(throwing: error ?? err)
                }
            }
            
            publicDatabase.add(operation)
        }
    }
    
    private func syncCustomItems() async throws -> [FurnitureItem] {
        let query = CKQuery(recordType: customItemRecordType, predicate: NSPredicate(value: true))
        
        let (records, _) = try await privateDatabase.records(matching: query)
        
        var customItems: [FurnitureItem] = []
        for (_, record) in records {
            if let item = createFurnitureItem(from: record) {
                customItems.append(item)
            }
        }
        
        return customItems
    }
    
    private func syncFavorites() async throws -> [UUID] {
        do {
            let record = try await getUserFavoritesRecord()
            let favoriteStrings = record["favoriteIDs"] as? [String] ?? []
            return favoriteStrings.compactMap { UUID(uuidString: $0) }
        } catch {
            if error is CKError && (error as! CKError).code == .unknownItem {
                // No favorites record exists yet
                return []
            }
            throw error
        }
    }
    
    private func syncRecents() async throws -> [UUID] {
        do {
            let record = try await getUserRecentsRecord()
            let recentStrings = record["recentIDs"] as? [String] ?? []
            return recentStrings.compactMap { UUID(uuidString: $0) }
        } catch {
            if error is CKError && (error as! CKError).code == .unknownItem {
                // No recents record exists yet
                return []
            }
            throw error
        }
    }
    
    private func getUserFavoritesRecord() async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: "userFavorites")
        
        do {
            return try await privateDatabase.record(for: recordID)
        } catch {
            if error is CKError && (error as! CKError).code == .unknownItem {
                // Create new record
                let record = CKRecord(recordType: userFavoritesRecordType, recordID: recordID)
                record["favoriteIDs"] = []
                record["lastModified"] = Date()
                return record
            }
            throw error
        }
    }
    
    private func getUserRecentsRecord() async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: "userRecents")
        
        do {
            return try await privateDatabase.record(for: recordID)
        } catch {
            if error is CKError && (error as! CKError).code == .unknownItem {
                // Create new record
                let record = CKRecord(recordType: userRecentsRecordType, recordID: recordID)
                record["recentIDs"] = []
                record["lastModified"] = Date()
                return record
            }
            throw error
        }
    }
    
    private func createPublicItemRecord(from item: FurnitureItem) -> CKRecord {
        let recordID = CKRecord.ID(recordName: item.id.uuidString)
        let record = CKRecord(recordType: furnitureItemRecordType, recordID: recordID)
        
        populateRecord(record, with: item)
        
        return record
    }
    
    private func createCustomItemRecord(from item: FurnitureItem) -> CKRecord {
        let recordID = CKRecord.ID(recordName: item.id.uuidString)
        let record = CKRecord(recordType: customItemRecordType, recordID: recordID)
        
        populateRecord(record, with: item)
        record["isCustom"] = true
        
        return record
    }
    
    private func populateRecord(_ record: CKRecord, with item: FurnitureItem) {
        // Basic properties
        record["name"] = item.name
        record["itemDescription"] = item.description
        record["category"] = item.category.rawValue
        record["subcategory"] = item.subcategory.rawValue
        record["brand"] = item.brand
        record["tags"] = item.tags
        record["dateAdded"] = item.dateAdded
        record["lastUpdated"] = item.lastUpdated
        record["isFeatured"] = item.isFeatured
        record["userRating"] = item.userRating
        record["popularityScore"] = item.popularityScore
        
        // Serialize complex objects as JSON
        do {
            record["model3D"] = try encoder.encode(item.model3D)
            record["metadata"] = try encoder.encode(item.metadata)
            record["pricing"] = try encoder.encode(item.pricing)
            record["availability"] = try encoder.encode(item.availability)
        } catch {
            logError("Failed to encode item data: \(error)", category: .general)
        }
        
        // Add thumbnail as asset if available
        if let thumbnailData = item.model3D.thumbnail {
            let tempURL = createTempThumbnailFile(data: thumbnailData)
            let asset = CKAsset(fileURL: tempURL)
            record["thumbnail"] = asset
        }
    }
    
    private func createFurnitureItem(from record: CKRecord) -> FurnitureItem? {
        do {
            guard let name = record["name"] as? String,
                  let description = record["itemDescription"] as? String,
                  let categoryString = record["category"] as? String,
                  let subcategoryString = record["subcategory"] as? String,
                  let category = FurnitureCategory(rawValue: categoryString),
                  let subcategory = FurnitureSubcategory(rawValue: subcategoryString) else {
                return nil
            }
            
            // Decode complex objects
            guard let model3DData = record["model3D"] as? Data,
                  let metadataData = record["metadata"] as? Data,
                  let pricingData = record["pricing"] as? Data,
                  let availabilityData = record["availability"] as? Data else {
                return nil
            }
            
            let model3D = try decoder.decode(Model3D.self, from: model3DData)
            let metadata = try decoder.decode(FurnitureMetadata.self, from: metadataData)
            let pricing = try decoder.decode(FurniturePricing.self, from: pricingData)
            let availability = try decoder.decode(FurnitureAvailability.self, from: availabilityData)
            
            // Extract other properties
            let brand = record["brand"] as? String
            let tags = record["tags"] as? [String] ?? []
            let dateAdded = record["dateAdded"] as? Date ?? Date()
            let lastUpdated = record["lastUpdated"] as? Date ?? Date()
            let isFeatured = record["isFeatured"] as? Bool ?? false
            let isCustom = record["isCustom"] as? Bool ?? false
            let userRating = record["userRating"] as? Float ?? 0.0
            let popularityScore = record["popularityScore"] as? Float ?? 0.0
            
            return FurnitureItem(
                id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
                name: name,
                description: description,
                category: category,
                subcategory: subcategory,
                brand: brand,
                model3D: model3D,
                metadata: metadata,
                pricing: pricing,
                availability: availability,
                tags: tags,
                dateAdded: dateAdded,
                lastUpdated: lastUpdated,
                isFeatured: isFeatured,
                isCustom: isCustom,
                userRating: userRating,
                popularityScore: popularityScore
            )
            
        } catch {
            logError("Failed to create furniture item from CloudKit record: \(error)", category: .general)
            return nil
        }
    }
    
    private func createTempThumbnailFile(data: Data) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        
        do {
            try data.write(to: tempFile)
            return tempFile
        } catch {
            logError("Failed to create temp thumbnail file: \(error)", category: .general)
            return tempDir.appendingPathComponent("placeholder.png")
        }
    }
}

// MARK: - Furniture Persistence Manager

public class FurniturePersistenceManager {
    
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var documentsDirectory: URL {
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private var furnitureDirectory: URL {
        return documentsDirectory.appendingPathComponent("Furniture")
    }
    
    private var catalogFile: URL {
        return furnitureDirectory.appendingPathComponent("catalog.json")
    }
    
    private var favoritesFile: URL {
        return furnitureDirectory.appendingPathComponent("favorites.json")
    }
    
    private var recentsFile: URL {
        return furnitureDirectory.appendingPathComponent("recents.json")
    }
    
    private var customItemsDirectory: URL {
        return furnitureDirectory.appendingPathComponent("CustomItems")
    }
    
    public init() {
        setupEncoder()
        createDirectories()
        
        logInfo("Furniture persistence manager initialized", category: .general)
    }
    
    // MARK: - Public Methods
    
    /// Load complete catalog data
    public func loadCatalogData() async throws -> CatalogData {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let items = try self.loadCatalogItems()
                    let favorites = try self.loadFavorites()
                    let recents = try self.loadRecents()
                    
                    let catalogData = CatalogData(
                        items: items,
                        favorites: favorites,
                        recent: recents
                    )
                    
                    continuation.resume(returning: catalogData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Save complete catalog data
    public func saveCatalogData(_ data: CatalogData) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try self.saveCatalogItems(data.items)
                    try self.saveFavorites(data.favorites)
                    try self.saveRecents(data.recent)
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Save favorites
    public func saveFavorites(_ favoriteIDs: [UUID]) async throws {
        let data = try encoder.encode(favoriteIDs)
        try data.write(to: favoritesFile)
    }
    
    /// Save recent items
    public func saveRecentItems(_ recentIDs: [UUID]) async throws {
        let data = try encoder.encode(recentIDs)
        try data.write(to: recentsFile)
    }
    
    /// Save custom furniture item
    public func saveCustomItem(_ item: FurnitureItem) async throws {
        let itemFile = customItemsDirectory.appendingPathComponent("\(item.id.uuidString).json")
        let data = try encoder.encode(item)
        try data.write(to: itemFile)
    }
    
    /// Delete custom furniture item
    public func deleteCustomItem(_ itemID: UUID) async throws {
        let itemFile = customItemsDirectory.appendingPathComponent("\(itemID.uuidString).json")
        
        if fileManager.fileExists(atPath: itemFile.path) {
            try fileManager.removeItem(at: itemFile)
        }
    }
    
    /// Load all custom items
    public func loadCustomItems() async throws -> [FurnitureItem] {
        let customFiles = try fileManager.contentsOfDirectory(at: customItemsDirectory, includingPropertiesForKeys: nil)
        
        var customItems: [FurnitureItem] = []
        
        for file in customFiles where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                let item = try decoder.decode(FurnitureItem.self, from: data)
                customItems.append(item)
            } catch {
                logWarning("Failed to load custom item from \(file.path): \(error)", category: .general)
            }
        }
        
        return customItems
    }
    
    // MARK: - Private Methods
    
    private func setupEncoder() {
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        
        decoder.dateDecodingStrategy = .iso8601
    }
    
    private func createDirectories() {
        let directories = [furnitureDirectory, customItemsDirectory]
        
        for directory in directories {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                logError("Failed to create directory \(directory.path): \(error)", category: .general)
            }
        }
    }
    
    private func loadCatalogItems() throws -> [FurnitureItem] {
        guard fileManager.fileExists(atPath: catalogFile.path) else {
            return []
        }
        
        let data = try Data(contentsOf: catalogFile)
        return try decoder.decode([FurnitureItem].self, from: data)
    }
    
    private func saveCatalogItems(_ items: [FurnitureItem]) throws {
        let data = try encoder.encode(items)
        try data.write(to: catalogFile)
    }
    
    private func loadFavorites() throws -> [UUID] {
        guard fileManager.fileExists(atPath: favoritesFile.path) else {
            return []
        }
        
        let data = try Data(contentsOf: favoritesFile)
        return try decoder.decode([UUID].self, from: data)
    }
    
    private func saveRecents(_ recentIDs: [UUID]) throws {
        let data = try encoder.encode(recentIDs)
        try data.write(to: recentsFile)
    }
    
    private func loadRecents() throws -> [UUID] {
        guard fileManager.fileExists(atPath: recentsFile.path) else {
            return []
        }
        
        let data = try Data(contentsOf: recentsFile)
        return try decoder.decode([UUID].self, from: data)
    }
}

// MARK: - Cloud Sync Errors

public enum CloudSyncError: LocalizedError {
    case accountUnavailable
    case networkUnavailable
    case quotaExceeded
    case authenticationFailed
    case dataCorrupted
    case syncTimeout
    
    public var errorDescription: String? {
        switch self {
        case .accountUnavailable:
            return "iCloud account not available"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .quotaExceeded:
            return "iCloud storage quota exceeded"
        case .authenticationFailed:
            return "iCloud authentication failed"
        case .dataCorrupted:
            return "Synchronized data is corrupted"
        case .syncTimeout:
            return "Synchronization timed out"
        }
    }
}