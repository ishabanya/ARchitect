import Foundation
import CoreData
import Combine

// MARK: - Project Template Management System

@MainActor
public class TemplateManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var availableTemplates: [ProjectTemplate] = []
    @Published public var featuredTemplates: [ProjectTemplate] = []
    @Published public var userTemplates: [ProjectTemplate] = []
    @Published public var isLoading: Bool = false
    @Published public var templateCategories: [TemplateCategory] = []
    
    // MARK: - Private Properties
    private let coreDataStack: CoreDataStack
    private let templateBuilder: TemplateBuilder
    private let templateValidator: TemplateValidator
    private let bundledTemplateLoader: BundledTemplateLoader
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Template Categories
    public enum TemplateCategory: String, CaseIterable {
        case livingRoom = "Living Room"
        case bedroom = "Bedroom"
        case kitchen = "Kitchen"
        case office = "Office"
        case diningRoom = "Dining Room"
        case bathroom = "Bathroom"
        case outdoor = "Outdoor"
        case commercial = "Commercial"
        case custom = "Custom"
        
        var icon: String {
            switch self {
            case .livingRoom: return "sofa.fill"
            case .bedroom: return "bed.double.fill"
            case .kitchen: return "cooktop.fill"
            case .office: return "desktopcomputer"
            case .diningRoom: return "table.furniture.fill"
            case .bathroom: return "bathtub.fill"
            case .outdoor: return "tree.fill"
            case .commercial: return "building.2.fill"
            case .custom: return "folder.fill"
            }
        }
        
        var description: String {
            switch self {
            case .livingRoom: return "Comfortable living spaces for relaxation and entertainment"
            case .bedroom: return "Peaceful bedroom arrangements for rest and privacy"
            case .kitchen: return "Functional kitchen layouts for cooking and dining"
            case .office: return "Productive workspace designs for work and study"
            case .diningRoom: return "Elegant dining arrangements for meals and gatherings"
            case .bathroom: return "Efficient bathroom layouts for daily routines"
            case .outdoor: return "Outdoor furniture arrangements for patios and gardens"
            case .commercial: return "Professional spaces for business and retail"
            case .custom: return "User-created templates and personalized designs"
            }
        }
    }
    
    public init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
        self.templateBuilder = TemplateBuilder(coreDataStack: coreDataStack)
        self.templateValidator = TemplateValidator()
        self.bundledTemplateLoader = BundledTemplateLoader()
        
        setupObservers()
        
        Task {
            await loadTemplates()
            await loadBundledTemplates()
        }
        
        logDebug("Template manager initialized", category: .persistence)
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshTemplates()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Template Loading
    
    public func loadTemplates() async {
        isLoading = true
        
        do {
            let templates = try await fetchAllTemplates()
            
            availableTemplates = templates
            userTemplates = templates.filter { $0.isUserCreated }
            featuredTemplates = templates.filter { $0.isFeatured }
            
            // Group by categories
            templateCategories = TemplateCategory.allCases.compactMap { category in
                let categoryTemplates = templates.filter { $0.category == category }
                return categoryTemplates.isEmpty ? nil : category
            }
            
            isLoading = false
            
            logInfo("Templates loaded", category: .persistence, context: LogContext(customData: [
                "total_templates": templates.count,
                "user_templates": userTemplates.count,
                "featured_templates": featuredTemplates.count
            ]))
            
        } catch {
            isLoading = false
            logError("Failed to load templates", category: .persistence, error: error)
        }
    }
    
    private func loadBundledTemplates() async {
        do {
            let bundledTemplates = try await bundledTemplateLoader.loadBundledTemplates()
            
            for templateData in bundledTemplates {
                if !templateExists(id: templateData.id) {
                    try await createTemplate(from: templateData)
                }
            }
            
            logInfo("Bundled templates loaded", category: .persistence, context: LogContext(customData: [
                "bundled_count": bundledTemplates.count
            ]))
            
        } catch {
            logError("Failed to load bundled templates", category: .persistence, error: error)
        }
    }
    
    // MARK: - Template Creation
    
    public func createTemplate(
        from project: ProjectMO,
        name: String,
        description: String,
        category: TemplateCategory,
        tags: [String] = [],
        isPublic: Bool = false
    ) async throws -> ProjectTemplate {
        
        // Validate project for template creation
        let validationResult = templateValidator.validateForTemplate(project: project)
        guard validationResult.isValid else {
            throw TemplateError.validationFailed(validationResult.issues)
        }
        
        let template = try await coreDataStack.executeInBackground { context in
            // Get project in background context
            let backgroundProject = try context.existingObject(with: project.objectID) as! ProjectMO
            
            // Create template entity
            let templateMO = context.insertObject(ProjectTemplateMO.self)
            templateMO.id = UUID()
            templateMO.name = name
            templateMO.templateDescription = description
            templateMO.category = category.rawValue
            templateMO.tags = tags.joined(separator: ",")
            templateMO.isUserCreated = true
            templateMO.isPublic = isPublic
            templateMO.isFeatured = false
            templateMO.createdAt = Date()
            templateMO.modifiedAt = Date()
            templateMO.usageCount = 0
            templateMO.rating = 0.0
            
            // Create template data from project
            let templateData = try self.templateBuilder.buildTemplateData(from: backgroundProject)
            templateMO.templateData = try JSONEncoder().encode(templateData)
            templateMO.dataSize = Int64(templateMO.templateData?.count ?? 0)
            
            // Generate preview image
            templateMO.previewImage = try await self.generatePreviewImage(from: backgroundProject)
            
            try context.save()
            
            return ProjectTemplate(from: templateMO)
        }
        
        // Update in-memory collections
        availableTemplates.append(template)
        userTemplates.append(template)
        
        logInfo("Template created", category: .persistence, context: LogContext(customData: [
            "template_id": template.id.uuidString,
            "template_name": name,
            "category": category.rawValue
        ]))
        
        return template
    }
    
    private func createTemplate(from bundledData: BundledTemplateData) async throws {
        _ = try await coreDataStack.executeInBackground { context in
            let templateMO = context.insertObject(ProjectTemplateMO.self)
            templateMO.id = bundledData.id
            templateMO.name = bundledData.name
            templateMO.templateDescription = bundledData.description
            templateMO.category = bundledData.category.rawValue
            templateMO.tags = bundledData.tags.joined(separator: ",")
            templateMO.isUserCreated = false
            templateMO.isPublic = true
            templateMO.isFeatured = bundledData.isFeatured
            templateMO.createdAt = Date()
            templateMO.modifiedAt = Date()
            templateMO.usageCount = 0
            templateMO.rating = bundledData.rating
            templateMO.templateData = bundledData.templateData
            templateMO.dataSize = Int64(bundledData.templateData.count)
            templateMO.previewImage = bundledData.previewImage
            
            try context.save()
        }
    }
    
    // MARK: - Template Application
    
    public func applyTemplate(
        _ template: ProjectTemplate,
        to project: ProjectMO,
        options: TemplateApplicationOptions = .default
    ) async throws {
        
        guard let templateData = try await getTemplateData(template) else {
            throw TemplateError.templateDataNotFound
        }
        
        try await coreDataStack.executeInBackground { context in
            let backgroundProject = try context.existingObject(with: project.objectID) as! ProjectMO
            
            // Clear existing content if specified
            if options.clearExisting {
                try self.clearProjectContent(backgroundProject, in: context)
            }
            
            // Apply template data
            try self.templateBuilder.applyTemplateData(
                templateData,
                to: backgroundProject,
                options: options
            )
            
            try context.save()
        }
        
        // Update template usage
        try await incrementTemplateUsage(template)
        
        logInfo("Template applied", category: .persistence, context: LogContext(customData: [
            "template_id": template.id.uuidString,
            "project_id": project.id?.uuidString ?? "unknown"
        ]))
    }
    
    public func createProjectFromTemplate(
        _ template: ProjectTemplate,
        name: String,
        options: TemplateApplicationOptions = .default
    ) async throws -> ProjectMO {
        
        guard let templateData = try await getTemplateData(template) else {
            throw TemplateError.templateDataNotFound
        }
        
        let project = try await coreDataStack.executeInBackground { context in
            // Create new project
            let projectMO = context.insertObject(ProjectMO.self)
            projectMO.id = UUID()
            projectMO.name = name
            projectMO.projectDescription = "Created from template: \(template.name)"
            projectMO.createdAt = Date()
            projectMO.modifiedAt = Date()
            projectMO.isTemplate = false
            
            // Apply template data
            try self.templateBuilder.applyTemplateData(
                templateData,
                to: projectMO,
                options: options
            )
            
            try context.save()
            
            return projectMO
        }
        
        // Update template usage
        try await incrementTemplateUsage(template)
        
        logInfo("Project created from template", category: .persistence, context: LogContext(customData: [
            "template_id": template.id.uuidString,
            "project_name": name
        ]))
        
        return project
    }
    
    // MARK: - Template Management
    
    public func updateTemplate(
        _ template: ProjectTemplate,
        name: String? = nil,
        description: String? = nil,
        tags: [String]? = nil,
        isPublic: Bool? = nil
    ) async throws {
        
        try await coreDataStack.executeInBackground { context in
            let templateMO = try context.existingObject(with: template.objectID) as! ProjectTemplateMO
            
            if let name = name { templateMO.name = name }
            if let description = description { templateMO.templateDescription = description }
            if let tags = tags { templateMO.tags = tags.joined(separator: ",") }
            if let isPublic = isPublic { templateMO.isPublic = isPublic }
            
            templateMO.modifiedAt = Date()
            
            try context.save()
        }
        
        // Refresh templates
        await refreshTemplates()
        
        logInfo("Template updated", category: .persistence, context: LogContext(customData: [
            "template_id": template.id.uuidString
        ]))
    }
    
    public func deleteTemplate(_ template: ProjectTemplate) async throws {
        guard template.isUserCreated else {
            throw TemplateError.cannotDeleteSystemTemplate
        }
        
        try await coreDataStack.executeInBackground { context in
            let templateMO = try context.existingObject(with: template.objectID) as! ProjectTemplateMO
            context.delete(templateMO)
            try context.save()
        }
        
        // Remove from in-memory collections
        availableTemplates.removeAll { $0.id == template.id }
        userTemplates.removeAll { $0.id == template.id }
        
        logInfo("Template deleted", category: .persistence, context: LogContext(customData: [
            "template_id": template.id.uuidString
        ]))
    }
    
    public func duplicateTemplate(
        _ template: ProjectTemplate,
        newName: String
    ) async throws -> ProjectTemplate {
        
        guard let templateData = try await getTemplateData(template) else {
            throw TemplateError.templateDataNotFound
        }
        
        let duplicatedTemplate = try await coreDataStack.executeInBackground { context in
            let templateMO = context.insertObject(ProjectTemplateMO.self)
            templateMO.id = UUID()
            templateMO.name = newName
            templateMO.templateDescription = "Copy of \(template.name)"
            templateMO.category = template.category.rawValue
            templateMO.tags = template.tags.joined(separator: ",")
            templateMO.isUserCreated = true
            templateMO.isPublic = false
            templateMO.isFeatured = false
            templateMO.createdAt = Date()
            templateMO.modifiedAt = Date()
            templateMO.usageCount = 0
            templateMO.rating = 0.0
            templateMO.templateData = try JSONEncoder().encode(templateData)
            templateMO.dataSize = Int64(templateMO.templateData?.count ?? 0)
            templateMO.previewImage = template.previewImage
            
            try context.save()
            
            return ProjectTemplate(from: templateMO)
        }
        
        // Update in-memory collections
        availableTemplates.append(duplicatedTemplate)
        userTemplates.append(duplicatedTemplate)
        
        logInfo("Template duplicated", category: .persistence, context: LogContext(customData: [
            "original_template_id": template.id.uuidString,
            "new_template_id": duplicatedTemplate.id.uuidString
        ]))
        
        return duplicatedTemplate
    }
    
    // MARK: - Template Discovery
    
    public func searchTemplates(
        query: String,
        category: TemplateCategory? = nil,
        tags: [String] = [],
        sortBy: TemplateSortOption = .name
    ) -> [ProjectTemplate] {
        
        var results = availableTemplates
        
        // Filter by query
        if !query.isEmpty {
            results = results.filter { template in
                template.name.localizedCaseInsensitiveContains(query) ||
                template.description.localizedCaseInsensitiveContains(query) ||
                template.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }
        
        // Filter by category
        if let category = category {
            results = results.filter { $0.category == category }
        }
        
        // Filter by tags
        if !tags.isEmpty {
            results = results.filter { template in
                !Set(template.tags).intersection(Set(tags)).isEmpty
            }
        }
        
        // Sort results
        switch sortBy {
        case .name:
            results.sort { $0.name < $1.name }
        case .popularity:
            results.sort { $0.usageCount > $1.usageCount }
        case .rating:
            results.sort { $0.rating > $1.rating }
        case .dateCreated:
            results.sort { $0.createdAt > $1.createdAt }
        case .dateModified:
            results.sort { $0.modifiedAt > $1.modifiedAt }
        }
        
        return results
    }
    
    public func getTemplatesByCategory(_ category: TemplateCategory) -> [ProjectTemplate] {
        return availableTemplates.filter { $0.category == category }
    }
    
    public func getPopularTemplates(limit: Int = 10) -> [ProjectTemplate] {
        return availableTemplates
            .sorted { $0.usageCount > $1.usageCount }
            .prefix(limit)
            .map { $0 }
    }
    
    public func getRecentTemplates(limit: Int = 10) -> [ProjectTemplate] {
        return availableTemplates
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }
    
    // MARK: - Template Rating
    
    public func rateTemplate(_ template: ProjectTemplate, rating: Float) async throws {
        let clampedRating = max(0.0, min(5.0, rating))
        
        try await coreDataStack.executeInBackground { context in
            let templateMO = try context.existingObject(with: template.objectID) as! ProjectTemplateMO
            
            // Simple average for now - could be improved with weighted average
            let currentRating = templateMO.rating
            let currentCount = templateMO.ratingCount
            let newCount = currentCount + 1
            let newRating = ((currentRating * Float(currentCount)) + clampedRating) / Float(newCount)
            
            templateMO.rating = newRating
            templateMO.ratingCount = newCount
            
            try context.save()
        }
        
        // Refresh templates
        await refreshTemplates()
        
        logInfo("Template rated", category: .persistence, context: LogContext(customData: [
            "template_id": template.id.uuidString,
            "rating": clampedRating
        ]))
    }
    
    // MARK: - Helper Methods
    
    private func fetchAllTemplates() async throws -> [ProjectTemplate] {
        return try await coreDataStack.executeInBackground { context in
            let request = ProjectTemplateMO.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \ProjectTemplateMO.isFeatured, ascending: false),
                NSSortDescriptor(keyPath: \ProjectTemplateMO.name, ascending: true)
            ]
            
            let templateEntities = try context.fetch(request)
            return templateEntities.map { ProjectTemplate(from: $0) }
        }
    }
    
    private func getTemplateData(_ template: ProjectTemplate) async throws -> TemplateData? {
        return try await coreDataStack.executeInBackground { context in
            let templateMO = try context.existingObject(with: template.objectID) as! ProjectTemplateMO
            
            guard let data = templateMO.templateData else { return nil }
            return try JSONDecoder().decode(TemplateData.self, from: data)
        }
    }
    
    private func templateExists(id: UUID) -> Bool {
        do {
            let count = try coreDataStack.count(for: ProjectTemplateMO.self, predicate: NSPredicate(format: "id == %@", id as CVarArg))
            return count > 0
        } catch {
            return false
        }
    }
    
    private func incrementTemplateUsage(_ template: ProjectTemplate) async throws {
        try await coreDataStack.executeInBackground { context in
            let templateMO = try context.existingObject(with: template.objectID) as! ProjectTemplateMO
            templateMO.usageCount += 1
            templateMO.lastUsedAt = Date()
            try context.save()
        }
    }
    
    private func clearProjectContent(_ project: ProjectMO, in context: NSManagedObjectContext) throws {
        // Clear furniture items
        if let furnitureItems = project.furnitureItems {
            for item in furnitureItems {
                context.delete(item as! NSManagedObject)
            }
        }
        
        // Clear room data
        if let roomData = project.roomData {
            context.delete(roomData)
        }
    }
    
    private func generatePreviewImage(from project: ProjectMO) async throws -> Data? {
        // This would generate a preview image of the project
        // Implementation would depend on rendering system
        return nil // Placeholder
    }
    
    private func refreshTemplates() async {
        await loadTemplates()
    }
    
    // MARK: - Public Interface
    
    public func getTemplate(by id: UUID) -> ProjectTemplate? {
        return availableTemplates.first { $0.id == id }
    }
    
    public func getTemplateStatistics() -> TemplateStatistics {
        return TemplateStatistics(
            totalTemplates: availableTemplates.count,
            userTemplates: userTemplates.count,
            featuredTemplates: featuredTemplates.count,
            categories: templateCategories.count,
            mostPopularTemplate: availableTemplates.max { $0.usageCount < $1.usageCount },
            highestRatedTemplate: availableTemplates.max { $0.rating < $1.rating }
        )
    }
    
    public func exportTemplate(_ template: ProjectTemplate) async throws -> Data {
        guard let templateData = try await getTemplateData(template) else {
            throw TemplateError.templateDataNotFound
        }
        
        let exportData = TemplateExportData(
            template: template,
            templateData: templateData,
            exportDate: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        )
        
        return try JSONEncoder().encode(exportData)
    }
    
    public func importTemplate(from data: Data) async throws -> ProjectTemplate {
        let importData = try JSONDecoder().decode(TemplateExportData.self, from: data)
        
        // Validate imported template
        let validationResult = templateValidator.validateImportedTemplate(importData)
        guard validationResult.isValid else {
            throw TemplateError.validationFailed(validationResult.issues)
        }
        
        let template = try await coreDataStack.executeInBackground { context in
            let templateMO = context.insertObject(ProjectTemplateMO.self)
            templateMO.id = UUID() // Generate new ID for imported template
            templateMO.name = "\(importData.template.name) (Imported)"
            templateMO.templateDescription = importData.template.description
            templateMO.category = importData.template.category.rawValue
            templateMO.tags = importData.template.tags.joined(separator: ",")
            templateMO.isUserCreated = true
            templateMO.isPublic = false
            templateMO.isFeatured = false
            templateMO.createdAt = Date()
            templateMO.modifiedAt = Date()
            templateMO.usageCount = 0
            templateMO.rating = 0.0
            templateMO.templateData = try JSONEncoder().encode(importData.templateData)
            templateMO.dataSize = Int64(templateMO.templateData?.count ?? 0)
            templateMO.previewImage = importData.template.previewImage
            
            try context.save()
            
            return ProjectTemplate(from: templateMO)
        }
        
        // Update in-memory collections
        availableTemplates.append(template)
        userTemplates.append(template)
        
        logInfo("Template imported", category: .persistence, context: LogContext(customData: [
            "template_name": template.name
        ]))
        
        return template
    }
}

