package com.mkdcorp.rnhost

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment

class RNFragment(
    private val bundle: String,
    private val module: String
) : Fragment() {
    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        val app = requireActivity().application
        return RNModuleLoader.loadModule(app, bundle, module)
    }
}
