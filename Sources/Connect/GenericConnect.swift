///
///  GenericConnect.swift
///
///  Copyright 2013 Tony Stone
///
///  Licensed under the Apache License, Version 2.0 (the "License");
///  you may not use this file except in compliance with the License.
///  You may obtain a copy of the License at
///
///  http://www.apache.org/licenses/LICENSE-2.0
///
///  Unless required by applicable law or agreed to in writing, software
///  distributed under the License is distributed on an "AS IS" BASIS,
///  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
///  See the License for the specific language governing permissions and
///  limitations under the License.
///
///  Created by Tony Stone on 3/26/13.
///  Rewritten by Tony Stone on 1/28/17.
///
import CoreData
import TraceLog
import UIKit

///
/// Constants
///
fileprivate struct Default {

    struct Queue {
        ///
        /// Prefix used for all queues
        ///
        static let prefix: String = "connect.queue"
    }

    struct ActionQueue {
        ///
        /// Qos for `ActionQueue`s within the system.
        ///
        static let qos: DispatchQoS = .utility

        ///
        /// The startup state of the queues
        ///
        static let suspended: Bool = true
    }
}

public class GenericConnect<Strategy: ContextStrategyType>: Connect {

    ///
    /// Internal types defining the MetaCache and DataCache CoreDataStack types
    ///
    fileprivate typealias DataCacheType = GenericPersistentContainer<Strategy>
    fileprivate typealias MetaCacheType = GenericPersistentContainer<ContextStrategy.DirectIndependent>

    ///
    /// The name of this instance of `Connect`
    ///
    public let name: String

    ///
    /// Returns the `NSPersistentStoreCoordinate` instance that
    /// this `Connect` instance contains. 
    ///
    public var persistentStoreCoordinator: NSPersistentStoreCoordinator {
        return self.dataCache.persistentStoreCoordinator
    }

    ///
    /// The persistent store configurations used to create the persistent stores referenced by this instance.
    ///
    public var configuration: Configuration

    public var storeConfigurations: [StoreConfiguration] {
        get {
            return configuration.storeConfigurations
        }
        set {
            configuration.storeConfigurations = newValue
        }
    }

    ///
    /// Stack used to manage meta data about the main cache
    ///
    fileprivate let metaCache: MetaCacheType

    ///
    /// Main user cache container
    ///
    fileprivate let dataCache: DataCacheType

    ///
    /// Notification service used by action containers and other services that post notifications.
    ///
    fileprivate let notificationService: NotificationService

    ///
    /// The internal write ahead log for logging transactions
    ///
    fileprivate var writeAheadLog: WriteAheadLog?

    ///
    /// Generic queue used for executing `GenericAction` types.
    ///
    fileprivate var genericQueue: ActionQueue

    ///
    /// Isolation queues used for executing `EntityAction` types.
    ///
    fileprivate var entityQueues: [String: ActionQueue]

    ///
    /// Background synchronization queue for synchronizing
    /// operations on `Connect`.
    ///
    fileprivate let synchronizationQueue: DispatchQueue

    ///
    /// Was this instance already started?
    ///
    fileprivate var started: Bool

    ///
    /// Initializes the receiver with the given name.
    ///
    /// By default, the provided `name` value is used to name the persistent store and is used to look up the name of the `NSManagedObjectModel` object to be used with the `GenericPersistentContainer` object.
    ///
    /// - Parameters:
    ///     - name: The name of the model file in the bundle. The model will be located based on the name given.
    ///
    /// - Returns: A Connect instance initialized with the given name.
    ///
    public convenience init(name: String) {

        let url = abortIfNil(message: "Could not locate model `\(name)` in any bundle.") {
            return Bundle.url(forManagedObjectModelName: name)
        }

        let model = abortIfNil(message: "Failed to load model at \(url).") {
            return NSManagedObjectModel(contentsOf: url)
        }
        self.init(name: name, managedObjectModel: model)
    }

