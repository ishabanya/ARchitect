import Foundation
import CoreData
import Combine

// MARK: - Automatic Save and Version Management System

@MainActor
public class VersionManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var currentVersion: ProjectVersion?
    @Published public var versionHistory: [ProjectVersion] = []
    @Published public var isAutoSaveEnabled: Bool = true
    @Published public var autoSaveInterval: TimeInterval = 30.0
    @Published public var unsavedChanges: Bool = false
    
    // MARK: - Private Properties
    private let coreDataStack: CoreDataStack
    private let autoSaveManager: AutoSaveManager
    private let versionTracker: VersionTracker
    private let changeDetector: ChangeDetector
    
    private var autoSaveTimer: Timer?
    private var changeTrackingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Configuration
    private let maxVersionHistory = 50
    private let minTimeBetweenVersions: TimeInterval = 60 // 1 minute
    private let changeDetectionInterval: TimeInterval = 5.0
    
    public init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
        self.autoSaveManager = AutoSaveManager(coreDataStack: coreDataStack)
        self.versionTracker = VersionTracker()
        self.changeDetector = ChangeDetector()
        
        setupObservers()
        startChangeDetection()
        
        logDebug("Version manager initialized", category: .persistence)
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Monitor auto-save setting changes
        $isAutoSaveEnabled
            .sink { [weak self] enabled in
                if enabled {
                    self?.startAutoSave()
                } else {
                    self?.stopAutoSave()
                }
            }
            .store(in: &cancellables)
        
        // Monitor interval changes
        $autoSaveInterval
            .sink { [weak self] _ in
                if self?.isAutoSaveEnabled == true {
                    self?.restartAutoSave()
                }
            }
            .store(in: &cancellables)
        
        // Monitor Core Data changes
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] notification in
                self?.handleContextSave(notification)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Version Management
    
    public func createVersion(
        for project: ProjectMO,
        type: VersionType = .automatic,
        comment: String? = nil
    ) async throws -> ProjectVersion {
        
        // Check if enough time has passed since last version
        if type == .automatic,
           let lastVersion = versionHistory.last,
           Date().timeIntervalSince(lastVersion.createdAt) < minTimeBetweenVersions {
            throw VersionError.tooFrequent
        }
        
        let version = try await coreDataStack.executeInBackground { context in
            // Get project in background context
            let backgroundProject = try context.existingObject(with: project.objectID) as! ProjectMO
            
            // Create version snapshot
            let versionData = try self.createVersionSnapshot(project: backgroundProject)
            
            // Create version entity
            let versionEntity = context.insertObject(ProjectVersionMO.self)
            versionEntity.id = UUID()
            versionEntity.project = backgroundProject
            versionEntity.versionNumber = self.getNextVersionNumber(for: backgroundProject)
            versionEntity.type = type.rawValue
            versionEntity.comment = comment
            versionEntity.createdAt = Date()
            versionEntity.createdBy = getCurrentUser()
            versionEntity.dataSize = Int64(versionData.count)
            versionEntity.versionData = versionData
            versionEntity.checksum = self.calculateChecksum(data: versionData)
            
            try context.save()
            
            return ProjectVersion(from: versionEntity)
        }
        
        // Update in-memory collections
        versionHistory.append(version)
        currentVersion = version
        
        // Cleanup old versions if needed
        try await cleanupOldVersions(for: project)
        
        logInfo("Version created", category: .persistence, context: LogContext(customData: [
            "project_id": project.id?.uuidString ?? "unknown",
            "version_number": version.versionNumber,
            "version_type": type.rawValue
        ]))
        
        return version
    }
    
    public func restoreVersion(_ version: ProjectVersion, to project: ProjectMO) async throws {
        try await coreDataStack.executeInBackground { context in
            // Get entities in background context
            let backgroundProject = try context.existingObject(with: project.objectID) as! ProjectMO
            let versionEntity = try context.existingObject(with: version.objectID) as! ProjectVersionMO
            
            guard let versionData = versionEntity.versionData else {
                throw VersionError.corruptedVersionData
            }
            
            // Verify data integrity
            let currentChecksum = self.calculateChecksum(data: versionData)
            if currentChecksum != versionEntity.checksum {
                throw VersionError.corruptedVersionData
            }
            
            // Create backup of current state before restore
            _ = try await self.createVersion(for: backgroundProject, type: .beforeRestore, comment: "Backup before restore to version \(version.versionNumber)")
            
            // Restore project data
            try self.restoreProjectFromSnapshot(project: backgroundProject, data: versionData)
            
            try context.save()
        }
        
        logInfo("Version restored", category: .persistence, context: LogContext(customData: [
            "project_id": project.id?.uuidString ?? "unknown",
            "restored_version": version.versionNumber
        ]))
    }
    
    public func deleteVersion(_ version: ProjectVersion) async throws {
        guard version.type != .manual else {
            throw VersionError.cannotDeleteManualVersion
        }
        
        try await coreDataStack.executeInBackground { context in
            let versionEntity = try context.existingObject(with: version.objectID) as! ProjectVersionMO
            context.delete(versionEntity)
            try context.save()
        }
        
        // Remove from in-memory collection
        versionHistory.removeAll { $0.id == version.id }
        
        logInfo("Version deleted", category: .persistence, context: LogContext(customData: [
            "version_id": version.id.uuidString,
            "version_number": version.versionNumber
        ]))
    }
    
    public func getVersionHistory(for project: ProjectMO) async throws -> [ProjectVersion] {
        return try await coreDataStack.executeInBackground { context in
            let request = ProjectVersionMO.fetchRequest()
            request.predicate = NSPredicate(format: "project == %@", project)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ProjectVersionMO.createdAt, ascending: false)]
            
            let versionEntities = try context.fetch(request)
            return versionEntities.map { ProjectVersion(from: $0) }
        }
    }
    
    // MARK: - Auto Save Management
    
    public func startAutoSave() {
        guard isAutoSaveEnabled else { return }
        
        stopAutoSave()
        
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: autoSaveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performAutoSave()
            }
        }
        
        logDebug("Auto-save started", category: .persistence, context: LogContext(customData: [
            "interval": autoSaveInterval
        ]))
    }
    
    public func stopAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        
        logDebug("Auto-save stopped", category: .persistence)
    }
    
    private func restartAutoSave() {
        stopAutoSave()
        startAutoSave()
    }
    
    private func performAutoSave() async {
        guard unsavedChanges else { return }
        
        do {
            // Save current changes
            coreDataStack.save()
            
            // Create automatic version if significant changes detected
            if let currentProject = getCurrentProject(),
               changeDetector.hasSignificantChanges() {
                _ = try await createVersion(for: currentProject, type: .automatic)
                changeDetector.resetChangeTracking()
            }
            
            unsavedChanges = false
            
            logDebug("Auto-save completed", category: .persistence)
            
        } catch {
            logError("Auto-save failed", category: .persistence, error: error)
        }
    }
    
    public func saveManually(comment: String? = nil) async throws {
        guard let currentProject = getCurrentProject() else {
            throw VersionError.noActiveProject
        }
        
        // Save current changes
        coreDataStack.save()
        
        // Create manual version
        _ = try await createVersion(for: currentProject, type: .manual, comment: comment)
        
        unsavedChanges = false
        
        logInfo("Manual save completed", category: .persistence)
    }
    
    // MARK: - Change Detection
    
    private func startChangeDetection() {
        changeTrackingTimer = Timer.scheduledTimer(withTimeInterval: changeDetectionInterval, repeats: true) { [weak self] _ in
            self?.detectChanges()
        }
    }
    
    private func detectChanges() {
        let hasChanges = coreDataStack.viewContext.hasChanges
        
        if hasChanges != unsavedChanges {
            unsavedChanges = hasChanges
        }
        
        // Update change detector
        if hasChanges {
            changeDetector.recordChanges(context: coreDataStack.viewContext)
        }
    }
    
    // MARK: - Version Snapshots
    
    private func createVersionSnapshot(project: ProjectMO) throws -> Data {
        let snapshot = ProjectSnapshot(
            projectData: try encodeProjectData(project),
            furnitureItems: try encodeFurnitureItems(project.furnitureItems?.allObjects as? [FurnitureItemMO] ?? []),
            roomData: try encodeRoomData(project.roomData),
            metadata: VersionMetadata(
                createdAt: Date(),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                dataModelVersion: getCurrentDataModelVersion()
            )
        )
        
        return try JSONEncoder().encode(snapshot)
    }
    
    private func restoreProjectFromSnapshot(project: ProjectMO, data: Data) throws {
        let snapshot = try JSONDecoder().decode(ProjectSnapshot.self, from: data)
        
        // Clear existing data
        if let furnitureItems = project.furnitureItems {
            for item in furnitureItems {
                coreDataStack.viewContext.delete(item as! NSManagedObject)
            }
        }
        
        // Restore project data
        try decodeProjectData(snapshot.projectData, to: project)
        
        // Restore furniture items
        for itemData in snapshot.furnitureItems {
            let item = coreDataStack.viewContext.insertObject(FurnitureItemMO.self)
            try decodeFurnitureItem(itemData, to: item)
            project.addToFurnitureItems(item)
        }
        
        // Restore room data
        if let roomDataSnapshot = snapshot.roomData {
            let roomData = coreDataStack.viewContext.insertObject(RoomDataMO.self)
            try decodeRoomData(roomDataSnapshot, to: roomData)
            project.roomData = roomData
        }
    }
    
    // MARK: - Data Encoding/Decoding
    
    private func encodeProjectData(_ project: ProjectMO) throws -> ProjectData {
        return ProjectData(
            id: project.id ?? UUID(),
            name: project.name ?? "",
            description: project.projectDescription,
            createdAt: project.createdAt ?? Date(),
            modifiedAt: project.modifiedAt ?? Date(),
            tags: project.tags?.components(separatedBy: ",") ?? [],
            isTemplate: project.isTemplate,
            templateCategory: project.templateCategory,
            settings: project.settings
        )
    }
    
    private func decodeProjectData(_ data: ProjectData, to project: ProjectMO) throws {
        project.id = data.id
        project.name = data.name
        project.projectDescription = data.description
        project.createdAt = data.createdAt
        project.modifiedAt = data.modifiedAt
        project.tags = data.tags.joined(separator: ",")
        project.isTemplate = data.isTemplate
        project.templateCategory = data.templateCategory
        project.settings = data.settings
    }
    
    private func encodeFurnitureItems(_ items: [FurnitureItemMO]) throws -> [FurnitureItemData] {
        return items.map { item in
            FurnitureItemData(
                id: item.id ?? UUID(),
                name: item.name ?? "",
                category: item.category ?? "",
                position: [item.positionX, item.positionY, item.positionZ],
                rotation: item.rotation,
                scale: [item.scaleX, item.scaleY, item.scaleZ],
                metadata: item.metadata
            )
        }
    }
    
    private func decodeFurnitureItem(_ data: FurnitureItemData, to item: FurnitureItemMO) throws {
        item.id = data.id
        item.name = data.name
        item.category = data.category
        item.positionX = data.position[0]
        item.positionY = data.position[1]
        item.positionZ = data.position[2]
        item.rotation = data.rotation
        item.scaleX = data.scale[0]
        item.scaleY = data.scale[1]
        item.scaleZ = data.scale[2]
        item.metadata = data.metadata
    }
    
    private func encodeRoomData(_ roomData: RoomDataMO?) throws -> RoomDataSnapshot? {
        guard let roomData = roomData else { return nil }
        
        return RoomDataSnapshot(
            id: roomData.id ?? UUID(),
            roomType: roomData.roomType ?? "",
            dimensions: [roomData.width, roomData.height, roomData.depth],
            features: roomData.features?.components(separatedBy: ",") ?? []
        )
    }
    
    private func decodeRoomData(_ data: RoomDataSnapshot, to roomData: RoomDataMO) throws {
        roomData.id = data.id
        roomData.roomType = data.roomType
        roomData.width = data.dimensions[0]
        roomData.height = data.dimensions[1]
        roomData.depth = data.dimensions[2]
        roomData.features = data.features.joined(separator: ",")
    }
    
    // MARK: - Helper Methods
    
    private func getNextVersionNumber(for project: ProjectMO) -> Int32 {
        let request = ProjectVersionMO.fetchRequest()
        request.predicate = NSPredicate(format: "project == %@", project)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ProjectVersionMO.versionNumber, ascending: false)]
        request.fetchLimit = 1
        
        do {
            let versions = try coreDataStack.viewContext.fetch(request)
            return (versions.first?.versionNumber ?? 0) + 1
        } catch {
            logError("Failed to get next version number", category: .persistence, error: error)
            return 1
        }
    }
    
    private func cleanupOldVersions(for project: ProjectMO) async throws {
        let versions = try await getVersionHistory(for: project)
        
        if versions.count > maxVersionHistory {
            let versionsToDelete = versions
                .filter { $0.type == .automatic } // Keep manual versions
                .sorted { $0.createdAt < $1.createdAt }
                .prefix(versions.count - maxVersionHistory)
            
            for version in versionsToDelete {
                try await deleteVersion(version)
            }
        }
    }
    
    private func calculateChecksum(data: Data) -> String {
        return data.sha256Hash
    }
    
    private func getCurrentUser() -> String {
        return "current_user" // Would be actual user identification
    }
    
    private func getCurrentProject() -> ProjectMO? {
        // This would be provided by the project manager
        return nil
    }
    
    private func getCurrentDataModelVersion() -> String {
        return coreDataStack.persistentContainer.managedObjectModel.versionIdentifiers.first as? String ?? "1.0"
    }
    
    // MARK: - Event Handlers
    
    private func handleContextSave(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext,
              context === coreDataStack.viewContext else { return }
        
        // Record save event
        recordSave()
        
        // Update change tracking
        changeDetector.resetChangeTracking()
    }
    
    func recordSave() {
        versionTracker.recordSave()
    }
    
    // MARK: - Public Interface
    
    public func setAutoSaveInterval(_ interval: TimeInterval) {
        autoSaveInterval = max(10.0, interval) // Minimum 10 seconds
    }
    
    public func enableAutoSave(_ enabled: Bool) {
        isAutoSaveEnabled = enabled
    }
    
    public func hasUnsavedChanges() -> Bool {
        return unsavedChanges
    }
    
    public func getVersionStatistics() -> VersionStatistics {
        return VersionStatistics(
            totalVersions: versionHistory.count,
            automaticVersions: versionHistory.filter { $0.type == .automatic }.count,
            manualVersions: versionHistory.filter { $0.type == .manual }.count,
            currentVersion: currentVersion?.versionNumber ?? 0,
            lastVersionDate: versionHistory.last?.createdAt,
            isAutoSaveEnabled: isAutoSaveEnabled,
            hasUnsavedChanges: unsavedChanges
        )
    }
}