// MARK: - Supporting Data Structures

public struct ProjectTemplate: Identifiable {
    public let id: UUID
    public let objectID: NSManagedObjectID
    public let name: String
    public let description: String
    public let category: TemplateManager.TemplateCategory
    public let tags: [String]
    public let isUserCreated: Bool
    public let isPublic: Bool
    public let isFeatured: Bool
    public let createdAt: Date
    public let modifiedAt: Date
    public let usageCount: Int32
    public let rating: Float
    public let ratingCount: Int32
    public let lastUsedAt: Date?
    public let previewImage: Data?
    public let dataSize: Int64
    
    init(from entity: ProjectTemplateMO) {
        self.id = entity.id ?? UUID()
        self.objectID = entity.objectID
        self.name = entity.name ?? ""
        self.description = entity.templateDescription ?? ""
        self.category = TemplateManager.TemplateCategory(rawValue: entity.category ?? "") ?? .custom
        self.tags = entity.tags?.components(separatedBy: ",") ?? []
        self.isUserCreated = entity.isUserCreated
        self.isPublic = entity.isPublic
        self.isFeatured = entity.isFeatured
        self.createdAt = entity.createdAt ?? Date()
        self.modifiedAt = entity.modifiedAt ?? Date()
        self.usageCount = entity.usageCount
        self.rating = entity.rating
        self.ratingCount = entity.ratingCount
        self.lastUsedAt = entity.lastUsedAt
        self.previewImage = entity.previewImage
        self.dataSize = entity.dataSize
    }
}

