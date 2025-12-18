// Copyright 2023-present 650 Industries. All rights reserved.

import Foundation
import UIKit
import VSCOExpoModulesCore
import VSCOExpoFileSystemObjC

@objc(FileSystemBackgroundSessionHandler)
public final class FileSystemBackgroundSessionHandler: ExpoAppDelegateSubscriber {
  public typealias BackgroundSessionCompletionHandler = () -> Void

  private var completionHandlers: [String: BackgroundSessionCompletionHandler] = [:]

  @objc
  public func invokeCompletionHandler(forSessionIdentifier identifier: String) {
    guard let completionHandler = completionHandlers[identifier] else {
      return
    }
    DispatchQueue.main.async {
      completionHandler()
    }
    completionHandlers.removeValue(forKey: identifier)
  }

  // MARK: - ExpoAppDelegateSubscriber

  #if os(iOS) || os(tvOS)
  public func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
    completionHandlers[identifier] = completionHandler
  }
  #endif
}

// Explicitly conform to the protocol (Swift renames it to EXSessionHandlerProtocol to avoid collision with the class)
extension FileSystemBackgroundSessionHandler: EXSessionHandlerProtocol {
}