// MARK: - Supporting Data Structures

public struct ProjectVersion: Identifiable {
    public let id: UUID
    public let objectID: NSManagedObjectID
    public let versionNumber: Int32
    public let type: VersionType
    public let comment: String?
    public let createdAt: Date
    public let createdBy: String
    public let dataSize: Int64
    public let checksum: String
    
    init(from entity: ProjectVersionMO) {
        self.id = entity.id ?? UUID()
        self.objectID = entity.objectID
        self.versionNumber = entity.versionNumber
        self.type = VersionType(rawValue: entity.type ?? "") ?? .automatic
        self.comment = entity.comment
        self.createdAt = entity.createdAt ?? Date()
        self.createdBy = entity.createdBy ?? ""
        self.dataSize = entity.dataSize
        self.checksum = entity.checksum ?? ""
    }
}

public enum VersionType: String, CaseIterable {
    case automatic = "automatic"
    case manual = "manual"
    case beforeRestore = "before_restore"
    case beforeMigration = "before_migration"
    case checkpoint = "checkpoint"
    
    var displayName: String {
        switch self {
        case .automatic: return "Auto Save"
        case .manual: return "Manual Save"
        case .beforeRestore: return "Before Restore"
        case .beforeMigration: return "Before Migration"
        case .checkpoint: return "Checkpoint"
        }
    }
}

