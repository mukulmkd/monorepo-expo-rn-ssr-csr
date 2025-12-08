package com.yourorg.pdp

import android.content.Context
import android.util.Log
import com.facebook.react.ReactInstanceManager
import com.facebook.react.ReactInstanceManagerBuilder
import com.facebook.react.ReactRootView
import com.facebook.react.bridge.JSBundleLoader
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.common.LifecycleState
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

/**
 * ModulePDPFramework
 * 
 * Android framework wrapper for ModulePDP React Native module.
 * 
 * This class provides a simple API to load and render the ModulePDP module
 * in any Android Activity or Fragment.
 * 
 * Usage:
 * ```kotlin
 * val framework = ModulePDPFramework.getInstance()
 * val bundlePath = framework.getBundlePath(context)
 * val moduleName = framework.getModuleName()
 * 
 * val rootView = ReactRootView(context)
 * rootView.startReactApplication(reactInstanceManager, moduleName, null)
 * ```
 */
class ModulePDPFramework private constructor() {
    
    companion object {
        private const val TAG = "ModulePDPFramework"
        private const val BUNDLE_NAME = "module-pdp.bundle"
        private const val MODULE_NAME = "ModulePDP"
        
        @Volatile
        private var INSTANCE: ModulePDPFramework? = null
        
        /**
         * Get the singleton instance of ModulePDPFramework
         */
        fun getInstance(): ModulePDPFramework {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: ModulePDPFramework().also { INSTANCE = it }
            }
        }
    }
    
    /**
     * Gets the bundle file path for the ModulePDP module
     * 
     * @param context Android context
     * @return The absolute path to the module-pdp.bundle file, or null if not found
     */
    fun getBundlePath(context: Context): String? {
        Log.d(TAG, "🔍 Looking for bundle: $BUNDLE_NAME")
        
        // Method 1: Try to find in assets directory (standard Android library location)
        try {
            val assets = context.assets
            assets.open(BUNDLE_NAME).use {
                // Bundle exists in assets
                val bundlePath = "file:///android_asset/$BUNDLE_NAME"
                Log.d(TAG, "✅ Found bundle in assets: $bundlePath")
                return bundlePath
            }
        } catch (e: Exception) {
            Log.d(TAG, "   Bundle not found in assets, trying other methods...")
        }
        
        // Method 2: Try to find in application's assets
        try {
            val appContext = context.applicationContext
            val assets = appContext.assets
            assets.open(BUNDLE_NAME).use {
                val bundlePath = "file:///android_asset/$BUNDLE_NAME"
                Log.d(TAG, "✅ Found bundle in application assets: $bundlePath")
                return bundlePath
            }
        } catch (e: Exception) {
            Log.d(TAG, "   Bundle not found in application assets")
        }
        
        // Method 3: Try to find in files directory (if copied there)
        val filesDir = context.filesDir
        val bundleFile = File(filesDir, BUNDLE_NAME)
        if (bundleFile.exists()) {
            val bundlePath = bundleFile.absolutePath
            Log.d(TAG, "✅ Found bundle in files directory: $bundlePath")
            return bundlePath
        }
        
        // Method 4: Try to find in external files directory
        val externalFilesDir = context.getExternalFilesDir(null)
        if (externalFilesDir != null) {
            val bundleFile = File(externalFilesDir, BUNDLE_NAME)
            if (bundleFile.exists()) {
                val bundlePath = bundleFile.absolutePath
                Log.d(TAG, "✅ Found bundle in external files directory: $bundlePath")
                return bundlePath
            }
        }
        
        Log.e(TAG, "❌ Bundle not found in any location")
        Log.e(TAG, "   Searched:")
        Log.e(TAG, "     - Assets: $BUNDLE_NAME")
        Log.e(TAG, "     - Files dir: ${filesDir.absolutePath}")
        if (externalFilesDir != null) {
            Log.e(TAG, "     - External files dir: ${externalFilesDir.absolutePath}")
        }
        
        return null
    }
    
    /**
     * Gets the module name for the ModulePDP module
     * 
     * @return The registered module name ("ModulePDP")
     */
    fun getModuleName(): String {
        return MODULE_NAME
    }
    
    /**
     * Creates a React Native root view for the module
     * 
     * @param context Android context
     * @param reactInstanceManager The ReactInstanceManager from the consuming app
     * @param initialProperties Optional initial properties to pass to the module
     * @return A configured ReactRootView ready to be added to a view hierarchy, or null if bundle not found
     */
    /**
     * Creates a ReactInstanceManager specifically for this module with its own bundle loader.
     * Each module has its own ReactInstanceManager to load its own bundle from AAR assets.
     * This allows multiple modules to coexist, each with their own bundle.
     */
    private fun createModuleReactInstanceManager(context: Context): ReactInstanceManager {
        val application = context.applicationContext as? android.app.Application
            ?: throw IllegalStateException("Context must be an Application context")
        
        val reactApplication = application as? com.facebook.react.ReactApplication
            ?: throw IllegalStateException("Application must implement ReactApplication")
        
        val reactNativeHost = reactApplication.reactNativeHost
        
        // Create a JSBundleLoader that loads the module's bundle from AAR assets
        // The bundle is merged into the app's assets at build time
        // Note: createAssetLoader takes (context, assetUrl, loadSynchronously)
        // assetUrl should be just the filename, not a full path
        // IMPORTANT: Use application context to access assets, not the passed context
        Log.d(TAG, "🔧 Creating module-specific ReactInstanceManager")
        Log.d(TAG, "   Bundle name: '$BUNDLE_NAME' (length: ${BUNDLE_NAME.length})")
        Log.d(TAG, "   Module: $MODULE_NAME")
        
        // Copy bundle from assets to internal storage and load from file
        // React Native's jniLoadScriptFromAssets has issues loading from AAR assets
        // So we copy to internal storage and use createFileLoader instead
        val appContext = application.applicationContext
        val bundleFile = File(appContext.filesDir, BUNDLE_NAME)
        
        // Check if bundle needs to be copied/updated from assets to internal storage
        var needsCopy = true
        if (bundleFile.exists() && bundleFile.length() > 0) {
            // Bundle exists - check if it needs updating by comparing sizes
            // This is a simple check; for production, consider using bundle hash/version
            try {
                val assets = appContext.assets
                assets.open(BUNDLE_NAME).use { assetStream ->
                    val assetSize = assetStream.available().toLong() // Convert Int to Long
                    val fileSize = bundleFile.length()
                    
                    if (assetSize == fileSize) {
                        // Sizes match - assume bundle is up to date
                        // Note: This is a simple heuristic. For production apps,
                        // consider embedding a bundle hash/version in the AAR and comparing that
                        needsCopy = false
                        Log.d(TAG, "   ✅ Bundle already in internal storage: ${bundleFile.absolutePath} (size: $fileSize bytes)")
                    } else {
                        // Size mismatch - AAR bundle was updated, need to recopy
                        Log.d(TAG, "   🔄 Bundle size mismatch (asset: $assetSize, file: $fileSize) - updating...")
                        needsCopy = true
                    }
                }
            } catch (e: Exception) {
                // If we can't read assets, assume we need to copy
                Log.w(TAG, "   ⚠️ Could not verify bundle from assets, will attempt copy: ${e.message}")
                needsCopy = true
            }
        }
        
        if (needsCopy) {
            try {
                // Copy bundle from assets to internal storage
                val assets = appContext.assets
                assets.open(BUNDLE_NAME).use { input ->
                    bundleFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
                val size = bundleFile.length()
                Log.d(TAG, "   ✅ Bundle copied to internal storage: ${bundleFile.absolutePath} (size: $size bytes)")
            } catch (e: Exception) {
                Log.e(TAG, "   ❌ Failed to copy bundle from assets: $BUNDLE_NAME", e)
                throw IllegalStateException("Failed to copy bundle $BUNDLE_NAME from assets to internal storage", e)
            }
        }
        
        // Load bundle from file path instead of assets
        // This avoids React Native's jniLoadScriptFromAssets issues with AAR assets
        val bundleLoader = JSBundleLoader.createFileLoader(
            bundleFile.absolutePath // Load from file path instead of assets
        )
        
        Log.d(TAG, "   ✅ JSBundleLoader created from file: ${bundleFile.absolutePath}")
        
        // Build a ReactInstanceManager specifically for this module
        // This allows each module to have its own bundle while sharing the same React Native runtime
        // We don't access reactNativeHost.reactInstanceManager to avoid triggering its creation
        // since the main ReactNativeHost may not be fully configured
        val builder = ReactInstanceManagerBuilder()
            .setApplication(application)
            .setBundleAssetName(null) // Don't use default bundle - use our custom loader
            .setJSBundleLoader(bundleLoader) // Use module's bundle from AAR assets
            .setUseDeveloperSupport(reactNativeHost.useDeveloperSupport)
            .setInitialLifecycleState(LifecycleState.BEFORE_CREATE)
        
        // Add core React Native package - required for ReactInstanceManager to work
        // The JavaScript bundle contains all the JS code, but native modules need to be registered
        builder.addPackage(com.facebook.react.shell.MainReactPackage())
        
        // Modules are self-contained - the bundle already contains all necessary JavaScript code
        // If additional native modules are needed, they should be included in the module's own ReactPackage
        
        return builder.build()
    }
    
    /**
     * Creates a React Native root view for the module
     * 
     * @param context Android context
     * @param reactInstanceManager Optional ReactInstanceManager. If null, creates a module-specific one.
     * @param initialProperties Optional initial properties to pass to the module
     * @return A configured ReactRootView ready to be added to a view hierarchy, or null if bundle not found
     */
    fun createView(
        context: Context,
        reactInstanceManager: ReactInstanceManager? = null,
        initialProperties: android.os.Bundle? = null
    ): ReactRootView? {
        val bundlePath = getBundlePath(context)
        if (bundlePath == null) {
            Log.e(TAG, "❌ Cannot create view: Bundle not found")
            return null
        }
        
        Log.d(TAG, "📦 Creating ReactRootView")
        Log.d(TAG, "   Bundle path: $bundlePath")
        Log.d(TAG, "   Module name: $MODULE_NAME")
        
        // Use provided ReactInstanceManager or create a module-specific one
        // Each module gets its own ReactInstanceManager to load its own bundle from AAR assets
        val moduleReactInstanceManager = reactInstanceManager 
            ?: createModuleReactInstanceManager(context)
        
        // Create ReactRootView
        val rootView = ReactRootView(context)
        
        // Start React application with the module-specific ReactInstanceManager
        // This ensures the module's bundle is loaded from AAR assets
        rootView.startReactApplication(moduleReactInstanceManager, MODULE_NAME, initialProperties)
        
        return rootView
    }
}