    ///
    /// Initializes the receiver with the given name and a managed object model.
    ///
    /// - Note: By default, the provided `name` value is used as the name of the persistent store associated with the instance. Passing in the `NSManagedObjectModel` object overrides the lookup of the model by the provided name value.
    ///
    /// - Parameters:
    ///     - name: The name of the model file in the bundle.
    ///     - managedObjectModel: A managed object model.
    ///
    /// - Returns: A Connect instance initialized with the given name and model.
    ///
    public required init(name: String, managedObjectModel model: NSManagedObjectModel) {

        self.name = name
        self.configuration = Configuration()
        
        self.dataCache = DataCacheType(name: name,                managedObjectModel: model,       logTag: Log.tag)
        self.metaCache = MetaCacheType(name: "\(name)._metadata", managedObjectModel: MetaModel(), logTag: Log.tag)

        self.notificationService = NotificationService()

        self.genericQueue = ActionQueue(label: "\(Default.Queue.prefix).generic", qos: Default.ActionQueue.qos, concurrencyMode: .concurrent, suspended: Default.ActionQueue.suspended)
        self.entityQueues = [:]
        ///
        /// Serial queue with background priority
        ///
        self.synchronizationQueue = DispatchQueue(label: "\(Default.Queue.prefix).synchronization", qos: .userInitiated)

        self.started = false

        ///
        /// Note: due to Swift requirement for not passing self until all instance
        ///       variables have a value, this has to be set here and not in the 
        ///       init method of the NotificationService.
        ///
        self.notificationService.source = self
    }

    deinit {
        self.unregisterForNotifications()
    }

    func registerForNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleProtectedDataDidBecomeAvailable(notification:)),     name: Foundation.Notification.Name.UIApplicationProtectedDataDidBecomeAvailable, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleProtectedDataWillBecomeUnavailable(notification:)),  name: Foundation.Notification.Name.UIApplicationProtectedDataWillBecomeUnavailable, object: nil)
    }

    func unregisterForNotifications() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc dynamic func handleProtectedDataDidBecomeAvailable(notification: NSNotification) {

        self.synchronizationQueue.async {
            logInfo(Log.tag) { "Protected data is now available." }

            self._suspended = false
        }
    }

    @objc dynamic func handleProtectedDataWillBecomeUnavailable(notification: NSNotification) {

        self.synchronizationQueue.async {
            logInfo(Log.tag) { "Protected data will become unavailable." }

            self._suspended = true
        }
    }
}

///
/// Context access methods
///
extension GenericConnect {

    ///
    /// The main context.
    ///
    /// This context should be used for read operations only.  Use it for all fetches and NSFetchedResultsControllers.
    ///
    /// It will be maintained automatically and be kept consistent.
    ///
    public var viewContext: NSManagedObjectContext {
        return self.dataCache.viewContext
    }

    ///
    /// Gets a new NSManagedObjectContext that can be used for updating objects.
    ///
    /// At save time, Connect will merge those changes back to the ViewContextType.
    ///
    public func newBackgroundContext() -> BackgroundContext {
        return self.newBackgroundContext(logged: true)
    }

    ///
    /// Gets a new NSManagedObjectContext that can be used for updating objects with the option to log changes into the write ahead log.
    ///
    /// At save time, Connect will merge those changes back to the ViewContextType.
    ///
    /// - Parameter logged: Enable/disable transaction logging to the write ahead log when context.save is called.
    ///
    public func newBackgroundContext(logged: Bool) -> BackgroundContext {

        let context: LoggingContext = self.dataCache.newBackgroundContext()

        if logged {
            ///
            /// Attached the logger to the context
            /// so updates can be logged.
            ///
            context.logger = self.writeAheadLog
        }
        return context
    }

    internal func newActionContext() -> ActionContext {

        let context: ActionContext = self.dataCache.newBackgroundContext()
        
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.logger = self.writeAheadLog

        return context
    }
}

///
/// Action Execution methods
///
public extension GenericConnect {

    ///
    /// Execute a generic action in a concurrent queue.
    ///
    /// - Parameters:
    ///     - action: The `GenericAction` implementation to execute.
    ///
    /// - Returns: An `ActionProxy` that represents your action.  This can be used to manage and monitor the action's status.
    ///
    /// - SeeAlso: `GenericAction` protocol
    /// - SeeAlso: `ActionProxy` protocol
    ///
    @discardableResult
    public func execute<ActionType: GenericAction>(_ action: ActionType) throws -> ActionProxy {
        return try self.execute(action, completionBlock: nil)
    }

