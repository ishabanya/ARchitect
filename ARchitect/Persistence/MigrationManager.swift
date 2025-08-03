import Foundation
import CoreData
import Combine

// MARK: - Data Migration Management System

@MainActor
public class MigrationManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var migrationState: MigrationState = .notRequired
    @Published public var migrationProgress: Double = 0.0
    @Published public var currentMigrationVersion: String?
    @Published public var availableMigrations: [MigrationPlan] = []
    
    // MARK: - Private Properties
    private let modelVersionManager: ModelVersionManager
    private let migrationValidator: MigrationValidator
    private let backupManager: MigrationBackupManager
    private let progressTracker: MigrationProgressTracker
    
    private var migrationTask: Task<Void, Never>?
    
    // MARK: - Migration Configuration
    private let migrationTimeout: TimeInterval = 300.0 // 5 minutes
    private let backupRetentionDays = 30
    
    public init() {
        self.modelVersionManager = ModelVersionManager()
        self.migrationValidator = MigrationValidator()
        self.backupManager = MigrationBackupManager()
        self.progressTracker = MigrationProgressTracker()
        
        loadAvailableMigrations()
        
        logDebug("Migration manager initialized", category: .persistence)
    }
    
    // MARK: - Migration States
    
    public enum MigrationState {
        case notRequired
        case required
        case preparing
        case backing_up
        case migrating
        case validating
        case completed
        case failed(Error)
        case rollback_required
        case rollback_in_progress
        case rollback_completed
        
        var description: String {
            switch self {
            case .notRequired: return "No migration required"
            case .required: return "Migration required"
            case .preparing: return "Preparing migration..."
            case .backing_up: return "Creating backup..."
            case .migrating: return "Migrating data..."
            case .validating: return "Validating migration..."
            case .completed: return "Migration completed"
            case .failed(let error): return "Migration failed: \(error.localizedDescription)"
            case .rollback_required: return "Rollback required"
            case .rollback_in_progress: return "Rolling back..."
            case .rollback_completed: return "Rollback completed"
            }
        }
        
        var isInProgress: Bool {
            switch self {
            case .preparing, .backing_up, .migrating, .validating, .rollback_in_progress:
                return true
            default:
                return false
            }
        }
    }
    
    // MARK: - Migration Detection
    
    public func checkForRequiredMigration(storeURL: URL?) async throws -> Bool {
        guard let storeURL = storeURL else {
            throw MigrationError.storeURLNotFound
        }
        
        // Check if store exists
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            migrationState = .notRequired
            return false
        }
        
        guard let currentModel = NSManagedObjectModel.mergedModel(from: [Bundle.main]) else {
            throw MigrationError.invalidModel("Unable to create model from bundle")
        }
        let storeMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: nil
        )
        
        let isCompatible = currentModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: storeMetadata)
        
        if !isCompatible {
            migrationState = .required
            
            // Identify required migration path
            let migrationPlan = try identifyMigrationPlan(
                from: storeMetadata,
                to: currentModel
            )
            
            currentMigrationVersion = migrationPlan.targetVersion
            
            logInfo("Migration required", category: .persistence, context: LogContext(customData: [
                "current_version": migrationPlan.sourceVersion,
                "target_version": migrationPlan.targetVersion,
                "migration_steps": migrationPlan.steps.count
            ]))
            
            return true
        } else {
            migrationState = .notRequired
            return false
        }
    }
    
    // MARK: - Migration Execution
    
    public func performMigration(storeURL: URL) async throws {
        guard migrationState == .required else {
            throw MigrationError.migrationNotRequired
        }
        
        migrationTask = Task {
            do {
                try await executeMigration(storeURL: storeURL)
            } catch {
                await handleMigrationError(error)
            }
        }
        
        await migrationTask?.value
    }
    
    private func executeMigration(storeURL: URL) async throws {
        migrationState = .preparing
        migrationProgress = 0.0
        
        // Step 1: Create backup
        migrationState = .backing_up
        let backupInfo = try await createPreMigrationBackup(storeURL: storeURL)
        migrationProgress = 0.1
        
        do {
            // Step 2: Identify migration plan
            let storeMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType,
                at: storeURL,
                options: nil
            )
            
            let currentModel = NSManagedObjectModel.mergedModel(from: [Bundle.main])!
            let migrationPlan = try identifyMigrationPlan(
                from: storeMetadata,
                to: currentModel
            )
            
            migrationProgress = 0.2
            
            // Step 3: Execute migration steps
            migrationState = .migrating
            try await executeMigrationSteps(
                migrationPlan: migrationPlan,
                storeURL: storeURL
            )
            
            migrationProgress = 0.8
            
            // Step 4: Validate migration
            migrationState = .validating
            try await validateMigration(storeURL: storeURL, migrationPlan: migrationPlan)
            
            migrationProgress = 0.95
            
            // Step 5: Cleanup
            try await performPostMigrationCleanup(backupInfo: backupInfo)
            
            migrationProgress = 1.0
            migrationState = .completed
            
            logInfo("Migration completed successfully", category: .persistence, context: LogContext(customData: [
                "migration_version": migrationPlan.targetVersion,
                "migration_steps": migrationPlan.steps.count
            ]))
            
        } catch {
            // Attempt rollback if migration fails
            logError("Migration failed, attempting rollback", category: .persistence, error: error)
            
            try await performRollback(
                storeURL: storeURL,
                backupInfo: backupInfo,
                originalError: error
            )
            
            throw error
        }
    }
    
    // MARK: - Migration Steps Execution
    
    private func executeMigrationSteps(
        migrationPlan: MigrationPlan,
        storeURL: URL
    ) async throws {
        
        let totalSteps = migrationPlan.steps.count
        var currentStoreURL = storeURL
        
        for (index, step) in migrationPlan.steps.enumerated() {
            logInfo("Executing migration step", category: .persistence, context: LogContext(customData: [
                "step": "\(index + 1)/\(totalSteps)",
                "from_version": step.sourceVersion,
                "to_version": step.targetVersion
            ]))
            
            // Execute single migration step
            let migratedStoreURL = try await executeSingleMigrationStep(
                step: step,
                sourceStoreURL: currentStoreURL
            )
            
            // Update progress
            let stepProgress = 0.6 * Double(index + 1) / Double(totalSteps)
            migrationProgress = 0.2 + stepProgress
            
            // Clean up intermediate stores
            if currentStoreURL != storeURL {
                try FileManager.default.removeItem(at: currentStoreURL)
            }
            
            currentStoreURL = migratedStoreURL
        }
        
        // Replace original store with final migrated store
        if currentStoreURL != storeURL {
            let backupURL = storeURL.appendingPathExtension("migration_temp")
            try FileManager.default.moveItem(at: storeURL, to: backupURL)
            try FileManager.default.moveItem(at: currentStoreURL, to: storeURL)
            try FileManager.default.removeItem(at: backupURL)
        }
    }
    
    private func executeSingleMigrationStep(
        step: MigrationStep,
        sourceStoreURL: URL
    ) async throws -> URL {
        
        let sourceModel = try loadManagedObjectModel(version: step.sourceVersion)
        let destinationModel = try loadManagedObjectModel(version: step.targetVersion)
        
        // Create mapping model
        let mappingModel = try createMappingModel(
            from: sourceModel,
            to: destinationModel,
            step: step
        )
        
        // Setup migration manager
        let migrationManager = NSMigrationManager(sourceModel: sourceModel, destinationModel: destinationModel)
        
        // Create destination store URL
        let destinationStoreURL = sourceStoreURL.appendingPathExtension("migrated_\(step.targetVersion)")
        
        // Remove existing destination store if exists
        if FileManager.default.fileExists(atPath: destinationStoreURL.path) {
            try FileManager.default.removeItem(at: destinationStoreURL)
        }
        
        // Perform migration
        try migrationManager.migrateStore(
            from: sourceStoreURL,
            sourceType: NSSQLiteStoreType,
            options: nil,
            with: mappingModel,
            toDestinationURL: destinationStoreURL,
            destinationType: NSSQLiteStoreType,
            destinationOptions: nil
        )
        
        return destinationStoreURL
    }
    
    // MARK: - Migration Planning
    
    private func identifyMigrationPlan(
        from storeMetadata: [String: Any],
        to destinationModel: NSManagedObjectModel
    ) throws -> MigrationPlan {
        
        let sourceVersion = extractModelVersion(from: storeMetadata)
        let destinationVersion = extractModelVersion(from: destinationModel)
        
        guard sourceVersion != destinationVersion else {
            throw MigrationError.noMigrationRequired
        }
        
        // Find migration path
        let migrationSteps = try findMigrationPath(
            from: sourceVersion,
            to: destinationVersion
        )
        
        return MigrationPlan(
            id: UUID(),
            sourceVersion: sourceVersion,
            targetVersion: destinationVersion,
            steps: migrationSteps,
            estimatedDuration: estimateMigrationDuration(steps: migrationSteps),
            createdAt: Date()
        )
    }
    
    private func findMigrationPath(
        from sourceVersion: String,
        to targetVersion: String
    ) throws -> [MigrationStep] {
        
        // Load available migration mappings
        let availableVersions = modelVersionManager.getAvailableVersions()
        let migrationMappings = modelVersionManager.getMigrationMappings()
        
        // Use Dijkstra's algorithm to find shortest migration path
        var steps: [MigrationStep] = []
        var currentVersion = sourceVersion
        
        while currentVersion != targetVersion {
            guard let nextVersion = findNextMigrationVersion(
                from: currentVersion,
                toward: targetVersion,
                availableVersions: availableVersions,
                mappings: migrationMappings
            ) else {
                throw MigrationError.migrationPathNotFound(from: currentVersion, to: targetVersion)
            }
            
            let step = MigrationStep(
                id: UUID(),
                sourceVersion: currentVersion,
                targetVersion: nextVersion,
                mappingModelName: "\(currentVersion)to\(nextVersion)",
                customMigrationPolicy: migrationMappings["\(currentVersion)->\(nextVersion)"]?.customPolicy,
                estimatedDuration: 30.0 // Default estimate
            )
            
            steps.append(step)
            currentVersion = nextVersion
        }
        
        return steps
    }
    
    private func findNextMigrationVersion(
        from currentVersion: String,
        toward targetVersion: String,
        availableVersions: [String],
        mappings: [String: MigrationMapping]
    ) -> String? {
        
        // Find available migration from current version
        let availableMigrations = mappings.keys.compactMap { key -> String? in
            if key.hasPrefix("\(currentVersion)->") {
                return String(key.dropFirst("\(currentVersion)->".count))
            }
            return nil
        }
        
        // Prefer direct migration to target if available
        if availableMigrations.contains(targetVersion) {
            return targetVersion
        }
        
        // Otherwise, choose next version in sequence
        return availableMigrations.sorted().first
    }
    
    // MARK: - Model Management
    
    private func loadManagedObjectModel(version: String) throws -> NSManagedObjectModel {
        return try modelVersionManager.loadModel(version: version)
    }
    
    private func createMappingModel(
        from sourceModel: NSManagedObjectModel,
        to destinationModel: NSManagedObjectModel,
        step: MigrationStep
    ) throws -> NSMappingModel {
        
        // Try to load custom mapping model first
        if let mappingModel = NSMappingModel(from: [Bundle.main], forSourceModel: sourceModel, destinationModel: destinationModel) {
            return mappingModel
        }
        
        // Generate mapping model automatically
        do {
            return try NSMappingModel.inferredMappingModel(
                forSourceModel: sourceModel,
                destinationModel: destinationModel
            )
        } catch {
            throw MigrationError.mappingModelCreationFailed(step.sourceVersion, step.targetVersion, error)
        }
    }
    
    // MARK: - Backup Management
    
    private func createPreMigrationBackup(storeURL: URL) async throws -> BackupInfo {
        return try await backupManager.createBackup(
            storeURL: storeURL,
            backupType: .preMigration,
            retainForDays: backupRetentionDays
        )
    }
    
    // MARK: - Validation
    
    private func validateMigration(
        storeURL: URL,
        migrationPlan: MigrationPlan
    ) async throws {
        
        let validationResult = try await migrationValidator.validateMigratedStore(
            storeURL: storeURL,
            expectedVersion: migrationPlan.targetVersion
        )
        
        guard validationResult.isValid else {
            throw MigrationError.validationFailed(validationResult.issues)
        }
        
        // Perform data integrity checks
        let integrityResult = try await migrationValidator.validateDataIntegrity(storeURL: storeURL)
        
        guard integrityResult.isValid else {
            throw MigrationError.dataIntegrityCheckFailed(integrityResult.issues)
        }
    }
    
    // MARK: - Rollback
    
    private func performRollback(
        storeURL: URL,
        backupInfo: BackupInfo,
        originalError: Error
    ) async throws {
        
        migrationState = .rollback_in_progress
        
        do {
            try await backupManager.restoreBackup(
                backupInfo: backupInfo,
                targetURL: storeURL
            )
            
            migrationState = .rollback_completed
            
            logInfo("Migration rollback completed", category: .persistence)
            
        } catch {
            migrationState = .failed(MigrationError.rollbackFailed(error))
            
            logError("Migration rollback failed", category: .persistence, error: error)
            throw MigrationError.rollbackFailed(error)
        }
    }
    
    // MARK: - Cleanup
    
    private func performPostMigrationCleanup(backupInfo: BackupInfo) async throws {
        // Clean up temporary files
        try backupManager.cleanupTemporaryFiles()
        
        // Optionally remove backup after successful migration
        // (keeping it for now for safety)
        
        logDebug("Post-migration cleanup completed", category: .persistence)
    }
    
    // MARK: - Helper Methods
    
    private func loadAvailableMigrations() {
        availableMigrations = modelVersionManager.getAvailableMigrationPlans()
    }
    
    private func extractModelVersion(from metadata: [String: Any]) -> String {
        if let versionHashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data],
           let versionIdentifiers = metadata[NSStoreModelVersionIdentifiersKey] as? [String] {
            return versionIdentifiers.first ?? "1.0"
        }
        return "1.0"
    }
    
    private func extractModelVersion(from model: NSManagedObjectModel) -> String {
        return model.versionIdentifiers.first as? String ?? "1.0"
    }
    
    private func estimateMigrationDuration(steps: [MigrationStep]) -> TimeInterval {
        return steps.reduce(0) { $0 + $1.estimatedDuration }
    }
    
    private func handleMigrationError(_ error: Error) async {
        migrationState = .failed(error)
        
        logError("Migration failed", category: .persistence, error: error)
    }
    
    // MARK: - Public Interface
    
    public func cancelMigration() {
        migrationTask?.cancel()
        migrationState = .notRequired
        migrationProgress = 0.0
    }
    
    public func getMigrationHistory() -> [MigrationHistoryEntry] {
        return backupManager.getMigrationHistory()
    }
    
    public func cleanupOldBackups() async throws {
        try await backupManager.cleanupOldBackups(olderThanDays: backupRetentionDays)
    }
    
    public func validateCurrentStore(storeURL: URL) async throws -> ValidationResult {
        return try await migrationValidator.validateCurrentStore(storeURL: storeURL)
    }
    
    public func getStoreDiagnostics(storeURL: URL) async throws -> StoreDiagnostics {
        return try await migrationValidator.getStoreDiagnostics(storeURL: storeURL)
    }
}

