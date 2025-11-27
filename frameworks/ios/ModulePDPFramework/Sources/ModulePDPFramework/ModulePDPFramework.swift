import UIKit
import React
// React Native types are provided by ReactNativeRuntime SPM package
// The consuming app must add ReactNativeRuntime as a dependency

public class ModulePDPFramework {
    public static let shared = ModulePDPFramework()
    
    private var bridge: RCTBridge?
    
    private init() {}
    
    /// Gets the bundle URL for the ModulePDP module
    /// - Returns: The URL to the module-pdp.bundle file
    public func getBundleURL() -> URL? {
        let frameworkBundle = Bundle(for: type(of: self))
        
        if let bundlePath = frameworkBundle.path(
            forResource: "module-pdp",
            ofType: "bundle"
        ) {
            return URL(fileURLWithPath: bundlePath)
        }
        
        // Also check main bundle
        if let mainBundlePath = Bundle.main.path(
            forResource: "module-pdp",
            ofType: "bundle"
        ) {
            return URL(fileURLWithPath: mainBundlePath)
        }
        
        return nil
    }
    
    /// Gets the module name for the ModulePDP module
    /// - Returns: The registered module name ("ModulePDP")
    public func getModuleName() -> String {
        return "ModulePDP"
    }
    
    /// Creates a React Native root view for the module
    /// - Parameters:
    ///   - moduleName: The registered module name (default: "ModulePDP")
    ///   - initialProperties: Optional initial props
    /// - Returns: A configured RCTRootView ready to be added to a view hierarchy
    /// - Note: Requires ReactNativeRuntime SPM package to be added to the consuming app
    public func createView(
        moduleName: String = "ModulePDP",
        initialProperties: [String: Any]? = nil
    ) -> RCTRootView? {
        guard let bundleURL = getBundleURL() else {
            print("❌ ModulePDPFramework: Bundle not found")
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
