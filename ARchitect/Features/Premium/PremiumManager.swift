import Foundation
import StoreKit
import SwiftUI
import Combine

// MARK: - Premium Manager
@MainActor
class PremiumManager: NSObject, ObservableObject {
    static let shared = PremiumManager()
    
    @Published private(set) var subscriptionStatus: SubscriptionStatus = .none
    @Published private(set) var availableProducts: [Product] = []
    @Published private(set) var purchasedProducts: [Product] = []
    @Published private(set) var premiumFeatures: [PremiumFeature] = []
    @Published private(set) var usageStats: PremiumUsageStats = PremiumUsageStats()
    
    private let featureFlags = FeatureFlagManager.shared
    private let analyticsManager = AnalyticsManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Product identifiers
    private let productIdentifiers: Set<String> = [
        "com.architect.premium.monthly",
        "com.architect.premium.annual",
        "com.architect.professional.monthly",
        "com.architect.lifetime"
    ]
    
    private var updateListenerTask: Task<Void, Error>? = nil
    
    override init() {
        super.init()
        setupPremiumFeatures()
        
        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()
        
        Task {
            await loadProducts()
            await refreshSubscriptionStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    func isPremiumUser() -> Bool {
        return subscriptionStatus != .none || featureFlags.isEnabled(.premiumTier)
    }
    
    func hasFeature(_ feature: PremiumFeatureType) -> Bool {
        guard featureFlags.isEnabled(.premiumTier) else { return false }
        
        switch subscriptionStatus {
        case .none:
            return false
        case .basic:
            return feature.isIncludedInBasic
        case .premium:
            return feature.isIncludedInPremium
        case .professional:
            return true // All features included
        case .lifetime:
            return true // All features included
        }
    }
    
    func getRemainingUsage(for feature: PremiumFeatureType) -> Int? {
        guard let limit = feature.usageLimit else { return nil }
        
        let currentUsage = getCurrentUsage(for: feature)
        return max(0, limit - currentUsage)
    }
    
    func trackFeatureUsage(_ feature: PremiumFeatureType) {
        usageStats.incrementUsage(for: feature)
        
        analyticsManager.trackFeatureUsage(.featureDiscovered, parameters: [
            "premium_feature": feature.rawValue,
            "subscription_status": subscriptionStatus.rawValue,
            "usage_count": getCurrentUsage(for: feature)
        ])
    }
    
    func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: productIdentifiers)
            await MainActor.run {
                self.availableProducts = storeProducts
            }
            
            analyticsManager.trackCustomEvent(
                name: "premium_products_loaded",
                parameters: [
                    "product_count": storeProducts.count,
                    "available_products": storeProducts.map { $0.id }
                ]
            )
            
        } catch {
            analyticsManager.trackError(error: error, context: [
                "feature": "premium_products_loading"
            ])
        }
    }
    
    func purchase(_ product: Product) async throws -> Transaction? {
        analyticsManager.trackCustomEvent(
            name: "premium_purchase_initiated",
            parameters: [
                "product_id": product.id,
                "price": product.price.doubleValue,
                "subscription_status": subscriptionStatus.rawValue
            ]
        )
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                await refreshSubscriptionStatus()
                
                analyticsManager.trackCustomEvent(
                    name: "premium_purchase_completed",
                    parameters: [
                        "product_id": product.id,
                        "transaction_id": String(transaction.id)
                    ],
                    severity: .high
                )
                
                return transaction
                
            case .unverified(let transaction, let error):
                analyticsManager.trackError(error: error, context: [
                    "feature": "premium_purchase_verification",
                    "transaction_id": String(transaction.id)
                ])
                throw PremiumError.verificationFailed
            }
            
        case .userCancelled:
            analyticsManager.trackCustomEvent(
                name: "premium_purchase_cancelled",
                parameters: [
                    "product_id": product.id
                ]
            )
            throw PremiumError.userCancelled
            
        case .pending:
            analyticsManager.trackCustomEvent(
                name: "premium_purchase_pending",
                parameters: [
                    "product_id": product.id
                ]
            )
            throw PremiumError.purchasePending
            
        @unknown default:
            throw PremiumError.unknownError
        }
    }
    
    func restorePurchases() async throws {
        try await AppStore.sync()
        await refreshSubscriptionStatus()
        
        analyticsManager.trackCustomEvent(
            name: "premium_purchases_restored",
            parameters: [
                "subscription_status": subscriptionStatus.rawValue
            ]
        )
    }
    
    func refreshSubscriptionStatus() async {
        var currentEntitlements: [Product] = []
        
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if let product = availableProducts.first(where: { $0.id == transaction.productID }) {
                    currentEntitlements.append(product)
                }
            case .unverified:
                continue
            }
        }
        
        await MainActor.run {
            self.purchasedProducts = currentEntitlements
            self.subscriptionStatus = self.determineSubscriptionStatus(from: currentEntitlements)
        }
    }
    
    func showPaywall(for feature: PremiumFeatureType) {
        analyticsManager.trackCustomEvent(
            name: "premium_paywall_shown",
            parameters: [
                "feature": feature.rawValue,
                "subscription_status": subscriptionStatus.rawValue
            ]
        )
    }
    
    // MARK: - Private Methods
    
    private func setupPremiumFeatures() {
        premiumFeatures = [
            PremiumFeature(
                type: .unlimitedProjects,
                title: "Unlimited Projects",
                description: "Save as many room designs as you want",
                icon: "folder.fill",
                tier: .premium
            ),
            PremiumFeature(
                type: .advancedMeasurements,
                title: "Advanced Measurements",
                description: "Professional-grade measurement tools with precision accuracy",
                icon: "ruler.fill",
                tier: .premium
            ),
            PremiumFeature(
                type: .aiLayoutSuggestions,
                title: "AI Layout Suggestions",
                description: "Get intelligent furniture arrangement recommendations",
                icon: "brain.head.profile",
                tier: .premium
            ),
            PremiumFeature(
                type: .cloudSync,
                title: "Cloud Synchronization",
                description: "Sync your projects across all devices",
                icon: "icloud.fill",
                tier: .premium
            ),
            PremiumFeature(
                type: .professionalExport,
                title: "Professional Export",
                description: "Export to CAD, PDF, and other professional formats",
                icon: "square.and.arrow.up.fill",
                tier: .professional
            ),
            PremiumFeature(
                type: .teamCollaboration,
                title: "Team Collaboration",
                description: "Work together with your team on projects",
                icon: "person.2.fill",
                tier: .professional
            ),
            PremiumFeature(
                type: .prioritySupport,
                title: "Priority Support",
                description: "Get faster response times for support requests",
                icon: "headphones",
                tier: .premium
            ),
            PremiumFeature(
                type: .exclusiveFurniture,
                title: "Exclusive Furniture",
                description: "Access to premium furniture collections",
                icon: "sofa.fill",
                tier: .premium
            )
        ]
    }
    
    private func determineSubscriptionStatus(from products: [Product]) -> SubscriptionStatus {
        // Check for lifetime first
        if products.contains(where: { $0.id.contains("lifetime") }) {
            return .lifetime
        }
        
        // Check for professional subscription
        if products.contains(where: { $0.id.contains("professional") }) {
            return .professional
        }
        
        // Check for premium subscription
        if products.contains(where: { $0.id.contains("premium") }) {
            return .premium
        }
        
        return .none
    }
    
    private func getCurrentUsage(for feature: PremiumFeatureType) -> Int {
        return usageStats.getUsage(for: feature)
    }
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    await self.refreshSubscriptionStatus()
                case .unverified:
                    continue
                }
            }
        }
    }
}

