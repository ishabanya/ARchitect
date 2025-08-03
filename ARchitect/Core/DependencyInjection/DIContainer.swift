import Foundation

/// Dependency injection container for managing app dependencies
@MainActor
final class DIContainer {
    static let shared = DIContainer()
    
    private var services: [String: Any] = [:]
    private var factories: [String: () -> Any] = [:]
    
    private init() {
        registerDefaultServices()
    }
    
    // MARK: - Registration
    
    /// Register a singleton service instance
    func register<T>(_ type: T.Type, instance: T) {
        let key = String(describing: type)
        services[key] = instance
    }
    
    /// Register a factory for creating service instances
    func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        let key = String(describing: type)
        factories[key] = factory
    }
    
    /// Register a singleton service with lazy initialization
    func registerSingleton<T>(_ type: T.Type, factory: @escaping () -> T) {
        let key = String(describing: type)
        factories[key] = {
            if let existing = self.services[key] as? T {
                return existing
            }
            let instance = factory()
            self.services[key] = instance
            return instance
        }
    }
    
    // MARK: - Resolution
    
    /// Resolve a service instance
    func resolve<T>(_ type: T.Type) -> T {
        let key = String(describing: type)
        
        // Check for existing instance
        if let instance = services[key] as? T {
            return instance
        }
        
        // Check for factory
        if let factory = factories[key] {
            if let instance = factory() as? T {
                return instance
            }
        }
        
        fatalError("Unable to resolve \(type). Make sure it's registered in the DI container.")
    }
    
    /// Try to resolve a service instance (returns nil if not found)
    func tryResolve<T>(_ type: T.Type) -> T? {
        let key = String(describing: type)
        
        // Check for existing instance
        if let instance = services[key] as? T {
            return instance
        }
        
        // Check for factory
        if let factory = factories[key] {
            return factory() as? T
        }
        
        return nil
    }
    
    // MARK: - Cleanup
    
    /// Remove a service from the container
    func unregister<T>(_ type: T.Type) {
        let key = String(describing: type)
        services.removeValue(forKey: key)
        factories.removeValue(forKey: key)
    }
    
    /// Clear all services (useful for testing)
    func reset() {
        services.removeAll()
        factories.removeAll()
        registerDefaultServices()
    }
    
    // MARK: - Default Services
    
    private func registerDefaultServices() {
        // Register singleton services
        registerSingleton(ARSessionManagerProtocol.self) {
            ARSessionManager()
        }
        
        registerSingleton(AnalyticsManagerProtocol.self) {
            AnalyticsManagerImpl()
        }
        
        registerSingleton(ErrorManagerProtocol.self) {
            ErrorManagerImpl()
        }
        
        registerSingleton(LoggingSystemProtocol.self) {
            LoggingSystemImpl()
        }
        
        // Register factory-based services
        register(ContentViewModel.self) {
            ContentViewModel(
                arSessionManager: DIContainer.shared.resolve(ARSessionManagerProtocol.self),
                analyticsManager: DIContainer.shared.resolve(AnalyticsManagerProtocol.self),
                errorManager: DIContainer.shared.resolve(ErrorManagerProtocol.self),
                loggingSystem: DIContainer.shared.resolve(LoggingSystemProtocol.self)
            )
        }
    }
}

// MARK: - Property Wrapper for Dependency Injection

@propertyWrapper
struct Injected<T> {
    private let keyPath: KeyPath<DIContainer, T>?
    private let container: DIContainer
    
    var wrappedValue: T {
        if let keyPath = keyPath {
            return container[keyPath: keyPath]
        }
        return container.resolve(T.self)
    }
    
    init() {
        self.keyPath = nil
        self.container = DIContainer.shared
    }
    
    init(_ keyPath: KeyPath<DIContainer, T>) {
        self.keyPath = keyPath
        self.container = DIContainer.shared
    }
}

// MARK: - Convenience Extensions

extension DIContainer {
    /// Register a service that conforms to both a protocol and concrete type
    func register<Protocol, Concrete: Protocol>(_ protocolType: Protocol.Type, concreteType: Concrete.Type, factory: @escaping () -> Concrete) {
        register(protocolType, factory: factory)
        register(concreteType, factory: factory)
    }
    
    /// Register a singleton service that conforms to both a protocol and concrete type
    func registerSingleton<Protocol, Concrete: Protocol>(_ protocolType: Protocol.Type, concreteType: Concrete.Type, factory: @escaping () -> Concrete) {
        registerSingleton(protocolType, factory: factory)
        registerSingleton(concreteType, factory: factory)
    }
}