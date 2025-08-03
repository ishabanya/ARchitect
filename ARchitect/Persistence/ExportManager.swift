import Foundation
import CoreData
import UniformTypeIdentifiers
import Combine

// MARK: - Multi-Format Export System

@MainActor
public class ExportManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var exportProgress: Double = 0.0
    @Published public var isExporting: Bool = false
    @Published public var lastExportResult: ExportResult?
    @Published public var supportedFormats: [ExportFormat] = []
    
    // MARK: - Private Properties
    private let coreDataStack: CoreDataStack
    private let formatExporters: [ExportFormat: FormatExporter]
    private let compressionManager: CompressionManager
    private let validationManager: ExportValidationManager
    
    private var currentExportTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    public init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
        self.compressionManager = CompressionManager()
        self.validationManager = ExportValidationManager()
        
        // Initialize format exporters
        self.formatExporters = [
            .json: JSONExporter(),
            .xml: XMLExporter(),
            .csv: CSVExporter(),
            .pdf: PDFExporter(),
            .zip: ZipExporter(),
            .usdz: USDZExporter(),
            .obj: OBJExporter(),
            .collada: ColladaExporter(),
            .excel: ExcelExporter(),
            .sqlite: SQLiteExporter()
        ]
        
        self.supportedFormats = Array(formatExporters.keys).sorted { $0.displayName < $1.displayName }
        
        setupObservers()
        
        logDebug("Export manager initialized", category: .persistence)
    }
    
    // MARK: - Export Formats
    
    public enum ExportFormat: String, CaseIterable {
        case json = "json"
        case xml = "xml"
        case csv = "csv"
        case pdf = "pdf"
        case zip = "zip"
        case usdz = "usdz"
        case obj = "obj"
        case collada = "dae"
        case excel = "xlsx"
        case sqlite = "sqlite"
        
        public var displayName: String {
            switch self {
            case .json: return "JSON"
            case .xml: return "XML"
            case .csv: return "CSV"
            case .pdf: return "PDF Report"
            case .zip: return "ZIP Archive"
            case .usdz: return "USDZ (AR)"
            case .obj: return "OBJ (3D)"
            case .collada: return "COLLADA (3D)"
            case .excel: return "Excel Spreadsheet"
            case .sqlite: return "SQLite Database"
            }
        }
        
        public var fileExtension: String {
            return rawValue
        }
        
        public var mimeType: String {
            switch self {
            case .json: return "application/json"
            case .xml: return "application/xml"
            case .csv: return "text/csv"
            case .pdf: return "application/pdf"
            case .zip: return "application/zip"
            case .usdz: return "model/vnd.usdz+zip"
            case .obj: return "model/obj"
            case .collada: return "model/vnd.collada+xml"
            case .excel: return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            case .sqlite: return "application/x-sqlite3"
            }
        }
        
        public var utType: UTType {
            switch self {
            case .json: return .json
            case .xml: return .xml
            case .csv: return .commaSeparatedText
            case .pdf: return .pdf
            case .zip: return .zip
            case .usdz: return .usdz
            case .obj: return UTType("public.geometry-definition-format")!
            case .collada: return UTType("org.khronos.collada.digital-asset-exchange")!
            case .excel: return UTType("org.openxmlformats.spreadsheetml.sheet")!
            case .sqlite: return UTType("public.database")!
            }
        }
        
        public var supportsMultipleProjects: Bool {
            switch self {
            case .zip, .excel, .sqlite: return true
            default: return false
            }
        }
        
        public var supports3D: Bool {
            switch self {
            case .usdz, .obj, .collada, .pdf: return true
            default: return false
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        $isExporting
            .sink { [weak self] exporting in
                if !exporting {
                    self?.exportProgress = 0.0
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Single Project Export
    
    public func exportProject(
        _ project: ProjectMO,
        format: ExportFormat,
        options: ExportOptions = .default
    ) async throws -> ExportResult {
        
        guard !isExporting else {
            throw ExportError.exportInProgress
        }
        
        isExporting = true
        exportProgress = 0.0
        
        return await withTaskCancellationHandler {
            do {
                let result = try await performProjectExport(project, format: format, options: options)
                
                isExporting = false
                lastExportResult = result
                
                logInfo("Project export completed", category: .persistence, context: LogContext(customData: [
                    "project_id": project.id?.uuidString ?? "unknown",
                    "format": format.rawValue,
                    "file_size": result.fileSize
                ]))
                
                return result
                
            } catch {
                isExporting = false
                
                logError("Project export failed", category: .persistence, error: error)
                throw error
            }
        } onCancel: {
            Task { @MainActor in
                self.isExporting = false
                self.exportProgress = 0.0
            }
        }
    }
    
    // MARK: - Multiple Projects Export
    
    public func exportProjects(
        _ projects: [ProjectMO],
        format: ExportFormat,
        options: ExportOptions = .default
    ) async throws -> ExportResult {
        
        guard format.supportsMultipleProjects else {
            throw ExportError.formatDoesNotSupportMultipleProjects
        }
        
        guard !isExporting else {
            throw ExportError.exportInProgress
        }
        
        isExporting = true
        exportProgress = 0.0
        
        return await withTaskCancellationHandler {
            do {
                let result = try await performMultipleProjectsExport(projects, format: format, options: options)
                
                isExporting = false
                lastExportResult = result
                
                logInfo("Multiple projects export completed", category: .persistence, context: LogContext(customData: [
                    "projects_count": projects.count,
                    "format": format.rawValue,
                    "file_size": result.fileSize
                ]))
                
                return result
                
            } catch {
                isExporting = false
                
                logError("Multiple projects export failed", category: .persistence, error: error)
                throw error
            }
        } onCancel: {
            Task { @MainActor in
                self.isExporting = false
                self.exportProgress = 0.0
            }
        }
    }
    
    // MARK: - Template Export
    
    public func exportTemplate(
        _ template: ProjectTemplate,
        format: ExportFormat,
        options: ExportOptions = .default
    ) async throws -> ExportResult {
        
        guard !isExporting else {
            throw ExportError.exportInProgress
        }
        
        isExporting = true
        exportProgress = 0.0
        
        do {
            let result = try await performTemplateExport(template, format: format, options: options)
            
            isExporting = false
            lastExportResult = result
            
            logInfo("Template export completed", category: .persistence, context: LogContext(customData: [
                "template_id": template.id.uuidString,
                "format": format.rawValue,
                "file_size": result.fileSize
            ]))
            
            return result
            
        } catch {
            isExporting = false
            
            logError("Template export failed", category: .persistence, error: error)
            throw error
        }
    }
    
    // MARK: - Batch Export
    
    public func exportBatch(
        _ batch: ExportBatch
    ) async throws -> BatchExportResult {
        
        guard !isExporting else {
            throw ExportError.exportInProgress
        }
        
        isExporting = true
        exportProgress = 0.0
        
        var results: [ExportResult] = []
        var failures: [ExportFailure] = []
        
        let totalItems = batch.items.count
        
        for (index, item) in batch.items.enumerated() {
            do {
                let result = try await exportBatchItem(item)
                results.append(result)
                
                exportProgress = Double(index + 1) / Double(totalItems)
                
            } catch {
                let failure = ExportFailure(
                    item: item,
                    error: error,
                    timestamp: Date()
                )
                failures.append(failure)
                
                logError("Batch export item failed", category: .persistence, error: error)
            }
        }
        
        isExporting = false
        
        let batchResult = BatchExportResult(
            id: UUID(),
            batch: batch,
            successfulExports: results,
            failures: failures,
            completedAt: Date(),
            totalSize: results.reduce(0) { $0 + $1.fileSize }
        )
        
        logInfo("Batch export completed", category: .persistence, context: LogContext(customData: [
            "total_items": totalItems,
            "successful": results.count,
            "failed": failures.count
        ]))
        
        return batchResult
    }
    
    // MARK: - Export Implementation
    
    private func performProjectExport(
        _ project: ProjectMO,
        format: ExportFormat,
        options: ExportOptions
    ) async throws -> ExportResult {
        
        // Validate project for export
        exportProgress = 0.1
        let validationResult = validationManager.validateProjectForExport(project, format: format)
        guard validationResult.isValid else {
            throw ExportError.validationFailed(validationResult.issues)
        }
        
        // Get exporter for format
        guard let exporter = formatExporters[format] else {
            throw ExportError.unsupportedFormat(format)
        }
        
        // Prepare export data
        exportProgress = 0.2
        let exportData = try await prepareProjectExportData(project, options: options)
        
        // Perform export
        exportProgress = 0.4
        let exportedData = try await exporter.export(exportData, options: options) { progress in
            Task { @MainActor in
                self.exportProgress = 0.4 + (progress * 0.4)
            }
        }
        
        // Post-process if needed
        exportProgress = 0.8
        let finalData = try await postProcessExportData(exportedData, format: format, options: options)
        
        // Save to file
        exportProgress = 0.9
        let fileURL = try await saveExportedData(finalData, fileName: generateFileName(for: project, format: format))
        
        exportProgress = 1.0
        
        return ExportResult(
            id: UUID(),
            fileName: fileURL.lastPathComponent,
            filePath: fileURL.path,
            format: format,
            fileSize: try getFileSize(at: fileURL),
            exportedAt: Date(),
            projectId: project.id,
            metadata: ExportMetadata(
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                exportOptions: options,
                validationResult: validationResult
            )
        )
    }
    
    private func performMultipleProjectsExport(
        _ projects: [ProjectMO],
        format: ExportFormat,
        options: ExportOptions
    ) async throws -> ExportResult {
        
        guard let exporter = formatExporters[format] else {
            throw ExportError.unsupportedFormat(format)
        }
        
        // Prepare export data for all projects
        var allExportData: [ProjectExportData] = []
        let projectCount = projects.count
        
        for (index, project) in projects.enumerated() {
            let exportData = try await prepareProjectExportData(project, options: options)
            allExportData.append(exportData)
            
            exportProgress = Double(index + 1) / Double(projectCount) * 0.6
        }
        
        // Combine data for multi-project export
        let combinedData = MultiProjectExportData(
            projects: allExportData,
            exportedAt: Date(),
            totalProjects: projectCount
        )
        
        // Perform export
        exportProgress = 0.7
        let exportedData = try await exporter.exportMultiple(combinedData, options: options) { progress in
            Task { @MainActor in
                self.exportProgress = 0.7 + (progress * 0.2)
            }
        }
        
        // Post-process and save
        exportProgress = 0.9
        let finalData = try await postProcessExportData(exportedData, format: format, options: options)
        let fileName = "ARchitect_Projects_\(DateFormatter.fileNameFormatter.string(from: Date())).\(format.fileExtension)"
        let fileURL = try await saveExportedData(finalData, fileName: fileName)
        
        exportProgress = 1.0
        
        return ExportResult(
            id: UUID(),
            fileName: fileURL.lastPathComponent,
            filePath: fileURL.path,
            format: format,
            fileSize: try getFileSize(at: fileURL),
            exportedAt: Date(),
            projectId: nil,
            metadata: ExportMetadata(
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                exportOptions: options,
                validationResult: ValidationResult(isValid: true, issues: [])
            )
        )
    }
    
    private func performTemplateExport(
        _ template: ProjectTemplate,
        format: ExportFormat,
        options: ExportOptions
    ) async throws -> ExportResult {
        
        guard let exporter = formatExporters[format] else {
            throw ExportError.unsupportedFormat(format)
        }
        
        // Prepare template export data
        exportProgress = 0.2
        let templateExportData = try await prepareTemplateExportData(template, options: options)
        
        // Perform export
        exportProgress = 0.5
        let exportedData = try await exporter.exportTemplate(templateExportData, options: options) { progress in
            Task { @MainActor in
                self.exportProgress = 0.5 + (progress * 0.3)
            }
        }
        
        // Post-process and save
        exportProgress = 0.8
        let finalData = try await postProcessExportData(exportedData, format: format, options: options)
        let fileName = generateTemplateFileName(for: template, format: format)
        let fileURL = try await saveExportedData(finalData, fileName: fileName)
        
        exportProgress = 1.0
        
        return ExportResult(
            id: UUID(),
            fileName: fileURL.lastPathComponent,
            filePath: fileURL.path,
            format: format,
            fileSize: try getFileSize(at: fileURL),
            exportedAt: Date(),
            projectId: nil,
            metadata: nil
        )
    }
    
    private func exportBatchItem(_ item: ExportBatchItem) async throws -> ExportResult {
        switch item.type {
        case .project(let project):
            return try await performProjectExport(project, format: item.format, options: item.options)
        case .template(let template):
            return try await performTemplateExport(template, format: item.format, options: item.options)
        case .multiple(let projects):
            return try await performMultipleProjectsExport(projects, format: item.format, options: item.options)
        }
    }
    
    // MARK: - Data Preparation
    
    private func prepareProjectExportData(
        _ project: ProjectMO,
        options: ExportOptions
    ) async throws -> ProjectExportData {
        
        return try await coreDataStack.executeInBackground { context in
            let backgroundProject = try context.existingObject(with: project.objectID) as! ProjectMO
            
            return ProjectExportData(
                projectInfo: ProjectInfo(
                    id: backgroundProject.id ?? UUID(),
                    name: backgroundProject.name ?? "",
                    description: backgroundProject.projectDescription,
                    createdAt: backgroundProject.createdAt ?? Date(),
                    modifiedAt: backgroundProject.modifiedAt ?? Date(),
                    tags: backgroundProject.tags?.components(separatedBy: ",") ?? []
                ),
                furnitureItems: try self.extractFurnitureItems(from: backgroundProject, options: options),
                roomData: try self.extractRoomData(from: backgroundProject, options: options),
                layoutData: try self.extractLayoutData(from: backgroundProject, options: options),
                metadata: self.createExportMetadata(options: options)
            )
        }
    }
    
    private func prepareTemplateExportData(
        _ template: ProjectTemplate,
        options: ExportOptions
    ) async throws -> TemplateExportData {
        
        return TemplateExportData(
            templateInfo: TemplateInfo(
                id: template.id,
                name: template.name,
                description: template.description,
                category: template.category.rawValue,
                tags: template.tags,
                createdAt: template.createdAt,
                isPublic: template.isPublic,
                rating: template.rating,
                usageCount: template.usageCount
            ),
            templateData: template, // Would extract actual template data
            previewImage: template.previewImage,
            metadata: createExportMetadata(options: options)
        )
    }
    
    private func extractFurnitureItems(from project: ProjectMO, options: ExportOptions) throws -> [FurnitureItemExportData] {
        guard let furnitureItems = project.furnitureItems?.allObjects as? [FurnitureItemMO] else {
            return []
        }
        
        return furnitureItems.map { item in
            FurnitureItemExportData(
                id: item.id ?? UUID(),
                name: item.name ?? "",
                category: item.category ?? "",
                position: [item.positionX, item.positionY, item.positionZ],
                rotation: item.rotation,
                scale: [item.scaleX, item.scaleY, item.scaleZ],
                color: item.color,
                material: item.material,
                metadata: item.metadata
            )
        }
    }
    
    private func extractRoomData(from project: ProjectMO, options: ExportOptions) throws -> RoomExportData? {
        guard let roomData = project.roomData else { return nil }
        
        return RoomExportData(
            id: roomData.id ?? UUID(),
            roomType: roomData.roomType ?? "",
            dimensions: [roomData.width, roomData.height, roomData.depth],
            features: roomData.features?.components(separatedBy: ",") ?? [],
            style: roomData.style
        )
    }
    
    private func extractLayoutData(from project: ProjectMO, options: ExportOptions) throws -> LayoutExportData {
        // Extract layout information
        return LayoutExportData(
            zones: [],
            trafficPaths: [],
            focalPoints: [],
            lightingSources: []
        )
    }
    
    private func createExportMetadata(options: ExportOptions) -> ExportDataMetadata {
        return ExportDataMetadata(
            exportedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            dataVersion: "1.0",
            options: options
        )
    }
    
    // MARK: - Post Processing
    
    private func postProcessExportData(
        _ data: Data,
        format: ExportFormat,
        options: ExportOptions
    ) async throws -> Data {
        
        var processedData = data
        
        // Apply compression if requested
        if options.compression.enabled {
            processedData = try compressionManager.compress(data, level: options.compression.level)
        }
        
        // Apply encryption if requested
        if let encryptionKey = options.encryptionKey {
            processedData = try encryptData(processedData, key: encryptionKey)
        }
        
        return processedData
    }
    
    private func saveExportedData(_ data: Data, fileName: String) async throws -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportsDirectory = documentsDirectory.appendingPathComponent("Exports")
        
        // Create exports directory if needed
        try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
        
        let fileURL = exportsDirectory.appendingPathComponent(fileName)
        try data.write(to: fileURL)
        
        return fileURL
    }
    
    // MARK: - Helper Methods
    
    private func generateFileName(for project: ProjectMO, format: ExportFormat) -> String {
        let projectName = project.name?.sanitizedForFileName ?? "Project"
        let timestamp = DateFormatter.fileNameFormatter.string(from: Date())
        return "\(projectName)_\(timestamp).\(format.fileExtension)"
    }
    
    private func generateTemplateFileName(for template: ProjectTemplate, format: ExportFormat) -> String {
        let templateName = template.name.sanitizedForFileName
        let timestamp = DateFormatter.fileNameFormatter.string(from: Date())
        return "Template_\(templateName)_\(timestamp).\(format.fileExtension)"
    }
    
    private func getFileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    private func encryptData(_ data: Data, key: String) throws -> Data {
        // Implement encryption logic
        return data // Placeholder
    }
    
    // MARK: - Public Interface
    
    public func cancelExport() {
        currentExportTask?.cancel()
        isExporting = false
        exportProgress = 0.0
    }
    
    public func getExportHistory() -> [ExportResult] {
        // Load export history from persistent storage
        return [] // Placeholder
    }
    
    public func cleanupExportFiles(olderThan date: Date) async throws {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportsDirectory = documentsDirectory.appendingPathComponent("Exports")
        
        guard FileManager.default.fileExists(atPath: exportsDirectory.path) else { return }
        
        let files = try FileManager.default.contentsOfDirectory(at: exportsDirectory, includingPropertiesForKeys: [.creationDateKey])
        
        for fileURL in files {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let creationDate = attributes[.creationDate] as? Date,
               creationDate < date {
                try FileManager.default.removeItem(at: fileURL)
            }
        }
    }
    
    public func validateFormat(_ format: ExportFormat, for project: ProjectMO) -> ValidationResult {
        return validationManager.validateProjectForExport(project, format: format)
    }
    
    public func estimateExportSize(_ project: ProjectMO, format: ExportFormat) -> Int64 {
        // Estimate export file size
        let baseSize = (project.furnitureItems?.count ?? 0) * 1024 // 1KB per item estimate
        
        switch format {
        case .json, .xml: return Int64(baseSize * 2)
        case .csv: return Int64(baseSize)
        case .pdf: return Int64(baseSize * 5)
        case .zip: return Int64(baseSize * 3)
        case .usdz, .obj, .collada: return Int64(baseSize * 10)
        case .excel: return Int64(baseSize * 2)
        case .sqlite: return Int64(baseSize * 1.5)
        }
    }
}

// MARK: - Export Data Structures

public struct ExportOptions {
    public let includeImages: Bool
    public let include3DModels: Bool
    public let includeMetadata: Bool
    public let compression: CompressionOptions
    public let encryptionKey: String?
    public let customFields: [String: Any]
    
    public static let `default` = ExportOptions(
        includeImages: true,
        include3DModels: true,
        includeMetadata: true,
        compression: CompressionOptions.none,
        encryptionKey: nil,
        customFields: [:]
    )
    
    public static let minimal = ExportOptions(
        includeImages: false,
        include3DModels: false,
        includeMetadata: false,
        compression: CompressionOptions.high,
        encryptionKey: nil,
        customFields: [:]
    )
}

public struct CompressionOptions {
    public let enabled: Bool
    public let level: CompressionLevel
    
    public static let none = CompressionOptions(enabled: false, level: .none)
    public static let low = CompressionOptions(enabled: true, level: .low)
    public static let medium = CompressionOptions(enabled: true, level: .medium)
    public static let high = CompressionOptions(enabled: true, level: .high)
    
    public enum CompressionLevel {
        case none, low, medium, high
    }
}

public struct ExportResult: Identifiable {
    public let id: UUID
    public let fileName: String
    public let filePath: String
    public let format: ExportManager.ExportFormat
    public let fileSize: Int64
    public let exportedAt: Date
    public let projectId: UUID?
    public let metadata: ExportMetadata?
}

public struct ExportMetadata {
    public let appVersion: String
    public let exportOptions: ExportOptions
    public let validationResult: ValidationResult
}

public struct ExportBatch {
    public let id: UUID
    public let name: String
    public let items: [ExportBatchItem]
    public let createdAt: Date
}

public struct ExportBatchItem {
    public let id: UUID
    public let type: ExportItemType
    public let format: ExportManager.ExportFormat
    public let options: ExportOptions
    
    public enum ExportItemType {
        case project(ProjectMO)
        case template(ProjectTemplate)
        case multiple([ProjectMO])
    }
}

public struct BatchExportResult {
    public let id: UUID
    public let batch: ExportBatch
    public let successfulExports: [ExportResult]
    public let failures: [ExportFailure]
    public let completedAt: Date
    public let totalSize: Int64
}

public struct ExportFailure {
    public let item: ExportBatchItem
    public let error: Error
    public let timestamp: Date
}

// MARK: - Export Data Models

public struct ProjectExportData {
    public let projectInfo: ProjectInfo
    public let furnitureItems: [FurnitureItemExportData]
    public let roomData: RoomExportData?
    public let layoutData: LayoutExportData
    public let metadata: ExportDataMetadata
}

public struct MultiProjectExportData {
    public let projects: [ProjectExportData]
    public let exportedAt: Date
    public let totalProjects: Int
}

public struct TemplateExportData {
    public let templateInfo: TemplateInfo
    public let templateData: ProjectTemplate
    public let previewImage: Data?
    public let metadata: ExportDataMetadata
}

public struct ProjectInfo {
    public let id: UUID
    public let name: String
    public let description: String?
    public let createdAt: Date
    public let modifiedAt: Date
    public let tags: [String]
}

public struct TemplateInfo {
    public let id: UUID
    public let name: String
    public let description: String
    public let category: String
    public let tags: [String]
    public let createdAt: Date
    public let isPublic: Bool
    public let rating: Float
    public let usageCount: Int32
}

public struct FurnitureItemExportData {
    public let id: UUID
    public let name: String
    public let category: String
    public let position: [Float]
    public let rotation: Float
    public let scale: [Float]
    public let color: String?
    public let material: String?
    public let metadata: String?
}

public struct RoomExportData {
    public let id: UUID
    public let roomType: String
    public let dimensions: [Float]
    public let features: [String]
    public let style: String?
}

public struct LayoutExportData {
    public let zones: [LayoutZoneExportData]
    public let trafficPaths: [TrafficPathExportData]
    public let focalPoints: [FocalPointExportData]
    public let lightingSources: [LightingSourceExportData]
}

public struct LayoutZoneExportData {
    public let name: String
    public let purpose: String
    public let bounds: [Float]
    public let furnitureIds: [UUID]
}

public struct TrafficPathExportData {
    public let points: [[Float]]
    public let width: Float
    public let importance: Float
}

public struct FocalPointExportData {
    public let position: [Float]
    public let type: String
    public let radius: Float
}

public struct LightingSourceExportData {
    public let position: [Float]
    public let type: String
    public let intensity: Float
    public let color: [Float]
}

public struct ExportDataMetadata {
    public let exportedAt: Date
    public let appVersion: String
    public let dataVersion: String
    public let options: ExportOptions
}

public enum ExportError: Error {
    case exportInProgress
    case unsupportedFormat(ExportManager.ExportFormat)
    case formatDoesNotSupportMultipleProjects
    case validationFailed([String])
    case fileSystemError(String)
    case compressionFailed(String)
    case encryptionFailed(String)
    case exportTimeout
    
    public var localizedDescription: String {
        switch self {
        case .exportInProgress:
            return "Export is already in progress"
        case .unsupportedFormat(let format):
            return "Export format '\(format.displayName)' is not supported"
        case .formatDoesNotSupportMultipleProjects:
            return "This format does not support multiple projects"
        case .validationFailed(let issues):
            return "Export validation failed: \(issues.joined(separator: ", "))"
        case .fileSystemError(let message):
            return "File system error: \(message)"
        case .compressionFailed(let message):
            return "Compression failed: \(message)"
        case .encryptionFailed(let message):
            return "Encryption failed: \(message)"
        case .exportTimeout:
            return "Export operation timed out"
        }
    }
}

// MARK: - Format Exporters Protocol

protocol FormatExporter {
    func export(_ data: ProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data
    func exportMultiple(_ data: MultiProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data
    func exportTemplate(_ data: TemplateExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data
}

// MARK: - Concrete Exporters

class JSONExporter: FormatExporter {
    func export(_ data: ProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(0.5)
        let jsonData = try JSONEncoder().encode(data)
        progressCallback(1.0)
        return jsonData
    }
    
    func exportMultiple(_ data: MultiProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(0.5)
        let jsonData = try JSONEncoder().encode(data)
        progressCallback(1.0)
        return jsonData
    }
    
    func exportTemplate(_ data: TemplateExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(0.5)
        let jsonData = try JSONEncoder().encode(data)
        progressCallback(1.0)
        return jsonData
    }
}

class XMLExporter: FormatExporter {
    func export(_ data: ProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        // Implementation would convert to XML format
        progressCallback(1.0)
        return Data()
    }
    
    func exportMultiple(_ data: MultiProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
    
    func exportTemplate(_ data: TemplateExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
}

class CSVExporter: FormatExporter {
    func export(_ data: ProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        // Implementation would convert to CSV format
        progressCallback(1.0)
        return Data()
    }
    
    func exportMultiple(_ data: MultiProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
    
    func exportTemplate(_ data: TemplateExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
}

class PDFExporter: FormatExporter {
    func export(_ data: ProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        // Implementation would generate PDF report
        progressCallback(1.0)
        return Data()
    }
    
    func exportMultiple(_ data: MultiProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
    
    func exportTemplate(_ data: TemplateExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
}

class ZipExporter: FormatExporter {
    func export(_ data: ProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        // Implementation would create ZIP archive
        progressCallback(1.0)
        return Data()
    }
    
    func exportMultiple(_ data: MultiProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
    
    func exportTemplate(_ data: TemplateExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
}

class USDZExporter: FormatExporter {
    func export(_ data: ProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        // Implementation would generate USDZ format
        progressCallback(1.0)
        return Data()
    }
    
    func exportMultiple(_ data: MultiProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
    
    func exportTemplate(_ data: TemplateExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
}

class OBJExporter: FormatExporter {
    func export(_ data: ProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        // Implementation would generate OBJ format
        progressCallback(1.0)
        return Data()
    }
    
    func exportMultiple(_ data: MultiProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
    
    func exportTemplate(_ data: TemplateExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
}

class ColladaExporter: FormatExporter {
    func export(_ data: ProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        // Implementation would generate COLLADA format
        progressCallback(1.0)
        return Data()
    }
    
    func exportMultiple(_ data: MultiProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
    
    func exportTemplate(_ data: TemplateExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
}

class ExcelExporter: FormatExporter {
    func export(_ data: ProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        // Implementation would generate Excel format
        progressCallback(1.0)
        return Data()
    }
    
    func exportMultiple(_ data: MultiProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
    
    func exportTemplate(_ data: TemplateExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
}

class SQLiteExporter: FormatExporter {
    func export(_ data: ProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        // Implementation would generate SQLite database
        progressCallback(1.0)
        return Data()
    }
    
    func exportMultiple(_ data: MultiProjectExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
    
    func exportTemplate(_ data: TemplateExportData, options: ExportOptions, progressCallback: @escaping (Double) -> Void) async throws -> Data {
        progressCallback(1.0)
        return Data()
    }
}

// MARK: - Supporting Classes

@MainActor
class CompressionManager {
    func compress(_ data: Data, level: CompressionOptions.CompressionLevel) throws -> Data {
        // Implementation would compress data
        return data
    }
}

@MainActor
class ExportValidationManager {
    func validateProjectForExport(_ project: ProjectMO, format: ExportManager.ExportFormat) -> ValidationResult {
        var issues: [String] = []
        
        // Check if project has required data
        if project.furnitureItems?.count == 0 {
            issues.append("Project has no furniture items")
        }
        
        // Format-specific validations
        if format.supports3D && project.roomData == nil {
            issues.append("3D export requires room data")
        }
        
        return ValidationResult(isValid: issues.isEmpty, issues: issues)
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}

extension String {
    var sanitizedForFileName: String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return self.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
}

// Make export data structures Codable
extension ProjectExportData: Codable {}
extension MultiProjectExportData: Codable {}
extension TemplateExportData: Codable {}
extension ProjectInfo: Codable {}
extension TemplateInfo: Codable {}
extension FurnitureItemExportData: Codable {}
extension RoomExportData: Codable {}
extension LayoutExportData: Codable {}
extension LayoutZoneExportData: Codable {}
extension TrafficPathExportData: Codable {}
extension FocalPointExportData: Codable {}
extension LightingSourceExportData: Codable {}
extension ExportDataMetadata: Codable {}
extension ExportOptions: Codable {}
extension CompressionOptions: Codable {}
extension CompressionOptions.CompressionLevel: Codable {}