import UIKit
import React
// React Native types are provided by ReactNativeRuntime SPM package
// The consuming app must add ReactNativeRuntime as a dependency

public class ModuleProductsFramework {
    public static let shared = ModuleProductsFramework()
    
    private var bridge: RCTBridge?
    
    private init() {}
    
    /// Gets the bundle URL for the ModuleProducts module
    /// - Returns: The URL to the module-products.bundle file
    public func getBundleURL() -> URL? {
        let frameworkBundle = Bundle(for: type(of: self))
        
        // Method 1: Try path(forResource:ofType:) - standard lookup
        if let bundlePath = frameworkBundle.path(
            forResource: "module-products",
            ofType: "bundle"
        ) {
            return URL(fileURLWithPath: bundlePath)
        }
        
        // Method 2: Try url(forResource:withExtension:) - alternative lookup
        if let bundleURL = frameworkBundle.url(
            forResource: "module-products",
            withExtension: "bundle"
        ) {
            return bundleURL
        }
        
        // Method 3: Check resource path directly
        if let resourcePath = frameworkBundle.resourcePath {
            let bundlePath = "\(resourcePath)/module-products.bundle"
            if FileManager.default.fileExists(atPath: bundlePath) {
                return URL(fileURLWithPath: bundlePath)
            }
        }
        
        // Method 4: Try Bundle.module (SPM-specific, Swift 5.3+)
        if #available(iOS 14.0, *) {
            if let bundleURL = Bundle.module.url(
                forResource: "module-products",
                withExtension: "bundle"
            ) {
                return bundleURL
            }
        }
        
        // Method 5: Check main bundle (fallback)
        if let mainBundlePath = Bundle.main.path(
            forResource: "module-products",
            ofType: "bundle"
        ) {
            return URL(fileURLWithPath: mainBundlePath)
        }
        
        // Method 6: Check main bundle resource path
        if let resourcePath = Bundle.main.resourcePath {
            let bundlePath = "\(resourcePath)/module-products.bundle"
            if FileManager.default.fileExists(atPath: bundlePath) {
                return URL(fileURLWithPath: bundlePath)
            }
        }
        
        return nil
    }
    
    /// Gets the module name for the ModuleProducts module
    /// - Returns: The registered module name ("ModuleProducts")
    public func getModuleName() -> String {
        return "ModuleProducts"
    }
    
    /// Creates a React Native root view for the module
    /// - Parameters:
    ///   - moduleName: The registered module name (default: "ModuleProducts")
    ///   - initialProperties: Optional initial props
    /// - Returns: A configured RCTRootView ready to be added to a view hierarchy
    /// - Note: Requires ReactNativeRuntime SPM package to be added to the consuming app
    public func createView(
        moduleName: String = "ModuleProducts",
        initialProperties: [String: Any]? = nil
    ) -> RCTRootView? {
        guard let bundleURL = getBundleURL() else {
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
