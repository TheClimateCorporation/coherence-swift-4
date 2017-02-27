///
///  ActionNotification.swift
///
///  Copyright 2017 Tony Stone
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
///  Created by Tony Stone on 1/22/17.
///
import Foundation
import TraceLog

///
/// Internal Notification service for the action proxy.
///
internal class NotificationService {

    ///
    /// The source of the notification that is sent.
    ///
    /// - Note: This is not initialized in the constructor
    ///         due to Swifts requirement for all properties
    ///         to have a value before referencing self.  
    /// 
    ///         With this configuration the init method
    ///         using this class can costruct an instance 
    ///         assigning it to it's propery and once 
    ///         the clss is fully initialized, assign 
    ///         self to `source`.
    ///
    internal weak var source: AnyObject?

    ///
    /// Init an instance of `NotificationService`.
    ///
    internal init() {}

    ///
    /// Notify the notificationService that an ActionProxy changed state.
    ///
    internal func actionProxy(_ actionProxy: ActionProxy, didChangeState newState: ActionState) {

        let userInfo = [Connect.Notification.Key.ActionProxy: actionProxy]

        switch newState {

        case .executing:
            NotificationCenter.default.post(name: Connect.Notification.ActionDidStartExecuting, object: self.source, userInfo: userInfo)
            break
        case .finished:
            NotificationCenter.default.post(name: Connect.Notification.ActionDidFinishExecuting, object: self.source, userInfo: userInfo)
            break
        default:
            break
        }
    }
}