// MARK: - Data Models

enum SubscriptionStatus: String, Codable {
    case none = "none"
    case basic = "basic"
    case premium = "premium"
    case professional = "professional"
    case lifetime = "lifetime"
    
    var displayName: String {
        switch self {
        case .none: return "Free"
        case .basic: return "Basic"
        case .premium: return "Premium"
        case .professional: return "Professional"
        case .lifetime: return "Lifetime"
        }
    }
    
    var color: Color {
        switch self {
        case .none: return .gray
        case .basic: return .blue
        case .premium: return .purple
        case .professional: return .gold
        case .lifetime: return .green
        }
    }
}

enum PremiumFeatureType: String, CaseIterable {
    case unlimitedProjects = "unlimited_projects"
    case advancedMeasurements = "advanced_measurements"
    case aiLayoutSuggestions = "ai_layout_suggestions"
    case cloudSync = "cloud_sync"
    case professionalExport = "professional_export"
    case teamCollaboration = "team_collaboration"
    case prioritySupport = "priority_support"
    case exclusiveFurniture = "exclusive_furniture"
    
    var isIncludedInBasic: Bool {
        switch self {
        case .unlimitedProjects, .prioritySupport:
            return true
        default:
            return false
        }
    }
    
    var isIncludedInPremium: Bool {
        switch self {
        case .teamCollaboration, .professionalExport:
            return false
        default:
            return true
        }
    }
    
