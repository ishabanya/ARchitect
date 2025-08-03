import Foundation
import CoreData
import Combine

// MARK: - Data Integrity Checking System

@MainActor
public class DataIntegrityChecker: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var lastCheckDate: Date?
    @Published public var integrityScore: Float = 1.0
    @Published public var isChecking: Bool = false
    @Published public var discoveredIssues: [IntegrityIssue] = []
    @Published public var repairHistory: [RepairRecord] = []
    
    // MARK: - Private Properties
    private let consistencyChecker: ConsistencyChecker
    private let relationshipValidator: RelationshipValidator
    private let dataCorruptionDetector: DataCorruptionDetector
    private let performanceAnalyzer: PerformanceAnalyzer
    private let healthMonitor: HealthMonitor
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Configuration
    private let maxIssuesPerCheck = 100
    private let criticalIssueThreshold = 0.8
    private let automaticRepairEnabled = true
    
    public init() {
        self.consistencyChecker = ConsistencyChecker()
        self.relationshipValidator = RelationshipValidator()
        self.dataCorruptionDetector = DataCorruptionDetector()
        self.performanceAnalyzer = PerformanceAnalyzer()
        self.healthMonitor = HealthMonitor()
        
        setupObservers()
        
        logDebug("Data integrity checker initialized", category: .persistence)
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Monitor Core Data changes for integrity impact
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] notification in
                self?.handleContextSave(notification)
            }
            .store(in: &cancellables)
        
        // Periodic integrity monitoring
        Timer.publish(every: 3600, on: .main, in: .default) // Every hour
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.performQuickIntegrityCheck()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Integrity Check Operations
    
    public func performIntegrityCheck(context: NSManagedObjectContext) async throws -> IntegrityCheckResult {
        isChecking = true
        
        let startTime = Date()
        var allIssues: [IntegrityIssue] = []
        
        do {
            logInfo("Starting comprehensive integrity check", category: .persistence)
            
            // 1. Entity Consistency Check
            let consistencyIssues = try await performConsistencyCheck(context: context)
            allIssues.append(contentsOf: consistencyIssues)
            
            // 2. Relationship Validation
            let relationshipIssues = try await performRelationshipValidation(context: context)
            allIssues.append(contentsOf: relationshipIssues)
            
            // 3. Data Corruption Detection
            let corruptionIssues = try await performCorruptionDetection(context: context)
            allIssues.append(contentsOf: corruptionIssues)
            
            // 4. Performance Analysis
            let performanceIssues = try await performPerformanceAnalysis(context: context)
            allIssues.append(contentsOf: performanceIssues)
            
            // 5. Health Monitoring
            let healthIssues = try await performHealthCheck(context: context)
            allIssues.append(contentsOf: healthIssues)
            
            // Calculate integrity score
            let score = calculateIntegrityScore(issues: allIssues)
            integrityScore = score
            
            // Update discovered issues
            discoveredIssues = Array(allIssues.prefix(maxIssuesPerCheck))
            lastCheckDate = Date()
            
            let duration = Date().timeIntervalSince(startTime)
            
            let result = IntegrityCheckResult(
                isValid: score >= criticalIssueThreshold,
                integrityScore: score,
                totalIssues: allIssues.count,
                criticalIssues: allIssues.filter { $0.severity == .critical }.count,
                warningIssues: allIssues.filter { $0.severity == .warning }.count,
                infoIssues: allIssues.filter { $0.severity == .info }.count,
                issues: allIssues,
                checkDuration: duration,
                checkedAt: Date()
            )
            
            isChecking = false
            
            logInfo("Integrity check completed", category: .persistence, context: LogContext(customData: [
                "integrity_score": score,
                "total_issues": allIssues.count,
                "duration": duration
            ]))
            
            // Automatic repair for non-critical issues
            if automaticRepairEnabled && !allIssues.isEmpty {
                let repairableIssues = allIssues.filter { $0.isRepairable && $0.severity != .critical }
                if !repairableIssues.isEmpty {
                    try await repairIntegrityIssues(repairableIssues, context: context)
                }
            }
            
            return result
            
        } catch {
            isChecking = false
            logError("Integrity check failed", category: .persistence, error: error)
            throw error
        }
    }
    
    public func performQuickIntegrityCheck() async {
        do {
            let context = CoreDataStack.shared.backgroundContext
            let quickResult = try await performBasicIntegrityCheck(context: context)
            
            // Update health score
            integrityScore = quickResult.integrityScore
            
            // Check for critical issues
            if quickResult.criticalIssues > 0 {
                logWarning("Critical integrity issues detected", category: .persistence, context: LogContext(customData: [
                    "critical_issues": quickResult.criticalIssues
                ]))
            }
            
        } catch {
            logError("Quick integrity check failed", category: .persistence, error: error)
        }
    }
    
    // MARK: - Consistency Checking
    
    private func performConsistencyCheck(context: NSManagedObjectContext) async throws -> [IntegrityIssue] {
        return try await context.perform {
            var issues: [IntegrityIssue] = []
            
            // Check project consistency
            issues.append(contentsOf: try self.consistencyChecker.checkProjectConsistency(context: context))
            
            // Check furniture item consistency
            issues.append(contentsOf: try self.consistencyChecker.checkFurnitureItemConsistency(context: context))
            
            // Check template consistency
            issues.append(contentsOf: try self.consistencyChecker.checkTemplateConsistency(context: context))
            
            // Check version consistency
            issues.append(contentsOf: try self.consistencyChecker.checkVersionConsistency(context: context))
            
            return issues
        }
    }
    
    // MARK: - Relationship Validation
    
    private func performRelationshipValidation(context: NSManagedObjectContext) async throws -> [IntegrityIssue] {
        return try await context.perform {
            var issues: [IntegrityIssue] = []
            
            // Validate project-furniture relationships
            issues.append(contentsOf: try self.relationshipValidator.validateProjectFurnitureRelationships(context: context))
            
            // Validate project-room relationships
            issues.append(contentsOf: try self.relationshipValidator.validateProjectRoomRelationships(context: context))
            
            // Validate project-version relationships
            issues.append(contentsOf: try self.relationshipValidator.validateProjectVersionRelationships(context: context))
            
            // Validate orphaned objects
            issues.append(contentsOf: try self.relationshipValidator.validateOrphanedObjects(context: context))
            
            return issues
        }
    }
    
    // MARK: - Corruption Detection
    
    private func performCorruptionDetection(context: NSManagedObjectContext) async throws -> [IntegrityIssue] {
        return try await context.perform {
            var issues: [IntegrityIssue] = []
            
            // Check for data corruption
            issues.append(contentsOf: try self.dataCorruptionDetector.detectDataCorruption(context: context))
            
            // Validate checksums
            issues.append(contentsOf: try self.dataCorruptionDetector.validateChecksums(context: context))
            
            // Check for invalid data formats
            issues.append(contentsOf: try self.dataCorruptionDetector.validateDataFormats(context: context))
            
            return issues
        }
    }
    
    // MARK: - Performance Analysis
    
    private func performPerformanceAnalysis(context: NSManagedObjectContext) async throws -> [IntegrityIssue] {
        return try await context.perform {
            var issues: [IntegrityIssue] = []
            
            // Analyze query performance
            issues.append(contentsOf: try self.performanceAnalyzer.analyzeQueryPerformance(context: context))
            
            // Check for memory leaks
            issues.append(contentsOf: try self.performanceAnalyzer.checkMemoryUsage(context: context))
            
            // Validate data sizes
            issues.append(contentsOf: try self.performanceAnalyzer.validateDataSizes(context: context))
            
            return issues
        }
    }
    
    // MARK: - Health Monitoring
    
    private func performHealthCheck(context: NSManagedObjectContext) async throws -> [IntegrityIssue] {
        return try await context.perform {
            var issues: [IntegrityIssue] = []
            
            // Monitor storage health
            issues.append(contentsOf: try self.healthMonitor.checkStorageHealth(context: context))
            
            // Check CloudKit sync health
            issues.append(contentsOf: try self.healthMonitor.checkCloudKitHealth(context: context))
            
            // Validate backup integrity
            issues.append(contentsOf: try self.healthMonitor.checkBackupIntegrity(context: context))
            
            return issues
        }
    }
    
    // MARK: - Basic Integrity Check
    
    private func performBasicIntegrityCheck(context: NSManagedObjectContext) async throws -> IntegrityCheckResult {
        return try await context.perform {
            var criticalIssues = 0
            var totalIssues = 0
            
            // Quick entity count validation
            let entities = context.persistentStoreCoordinator?.managedObjectModel.entities ?? []
            for entity in entities {
                if let entityName = entity.name {
                    let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                    request.includesSubentities = false
                    
                    do {
                        let count = try context.count(for: request)
                        if count < 0 {
                            criticalIssues += 1
                            totalIssues += 1
                        }
                    } catch {
                        criticalIssues += 1
                        totalIssues += 1
                    }
                }
            }
            
            // Quick relationship validation
            let projectRequest = ProjectMO.fetchRequest()
            projectRequest.fetchLimit = 10 // Sample check
            
            let projects = try context.fetch(projectRequest)
            for project in projects {
                if project.furnitureItems == nil {
                    totalIssues += 1
                }
            }
            
            let score = totalIssues == 0 ? 1.0 : max(0.0, 1.0 - (Float(criticalIssues) * 0.2))
            
            return IntegrityCheckResult(
                isValid: score >= self.criticalIssueThreshold,
                integrityScore: score,
                totalIssues: totalIssues,
                criticalIssues: criticalIssues,
                warningIssues: totalIssues - criticalIssues,
                infoIssues: 0,
                issues: [],
                checkDuration: 0.1,
                checkedAt: Date()
            )
        }
    }
    
    // MARK: - Issue Repair
    
    public func repairIntegrityIssues(_ issues: [IntegrityIssue], context: NSManagedObjectContext) async throws {
        let startTime = Date()
        var repairedCount = 0
        var failedRepairs: [IntegrityIssue] = []
        
        for issue in issues {
            do {
                if try await repairSingleIssue(issue, context: context) {
                    repairedCount += 1
                } else {
                    failedRepairs.append(issue)
                }
            } catch {
                failedRepairs.append(issue)
                logError("Failed to repair integrity issue", category: .persistence, error: error, context: LogContext(customData: [
                    "issue_type": issue.type.rawValue,
                    "issue_id": issue.id.uuidString
                ]))
            }
        }
        
        // Record repair attempt
        let repairRecord = RepairRecord(
            id: UUID(),
            date: Date(),
            issuesAttempted: issues.count,
            issuesRepaired: repairedCount,
            issuesFailed: failedRepairs.count,
            duration: Date().timeIntervalSince(startTime),
            repairType: .automatic
        )
        
        repairHistory.append(repairRecord)
        
        // Remove repaired issues from discovered issues
        discoveredIssues.removeAll { issue in
            !failedRepairs.contains { $0.id == issue.id }
        }
        
        logInfo("Integrity repair completed", category: .persistence, context: LogContext(customData: [
            "repaired_count": repairedCount,
            "failed_count": failedRepairs.count
        ]))
    }
    
    private func repairSingleIssue(_ issue: IntegrityIssue, context: NSManagedObjectContext) async throws -> Bool {
        guard issue.isRepairable else { return false }
        
        switch issue.type {
        case .orphanedFurnitureItem:
            return try await repairOrphanedFurnitureItem(issue, context: context)
        case .missingRelationship:
            return try await repairMissingRelationship(issue, context: context)
        case .invalidData:
            return try await repairInvalidData(issue, context: context)
        case .corruptedChecksum:
            return try await repairCorruptedChecksum(issue, context: context)
        case .duplicateEntity:
            return try await repairDuplicateEntity(issue, context: context)
        case .inconsistentState:
            return try await repairInconsistentState(issue, context: context)
        default:
            return false
        }
    }
    
    // MARK: - Specific Repair Methods
    
    private func repairOrphanedFurnitureItem(_ issue: IntegrityIssue, context: NSManagedObjectContext) async throws -> Bool {
        guard let objectID = issue.affectedObjectID,
              let furnitureItem = try? context.existingObject(with: objectID) as? FurnitureItemMO else {
            return false
        }
        
        // Delete orphaned furniture item
        context.delete(furnitureItem)
        try context.save()
        
        return true
    }
    
    private func repairMissingRelationship(_ issue: IntegrityIssue, context: NSManagedObjectContext) async throws -> Bool {
        // Implementation would depend on the specific relationship issue
        return false // Placeholder
    }
    
    private func repairInvalidData(_ issue: IntegrityIssue, context: NSManagedObjectContext) async throws -> Bool {
        guard let objectID = issue.affectedObjectID,
              let object = try? context.existingObject(with: objectID) else {
            return false
        }
        
        // Reset invalid properties to default values
        if let project = object as? ProjectMO {
            if project.name?.isEmpty ?? true {
                project.name = "Untitled Project"
            }
            if project.createdAt == nil {
                project.createdAt = Date()
            }
        }
        
        try context.save()
        return true
    }
    
    private func repairCorruptedChecksum(_ issue: IntegrityIssue, context: NSManagedObjectContext) async throws -> Bool {
        guard let objectID = issue.affectedObjectID,
              let versionEntity = try? context.existingObject(with: objectID) as? ProjectVersionMO,
              let versionData = versionEntity.versionData else {
            return false
        }
        
        // Recalculate checksum
        let newChecksum = versionData.sha256Hash
        versionEntity.checksum = newChecksum
        
        try context.save()
        return true
    }
    
    private func repairDuplicateEntity(_ issue: IntegrityIssue, context: NSManagedObjectContext) async throws -> Bool {
        // Implementation would merge or remove duplicate entities
        return false // Placeholder
    }
    
    private func repairInconsistentState(_ issue: IntegrityIssue, context: NSManagedObjectContext) async throws -> Bool {
        // Implementation would fix state inconsistencies
        return false // Placeholder
    }
    
    // MARK: - Helper Methods
    
    private func calculateIntegrityScore(issues: [IntegrityIssue]) -> Float {
        guard !issues.isEmpty else { return 1.0 }
        
        let criticalWeight: Float = 0.5
        let warningWeight: Float = 0.3
        let infoWeight: Float = 0.1
        
        let criticalCount = Float(issues.filter { $0.severity == .critical }.count)
        let warningCount = Float(issues.filter { $0.severity == .warning }.count)
        let infoCount = Float(issues.filter { $0.severity == .info }.count)
        
        let totalWeightedIssues = (criticalCount * criticalWeight) + 
                                 (warningCount * warningWeight) + 
                                 (infoCount * infoWeight)
        
        // Score decreases with more weighted issues
        let score = max(0.0, 1.0 - (totalWeightedIssues / 10.0))
        return score
    }
    
    private func handleContextSave(_ notification: Notification) {
        // Monitor saves for potential integrity impact
        guard let context = notification.object as? NSManagedObjectContext else { return }
        
        let hasSignificantChanges = context.insertedObjects.count > 5 ||
                                   context.deletedObjects.count > 5 ||
                                   context.updatedObjects.count > 10
        
        if hasSignificantChanges {
            Task {
                await performQuickIntegrityCheck()
            }
        }
    }
    
    // MARK: - Public Interface
    
    public func getIntegrityReport() -> IntegrityReport {
        return IntegrityReport(
            overallScore: integrityScore,
            lastCheckDate: lastCheckDate,
            totalIssues: discoveredIssues.count,
            issuesByType: Dictionary(grouping: discoveredIssues, by: { $0.type }),
            issuesBySeverity: Dictionary(grouping: discoveredIssues, by: { $0.severity }),
            repairHistory: repairHistory,
            recommendations: generateRecommendations()
        )
    }
    
    public func schedulePeriodicCheck(interval: TimeInterval = 86400) { // Default: daily
        Timer.publish(every: interval, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    try? await self?.performIntegrityCheck(context: CoreDataStack.shared.backgroundContext)
                }
            }
            .store(in: &cancellables)
    }
    
    private func generateRecommendations() -> [String] {
        var recommendations: [String] = []
        
        if integrityScore < 0.8 {
            recommendations.append("Consider running a full integrity repair")
        }
        
        if discoveredIssues.count > 20 {
            recommendations.append("Large number of issues detected - investigate data sources")
        }
        
        let criticalIssues = discoveredIssues.filter { $0.severity == .critical }
        if criticalIssues.count > 0 {
            recommendations.append("Critical issues require immediate attention")
        }
        
        return recommendations
    }
}