public struct TemplateApplicationOptions {
    public let clearExisting: Bool
    public let preserveRoomData: Bool
    public let scaleFurniture: Bool
    public let adjustColors: Bool
    public let mergeFurniture: Bool
    
    public static let `default` = TemplateApplicationOptions(
        clearExisting: true,
        preserveRoomData: false,
        scaleFurniture: true,
        adjustColors: false,
        mergeFurniture: false
    )
    
    public static let merge = TemplateApplicationOptions(
        clearExisting: false,
        preserveRoomData: true,
        scaleFurniture: true,
        adjustColors: true,
        mergeFurniture: true
    )
}

public enum TemplateSortOption {
    case name
    case popularity
    case rating
    case dateCreated
    case dateModified
}

public struct TemplateStatistics {
    public let totalTemplates: Int
    public let userTemplates: Int
    public let featuredTemplates: Int
    public let categories: Int
    public let mostPopularTemplate: ProjectTemplate?
    public let highestRatedTemplate: ProjectTemplate?
}

public struct TemplateExportData: Codable {
    public let template: ProjectTemplate
    public let templateData: TemplateData
    public let exportDate: Date
    public let appVersion: String
}

public enum TemplateError: Error {
    case validationFailed([String])
    case templateDataNotFound
    case cannotDeleteSystemTemplate
    case importFailed(String)
    case buildFailed(String)
    
