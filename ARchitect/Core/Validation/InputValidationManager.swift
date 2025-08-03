import Foundation
import UIKit

// MARK: - Input Validation Manager
@MainActor
public class InputValidationManager: ObservableObject {
    public static let shared = InputValidationManager()
    
    @Published public var validationErrors: [ValidationError] = []
    @Published public var isValidating: Bool = false
    
    private let errorManager = ErrorManager.shared
    private var validationQueue = DispatchQueue(label: "validation.queue", qos: .userInitiated)
    
    private init() {}
    
    // MARK: - Validation Results
    public struct ValidationResult {
        public let isValid: Bool
        public let errors: [ValidationError]
        public let warnings: [ValidationWarning]
        
        public static let valid = ValidationResult(isValid: true, errors: [], warnings: [])
        
        public init(isValid: Bool, errors: [ValidationError] = [], warnings: [ValidationWarning] = []) {
            self.isValid = isValid
            self.errors = errors
            self.warnings = warnings
        }
    }
    
    // MARK: - Text Input Validation
    public func validateText(_ text: String, for field: TextFieldType, rules: [ValidationRule] = []) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        let allRules = defaultRules(for: field) + rules
        
        for rule in allRules {
            switch rule.validate(text) {
            case .valid:
                continue
            case .invalid(let error):
                errors.append(error)
            case .warning(let warning):
                warnings.append(warning)
            }
        }
        
        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
    
    public func validateEmail(_ email: String) -> ValidationResult {
        return validateText(email, for: .email, rules: [
            LengthRule(min: 5, max: 254),
            EmailFormatRule(),
            DisposableEmailRule()
        ])
    }
    
    public func validatePassword(_ password: String) -> ValidationResult {
        return validateText(password, for: .password, rules: [
            LengthRule(min: 8, max: 128),
            PasswordStrengthRule(),
            CommonPasswordRule(),
            PasswordCharacterRule()
        ])
    }
    
    public func validatePhoneNumber(_ phone: String) -> ValidationResult {
        return validateText(phone, for: .phoneNumber, rules: [
            PhoneFormatRule(),
            CountryCodeRule()
        ])
    }
    
    public func validateURL(_ url: String) -> ValidationResult {
        return validateText(url, for: .url, rules: [
            URLFormatRule(),
            URLSecurityRule()
        ])
    }
    
    // MARK: - Numeric Input Validation
    public func validateInteger(_ value: String, min: Int? = nil, max: Int? = nil) -> ValidationResult {
        guard let intValue = Int(value) else {
            return ValidationResult(isValid: false, errors: [.invalidFormat("Must be a valid integer")])
        }
        
        var errors: [ValidationError] = []
        
        if let min = min, intValue < min {
            errors.append(.outOfRange("Value must be at least \(min)"))
        }
        
        if let max = max, intValue > max {
            errors.append(.outOfRange("Value must be no more than \(max)"))
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors)
    }
    
    public func validateDouble(_ value: String, min: Double? = nil, max: Double? = nil) -> ValidationResult {
        guard let doubleValue = Double(value) else {
            return ValidationResult(isValid: false, errors: [.invalidFormat("Must be a valid number")])
        }
        
        var errors: [ValidationError] = []
        
        if let min = min, doubleValue < min {
            errors.append(.outOfRange("Value must be at least \(min)"))
        }
        
        if let max = max, doubleValue > max {
            errors.append(.outOfRange("Value must be no more than \(max)"))
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors)
    }
    
    // MARK: - Room Measurement Validation
    public func validateMeasurement(_ measurement: Double, unit: String = "meters") -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        // Basic range checks for room measurements
        if measurement <= 0 {
            errors.append(.invalidValue("Measurement must be positive"))
        } else if measurement < 0.1 {
            warnings.append(.suspiciousValue("Very small measurement detected"))
        } else if measurement > 100 {
            warnings.append(.suspiciousValue("Very large measurement detected"))
        }
        
        // Check for reasonable precision
        let decimalPlaces = countDecimalPlaces(measurement)
        if decimalPlaces > 3 {
            warnings.append(.precisionWarning("Measurement precision may be excessive"))
        }
        
        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
    
    // MARK: - AR Data Validation
    public func validateARTransform(_ transform: simd_float4x4) -> ValidationResult {
        var errors: [ValidationError] = []
        
        // Check for invalid transformations
        if !isValidTransformMatrix(transform) {
            errors.append(.invalidValue("Invalid transformation matrix"))
        }
        
        // Check for extreme translations
        let translation = transform.columns.3
        let distance = sqrt(translation.x * translation.x + translation.y * translation.y + translation.z * translation.z)
        
        if distance > 1000 { // 1km limit
            errors.append(.outOfRange("Object position too far from origin"))
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors)
    }
    