// MARK: - Supporting Data Structures

public struct MigrationPlan: Identifiable {
    public let id: UUID
    public let sourceVersion: String
    public let targetVersion: String
    public let steps: [MigrationStep]
    public let estimatedDuration: TimeInterval
    public let createdAt: Date
}

public struct MigrationStep: Identifiable {
    public let id: UUID
    public let sourceVersion: String
    public let targetVersion: String
    public let mappingModelName: String
    public let customMigrationPolicy: String?
    public let estimatedDuration: TimeInterval
}

public struct MigrationMapping {
    public let sourceVersion: String
    public let targetVersion: String
    public let mappingModelName: String
    public let customPolicy: String?
    public let isRequired: Bool
}

public struct BackupInfo {
    public let id: UUID
    public let originalStoreURL: URL
    public let backupURL: URL
    public let backupType: BackupType
    public let createdAt: Date
    public let expiresAt: Date
    public let fileSize: Int64
    
    public enum BackupType {
        case preMigration
        case manual
        case automatic
        case beforeRollback
    }
}

public struct MigrationHistoryEntry: Identifiable {
    public let id: UUID
    public let fromVersion: String
    public let toVersion: String
    public let startedAt: Date
    public let completedAt: Date?
    public let result: MigrationResult
    public let backupInfo: BackupInfo?
    