    public var localizedDescription: String {
        switch self {
        case .validationFailed(let issues):
            return "Template validation failed: \(issues.joined(separator: ", "))"
        case .templateDataNotFound:
            return "Template data not found"
        case .cannotDeleteSystemTemplate:
            return "Cannot delete system templates"
        case .importFailed(let message):
            return "Template import failed: \(message)"
        case .buildFailed(let message):
            return "Template build failed: \(message)"
        }
    }
}

// MARK: - Template Data Structures

public struct TemplateData: Codable {
    let projectData: ProjectDataTemplate
    let furnitureItems: [FurnitureItemTemplate]
    let roomData: RoomDataTemplate?
    let layout: LayoutTemplate
    let metadata: TemplateMetadata
}

public struct ProjectDataTemplate: Codable {
    let name: String
    let description: String?
    let tags: [String]
    let settings: [String: String]
}

public struct FurnitureItemTemplate: Codable {
    let id: UUID
    let name: String
    let category: String
    let relativePosition: [Float] // Relative to room center
    let rotation: Float
    let scale: [Float]
    let color: String?
    let material: String?
    let metadata: [String: String]
}

public struct RoomDataTemplate: Codable {
    let roomType: String
    let relativeDimensions: [Float] // Normalized dimensions
    let features: [String]
    let style: String?
}

