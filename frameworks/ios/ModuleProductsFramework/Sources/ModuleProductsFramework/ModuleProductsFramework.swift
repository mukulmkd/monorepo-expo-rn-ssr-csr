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
        
        print("🔍 ModuleProductsFramework: Looking for bundle...")
        print("   Framework bundle path: \(frameworkBundle.bundlePath)")
        print("   Framework bundle identifier: \(frameworkBundle.bundleIdentifier ?? "nil")")
        print("   Framework bundle resource path: \(frameworkBundle.resourcePath ?? "nil")")
        
        // Method 1: Try path(forResource:ofType:) - standard lookup
        if let bundlePath = frameworkBundle.path(
            forResource: "module-products",
            ofType: "bundle"
        ) {
            print("   ✅ Found bundle via path(forResource:ofType:): \(bundlePath)")
            return URL(fileURLWithPath: bundlePath)
        }
        
        // Method 2: Try url(forResource:withExtension:) - alternative lookup
        if let bundleURL = frameworkBundle.url(
            forResource: "module-products",
            withExtension: "bundle"
        ) {
            print("   ✅ Found bundle via url(forResource:withExtension:): \(bundleURL.path)")
            return bundleURL
        }
        
        // Method 3: Check resource path directly
        if let resourcePath = frameworkBundle.resourcePath {
            print("   Checking resource path: \(resourcePath)")
            let bundlePath = "\(resourcePath)/module-products.bundle"
            if FileManager.default.fileExists(atPath: bundlePath) {
                print("   ✅ Found bundle in resource path: \(bundlePath)")
                return URL(fileURLWithPath: bundlePath)
            }
            
            // List all resources for debugging
            print("   Available resources in framework bundle:")
            if let resources = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
                resources.forEach { print("     - \($0)") }
            } else {
                print("     (could not list resources)")
            }
        }
        
        // Method 4: Try Bundle.module (SPM-specific, Swift 5.3+)
        if #available(iOS 14.0, *) {
            if let bundleURL = Bundle.module.url(
                forResource: "module-products",
                withExtension: "bundle"
            ) {
                print("   ✅ Found bundle via Bundle.module: \(bundleURL.path)")
                return bundleURL
            }
        }
        
        // Method 5: Check main bundle (fallback)
        print("   Checking main bundle...")
        if let mainBundlePath = Bundle.main.path(
            forResource: "module-products",
            ofType: "bundle"
        ) {
            print("   ✅ Found bundle in main bundle: \(mainBundlePath)")
            return URL(fileURLWithPath: mainBundlePath)
        }
        
        // Method 6: Check main bundle resource path
        if let resourcePath = Bundle.main.resourcePath {
            let bundlePath = "\(resourcePath)/module-products.bundle"
            if FileManager.default.fileExists(atPath: bundlePath) {
                print("   ✅ Found bundle in main bundle resource path: \(bundlePath)")
                return URL(fileURLWithPath: bundlePath)
            }
        }
        
        print("   ❌ Bundle not found in any location")
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
            print("❌ ModuleProductsFramework: Bundle not found")
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