// MARK: - Supporting Data Structures

public struct IntegrityCheckResult {
    public let isValid: Bool
    public let integrityScore: Float
    public let totalIssues: Int
    public let criticalIssues: Int
    public let warningIssues: Int
    public let infoIssues: Int
    public let issues: [IntegrityIssue]
    public let checkDuration: TimeInterval
    public let checkedAt: Date
}

public struct IntegrityIssue: Identifiable {
    public let id: UUID
    public let type: IssueType
    public let severity: IssueSeverity
    public let title: String
    public let description: String
    public let affectedEntity: String?
    public let affectedObjectID: NSManagedObjectID?
    public let isRepairable: Bool
    public let repairSuggestion: String?
    public let discoveredAt: Date
    
    public enum IssueType: String, CaseIterable {
        case orphanedFurnitureItem = "orphaned_furniture_item"
        case missingRelationship = "missing_relationship"
        case invalidData = "invalid_data"
        case corruptedChecksum = "corrupted_checksum"
        case duplicateEntity = "duplicate_entity"
        case inconsistentState = "inconsistent_state"
        case performanceIssue = "performance_issue"
        case storageIssue = "storage_issue"
        case syncIssue = "sync_issue"
        case backupIssue = "backup_issue"
    }
    
    public enum IssueSeverity: String, CaseIterable {
        case critical = "critical"
        case warning = "warning"
        case info = "info"
        
