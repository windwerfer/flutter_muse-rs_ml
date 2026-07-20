# Lessons Learned

## Android BLE via btleplug — what we tried and why it was abandoned

**Context:** The app's BLE scan silently returned nothing. Logcat from the
Bluetooth stack showed no scan originating from `com.example.muse_ml`. The
failure was entirely on the Rust/btleplug side, not Dart.

### Attempt 1 — `btleplug::platform::init()` in Rust `init_app()`
- **Tried:** call `btleplug::platform::init()` inside `#[frb(init)] init_app()`.
- **Failed:** `init()` in this fork takes a `&JNIEnv` argument and must be
  called from a JNI context. `init_app()` runs from Dart with no `JNIEnv`
  available, and `flutter_rust_bridge` 2.11.1 does **not** expose
  `get_jvm()`/`get_env()`. Compile error: `this function takes 1 argument but 0
  arguments were supplied`.
- **Lesson:** frb 2.11.1 has no JVM access; you cannot init btleplug purely
  from Rust `init_app()` on Android. (Newer frb 2.12+ may add it, but the
  sandbox has no network to upgrade.)

### Attempt 2 — init from Kotlin `MainActivity.onCreate` (with `JNIEnv`)
- **Tried:** Added `external fun museAndroidInit()` to a custom
  `MainActivity.kt`, calling a Rust `extern "C"
  Java_com_example_muse_1ml_MainActivity_museAndroidInit(env)` that calls
  `btleplug::platform::init(&env)`. Added `btleplug` + `jni = "=0.19"` as
  direct deps (must match btleplug's own `jni 0.19`, not 0.21).
- **Result:** got past "Droidplug has not been initialized" — progress!
- **New failure:** `java.lang.ClassNotFoundException:
  com.nonpolynomial.btleplug.android.impl.Adapter`. btleplug's native-method
  registration needs its Java classes bundled in the APK.

### Attempt 3 — bundle btleplug's Java classes + `jni-utils`
- **Tried:** copied `btleplug/.../com/nonpolynomial/btleplug/android/impl/*.java`
  and the `io.github.gedgygedgy.rust.*` Java sources (found in the `jni-utils`
  cargo crate, since the SNAPSHOT Maven dep was unreachable) into
  `android/app/src/main/java/`.
- **Result:** classes load; init succeeds; scan starts.
- **New failure:** `AnyhowException(JNI call failed)` immediately on scan.

### Attempt 4 — diagnose the JNI failure (root cause found)
- **Found:** btleplug calls `global_jvm().get_env()` from a **tokio worker
  thread** (the scan runs off the Dart/UI thread). `JavaVM::get_env()` returns
  `JNI_EDETACHED` for threads not attached to the JVM, and the `jni` crate's
  `get_env()` does **not** auto-attach. Hence "JNI call failed".
- **Confirmed via:** verbose `jni` logs in logcat
  (`calling unchecked JavaVM method: GetEnv` on thread 14765) and the
  `muse_rs::muse_client: scan_all` line immediately preceding the error.

### Attempt 5 — patch btleplug to attach-on-demand
- **Tried:** vendored btleplug locally (`rust/vendor/btleplug`), added an
  attach-aware `get_env()` wrapper (`match get_env() { Ok(e) => e, Err(_) =>
  attach_current_thread() }`), replaced all `global_jvm().get_env()` calls, and
  wired it via `[patch.'https://github.com/eugenehp/btleplug.git']`.
- **Failed to compile cleanly** (a `match` arms type mismatch:
  `attach_current_thread()` returns an `AttachGuard`, not `JNIEnv`; also
  `[patch]` cannot carry a `branch` key). Was mid-fix when the approach was
  abandoned.
- **Why abandoned:** the whole stack (Kotlin glue + ~30 Java files + patched
  fork + JVM-attach hack on a non-standard btleplug fork) is fragile and
  high-maintenance. The user chose to instead use `flutter_blue_plus` for BLE
  and keep only muse-rs's protocol core in Rust.

## Things that DID work (keep these)
- **Diagnostic harness:** `debugPrint('[muse] …')` in `app.dart` and
  `connection_provider.dart`, plus an on-screen `scanMessage` field in
  `AppUiState` shown in `connect_window.dart`. `debugPrint` DOES reach logcat
  on this ZUI ROM (tag `flutter`), so `adb logcat | grep muse` is reliable.
- **Test loop (see testing-guide.md):** clear logcat, `flutter run` detached,
  wait ~100–120s, kill the flutter process (NOT adb), then
  `adb logcat -d | grep muse`. This avoids the back-and-forth.
- **Dart permission flow is correct:** `requestBlePermissions()` grants
  `bluetoothScan` + `bluetoothConnect` (location only on SDK ≤ 30). Confirmed
  `result = granted, granted` in logcat.

## Gotchas
- **Never `pkill -f adb`** — it kills the adb server and wedges the shell.
  Kill only `flutter`/`dart`/`gradle` processes.
- **`flutter run` holds the logcat stream**, so `adb logcat -d` hangs (timeout)
  while the run is alive. Kill the flutter process first, then dump logcat.
- **`cargo check --target aarch64-linux-android` fails in this sandbox** with a
  permission-denied on the NDK clang. The real compile path is `flutter run`
  (cargokit + cargo-ndk), which works. Don't trust local `cargo check` here.
- **muse-rs protocol core is btleplug-free:** `parse.rs`, `protocol.rs`,
  `types.rs`, `lib.rs` have zero btleplug imports. Only `muse_client.rs` and
  `bin/` use btleplug — safe to delete in the fork.
- **`flutter_rust_bridge` 2.11.1 already enables `android_logger`** when the
  `log` feature is on, so plain `log::` calls print to logcat. The
  `enable_frb_rust_to_dart_logging!()` macro the user suggested does NOT exist
  in 2.11.1 (added later); not needed here.
