import UIKit
import React

public class ModuleProductsFramework {
    public static let shared = ModuleProductsFramework()
    
    private var bridge: RCTBridge?
    
    private init() {}
    
    /// Creates a React Native root view for the Products module
    /// - Parameters:
    ///   - moduleName: The registered module name (default: "ModuleProducts")
    ///   - initialProperties: Optional initial props
    /// - Returns: A configured RCTRootView ready to be added to a view hierarchy
    public func createProductsView(
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
    
    /// Returns a ViewController ready to present the Products module
    public func createProductsViewController(
        moduleName: String = "ModuleProducts",
        initialProperties: [String: Any]? = nil
    ) -> UIViewController {
        let viewController = UIViewController()
        
        if let rootView = createProductsView(
            moduleName: moduleName,
            initialProperties: initialProperties
        ) {
            viewController.view = rootView
        } else {
            let errorLabel = UILabel()
            errorLabel.text = "Failed to load Products module"
            errorLabel.textAlignment = .center
            viewController.view = errorLabel
        }
        
        return viewController
    }
    
    /// Invalidates the bridge (call when done)
    public func invalidate() {
        bridge?.invalidate()
        bridge = nil
    }
    
    // MARK: - Private
    
    private func getBundleURL() -> URL? {
        guard let frameworkBundle = Bundle(for: type(of: self)) else {
            return nil
        }
        
        if let bundlePath = frameworkBundle.path(
            forResource: "module-products",
            ofType: "bundle"
        ) {
            return URL(fileURLWithPath: bundlePath)
        }
        
        if let mainBundlePath = Bundle.main.path(
            forResource: "module-products",
            ofType: "bundle"
        ) {
            return URL(fileURLWithPath: mainBundlePath)
        }
        
        return nil
    }
}