        var color: String {
            switch self {
            case .critical: return "red"
            case .warning: return "orange"
            case .info: return "blue"
            }
        }
    }
}

public struct RepairRecord: Identifiable {
    public let id: UUID
    public let date: Date
    public let issuesAttempted: Int
    public let issuesRepaired: Int
    public let issuesFailed: Int
    public let duration: TimeInterval
    public let repairType: RepairType
    
    public enum RepairType: String {
        case automatic = "automatic"
        case manual = "manual"
    }
}

public struct IntegrityReport {
    public let overallScore: Float
    public let lastCheckDate: Date?
    public let totalIssues: Int
    public let issuesByType: [IntegrityIssue.IssueType: [IntegrityIssue]]
    public let issuesBySeverity: [IntegrityIssue.IssueSeverity: [IntegrityIssue]]
    public let repairHistory: [RepairRecord]
    public let recommendations: [String]
}

// MARK: - Specialized Checker Classes

@MainActor
class ConsistencyChecker {
    func checkProjectConsistency(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        var issues: [IntegrityIssue] = []
        
        let request = ProjectMO.fetchRequest()
        let projects = try context.fetch(request)
        
        for project in projects {
            // Check required fields
            if project.name?.isEmpty ?? true {
                issues.append(IntegrityIssue(
                    id: UUID(),
                    type: .invalidData,
                    severity: .warning,
                    title: "Project Missing Name",
                    description: "Project does not have a valid name",
                    affectedEntity: "ProjectMO",
                    affectedObjectID: project.objectID,
                    isRepairable: true,
                    repairSuggestion: "Set default name",
                    discoveredAt: Date()
                ))
            }
            
            // Check dates
            if project.createdAt == nil {
                issues.append(IntegrityIssue(
                    id: UUID(),
                    type: .invalidData,
                    severity: .warning,
                    title: "Project Missing Creation Date",
                    description: "Project does not have a creation date",
                    affectedEntity: "ProjectMO",
                    affectedObjectID: project.objectID,
                    isRepairable: true,
                    repairSuggestion: "Set current date",
                    discoveredAt: Date()
                ))
            }
        }
        
        return issues
    }
    
