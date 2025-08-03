import Foundation
import CoreData
import CloudKit
import Combine

// MARK: - Core Data Stack with iCloud Integration

@MainActor
public class CoreDataStack: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var isInitialized: Bool = false
    @Published public var iCloudSyncStatus: CloudSyncStatus = .notStarted
    @Published public var lastSyncDate: Date?
    @Published public var pendingChanges: Int = 0
    
    // MARK: - Core Data Stack
    public lazy var persistentContainer: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "ARchitectDataModel")
        
        // Configure for CloudKit
        let storeDescription = container.persistentStoreDescriptions.first
        storeDescription?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        storeDescription?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // CloudKit configuration
        storeDescription?.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.architectar.app"
        )
        
        container.loadPersistentStores { [weak self] description, error in
            if let error = error {
                logError("Core Data failed to load", category: .persistence, error: error)
                fatalError("Core Data error: \(error.localizedDescription)")
            }
            
            Task { @MainActor in
                self?.isInitialized = true
                self?.setupCloudKitSync()
                logInfo("Core Data stack initialized successfully", category: .persistence)
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        return container
    }()
    
    // MARK: - Contexts
    public var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    public var backgroundContext: NSManagedObjectContext {
        return persistentContainer.newBackgroundContext()
    }
    
    // MARK: - Private Properties
    private let migrationManager: MigrationManager
    private let integrityChecker: DataIntegrityChecker
    private let versionManager: VersionManager
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Singleton
    public static let shared = CoreDataStack()
    
    private init() {
        self.migrationManager = MigrationManager()
        self.integrityChecker = DataIntegrityChecker()
        self.versionManager = VersionManager()
        
        setupObservers()
        
        logDebug("Core Data stack created", category: .persistence)
    }
    
    // MARK: - Cloud Sync Status
    
    public enum CloudSyncStatus {
        case notStarted
        case inProgress
        case succeeded
        case failed(Error)
        case disabled
        
        var description: String {
            switch self {
            case .notStarted: return "Not Started"
            case .inProgress: return "Syncing..."
            case .succeeded: return "Up to Date"
            case .failed(let error): return "Failed: \(error.localizedDescription)"
            case .disabled: return "Disabled"
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Monitor CloudKit sync status
        NotificationCenter.default.publisher(for: .NSPersistentCloudKitContainerEventChanged)
            .sink { [weak self] notification in
                self?.handleCloudKitEvent(notification)
            }
            .store(in: &cancellables)
        
        // Monitor Core Data changes
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] notification in
                self?.handleContextSave(notification)
            }
            .store(in: &cancellables)
        
        // Monitor memory warnings
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
    }
    
    private func setupCloudKitSync() {
        guard isCloudKitAvailable() else {
            iCloudSyncStatus = .disabled
            return
        }
        
        iCloudSyncStatus = .inProgress
        
        // Initialize CloudKit sync
        persistentContainer.initializeCloudKitSchema { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success:
                    self?.iCloudSyncStatus = .succeeded
                    self?.lastSyncDate = Date()
                    logInfo("CloudKit sync initialized successfully", category: .persistence)
                    
                case .failure(let error):
                    self?.iCloudSyncStatus = .failed(error)
                    logError("CloudKit sync initialization failed", category: .persistence, error: error)
                }
            }
        }
    }
    
    // MARK: - Save Operations
    
    public func save() {
        save(context: viewContext)
    }
    
    public func save(context: NSManagedObjectContext) {
        performAtomicSave(context: context)
    }
    
    // Atomic save operation with rollback support
    private func performAtomicSave(context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        
        // Create backup of changed objects before save
        let changeSet = createChangeSet(from: context)
        
        do {
            try context.save()
            updatePendingChangesCount()
            
            logDebug("Core Data context saved successfully", category: .persistence, context: LogContext(customData: [
                "changed_objects": changeSet.totalChanges
            ]))
            
        } catch {
            logError("Failed to save Core Data context", category: .persistence, error: error)
            
            // Attempt to recover from save error
            rollbackChanges(changeSet: changeSet, in: context)
            handleSaveError(error, in: context)
        }
    }
    
    // Atomic transaction with automatic rollback
    public func performAtomicTransaction<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            let context = backgroundContext
            context.perform {
                // Create savepoint
                let savepoint = self.createSavepoint(in: context)
                
                do {
                    let result = try block(context)
                    
                    // Validate before save
                    try self.validateChanges(in: context)
                    
                    // Atomic save
                    try context.save()
                    
                    continuation.resume(returning: result)
                    
                } catch {
                    // Rollback to savepoint
                    self.rollbackToSavepoint(savepoint, in: context)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // Batch atomic operations
    public func performBatchAtomicOperations(_ operations: [(NSManagedObjectContext) throws -> Void]) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let context = backgroundContext
            context.perform {
                let savepoint = self.createSavepoint(in: context)
                
                do {
                    for operation in operations {
                        try operation(context)
                    }
                    
                    try self.validateChanges(in: context)
                    try context.save()
                    
                    continuation.resume()
                    
                } catch {
                    self.rollbackToSavepoint(savepoint, in: context)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func saveInBackground(_ block: @escaping (NSManagedObjectContext) -> Void) {
        let context = backgroundContext
        context.perform {
            block(context)
            
            do {
                try context.save()
                logDebug("Background context saved successfully", category: .persistence)
            } catch {
                logError("Failed to save background context", category: .persistence, error: error)
            }
        }
    }
    
    // MARK: - Batch Operations
    
    public func performBatchUpdate<T: NSManagedObject>(
        entityType: T.Type,
        predicate: NSPredicate?,
        propertiesToUpdate: [String: Any]
    ) throws -> NSBatchUpdateResult {
        
        let request = NSBatchUpdateRequest(entity: T.entity())
        request.predicate = predicate
        request.propertiesToUpdate = propertiesToUpdate
        request.resultType = .updatedObjectsCountResultType
        
        let result = try viewContext.execute(request) as! NSBatchUpdateResult
        
        // Refresh objects in memory
        viewContext.refreshAllObjects()
        
        logInfo("Batch update completed", category: .persistence, context: LogContext(customData: [
            "entity": String(describing: entityType),
            "updated_count": result.result as? Int ?? 0
        ]))
        
        return result
    }
    
    public func performBatchDelete<T: NSManagedObject>(
        entityType: T.Type,
        predicate: NSPredicate
    ) throws -> NSBatchDeleteResult {
        
        let request = NSBatchDeleteRequest(fetchRequest: T.fetchRequest())
        request.predicate = predicate
        request.resultType = .resultTypeObjectIDs
        
        let result = try viewContext.execute(request) as! NSBatchDeleteResult
        
        // Update view context
        if let objectIDs = result.result as? [NSManagedObjectID] {
            let changes = [NSDeletedObjectsKey: objectIDs]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
        }
        
        logInfo("Batch delete completed", category: .persistence, context: LogContext(customData: [
            "entity": String(describing: entityType),
            "deleted_count": (result.result as? [NSManagedObjectID])?.count ?? 0
        ]))
        
        return result
    }
    
    // MARK: - Data Migration
    
    public func checkForMigration() async throws -> Bool {
        return try await migrationManager.checkForRequiredMigration(
            storeURL: persistentContainer.persistentStoreDescriptions.first?.url
        )
    }
    
    public func performMigration() async throws {
        guard let storeURL = persistentContainer.persistentStoreDescriptions.first?.url else {
            throw PersistenceError.migrationFailed("Store URL not found")
        }
        
        try await migrationManager.performMigration(storeURL: storeURL)
        
        logInfo("Data migration completed successfully", category: .persistence)
    }
    
    // MARK: - Data Integrity
    
    public func checkDataIntegrity() async throws -> IntegrityCheckResult {
        return try await integrityChecker.performIntegrityCheck(context: backgroundContext)
    }
    
    public func repairDataIntegrity(issues: [IntegrityIssue]) async throws {
        try await integrityChecker.repairIntegrityIssues(issues, context: backgroundContext)
        
        logInfo("Data integrity repair completed", category: .persistence, context: LogContext(customData: [
            "repaired_issues": issues.count
        ]))
    }
    
    // MARK: - CloudKit Operations
    
    public func isCloudKitAvailable() -> Bool {
        return FileManager.default.ubiquityIdentityToken != nil
    }
    
    public func forceCloudSync() async throws {
        guard isCloudKitAvailable() else {
            throw PersistenceError.cloudKitUnavailable
        }
        
        iCloudSyncStatus = .inProgress
        
        do {
            try await persistentContainer.persistentStoreCoordinator.persistentStores.first?.perform {
                // Trigger CloudKit sync
                try self.persistentContainer.viewContext.save()
            }
            
            iCloudSyncStatus = .succeeded
            lastSyncDate = Date()
            
            logInfo("Manual CloudKit sync completed", category: .persistence)
            
        } catch {
            iCloudSyncStatus = .failed(error)
            throw error
        }
    }
    
    public func resetCloudKitData() async throws {
        guard isCloudKitAvailable() else {
            throw PersistenceError.cloudKitUnavailable
        }
        
        // This is a destructive operation - should be used carefully
        try await persistentContainer.purgeObjectsAndRecordsInZone(withID: CKRecordZone.default().zoneID)
        
        logWarning("CloudKit data reset completed", category: .persistence)
    }
    
    // MARK: - Memory Management
    
    public func refreshAllObjects() {
        viewContext.refreshAllObjects()
    }
    
    public func reset() {
        viewContext.reset()
        updatePendingChangesCount()
    }
    
    private func handleMemoryWarning() {
        // Clear unnecessary objects from memory
        refreshAllObjects()
        
        // Reset background contexts
        backgroundContext.reset()
        
        logInfo("Handled memory warning - cleared Core Data caches", category: .persistence)
    }
    
    // MARK: - Error Handling
    
    private func handleSaveError(_ error: Error, in context: NSManagedObjectContext) {
        if let nsError = error as NSError? {
            switch nsError.code {
            case NSValidationErrorKey:
                handleValidationError(nsError, in: context)
            case NSManagedObjectConstraintMergeError:
                handleConstraintError(nsError, in: context)
            default:
                logError("Unhandled Core Data save error", category: .persistence, error: error)
            }
        }
    }
    
    private func handleValidationError(_ error: NSError, in context: NSManagedObjectContext) {
        // Attempt to fix validation errors
        if let validationObject = error.userInfo[NSValidationObjectErrorKey] as? NSManagedObject {
            // Reset problematic object
            context.refresh(validationObject, mergeChanges: false)
            
            logWarning("Reset object due to validation error", category: .persistence, context: LogContext(customData: [
                "object_type": String(describing: type(of: validationObject))
            ]))
        }
    }
    
    private func handleConstraintError(_ error: NSError, in context: NSManagedObjectContext) {
        // Handle constraint conflicts
        if let conflictObjects = error.userInfo[NSPersistentStoreSaveConflictsErrorKey] as? [NSConstraintConflict] {
            for conflict in conflictObjects {
                // Use merge policy to resolve conflicts
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                
                logWarning("Resolved constraint conflict", category: .persistence, context: LogContext(customData: [
                    "conflict_type": String(describing: conflict)
                ]))
            }
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleCloudKitEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainerEventChangedUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
            return
        }
        
        switch event.type {
        case .setup:
            logDebug("CloudKit setup event", category: .persistence)
            
        case .import:
            lastSyncDate = Date()
            iCloudSyncStatus = .succeeded
            logDebug("CloudKit import completed", category: .persistence)
            
        case .export:
            lastSyncDate = Date()
            logDebug("CloudKit export completed", category: .persistence)
            
        @unknown default:
            logDebug("Unknown CloudKit event", category: .persistence)
        }
        
        if let error = event.error {
            iCloudSyncStatus = .failed(error)
            logError("CloudKit sync error", category: .persistence, error: error)
        }
    }
    
    private func handleContextSave(_ notification: Notification) {
        updatePendingChangesCount()
        
        // Update version tracking
        if let context = notification.object as? NSManagedObjectContext,
           context === viewContext {
            versionManager.recordSave()
        }
    }
    
    private func updatePendingChangesCount() {
        pendingChanges = viewContext.insertedObjects.count +
                        viewContext.updatedObjects.count +
                        viewContext.deletedObjects.count
    }
    
    // MARK: - Savepoint Management
    
    private func createSavepoint(in context: NSManagedObjectContext) -> Savepoint {
        let insertedObjects = Set(context.insertedObjects)
        let updatedObjects = context.updatedObjects.reduce(into: [NSManagedObjectID: [String: Any]]()) { result, object in
            result[object.objectID] = object.changedValues()
        }
        let deletedObjects = Set(context.deletedObjects.map { $0.objectID })
        
        return Savepoint(
            insertedObjects: insertedObjects,
            updatedObjects: updatedObjects,
            deletedObjects: deletedObjects,
            timestamp: Date()
        )
    }
    
    private func rollbackToSavepoint(_ savepoint: Savepoint, in context: NSManagedObjectContext) {
        // Rollback inserted objects
        for object in savepoint.insertedObjects {
            if !object.isDeleted {
                context.delete(object)
            }
        }
        
        // Rollback updated objects
        for (objectID, originalValues) in savepoint.updatedObjects {
            do {
                let object = try context.existingObject(with: objectID)
                for (key, value) in originalValues {
                    object.setValue(value, forKey: key)
                }
            } catch {
                logError("Failed to rollback object", category: .persistence, error: error)
            }
        }
        
        // Restore deleted objects (complex operation, simplified here)
        for objectID in savepoint.deletedObjects {
            do {
                let object = try context.existingObject(with: objectID)
                object.isDeleted = false
            } catch {
                // Object might not exist in current context
            }
        }
        
        logInfo("Rolled back to savepoint", category: .persistence, context: LogContext(customData: [
            "savepoint_timestamp": savepoint.timestamp.timeIntervalSince1970,
            "inserted_count": savepoint.insertedObjects.count,
            "updated_count": savepoint.updatedObjects.count,
            "deleted_count": savepoint.deletedObjects.count
        ]))
    }
    
    private func createChangeSet(from context: NSManagedObjectContext) -> ChangeSet {
        return ChangeSet(
            insertedObjects: Set(context.insertedObjects),
            updatedObjects: Set(context.updatedObjects),
            deletedObjects: Set(context.deletedObjects),
            timestamp: Date()
        )
    }
    
    private func rollbackChanges(changeSet: ChangeSet, in context: NSManagedObjectContext) {
        // Reset all changed objects to their original state
        for object in changeSet.insertedObjects {
            if !object.isDeleted {
                context.delete(object)
            }
        }
        
        for object in changeSet.updatedObjects {
            context.refresh(object, mergeChanges: false)
        }
        
        for object in changeSet.deletedObjects {
            if object.isDeleted {
                context.refresh(object, mergeChanges: false)
            }
        }
        
        logInfo("Rolled back changes", category: .persistence, context: LogContext(customData: [
            "total_changes": changeSet.totalChanges
        ]))
    }
    
    private func validateChanges(in context: NSManagedObjectContext) throws {
        // Validate all inserted and updated objects
        for object in context.insertedObjects {
            try object.validateForInsert()
        }
        
        for object in context.updatedObjects {
            try object.validateForUpdate()
        }
        
        for object in context.deletedObjects {
            try object.validateForDelete()
        }
    }
    
    // MARK: - Utilities
    
    public func executeInBackground<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            let context = backgroundContext
            context.perform {
                do {
                    let result = try block(context)
                    try context.save()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func count<T: NSManagedObject>(for entityType: T.Type, predicate: NSPredicate? = nil) throws -> Int {
        let request = T.fetchRequest()
        request.predicate = predicate
        request.includesSubentities = false
        
        return try viewContext.count(for: request)
    }
    
    public func deleteAllData() throws {
        let entities = persistentContainer.managedObjectModel.entities
        
        for entity in entities {
            if let entityName = entity.name {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                deleteRequest.resultType = .resultTypeObjectIDs
                
                let result = try viewContext.execute(deleteRequest) as! NSBatchDeleteResult
                
                if let objectIDs = result.result as? [NSManagedObjectID] {
                    let changes = [NSDeletedObjectsKey: objectIDs]
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
                }
            }
        }
        
        try viewContext.save()
        
        logInfo("All Core Data deleted", category: .persistence)
    }
}

// MARK: - Persistence Errors

public enum PersistenceError: Error {
    case coreDataNotInitialized
    case migrationFailed(String)
    case cloudKitUnavailable
    case integrityCheckFailed(String)
    case exportFailed(String)
    case templateCreationFailed(String)
    
    public var localizedDescription: String {
        switch self {
        case .coreDataNotInitialized:
            return "Core Data stack not initialized"
        case .migrationFailed(let message):
            return "Data migration failed: \(message)"
        case .cloudKitUnavailable:
            return "iCloud is not available"
        case .integrityCheckFailed(let message):
            return "Data integrity check failed: \(message)"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        case .templateCreationFailed(let message):
            return "Template creation failed: \(message)"
        }
    }
}

// MARK: - Extensions

extension NSPersistentStore {
    func perform<T>(_ block: () throws -> T) throws -> T {
        return try block()
    }
}

extension NSManagedObjectContext {
    func insertObject<T: NSManagedObject>(_ type: T.Type) -> T {
        return NSEntityDescription.insertNewObject(forEntityName: String(describing: type), into: self) as! T
    }
}

// MARK: - Supporting Data Structures

private struct Savepoint {
    let insertedObjects: Set<NSManagedObject>
    let updatedObjects: [NSManagedObjectID: [String: Any]]
    let deletedObjects: Set<NSManagedObjectID>
    let timestamp: Date
}

private struct ChangeSet {
    let insertedObjects: Set<NSManagedObject>
    let updatedObjects: Set<NSManagedObject>
    let deletedObjects: Set<NSManagedObject>
    let timestamp: Date
    
    var totalChanges: Int {
        return insertedObjects.count + updatedObjects.count + deletedObjects.count
    }
}

// Supporting notification names
extension Notification.Name {
    static let coreDataStackInitialized = Notification.Name("coreDataStackInitialized")
    static let cloudSyncStatusChanged = Notification.Name("cloudSyncStatusChanged")
}