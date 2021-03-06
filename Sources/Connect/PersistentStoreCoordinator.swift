/**
 *   PersistentStoreCoordinator.swift
 *
 *   Copyright 2015 Tony Stone
 *
 *   Licensed under the Apache License, Version 2.0 (the "License");
 *   you may not use this file except in compliance with the License.
 *   You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS,
 *   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *   See the License for the specific language governing permissions and
 *   limitations under the License.
 *
 *   Created by Tony Stone on 12/8/15.
 */
import Foundation
import CoreData
import TraceLog

open class PersistentStoreCoordinator : NSPersistentStoreCoordinator {
    
    // The internal write ahead log for logging transactions
    fileprivate let writeAheadLog: WriteAheadLog?
    
    override public convenience init(managedObjectModel model: NSManagedObjectModel) {
        self.init(managedObjectModel: model, enableLogging: true)
    }
    
    init(managedObjectModel model: NSManagedObjectModel, enableLogging: Bool) {
        
        logInfo { "Initializing instance..." }
        
        if enableLogging {
            //
            // Figure out where to put things
            //
            let cachePath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
            
            //
            // Create our write ahead logger
            //
            do {
                writeAheadLog = try WriteAheadLog(identifier: model.uniqueIdentifier(), path: cachePath)
            } catch {
                writeAheadLog = nil
                
                logError { "Failed to enable logging." }
            }
        } else {
            writeAheadLog = nil
            
            logInfo { "Logging is diabled." }
        }
        super.init(managedObjectModel: model)
        
        logInfo { "Instance initialized." }
    }
    
    override open func addPersistentStore(ofType storeType: String, configurationName configuration: String?, at storeURL: URL?, options: [AnyHashable: Any]?) throws -> NSPersistentStore {
        
        logInfo {
            "Attaching persistent store for type: \(storeType) at path: \(storeURL?.absoluteString)..."
        }
        var persistentStore: NSPersistentStore? = nil;
        
        do {
            persistentStore = try super.addPersistentStore(ofType: storeType, configurationName: configuration, at: storeURL, options: options)
        
            logInfo { "Persistent Store attached." }

        } catch let error as NSError {
            logError { "Failed to attach persistent store: \(error.localizedDescription)" }
            
            throw error
        }
        return persistentStore!
    }
    
    override open func remove(_ store: NSPersistentStore) throws {
        logInfo { "Removing persistent store for type: \(store.type) at path: \(store.url)..." }
        
        try super.remove(store)

        logInfo { "Persistent Store removed." }
    }
    
    override open func execute(_ request: NSPersistentStoreRequest, with context: NSManagedObjectContext) throws -> Any {
        
        switch (request.requestType) {
            
        case NSPersistentStoreRequestType.saveRequestType: fallthrough
        case NSPersistentStoreRequestType.batchUpdateRequestType:
            
            if let log = self.writeAheadLog {
                
                //
                // Obtain permanent IDs for all inserted objects
                //
                try context.obtainPermanentIDs(for: [NSManagedObject](context.insertedObjects))
                
                //
                // Log the changes from the context in a transaction
                //
                let transactionID = try log.logTransactionForContextChanges(context)
                
                //
                // Save the main context
                //
                do {
                    let results = try super.execute(request, with:context)
                    
                    return results;
                } catch {
                    log.removeTransaction(transactionID)
                    
                    throw error
                }
            } else {
                fallthrough
            }
        case NSPersistentStoreRequestType.fetchRequestType: fallthrough
        default:
            return try super.execute(request, with:context)
        }
    }
    
}