    func checkFurnitureItemConsistency(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        var issues: [IntegrityIssue] = []
        
        let request = FurnitureItemMO.fetchRequest()
        let items = try context.fetch(request)
        
        for item in items {
            // Check for valid position
            if item.positionX.isNaN || item.positionY.isNaN || item.positionZ.isNaN {
                issues.append(IntegrityIssue(
                    id: UUID(),
                    type: .invalidData,
                    severity: .critical,
                    title: "Invalid Furniture Position",
                    description: "Furniture item has invalid position coordinates",
                    affectedEntity: "FurnitureItemMO",
                    affectedObjectID: item.objectID,
                    isRepairable: true,
                    repairSuggestion: "Reset to origin position",
                    discoveredAt: Date()
                ))
            }
        }
        
        return issues
    }
    
    func checkTemplateConsistency(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        var issues: [IntegrityIssue] = []
        
        let request = ProjectTemplateMO.fetchRequest()
        let templates = try context.fetch(request)
        
        for template in templates {
            // Check template data integrity
            if template.templateData == nil {
                issues.append(IntegrityIssue(
                    id: UUID(),
                    type: .invalidData,
                    severity: .critical,
                    title: "Template Missing Data",
                    description: "Template does not contain template data",
                    affectedEntity: "ProjectTemplateMO",
                    affectedObjectID: template.objectID,
                    isRepairable: false,
                    repairSuggestion: "Template needs to be recreated",
                    discoveredAt: Date()
                ))
            }
        }
        
        return issues
    }
    
