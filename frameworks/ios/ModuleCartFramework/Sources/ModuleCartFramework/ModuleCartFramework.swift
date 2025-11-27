import UIKit
import React
// React Native types are provided by ReactNativeRuntime SPM package
// The consuming app must add ReactNativeRuntime as a dependency

public class ModuleCartFramework {
    public static let shared = ModuleCartFramework()
    
    private var bridge: RCTBridge?
    
    private init() {}
    
    /// Gets the bundle URL for the ModuleCart module
    /// - Returns: The URL to the module-cart.bundle file
    public func getBundleURL() -> URL? {
        let frameworkBundle = Bundle(for: type(of: self))
        
        if let bundlePath = frameworkBundle.path(
            forResource: "module-cart",
            ofType: "bundle"
        ) {
            return URL(fileURLWithPath: bundlePath)
        }
        
        // Also check main bundle
        if let mainBundlePath = Bundle.main.path(
            forResource: "module-cart",
            ofType: "bundle"
        ) {
            return URL(fileURLWithPath: mainBundlePath)
        }
        
        return nil
    }
    
    /// Gets the module name for the ModuleCart module
    /// - Returns: The registered module name ("ModuleCart")
    public func getModuleName() -> String {
        return "ModuleCart"
    }
    
    /// Creates a React Native root view for the module
    /// - Parameters:
    ///   - moduleName: The registered module name (default: "ModuleCart")
    ///   - initialProperties: Optional initial props
    /// - Returns: A configured RCTRootView ready to be added to a view hierarchy
    /// - Note: Requires ReactNativeRuntime SPM package to be added to the consuming app
    public func createView(
        moduleName: String = "ModuleCart",
        initialProperties: [String: Any]? = nil
    ) -> RCTRootView? {
        guard let bundleURL = getBundleURL() else {
            print("❌ ModuleCartFramework: Bundle not found")
            return nil
        }
        
        if bridge == nil {
            bridge = RCTBridge(bundleURL: bundleURL, moduleProvider: nil, launchOptions: nil)
        }
        
        guard let bridge = bridge else {
            return nil
        }
        
        let rootView = RCTRootView(
            bridge: bridge,
            moduleName: moduleName,
            initialProperties: initialProperties
        )
        
        rootView.backgroundColor = .white
        return rootView
    }
    
    /// Invalidates the bridge (call when done)
    public func invalidate() {
        bridge?.invalidate()
        bridge = nil
    }
}