    public func validateARPlane(center: simd_float3, extent: simd_float3) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        // Check for reasonable plane sizes
        let area = extent.x * extent.z
        if area < 0.01 { // 10cm²
            warnings.append(.suspiciousValue("Very small plane detected"))
        } else if area > 10000 { // 10,000m²
            warnings.append(.suspiciousValue("Extremely large plane detected"))
        }
        
        // Check for reasonable height (Y position)
        if abs(center.y) > 10 { // 10 meters
            warnings.append(.suspiciousValue("Plane at unusual height"))
        }
        
        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
    
    // MARK: - File Input Validation
    public func validateFileUpload(_ data: Data, allowedTypes: [String], maxSize: Int) -> ValidationResult {
        var errors: [ValidationError] = []
        
        // Size validation
        if data.count > maxSize {
            errors.append(.fileTooLarge("File size exceeds \(formatBytes(maxSize)) limit"))
        }
        
        if data.isEmpty {
            errors.append(.invalidValue("File is empty"))
        }
        
        // Basic file type validation (would need more sophisticated detection in practice)
        if !allowedTypes.isEmpty {
            let isValidType = validateFileType(data, allowedTypes: allowedTypes)
            if !isValidType {
                errors.append(.unsupportedFileType("File type not supported"))
            }
        }
        
        // Security scan
        if containsSuspiciousContent(data) {
            errors.append(.securityThreat("File contains suspicious content"))
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors)
    }
    
    // MARK: - Batch Validation
    public func validateForm(_ fields: [String: String], rules: [String: [ValidationRule]]) async -> ValidationResult {
        isValidating = true
        defer { isValidating = false }
        
        return await withTaskGroup(of: (String, ValidationResult).self) { group in
            for (fieldName, fieldValue) in fields {
                group.addTask {
                    let fieldRules = rules[fieldName] ?? []
                    let result = self.validateText(fieldValue, for: .generic, rules: fieldRules)
                    return (fieldName, result)
                }
            }
            
            var allErrors: [ValidationError] = []
            var allWarnings: [ValidationWarning] = []
            var isFormValid = true
            
            for await (_, result) in group {
                if !result.isValid {
                    isFormValid = false
                }
                allErrors.append(contentsOf: result.errors)
                allWarnings.append(contentsOf: result.warnings)
            }
            
            return ValidationResult(
                isValid: isFormValid,
                errors: allErrors,
                warnings: allWarnings
            )
        }
    }
    
    // MARK: - Sanitization
    public func sanitizeInput(_ input: String, for context: SanitizationContext) -> String {
        switch context {
        case .html:
            return sanitizeHTML(input)
        case .sql:
            return sanitizeSQL(input)
        case .fileName:
            return sanitizeFileName(input)
        case .userInput:
            return sanitizeUserInput(input)
        }
    }
    
    // MARK: - Real-time Validation
    public func enableRealTimeValidation(for textField: UITextField, type: TextFieldType) {
        textField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        textField.tag = type.rawValue
    }
    
    @objc private func textFieldDidChange(_ textField: UITextField) {
        guard let type = TextFieldType(rawValue: textField.tag),
              let text = textField.text else { return }
        
        let result = validateText(text, for: type)
        
        // Update UI based on validation result
        if result.isValid {
            textField.layer.borderColor = UIColor.systemGreen.cgColor
            textField.layer.borderWidth = 1.0
        } else {
            textField.layer.borderColor = UIColor.systemRed.cgColor
            textField.layer.borderWidth = 2.0
        }
        
        // Store validation errors for later use
        validationErrors = result.errors
    }
    
    // MARK: - Helper Methods
    private func defaultRules(for field: TextFieldType) -> [ValidationRule] {
        switch field {
        case .email:
            return [RequiredRule(), EmailFormatRule()]
        case .password:
            return [RequiredRule(), LengthRule(min: 8, max: 128)]
        case .phoneNumber:
            return [RequiredRule(), PhoneFormatRule()]
        case .url:
            return [URLFormatRule()]
        case .generic:
            return [RequiredRule()]
        }
    }
    