    func checkVersionConsistency(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        var issues: [IntegrityIssue] = []
        
        let request = ProjectVersionMO.fetchRequest()
        let versions = try context.fetch(request)
        
        for version in versions {
            // Check version data integrity
            if let versionData = version.versionData,
               let checksum = version.checksum {
                let calculatedChecksum = versionData.sha256Hash
                if calculatedChecksum != checksum {
                    issues.append(IntegrityIssue(
                        id: UUID(),
                        type: .corruptedChecksum,
                        severity: .critical,
                        title: "Version Checksum Mismatch",
                        description: "Version data checksum does not match stored checksum",
                        affectedEntity: "ProjectVersionMO",
                        affectedObjectID: version.objectID,
                        isRepairable: true,
                        repairSuggestion: "Recalculate checksum",
                        discoveredAt: Date()
                    ))
                }
            }
        }
        
        return issues
    }
}

@MainActor
class RelationshipValidator {
    func validateProjectFurnitureRelationships(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        var issues: [IntegrityIssue] = []
        
        // Find orphaned furniture items
        let furnitureRequest = FurnitureItemMO.fetchRequest()
        furnitureRequest.predicate = NSPredicate(format: "project == nil")
        
        let orphanedItems = try context.fetch(furnitureRequest)
        
        for item in orphanedItems {
            issues.append(IntegrityIssue(
                id: UUID(),
                type: .orphanedFurnitureItem,
                severity: .warning,
                title: "Orphaned Furniture Item",
                description: "Furniture item is not associated with any project",
                affectedEntity: "FurnitureItemMO",
                affectedObjectID: item.objectID,
                isRepairable: true,
                repairSuggestion: "Delete orphaned item",
                discoveredAt: Date()
            ))
        }
        
        return issues
    }
    