public struct VersionStatistics {
    public let totalVersions: Int
    public let automaticVersions: Int
    public let manualVersions: Int
    public let currentVersion: Int32
    public let lastVersionDate: Date?
    public let isAutoSaveEnabled: Bool
    public let hasUnsavedChanges: Bool
}

public enum VersionError: Error {
    case noActiveProject
    case tooFrequent
    case corruptedVersionData
    case cannotDeleteManualVersion
    case versionNotFound
    case restoreFailed(String)
    
    public var localizedDescription: String {
        switch self {
        case .noActiveProject:
            return "No active project to version"
        case .tooFrequent:
            return "Version creation too frequent"
        case .corruptedVersionData:
            return "Version data is corrupted"
        case .cannotDeleteManualVersion:
            return "Cannot delete manual versions"
        case .versionNotFound:
            return "Version not found"
        case .restoreFailed(let message):
            return "Version restore failed: \(message)"
        }
    }
}

// MARK: - Snapshot Data Structures

private struct ProjectSnapshot: Codable {
    let projectData: ProjectData
    let furnitureItems: [FurnitureItemData]
    let roomData: RoomDataSnapshot?
    let metadata: VersionMetadata
}

private struct ProjectData: Codable {
    let id: UUID
    let name: String
    let description: String?
    let createdAt: Date
    let modifiedAt: Date
    let tags: [String]
    let isTemplate: Bool
    let templateCategory: String?
    let settings: String?
}