    public enum MigrationResult {
        case succeeded
        case failed(Error)
        case rolledBack
        case cancelled
    }
}

public struct StoreDiagnostics {
    public let storeURL: URL
    public let storeType: String
    public let modelVersion: String
    public let fileSize: Int64
    public let isCompatible: Bool
    public let lastModified: Date
    public let entityCounts: [String: Int]
    public let healthScore: Float
}

public enum MigrationError: Error {
    case storeURLNotFound
    case migrationNotRequired
    case noMigrationRequired
    case migrationPathNotFound(from: String, to: String)
    case mappingModelCreationFailed(String, String, Error)
    case validationFailed([String])
    case dataIntegrityCheckFailed([String])
    case rollbackFailed(Error)
    case migrationTimeout
    case backupCreationFailed(Error)
    case customMigrationFailed(String, Error)
    
    public var localizedDescription: String {
        switch self {
        case .storeURLNotFound:
            return "Store URL not found"
        case .migrationNotRequired:
            return "Migration not required"
        case .noMigrationRequired:
            return "No migration required"
        case .migrationPathNotFound(let from, let to):
            return "Migration path not found from \(from) to \(to)"
        case .mappingModelCreationFailed(let from, let to, let error):
            return "Failed to create mapping model from \(from) to \(to): \(error.localizedDescription)"
        case .validationFailed(let issues):
            return "Migration validation failed: \(issues.joined(separator: ", "))"
        case .dataIntegrityCheckFailed(let issues):
            return "Data integrity check failed: \(issues.joined(separator: ", "))"
        case .rollbackFailed(let error):
            return "Migration rollback failed: \(error.localizedDescription)"
        case .migrationTimeout:
            return "Migration operation timed out"
        case .backupCreationFailed(let error):
            return "Backup creation failed: \(error.localizedDescription)"
        case .customMigrationFailed(let step, let error):
            return "Custom migration step '\(step)' failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Supporting Classes

@MainActor
class ModelVersionManager {
    private let availableVersions = ["1.0", "1.1", "1.2", "2.0"] // Would be dynamically loaded
    private let migrationMappings: [String: MigrationMapping] = [:]
    
    func getAvailableVersions() -> [String] {
        return availableVersions
    }
    
    func getMigrationMappings() -> [String: MigrationMapping] {
        return migrationMappings
    }
    
    func loadModel(version: String) throws -> NSManagedObjectModel {
        guard let modelURL = Bundle.main.url(forResource: "ARchitectDataModel_\(version)", withExtension: "momd") ??
                Bundle.main.url(forResource: "ARchitectDataModel", withExtension: "momd") else {
            throw MigrationError.mappingModelCreationFailed(version, "current", NSError(domain: "ModelNotFound", code: 404))
        }
        
        guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw MigrationError.mappingModelCreationFailed(version, "current", NSError(domain: "ModelLoadFailed", code: 500))
        }
        
        return model
    }
    
    func getAvailableMigrationPlans() -> [MigrationPlan] {
        // Load available migration plans from configuration
        return []
    }
}

@MainActor
class MigrationValidator {
    func validateMigratedStore(storeURL: URL, expectedVersion: String) async throws -> ValidationResult {
        var issues: [String] = []
        
        // Check if store exists
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            issues.append("Migrated store file not found")
            return ValidationResult(isValid: false, issues: issues)
        }
        
        // Check store metadata
        do {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType,
                at: storeURL,
                options: nil
            )
            
            // Validate version
            if let versionIdentifiers = metadata[NSStoreModelVersionIdentifiersKey] as? [String],
               !versionIdentifiers.contains(expectedVersion) {
                issues.append("Store version does not match expected version")
            }
            
        } catch {
            issues.append("Failed to read store metadata: \(error.localizedDescription)")
        }
        
        return ValidationResult(isValid: issues.isEmpty, issues: issues)
    }
    