public struct LayoutTemplate: Codable {
    let zones: [LayoutZone]
    let trafficPaths: [TrafficPath]
    let focalPoints: [FocalPoint]
}

public struct LayoutZone: Codable {
    let name: String
    let purpose: String
    let bounds: [Float] // Relative bounds
    let furnitureIds: [UUID]
}

public struct TrafficPath: Codable {
    let points: [[Float]] // Relative coordinates
    let width: Float
    let importance: Float
}

public struct FocalPoint: Codable {
    let position: [Float] // Relative position
    let type: String
    let radius: Float
}

public struct TemplateMetadata: Codable {
    let createdAt: Date
    let appVersion: String
    let minRoomSize: [Float]
    let maxRoomSize: [Float]
    let complexity: TemplateComplexity
    let estimatedSetupTime: TimeInterval
}

public enum TemplateComplexity: String, Codable {
    case simple = "Simple"
    case moderate = "Moderate"
    case complex = "Complex"
    case expert = "Expert"
}

// MARK: - Supporting Classes

@MainActor
class TemplateBuilder {
    private let coreDataStack: CoreDataStack
    
    init(coreDataStack: CoreDataStack) {
        self.coreDataStack = coreDataStack
    }
    
    func buildTemplateData(from project: ProjectMO) throws -> TemplateData {
        // Implementation would extract template data from project
        return TemplateData(
            projectData: ProjectDataTemplate(
                name: project.name ?? "",
                description: project.projectDescription,
                tags: project.tags?.components(separatedBy: ",") ?? [],
                settings: [:]
            ),
            furnitureItems: [],
            roomData: nil,
            layout: LayoutTemplate(zones: [], trafficPaths: [], focalPoints: []),
            metadata: TemplateMetadata(
                createdAt: Date(),
                appVersion: "1.0",
                minRoomSize: [3.0, 3.0, 2.5],
                maxRoomSize: [10.0, 10.0, 4.0],
                complexity: .moderate,
                estimatedSetupTime: 300
            )
        )
    }
    