    ///
    /// Execute a generic action in a concurrent queue.
    ///
    /// - Parameters:
    ///     - action: The `GenericAction` implementation to execute.
    ///     - completionBlock: An optional block that will be called after teh action completes (succeeds or fails).
    ///
    /// - Returns: An `ActionProxy` that represents your action.  This can be used to manage and monitor the action's status.
    ///
    /// - SeeAlso: `GenericAction` protocol
    /// - SeeAlso: `ActionProxy` protocol
    ///
    @discardableResult
    public func execute<ActionType: GenericAction>(_ action: ActionType, completionBlock: ((_ actionProxy: ActionProxy) -> Void)?) throws -> ActionProxy {

        return self.synchronizationQueue.sync {

            let container = GenericActionContainer<ActionType>(action: action, notificationService: self.notificationService, completionBlock: completionBlock)

            logInfo(Log.tag) { "Queuing \(container) on queue `\(self.genericQueue)'" }

            self.genericQueue.addAction(container, waitUntilDone: false)
            
            return container
        }
    }

    ///
    /// Execute a entity action in a serial queue. Entity actions also get passed a specific action context for access to the persistent storage.
    ///
    /// - Parameters:
    ///     - action: The `EntityAction` implementation to execute.
    ///
    /// - Returns: An `ActionProxy` that represents your action.  This can be used to manage and monitor the action's status.
    ///
    /// - SeeAlso: `EntityAction` protocol
    /// - SeeAlso: `ActionProxy` protocol
    ///
    @discardableResult
    public func execute<ActionType: EntityAction>(_ action: ActionType) throws -> ActionProxy {
        return try self.execute(action, completionBlock: nil)
    }

    ///
    /// Execute a entity action in a serial queue. Entity actions also get passed a specific action context for access to the persistent storage.
    ///
    /// - Parameters:
    ///     - action: The `EntityAction` implementation to execute.
    ///     - completionBlock: An optional block that will be called after teh action completes (succeeds or fails).
    ///
    /// - Returns: An `ActionProxy` that represents your action.  This can be used to manage and monitor the action's status.
    ///
    /// - SeeAlso: `EntityAction` protocol
    /// - SeeAlso: `ActionProxy` protocol
    ///
    @discardableResult
    public func execute<ActionType: EntityAction>(_ action: ActionType, completionBlock: ((_ actionProxy: ActionProxy) -> Void)?) throws -> ActionProxy {

        return try self.synchronizationQueue.sync {

            let entityQueue = try queue(entity: ActionType.ManagedObjectType.self)

            let context = self.newActionContext()

            let container = EntityActionContainer<ActionType>(action: action, context: context, notificationService: self.notificationService, completionBlock: completionBlock)

            logInfo(Log.tag) { "Queuing \(container) on queue `\(entityQueue)'" }

            entityQueue.addAction(container, waitUntilDone: false)
            
            return container
        }
    }
}

///
/// Connect state management (public synchronized)
///
public extension GenericConnect {

    ///
    /// Synchronously start the instance of `Connect`
    ///
    /// - Throws: If an error occurs.
    ///
    public func start() throws {

        try self.synchronizationQueue.sync {
            try self._start()
        }
    }

    ///
    /// Asynchronously start the instance of `Connect`
    ///
    /// - Parameter completionBlock: Block to call when the startup sequence is complete. If an error occurs, `Error` will be non nil and contain the error indicating the reason for the failure.
    ///
    public func start(block: @escaping (Error?) -> Void) {

        self.synchronizationQueue.async {
            do {
                try self._start()

                /// Keep the user block execution outside of our synchronization queue
                DispatchQueue.global().async {
                    block(nil)
                }
            } catch {
                /// Keep the user block execution outside of our synchronization queue
                DispatchQueue.global().async {
                    block(error)
                }
            }
        }
    }