    func validateDataIntegrity(storeURL: URL) async throws -> ValidationResult {
        var issues: [String] = []
        
        // Perform integrity checks
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel.mergedModel(from: [Bundle.main])!)
        
        do {
            let store = try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: [NSReadOnlyPersistentStoreOption: true]
            )
            
            // Check entities
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            
            try context.performAndWait {
                // Validate each entity
                for entity in coordinator.managedObjectModel.entities {
                    if let entityName = entity.name {
                        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
                        request.fetchLimit = 1
                        
                        do {
                            _ = try context.fetch(request)
                        } catch {
                            issues.append("Failed to query entity \(entityName): \(error.localizedDescription)")
                        }
                    }
                }
            }
            
            try coordinator.remove(store)
            
        } catch {
            issues.append("Failed to validate store: \(error.localizedDescription)")
        }
        
        return ValidationResult(isValid: issues.isEmpty, issues: issues)
    }
    
    func validateCurrentStore(storeURL: URL) async throws -> ValidationResult {
        // Validate current store without migration
        return try await validateDataIntegrity(storeURL: storeURL)
    }
    
    func getStoreDiagnostics(storeURL: URL) async throws -> StoreDiagnostics {
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        let lastModified = fileAttributes[.modificationDate] as? Date ?? Date()
        
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: nil
        )
        
        let modelVersion = (metadata[NSStoreModelVersionIdentifiersKey] as? [String])?.first ?? "Unknown"
        let currentModel = NSManagedObjectModel.mergedModel(from: [Bundle.main])!
        let isCompatible = currentModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
        
        return StoreDiagnostics(
            storeURL: storeURL,
            storeType: NSSQLiteStoreType,
            modelVersion: modelVersion,
            fileSize: fileSize,
            isCompatible: isCompatible,
            lastModified: lastModified,
            entityCounts: [:], // Would be populated with actual counts
            healthScore: isCompatible ? 1.0 : 0.5
        )
    }
}

