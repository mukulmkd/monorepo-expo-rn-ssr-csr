package com.mkdcorp.rnhost

import android.app.Application
import com.facebook.react.ReactInstanceManager
import com.facebook.react.ReactNativeHost
import com.facebook.react.ReactPackage
import com.facebook.react.defaults.DefaultReactNativeHost

object RNHost {
    private lateinit var reactHost: ReactNativeHost

    fun init(app: Application, baseBundle: String = "index.android.bundle") {
        HermesLoader.loadHermes()

        reactHost = object : DefaultReactNativeHost(app) {
            override fun getUseDeveloperSupport() = false
            
            override fun getPackages(): List<ReactPackage> {
                // Return empty list - packages should be added by consuming app
                return emptyList()
            }
            
            override fun getJSMainModuleName(): String = baseBundle
        }

        // Force initialization
        reactHost.reactInstanceManager
    }

    fun getInstanceManager(): ReactInstanceManager {
        if (!::reactHost.isInitialized) {
            throw IllegalStateException("RNHost.init() must be called before getInstanceManager()")
        }
        return reactHost.reactInstanceManager
    }
}
