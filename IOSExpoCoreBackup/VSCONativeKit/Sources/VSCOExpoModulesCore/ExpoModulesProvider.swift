import Foundation

/// Default ExpoModulesProvider for VSCONativeKit
/// This automatically registers all modules included in the VSCONativeKit package
/// Users don't need to create their own provider - this one will be used automatically
/// The AppContext will automatically discover this class via NSClassFromString("ExpoModulesProvider")
/// 
/// Modules are discovered at runtime using NSClassFromString to avoid circular dependencies
@objc(ExpoModulesProvider)
public class ExpoModulesProvider: ModulesProvider {
    
    public override func getModuleClasses() -> [AnyModule.Type] {
        var modules: [AnyModule.Type] = []
        
        // File System module (from VSCOExpoFileSystem)
        // Use runtime discovery to avoid circular dependencies
        if let fileSystemModuleClass = NSClassFromString("FileSystemModule") as? AnyModule.Type {
            modules.append(fileSystemModuleClass)
        }
        
        // Add other modules from VSCONativeKit here as they're added
        // Use runtime discovery pattern:
        // if let moduleClass = NSClassFromString("ModuleName") as? AnyModule.Type {
        //     modules.append(moduleClass)
        // }
        
        return modules
    }
    
    public override func getAppDelegateSubscribers() -> [ExpoAppDelegateSubscriber.Type] {
        var subscribers: [ExpoAppDelegateSubscriber.Type] = []
        
        // File System background session handler
        // Use runtime discovery to avoid circular dependencies
        if let fileSystemHandlerClass = NSClassFromString("FileSystemBackgroundSessionHandler") as? ExpoAppDelegateSubscriber.Type {
            subscribers.append(fileSystemHandlerClass)
        }
        
        // Add other app delegate subscribers here as they're added
        // Use runtime discovery pattern:
        // if let handlerClass = NSClassFromString("HandlerName") as? ExpoAppDelegateSubscriber.Type {
        //     subscribers.append(handlerClass)
        // }
        
        return subscribers
    }
    
    public override func getReactDelegateHandlers() -> [ExpoReactDelegateHandlerTupleType] {
        return []
    }
}