private struct FurnitureItemData: Codable {
    let id: UUID
    let name: String
    let category: String
    let position: [Float]
    let rotation: Float
    let scale: [Float]
    let metadata: String?
}

private struct RoomDataSnapshot: Codable {
    let id: UUID
    let roomType: String
    let dimensions: [Float]
    let features: [String]
}

private struct VersionMetadata: Codable {
    let createdAt: Date
    let appVersion: String
    let dataModelVersion: String
}

// MARK: - Supporting Classes

@MainActor
class AutoSaveManager {
    private let coreDataStack: CoreDataStack
    
    init(coreDataStack: CoreDataStack) {
        self.coreDataStack = coreDataStack
    }
    
    func performAutoSave() {
        guard coreDataStack.viewContext.hasChanges else { return }
        coreDataStack.save()
    }
}

@MainActor
class VersionTracker {
    private var saveCount = 0
    private var lastSaveTime = Date()
    
    func recordSave() {
        saveCount += 1
        lastSaveTime = Date()
    }
    
    func getSaveCount() -> Int {
        return saveCount
    }
    
    func getLastSaveTime() -> Date {
        return lastSaveTime
    }
}

@MainActor
class ChangeDetector {
    private var significantChangeThreshold = 5
    private var changeCount = 0
    private var lastSignificantChange = Date()
    
    func recordChanges(context: NSManagedObjectContext) {
        let totalChanges = context.insertedObjects.count +
                          context.updatedObjects.count +
                          context.deletedObjects.count
        
        if totalChanges > 0 {
            changeCount += totalChanges
        }
    }
    
    func hasSignificantChanges() -> Bool {
        return changeCount >= significantChangeThreshold
    }
    
    func resetChangeTracking() {
        changeCount = 0
        lastSignificantChange = Date()
    }
}

// Extensions
extension Data {
    var sha256Hash: String {
        let digest = self.withUnsafeBytes { bytes in
            return SHA256.hash(data: bytes)
        }
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

import CryptoKit

extension SHA256.Digest {
    var hexString: String {
        return self.compactMap { String(format: "%02x", $0) }.joined()
    }
}