    func validateProjectRoomRelationships(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        var issues: [IntegrityIssue] = []
        
        // Find rooms without projects
        let roomRequest = RoomDataMO.fetchRequest()
        roomRequest.predicate = NSPredicate(format: "project == nil")
        
        let orphanedRooms = try context.fetch(roomRequest)
        
        for room in orphanedRooms {
            issues.append(IntegrityIssue(
                id: UUID(),
                type: .orphanedFurnitureItem,
                severity: .warning,
                title: "Orphaned Room Data",
                description: "Room data is not associated with any project",
                affectedEntity: "RoomDataMO",
                affectedObjectID: room.objectID,
                isRepairable: true,
                repairSuggestion: "Delete orphaned room data",
                discoveredAt: Date()
            ))
        }
        
        return issues
    }
    
    func validateProjectVersionRelationships(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        var issues: [IntegrityIssue] = []
        
        // Find versions without projects
        let versionsRequest = ProjectVersionMO.fetchRequest()
        versionsRequest.predicate = NSPredicate(format: "project == nil")
        
        let orphanedVersions = try context.fetch(versionsRequest)
        
        for version in orphanedVersions {
            issues.append(IntegrityIssue(
                id: UUID(),
                type: .orphanedFurnitureItem,
                severity: .critical,
                title: "Orphaned Version Data",
                description: "Version data is not associated with any project",
                affectedEntity: "ProjectVersionMO",
                affectedObjectID: version.objectID,
                isRepairable: true,
                repairSuggestion: "Delete orphaned version",
                discoveredAt: Date()
            ))
        }
        
        return issues
    }
    
    func validateOrphanedObjects(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        // This method would be expanded to check all entity relationships
        return []
    }
}