    private func isValidTransformMatrix(_ matrix: simd_float4x4) -> Bool {
        // Check for NaN or infinite values
        for column in 0..<4 {
            for row in 0..<4 {
                let value = matrix[column][row]
                if value.isNaN || value.isInfinite {
                    return false
                }
            }
        }
        
        // Check if it's a valid transformation matrix (determinant != 0)
        let det = simd_determinant(matrix)
        return !det.isZero && !det.isNaN && !det.isInfinite
    }
    
    private func countDecimalPlaces(_ number: Double) -> Int {
        let string = String(number)
        if let dotIndex = string.firstIndex(of: ".") {
            return string.distance(from: string.index(after: dotIndex), to: string.endIndex)
        }
        return 0
    }
    
    private func validateFileType(_ data: Data, allowedTypes: [String]) -> Bool {
        // Basic file signature validation
        if data.count < 4 { return false }
        
        let bytes = data.prefix(4)
        let signature = bytes.map { String(format: "%02x", $0) }.joined()
        
        for type in allowedTypes {
            switch type.lowercased() {
            case "png":
                if signature.hasPrefix("89504e47") { return true }
            case "jpg", "jpeg":
                if signature.hasPrefix("ffd8ff") { return true }
            case "pdf":
                if signature.hasPrefix("25504446") { return true }
            case "usdz":
                if signature.hasPrefix("504b0304") { return true } // ZIP-based
            default:
                continue
            }
        }
        
        return false
    }
    
    private func containsSuspiciousContent(_ data: Data) -> Bool {
        // Basic security check for suspicious patterns
        let suspiciousPatterns = [
            "javascript:",
            "<script",
            "data:text/html",
            "vbscript:",
            "onload=",
            "onerror="
        ]
        
        let dataString = String(data: data, encoding: .utf8) ?? ""
        return suspiciousPatterns.contains { dataString.lowercased().contains($0) }
    }
    
    private func sanitizeHTML(_ input: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(.punctuationCharacters)
        
        return String(input.unicodeScalars.filter { allowedCharacters.contains($0) })
    }
    
    private func sanitizeSQL(_ input: String) -> String {
        return input
            .replacingOccurrences(of: "'", with: "''")
            .replacingOccurrences(of: ";", with: "")
            .replacingOccurrences(of: "--", with: "")
            .replacingOccurrences(of: "/*", with: "")
            .replacingOccurrences(of: "*/", with: "")
    }
    
    private func sanitizeFileName(_ input: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "<>:\"/\\|?*")
        return String(input.unicodeScalars.filter { !invalidChars.contains($0) })
    }
    
    private func sanitizeUserInput(_ input: String) -> String {
        return input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\0", with: "")
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Supporting Types
public enum TextFieldType: Int, CaseIterable {
    case email = 1
    case password = 2
    case phoneNumber = 3
    case url = 4
    case generic = 5
}

public enum SanitizationContext {
    case html
    case sql
    case fileName
    case userInput
}

public enum ValidationError: Error, LocalizedError {
    case required(String)
    case invalidFormat(String)
    case invalidValue(String)
    case outOfRange(String)
    case tooShort(String)
    case tooLong(String)
    case fileTooLarge(String)
    case unsupportedFileType(String)
    case securityThreat(String)
    
    public var errorDescription: String? {
        switch self {
        case .required(let message),
             .invalidFormat(let message),
             .invalidValue(let message),
             .outOfRange(let message),
             .tooShort(let message),
             .tooLong(let message),
             .fileTooLarge(let message),
             .unsupportedFileType(let message),
             .securityThreat(let message):
            return message
        }
    }
}

public enum ValidationWarning {
    case suspiciousValue(String)
    case precisionWarning(String)
    case performanceWarning(String)
    
    public var message: String {
        switch self {
        case .suspiciousValue(let message),
             .precisionWarning(let message),
             .performanceWarning(let message):
            return message
        }
    }
}

// MARK: - Validation Rules
public protocol ValidationRule {
    func validate(_ input: String) -> ValidationRuleResult
}

public enum ValidationRuleResult {
    case valid
    case invalid(ValidationError)
    case warning(ValidationWarning)
}

public struct RequiredRule: ValidationRule {
    public func validate(_ input: String) -> ValidationRuleResult {
        return input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .invalid(.required("This field is required"))
            : .valid
    }
}

public struct LengthRule: ValidationRule {
    let min: Int
    let max: Int
    
    public init(min: Int = 0, max: Int = Int.max) {
        self.min = min
        self.max = max
    }
    
    public func validate(_ input: String) -> ValidationRuleResult {
        let length = input.count
        
        if length < min {
            return .invalid(.tooShort("Must be at least \(min) characters"))
        } else if length > max {
            return .invalid(.tooLong("Must be no more than \(max) characters"))
        }
        
        return .valid
    }
}

public struct EmailFormatRule: ValidationRule {
    public func validate(_ input: String) -> ValidationRuleResult {
        let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        
        return emailPredicate.evaluate(with: input)
            ? .valid
            : .invalid(.invalidFormat("Invalid email format"))
    }
}

public struct PhoneFormatRule: ValidationRule {
    public func validate(_ input: String) -> ValidationRuleResult {
        let phoneRegex = "^[+]?[0-9\\s\\-\\(\\)]{10,}$"
        let phonePredicate = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        
        return phonePredicate.evaluate(with: input)
            ? .valid
            : .invalid(.invalidFormat("Invalid phone number format"))
    }
}

public struct URLFormatRule: ValidationRule {
    public func validate(_ input: String) -> ValidationRuleResult {
        guard let url = URL(string: input),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            return .invalid(.invalidFormat("Invalid URL format"))
        }
        
        return .valid
    }
}