    ///
    /// Synchronously stop the instance of `Connect` unloading the persistent stores.
    ///
    /// - Throws: If an error occurs.
    ///
    public func stop() throws {

        try self.synchronizationQueue.sync {
            try self._stop()
        }
    }

    ///
    /// Asynchronously stop the instance of `Connect` unloading the persistent stores.
    ///
    /// - Parameter completionBlock: Block to call when the shutdown sequence is complete. If an error occurs, `Error` will be non nil and contain the error indicating the reason for the failure.
    ///
    public func stop(block: @escaping (Error?) -> Void) {

        self.synchronizationQueue.async {
            do {
                try self._stop()

                /// Keep the user block execution outside of our synchronization queue
                DispatchQueue.global().async {
                    block(nil)
                }
            } catch {
                /// Keep the user block execution outside of our synchronization queue
                DispatchQueue.global().async {
                    block(error)
                }
            }
        }
    }

    ///
    /// Suspend or resume the operation of `Connect`.
    ///
    /// - Note: This will suspend or activate all Queues.
    ///
    public var suspended: Bool {
        get {
            return self.synchronizationQueue.sync {
                return self._suspended
            }
        }
        set {
            self.synchronizationQueue.sync {
                self._suspended = newValue
            }
        }
    }
}

///
/// Connect state management (private unsynchronized)
///
fileprivate extension GenericConnect {

    ///
    /// Note: This private implementation method is unsynchronized  and
    ///       must be syncrhonized through `self.syncrhonizationQueue` when used.
    ///
    fileprivate func _start() throws {

        guard !started else {
            logWarning(Log.tag) { "Instance '\(self.name)' already started, no action taken." }
            return
        }

        try autoreleasepool {

            logInfo(Log.tag) { "Starting instance '\(self.name)'..." }

            try self._loadModel()

            try self._loadPersistentStores()

            self.writeAheadLog = try WriteAheadLog(persistentStack: self.metaCache)

            self.registerForNotifications()

            if self._suspended {
                self._suspended = false
            }
            
            self.started = true
            
            logInfo(Log.tag) { "Instance '\(self.name)' started." }
        }
    }

    /// Note: This private implementation method is unsynchronized  and
    ///       must be syncrhonized through `self.syncrhonizationQueue` when used.
    ///
    fileprivate func _stop() throws {

        guard started else {
            logWarning(Log.tag) { "Instance '\(self.name)' already stopped, no action taken." }
            return
        }

        try autoreleasepool {

            logInfo(Log.tag) { "Stopping instance '\(self.name)'..." }

            if !self._suspended {
                self._suspended = true
            }

            self.unregisterForNotifications()

            try self._unloadPersistentStores()

            self.writeAheadLog = nil

            try self._unloadModel()

            self.started = false
            
            logInfo(Log.tag) { "Instance '\(self.name)' stopped." }
        }
    }

    fileprivate func _loadPersistentStores() throws {

        logInfo(Log.tag) { "Loading persistent stores..." }

        let defaultLocation = BundleManager.url(for: self.name, bundleLocation: GenericConnect.defaultStoreLocation())

        let resolvedConfiguration  = self.configuration.resolved(defaultLocation: defaultLocation)
        let metaStoreConfiguration = StoreConfiguration(name: MetaModel.metaConfigurationName, type: NSSQLiteStoreType, overwriteIncompatibleStore: true).resolved(defaultLocation: resolvedConfiguration.location)

        try BundleManager.createIfAbsent(url: resolvedConfiguration.location)

        self.dataCache.storeConfigurations = resolvedConfiguration.storeConfigurations
        self.metaCache.storeConfigurations = [metaStoreConfiguration]

        try self.dataCache.loadPersistentStores()
        try self.metaCache.loadPersistentStores()
    }

    fileprivate func _unloadPersistentStores() throws {

        logInfo(Log.tag) { "Unloading persistent stores..." }

        try self.dataCache.unloadPersistentStores()
        try self.metaCache.unloadPersistentStores()
    }

    fileprivate func _loadModel() throws {

        logInfo(Log.tag) { "Loading model for instance '\(self.name)'..." }
        ///
        /// Initialize the entities
        ///
        for (name, entity) in self.dataCache.managedObjectModel.entitiesByName {
            self.manage(name: name, entity: entity)
        }

        logInfo(Log.tag) { "Model for instance '\(self.name)' loaded." }
    }

    fileprivate func _unloadModel() throws {

        logInfo(Log.tag) { "Unloading model for instance '\(self.name)'..." }
        ///
        /// Initialize the entities
        ///
        for (name, entity) in self.dataCache.managedObjectModel.entitiesByName {

            if entity.managed {
                entity.managed = false

                self.entityQueues[name] = nil
            }
        }

        logInfo(Log.tag) { "Model for instance '\(self.name)' unloaded." }
    }

    ///
    /// Note: This private implementation method is unsynchronized  and
    ///       must be syncrhonized through `self.syncrhonizationQueue` when used.
    ///
    fileprivate var _suspended: Bool {
        get {
            return self.genericQueue.suspended
        }
        set {
            if newValue != self.genericQueue.suspended {
                logInfo(Log.tag) { "\(newValue ? "Suspending" : "Resuming") queues." }
                self.genericQueue.suspended = newValue

                logInfo(Log.tag) { "Queue '\(self.genericQueue.label)' \(newValue ? "suspended" : "active")." }

                for queue in self.entityQueues.values {
                    queue.suspended = newValue

                    logInfo(Log.tag) { "Queue '\(queue.label)' \(newValue ? "suspended" : "active")." }
                }
            }
        }
    }
}