@MainActor
class DataCorruptionDetector {
    func detectDataCorruption(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        var issues: [IntegrityIssue] = []
        
        // Check for data format corruption
        let projectRequest = ProjectMO.fetchRequest()
        let projects = try context.fetch(projectRequest)
        
        for project in projects {
            // Check JSON data validity
            if let settingsData = project.settings?.data(using: .utf8) {
                do {
                    _ = try JSONSerialization.jsonObject(with: settingsData)
                } catch {
                    issues.append(IntegrityIssue(
                        id: UUID(),
                        type: .invalidData,
                        severity: .warning,
                        title: "Corrupted Settings Data",
                        description: "Project settings contain invalid JSON data",
                        affectedEntity: "ProjectMO",
                        affectedObjectID: project.objectID,
                        isRepairable: true,
                        repairSuggestion: "Reset settings to default",
                        discoveredAt: Date()
                    ))
                }
            }
        }
        
        return issues
    }
    
    func validateChecksums(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        // Already implemented in ConsistencyChecker
        return []
    }
    
    func validateDataFormats(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        // Implementation for validating data formats
        return []
    }
}

@MainActor
class PerformanceAnalyzer {
    func analyzeQueryPerformance(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        var issues: [IntegrityIssue] = []
        
        // Check for entities with unusually large counts
        let entities = context.persistentStoreCoordinator?.managedObjectModel.entities ?? []
        
        for entity in entities {
            if let entityName = entity.name {
                let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                request.includesSubentities = false
                
                let count = try context.count(for: request)
                
                // Flag entities with more than 10,000 records
                if count > 10000 {
                    issues.append(IntegrityIssue(
                        id: UUID(),
                        type: .performanceIssue,
                        severity: .info,
                        title: "Large Entity Count",
                        description: "Entity \(entityName) has \(count) records",
                        affectedEntity: entityName,
                        affectedObjectID: nil,
                        isRepairable: false,
                        repairSuggestion: "Consider data archiving or cleanup",
                        discoveredAt: Date()
                    ))
                }
            }
        }
        
        return issues
    }
    
    func checkMemoryUsage(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        // Implementation for memory usage analysis
        return []
    }
    
    func validateDataSizes(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        var issues: [IntegrityIssue] = []
        
        // Check for unusually large template data
        let templateRequest = ProjectTemplateMO.fetchRequest()
        let templates = try context.fetch(templateRequest)
        
        for template in templates {
            if template.dataSize > 10 * 1024 * 1024 { // 10MB
                issues.append(IntegrityIssue(
                    id: UUID(),
                    type: .performanceIssue,
                    severity: .warning,
                    title: "Large Template Data",
                    description: "Template data size is unusually large (\(template.dataSize) bytes)",
                    affectedEntity: "ProjectTemplateMO",
                    affectedObjectID: template.objectID,
                    isRepairable: false,
                    repairSuggestion: "Consider optimizing template data",
                    discoveredAt: Date()
                ))
            }
        }
        
        return issues
    }
}

@MainActor
class HealthMonitor {
    func checkStorageHealth(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        var issues: [IntegrityIssue] = []
        
        // Check available disk space
        if let storeURL = context.persistentStoreCoordinator?.persistentStores.first?.url {
            do {
                let resourceValues = try storeURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
                if let availableCapacity = resourceValues.volumeAvailableCapacity,
                   availableCapacity < 100 * 1024 * 1024 { // Less than 100MB
                    issues.append(IntegrityIssue(
                        id: UUID(),
                        type: .storageIssue,
                        severity: .critical,
                        title: "Low Disk Space",
                        description: "Available disk space is critically low",
                        affectedEntity: nil,
                        affectedObjectID: nil,
                        isRepairable: false,
                        repairSuggestion: "Free up disk space",
                        discoveredAt: Date()
                    ))
                }
            } catch {
                // Could not check disk space
            }
        }
        
        return issues
    }
    
    func checkCloudKitHealth(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        var issues: [IntegrityIssue] = []
        
        // Check CloudKit availability
        if !CoreDataStack.shared.isCloudKitAvailable() {
            issues.append(IntegrityIssue(
                id: UUID(),
                type: .syncIssue,
                severity: .warning,
                title: "CloudKit Unavailable",
                description: "iCloud synchronization is not available",
                affectedEntity: nil,
                affectedObjectID: nil,
                isRepairable: false,
                repairSuggestion: "Check iCloud account settings",
                discoveredAt: Date()
            ))
        }
        
        return issues
    }
    
    func checkBackupIntegrity(context: NSManagedObjectContext) throws -> [IntegrityIssue] {
        // Implementation for backup integrity checking
        return []
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