public struct PasswordStrengthRule: ValidationRule {
    public func validate(_ input: String) -> ValidationRuleResult {
        let hasLower = input.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasUpper = input.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasDigit = input.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSpecial = input.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()")) != nil
        
        let strength = [hasLower, hasUpper, hasDigit, hasSpecial].filter { $0 }.count
        
        if strength < 3 {
            return .invalid(.invalidValue("Password must contain uppercase, lowercase, numbers, and special characters"))
        } else if strength == 3 {
            return .warning(.suspiciousValue("Consider adding more character types for better security"))
        }
        
        return .valid
    }
}

public struct CommonPasswordRule: ValidationRule {
    private let commonPasswords = [
        "password", "123456", "password123", "admin", "qwerty",
        "letmein", "welcome", "monkey", "dragon", "master"
    ]
    
    public func validate(_ input: String) -> ValidationRuleResult {
        return commonPasswords.contains(input.lowercased())
            ? .invalid(.invalidValue("This password is too common"))
            : .valid
    }
}

public struct PasswordCharacterRule: ValidationRule {
    public func validate(_ input: String) -> ValidationRuleResult {
        let consecutiveChars = hasConsecutiveCharacters(input)
        let repeatedChars = hasRepeatedCharacters(input)
        
        if consecutiveChars {
            return .warning(.suspiciousValue("Avoid consecutive characters"))
        } else if repeatedChars {
            return .warning(.suspiciousValue("Avoid repeated characters"))
        }
        
        return .valid
    }
    
    private func hasConsecutiveCharacters(_ input: String) -> Bool {
        let chars = Array(input.lowercased())
        for i in 0..<(chars.count - 2) {
            let ascii1 = chars[i].asciiValue ?? 0
            let ascii2 = chars[i + 1].asciiValue ?? 0
            let ascii3 = chars[i + 2].asciiValue ?? 0
            
            if ascii2 == ascii1 + 1 && ascii3 == ascii2 + 1 {
                return true
            }
        }
        return false
    }
    
    private func hasRepeatedCharacters(_ input: String) -> Bool {
        let chars = Array(input)
        for i in 0..<(chars.count - 2) {
            if chars[i] == chars[i + 1] && chars[i + 1] == chars[i + 2] {
                return true
            }
        }
        return false
    }
}

public struct DisposableEmailRule: ValidationRule {
    private let disposableDomains = [
        "10minutemail.com", "guerrillamail.com", "mailinator.com",
        "tempmail.org", "throwaway.email"
    ]
    
    public func validate(_ input: String) -> ValidationRuleResult {
        let domain = input.components(separatedBy: "@").last?.lowercased() ?? ""
        
        return disposableDomains.contains(domain)
            ? .warning(.suspiciousValue("Disposable email address detected"))
            : .valid
    }
}

public struct CountryCodeRule: ValidationRule {
    public func validate(_ input: String) -> ValidationRuleResult {
        if input.hasPrefix("+") && input.count > 3 {
            return .valid
        } else if input.count >= 10 {
            return .warning(.suspiciousValue("Consider including country code"))
        }
        
        return .valid
    }
}

public struct URLSecurityRule: ValidationRule {
    private let suspiciousDomains = [
        "bit.ly", "tinyurl.com", "t.co", "short.link"
    ]
    
    public func validate(_ input: String) -> ValidationRuleResult {
        guard let url = URL(string: input),
              let host = url.host?.lowercased() else {
            return .valid
        }
        
        return suspiciousDomains.contains(host)
            ? .warning(.suspiciousValue("Shortened URL detected - verify destination"))
            : .valid
    }
}