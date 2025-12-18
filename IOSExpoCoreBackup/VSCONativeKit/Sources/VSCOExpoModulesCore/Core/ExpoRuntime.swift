import Foundation
import VSCOExpoModulesCoreObjC

@objc(EXRuntime)
public final class ExpoRuntime: JavaScriptRuntime {
  internal func initializeCoreObject(_ coreObject: JavaScriptObject) throws {
    global().defineProperty(EXGlobalCoreObjectPropertyName, value: coreObject, options: .enumerable)
  }
}
