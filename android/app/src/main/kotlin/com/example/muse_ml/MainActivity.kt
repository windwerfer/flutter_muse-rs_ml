package com.example.muse_ml

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // Defined in Rust (rust/src/api/muse.rs) — initializes btleplug's global
    // Android adapter before any BLE operation.
    private external fun museAndroidInit()

    override fun onCreate(savedInstanceState: Bundle?) {
        museAndroidInit()
        super.onCreate(savedInstanceState)
    }

    companion object {
        init {
            System.loadLibrary("rust_lib_muse_ml")
        }
    }
}