    var usageLimit: Int? {
        switch self {
        case .unlimitedProjects:
            return nil // Truly unlimited for premium users
        case .advancedMeasurements:
            return 50 // 50 advanced measurements per month
        case .aiLayoutSuggestions:
            return 20 // 20 AI suggestions per month
        case .professionalExport:
            return 10 // 10 exports per month
        default:
            return nil
        }
    }
}

struct PremiumFeature: Identifiable {
    let id = UUID()
    let type: PremiumFeatureType
    let title: String
    let description: String
    let icon: String
    let tier: SubscriptionTier
}

enum SubscriptionTier {
    case premium
    case professional
}

struct PremiumUsageStats {
    private var usage: [String: Int] = [:]
    private let resetDate: Date = Calendar.current.startOfDay(for: Date())
    
    mutating func incrementUsage(for feature: PremiumFeatureType) {
        let key = feature.rawValue
        usage[key, default: 0] += 1
    }
    
    func getUsage(for feature: PremiumFeatureType) -> Int {
        return usage[feature.rawValue, default: 0]
    }
    
    mutating func resetUsage() {
        usage.removeAll()
    }
}

enum PremiumError: Error, LocalizedError {
    case userCancelled
    case purchasePending
    case verificationFailed
    case networkError
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Purchase was cancelled"
        case .purchasePending:
            return "Purchase is pending approval"
        case .verificationFailed:
            return "Could not verify purchase"
        case .networkError:
            return "Network connection error"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}

// MARK: - Extensions

extension Color {
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.0)
}

// MARK: - Premium Views

struct PremiumFeatureCard: View {
    let feature: PremiumFeature
    let isEnabled: Bool
    let remainingUsage: Int?
    
    var body: some View {
        HStack {
            Image(systemName: feature.icon)
                .foregroundColor(isEnabled ? .blue : .gray)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.headline)
                    .foregroundColor(isEnabled ? .primary : .secondary)
                
                Text(feature.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let remaining = remainingUsage {
                    Text("\(remaining) remaining this month")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            if !isEnabled {
                Image(systemName: "lock.fill")
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct SubscriptionCard: View {
    let product: Product
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                Text(product.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(product.displayPrice)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                
                if product.id.contains("annual") {
                    Text("Save 33%")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(12)
                }
                
                Text(product.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color(.systemGray4), lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PremiumPaywall: View {
    @StateObject private var premiumManager = PremiumManager.shared
    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    let feature: PremiumFeatureType?
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gold)
                        
                        Text("Unlock Premium Features")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        if let feature = feature {
                            Text("Upgrade to access \(feature.rawValue.replacingOccurrences(of: "_", with: " "))")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top)
                    
                    // Features
                    LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                        ForEach(premiumManager.premiumFeatures) { premiumFeature in
                            PremiumFeatureCard(
                                feature: premiumFeature,
                                isEnabled: false,
                                remainingUsage: nil
                            )
                        }
                    }
                    
                    // Subscription Options
                    VStack(spacing: 16) {
                        Text("Choose Your Plan")
                            .font(.headline)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(premiumManager.availableProducts, id: \.id) { product in
                                SubscriptionCard(
                                    product: product,
                                    isSelected: selectedProduct?.id == product.id,
                                    onSelect: {
                                        selectedProduct = product
                                    }
                                )
                            }
                        }
                    }
                    
                    // Purchase Button
                    if let selectedProduct = selectedProduct {
                        Button(action: {
                            purchaseProduct(selectedProduct)
                        }) {
                            HStack {
                                if isPurchasing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Subscribe for \(selectedProduct.displayPrice)")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isPurchasing)
                    }
                    
                    // Restore Purchases
                    Button("Restore Purchases") {
                        restorePurchases()
                    }
                    .foregroundColor(.blue)
                    
                    // Terms and Privacy
                    HStack {
                        Link("Terms of Service", destination: URL(string: "https://example.com/terms")!)
                        Text("•")
                        Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Cancel", action: onDismiss)
            )
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .task {
            await premiumManager.loadProducts()
            if let firstProduct = premiumManager.availableProducts.first {
                selectedProduct = firstProduct
            }
        }
    }
    
    private func purchaseProduct(_ product: Product) {
        Task {
            isPurchasing = true
            defer { isPurchasing = false }
            
            do {
                _ = try await premiumManager.purchase(product)
                onDismiss()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func restorePurchases() {
        Task {
            do {
                try await premiumManager.restorePurchases()
                if premiumManager.isPremiumUser() {
                    onDismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}