@MainActor
class MigrationBackupManager {
    private let backupsDirectory: URL
    
    init() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.backupsDirectory = documentsDirectory.appendingPathComponent("Migration_Backups")
        
        // Create backups directory if needed
        try? FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
    }
    
    func createBackup(
        storeURL: URL,
        backupType: BackupInfo.BackupType,
        retainForDays: Int
    ) async throws -> BackupInfo {
        
        let backupId = UUID()
        let timestamp = DateFormatter.backupFormatter.string(from: Date())
        let backupFileName = "backup_\(timestamp)_\(backupId.uuidString).sqlite"
        let backupURL = backupsDirectory.appendingPathComponent(backupFileName)
        
        // Copy store file
        try FileManager.default.copyItem(at: storeURL, to: backupURL)
        
        // Copy WAL and SHM files if they exist
        let walURL = storeURL.appendingPathExtension("sqlite-wal")
        let shmURL = storeURL.appendingPathExtension("sqlite-shm")
        
        if FileManager.default.fileExists(atPath: walURL.path) {
            try FileManager.default.copyItem(
                at: walURL,
                to: backupURL.appendingPathExtension("sqlite-wal")
            )
        }
        
        if FileManager.default.fileExists(atPath: shmURL.path) {
            try FileManager.default.copyItem(
                at: shmURL,
                to: backupURL.appendingPathExtension("sqlite-shm")
            )
        }
        
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: backupURL.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        
        let backupInfo = BackupInfo(
            id: backupId,
            originalStoreURL: storeURL,
            backupURL: backupURL,
            backupType: backupType,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(TimeInterval(retainForDays * 24 * 60 * 60)),
            fileSize: fileSize
        )
        
        // Save backup metadata
        try saveBackupMetadata(backupInfo)
        
        logInfo("Migration backup created", category: .persistence, context: LogContext(customData: [
            "backup_id": backupId.uuidString,
            "backup_size": fileSize,
            "backup_type": String(describing: backupType)
        ]))
        
        return backupInfo
    }
    
    func restoreBackup(backupInfo: BackupInfo, targetURL: URL) async throws {
        // Remove current store files
        try? FileManager.default.removeItem(at: targetURL)
        try? FileManager.default.removeItem(at: targetURL.appendingPathExtension("sqlite-wal"))
        try? FileManager.default.removeItem(at: targetURL.appendingPathExtension("sqlite-shm"))
        
        // Restore from backup
        try FileManager.default.copyItem(at: backupInfo.backupURL, to: targetURL)
        
        // Restore WAL and SHM files if they exist
        let backupWalURL = backupInfo.backupURL.appendingPathExtension("sqlite-wal")
        let backupShmURL = backupInfo.backupURL.appendingPathExtension("sqlite-shm")
        
        if FileManager.default.fileExists(atPath: backupWalURL.path) {
            try FileManager.default.copyItem(
                at: backupWalURL,
                to: targetURL.appendingPathExtension("sqlite-wal")
            )
        }
        
        if FileManager.default.fileExists(atPath: backupShmURL.path) {
            try FileManager.default.copyItem(
                at: backupShmURL,
                to: targetURL.appendingPathExtension("sqlite-shm")
            )
        }
        
        logInfo("Migration backup restored", category: .persistence, context: LogContext(customData: [
            "backup_id": backupInfo.id.uuidString
        ]))
    }
    
    func cleanupOldBackups(olderThanDays: Int) async throws {
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(olderThanDays * 24 * 60 * 60))
        
        let backupFiles = try FileManager.default.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        )
        
        for backupURL in backupFiles {
            let attributes = try FileManager.default.attributesOfItem(atPath: backupURL.path)
            if let creationDate = attributes[.creationDate] as? Date,
               creationDate < cutoffDate {
                try FileManager.default.removeItem(at: backupURL)
            }
        }
    }
    
    func getMigrationHistory() -> [MigrationHistoryEntry] {
        // Load migration history from metadata
        return []
    }
    
    func cleanupTemporaryFiles() throws {
        // Clean up any temporary migration files
        let tempFiles = try FileManager.default.contentsOfDirectory(at: backupsDirectory)
            .filter { $0.pathExtension.contains("temp") || $0.pathExtension.contains("migrated") }
        
        for tempFile in tempFiles {
            try FileManager.default.removeItem(at: tempFile)
        }
    }
    
    private func saveBackupMetadata(_ backupInfo: BackupInfo) throws {
        let metadataURL = backupsDirectory.appendingPathComponent("backup_metadata.json")
        
        var metadata: [BackupInfo] = []
        
        // Load existing metadata
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            let data = try Data(contentsOf: metadataURL)
            metadata = try JSONDecoder().decode([BackupInfo].self, from: data)
        }
        
        // Add new backup info
        metadata.append(backupInfo)
        
        // Save updated metadata
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL)
    }
}

@MainActor
class MigrationProgressTracker {
    private var currentProgress: Double = 0.0
    
    func updateProgress(_ progress: Double) {
        currentProgress = progress
    }
    
    func getCurrentProgress() -> Double {
        return currentProgress
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let backupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}

// Make BackupInfo Codable
extension BackupInfo: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, originalStoreURL, backupURL, backupType, createdAt, expiresAt, fileSize
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        originalStoreURL = try container.decode(URL.self, forKey: .originalStoreURL)
        backupURL = try container.decode(URL.self, forKey: .backupURL)
        backupType = try container.decode(BackupType.self, forKey: .backupType)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        fileSize = try container.decode(Int64.self, forKey: .fileSize)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(originalStoreURL, forKey: .originalStoreURL)
        try container.encode(backupURL, forKey: .backupURL)
        try container.encode(backupType, forKey: .backupType)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(fileSize, forKey: .fileSize)
    }
}

extension BackupInfo.BackupType: Codable {}