package com.mkdcorp.rnhost

import android.app.Application
import android.os.Bundle
import com.facebook.react.ReactRootView

object RNModuleLoader {
    fun loadModule(
        app: Application,
        bundleName: String,
        moduleName: String,
        props: Map<String, Any>? = null
    ): ReactRootView {
        // Note: RNHost.init() must be called before using loadModule
        // This is a design choice - initialization should happen in Application.onCreate()
        
        val manager = RNHost.getInstanceManager()
        val view = ReactRootView(app)
        
        // Convert Map to Bundle if props provided
        val bundle: Bundle? = if (props != null) {
            Bundle().apply {
                props.forEach { (key, value) ->
                    when (value) {
                        is String -> putString(key, value)
                        is Int -> putInt(key, value)
                        is Boolean -> putBoolean(key, value)
                        is Double -> putDouble(key, value)
                        is Float -> putFloat(key, value)
                        else -> putString(key, value.toString())
                    }
                }
            }
        } else {
            null
        }
        
        view.startReactApplication(manager, moduleName, bundle)
        return view
    }
}