///
/// Utility methods
///
fileprivate extension GenericConnect {

    @discardableResult
    func manage(name: String, entity: NSEntityDescription) -> Bool {
        logInfo(Log.tag) { "Determining if entity '\(name)' can be managed...."}

        var canBeManaged = true

        if let userInfo = entity.userInfo, userInfo.count > 0 {
            logInfo(Log.tag) { "UserInfo found on entity '\(name)', reading static settings (if any)." }
            entity.setSettings(from: userInfo)
        }

        if !entity.uniquenessAttributes.isEmpty {
            var valid = true

            for attribute in entity.uniquenessAttributes {
                if !entity.attributesByName.keys.contains(attribute) {
                    valid = false

                    logWarning(Log.tag) { "Uniqueness attribute '\(attribute)' specified but it is not present on entity." }
                    break
                }
            }

            if !valid {
                canBeManaged = false

                logWarning(Log.tag) { "Setting value '\(entity.uniquenessAttributes)' for 'uniquenessAttributes' invalid." }
            }

        } else {

            if #available(iOS 9.0, *), entity.uniquenessConstraints.count > 0 {

                logInfo(Log.tag) { "Found constraints, using the least complex key for 'uniquenessAttributes'.  To override define 'uniquenessAttributes' in your CoreData model for entity '\(name)'."}

                var shortest = entity.uniquenessConstraints[0]

                for attributes in entity.uniquenessConstraints {
                    if attributes.count < shortest.count {
                        shortest = attributes
                    }
                }

                entity.uniquenessAttributes = {
                    var array: [String] = []

                    for case let attribute as NSAttributeDescription in shortest {
                        array.append(attribute.name)
                    }
                    return array
                }()

            } else {
                canBeManaged = false

                logInfo(Log.tag) { "Missing 'uniquenessAttributes' setting."}
            }
        }

        if canBeManaged {

            let label = "\(Default.Queue.prefix).entity.\(name.lowercased())"

            logInfo(Log.tag) { "Creating action queue for entity '\(name)' (\(label))" }

            self.entityQueues[name] = ActionQueue(label: label, qos: Default.ActionQueue.qos, concurrencyMode: .serial, suspended: Default.ActionQueue.suspended)

            entity.managed = true
        } else {
            entity.managed = false

            logInfo(Log.tag) { "Entity '\(name)' cannot be managed."}
        }

        return entity.managed
    }

    func queue<EntityType: NSManagedObject>(entity: EntityType.Type) throws -> ActionQueue {
        let entityName = String(describing: entity)

        guard let queue = self.entityQueues[entityName] else {
            throw Errors.unmanagedEntity("Entity '\(entityName)' not managed by \(Log.tag)")
        }
        return queue
    }
}