    func applyTemplateData(
        _ templateData: TemplateData,
        to project: ProjectMO,
        options: TemplateApplicationOptions
    ) throws {
        // Implementation would apply template data to project
        if !options.preserveRoomData {
            project.name = templateData.projectData.name
            project.projectDescription = templateData.projectData.description
        }
        
        // Apply furniture items, room data, etc.
    }
}

@MainActor
class TemplateValidator {
    func validateForTemplate(project: ProjectMO) -> ValidationResult {
        var issues: [String] = []
        
        // Check if project has content
        if project.furnitureItems?.count == 0 {
            issues.append("Project must contain furniture items")
        }
        
        // Check if room data exists
        if project.roomData == nil {
            issues.append("Project must have room data")
        }
        
        return ValidationResult(isValid: issues.isEmpty, issues: issues)
    }
    
    func validateImportedTemplate(_ importData: TemplateExportData) -> ValidationResult {
        var issues: [String] = []
        
        // Validate template data structure
        if importData.templateData.furnitureItems.isEmpty {
            issues.append("Template must contain furniture items")
        }
        
        return ValidationResult(isValid: issues.isEmpty, issues: issues)
    }
}

struct ValidationResult {
    let isValid: Bool
    let issues: [String]
}

@MainActor
class BundledTemplateLoader {
    func loadBundledTemplates() async throws -> [BundledTemplateData] {
        // Load templates from app bundle
        guard let bundleURL = Bundle.main.url(forResource: "BundledTemplates", withExtension: "json") else {
            return []
        }
        
        let data = try Data(contentsOf: bundleURL)
        return try JSONDecoder().decode([BundledTemplateData].self, from: data)
    }
}

