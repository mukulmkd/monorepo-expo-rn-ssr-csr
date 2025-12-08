package com.mkdcorp.rnhost

import com.facebook.soloader.SoLoader

object HermesLoader {
    fun loadHermes() {
        try {
            SoLoader.loadLibrary("hermes")
            SoLoader.loadLibrary("hermes_executor")
        } catch (e: Throwable) {
            e.printStackTrace()
        }
    }
}
