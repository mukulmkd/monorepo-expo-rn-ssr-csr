import Foundation
import VSCOExpoModulesCoreObjC
// Copyright 2021-present 650 Industries. All rights reserved.

public struct Promise: AnyArgument {
  public typealias ResolveClosure = (Any?) -> Void
  public typealias RejectClosure = (Exception) -> Void

  internal weak var appContext: AppContext?
  public var resolver: ResolveClosure
  public var rejecter: RejectClosure

  /**
   Initializes a Promise with appContext and resolver/rejecter closures.
   */
  public init(appContext: AppContext?, resolver: @escaping ResolveClosure, rejecter: @escaping RejectClosure) {
    self.appContext = appContext
    self.resolver = resolver
    self.rejecter = rejecter
  }

  /**
   The resolver that is compatible with the legacy `EXPromiseResolveBlock`.
   Necessary for Objective-C handlers that expect the legacy block type.
   The resolver closure should be called on the JavaScript thread, which is handled by the AppContext.
   */
  public var legacyResolver: EXPromiseResolveBlock {
    return { result in
      // The resolver closure from AsyncFunctionDefinition already handles threading
      // It will call the callback on the JavaScript thread via AppContext
      self.resolve(result)
    }
  }

  /**
   The rejecter that is compatible with the legacy `EXPromiseRejectBlock`.
   Necessary in some places not converted to Swift, such as `EXPermissionsMethodsDelegate`.
   The rejecter closure should be called on the JavaScript thread, which is handled by the AppContext.
   */
  public var legacyRejecter: EXPromiseRejectBlock {
    return { code, description, _ in
      // The rejecter closure from AsyncFunctionDefinition already handles threading
      // It will call the callback on the JavaScript thread via AppContext
      self.reject(code ?? "", description ?? "")
    }
  }

  public func resolve(_ value: Any? = nil) {
    resolver(value)
  }

  public func reject(_ error: Error) {
    if let exception = error as? Exception {
      rejecter(exception)
    } else {
      rejecter(UnexpectedException(error))
    }
  }

  public func reject(_ error: Exception) {
    rejecter(error)
  }

  public func reject(_ code: String, _ description: String) {
    rejecter(Exception(name: code, description: description, code: code))
  }

  public func settle<ValueType, ExceptionType: Exception>(with result: Result<ValueType, ExceptionType>) {
    switch result {
    case .success(let value):
      resolve(value)
    case .failure(let exception):
      reject(exception)
    }
  }
}