struct BundledTemplateData: Codable {
    let id: UUID
    let name: String
    let description: String
    let category: TemplateManager.TemplateCategory
    let tags: [String]
    let isFeatured: Bool
    let rating: Float
    let templateData: Data
    let previewImage: Data?
}

// Make ProjectTemplate Codable for export/import
extension ProjectTemplate: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, description, category, tags, isUserCreated, isPublic, isFeatured
        case createdAt, modifiedAt, usageCount, rating, ratingCount, lastUsedAt
        case previewImage, dataSize
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        objectID = NSManagedObjectID() // This would need proper handling
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        category = try container.decode(TemplateManager.TemplateCategory.self, forKey: .category)
        tags = try container.decode([String].self, forKey: .tags)
        isUserCreated = try container.decode(Bool.self, forKey: .isUserCreated)
        isPublic = try container.decode(Bool.self, forKey: .isPublic)
        isFeatured = try container.decode(Bool.self, forKey: .isFeatured)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        usageCount = try container.decode(Int32.self, forKey: .usageCount)
        rating = try container.decode(Float.self, forKey: .rating)
        ratingCount = try container.decode(Int32.self, forKey: .ratingCount)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        previewImage = try container.decodeIfPresent(Data.self, forKey: .previewImage)
        dataSize = try container.decode(Int64.self, forKey: .dataSize)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(category, forKey: .category)
        try container.encode(tags, forKey: .tags)
        try container.encode(isUserCreated, forKey: .isUserCreated)
        try container.encode(isPublic, forKey: .isPublic)
        try container.encode(isFeatured, forKey: .isFeatured)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(usageCount, forKey: .usageCount)
        try container.encode(rating, forKey: .rating)
        try container.encode(ratingCount, forKey: .ratingCount)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encodeIfPresent(previewImage, forKey: .previewImage)
        try container.encode(dataSize, forKey: .dataSize)
    }
}