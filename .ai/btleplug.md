# btleplug fork — Android JNI thread-attach patch

## Purpose

Patch btleplug 0.11.8 (Rust) to survive the **JNI `ThreadDetached` error**
that occurs when BLE operations run on tokio worker threads instead of the
JVM-attached Dart/UI thread. Without this patch, every BLE scan fails with
`"JNI call failed"` — a silent, opaque error that bubbles up as an
`anyhow::Error` from `muse_rs::MuseClient::scan_all()`.

## Where is the fork

```
../../btleplug/     (sibling of muse_ml/)
```

Referenced from `muse_ml/rust/Cargo.toml` via `[patch]`:

```toml
btleplug = { git = "https://github.com/eugenehp/btleplug.git", branch = "imrpoved_mac_version", version = "0.11.8" }

[patch.'https://github.com/eugenehp/btleplug.git']
btleplug = { path = "../../btleplug" }
```

## Critical pitfall — Cargo `[patch]` semver check

**Cargo silently ignores `[patch]` if the patched crate's `version` field is
semver-incompatible with the dependency constraint.** Our fork was originally
`version = "0.12.0"`, but the project depends on `^0.11.8`. The patch was
silently skipped — the unpatched upstream 0.11.8 was used instead.

**Fix:** set `version = "0.11.8"` in the fork's `Cargo.toml`. Even though the
source code is based on upstream 0.12.0 (with our patches), the version must
match `^0.11.8` for Cargo to apply the `[patch]`.

Verify the patch is actually applied:
```bash
cargo tree -p btleplug --depth 0
# Should show: btleplug v0.11.8 (/path/to/btleplug)
```

## Local vs remote development

The `Cargo.toml` in `muse_ml/rust/` points to the **remote git tag** by default:

```toml
btleplug = { git = "https://github.com/windwerfer/btleplug.git", tag = "0.12.0-muse-2", version = "0.11.8" }
```

When debugging or modifying the btleplug fork, swap to the **local path**:

```toml
# Comment out the git line above, and uncomment this:
[patch.'https://github.com/windwerfer/btleplug.git']
btleplug = { path = "../../btleplug" }
```

**Important:** the local fork's `Cargo.toml` must have `version = "0.11.8"` or
the patch will be silently ignored (see critical pitfall below).

## Changes made

### 1. `src/droidplug/jni/mod.rs` — `get_env()` with auto-attach

```rust
pub(crate) fn get_env() -> Result<JNIEnv<'static>, ::jni::errors::Error> {
    match global_jvm().get_env() {
        Ok(env) => Ok(env),
        Err(_) => global_jvm().attach_current_thread_permanently(),
    }
}
```

This is the core fix. When a tokio worker thread calls `get_env()`, the JVM
reports `JNI_EDETACHED`. The fallback permanently attaches the thread so all
subsequent JNI calls succeed.

Added `log::debug!` / `log::warn!` / `log::info!` calls around each branch
for diagnostics in logcat.

### 2. All callers — `global_jvm().get_env()` → `get_env()`

Files changed:
- `src/droidplug/adapter.rs` (5 call sites)
- `src/droidplug/peripheral.rs` (2 call sites)

The upstream code directly calls `global_jvm().get_env()` which cannot handle
detached threads. Every call site was replaced with the wrapper.

### 3. `src/droidplug/jni_utils/classcache.rs` — `.unwrap()` → `?`

The upstream uses `.unwrap()` on `find_class()`, which panics (SIGABRT) when
a Java class is missing from the classpath. Replaced with `?` so the error
propagates as a proper `Result`.

### 4. Java source files (`muse_ml/android/app/src/main/java/...`)

The Rust code is based on btleplug 0.12.0 but the bundled Java sources were
from 0.11.8. Missing additions:

| File | Reason |
|------|--------|
| `NoBluetoothAdapterException.java` | Referenced in `jni::init()` + `start_scan` catch block |
| `Peripheral.java` methods | `getDeviceName`, `requestMtu`, `getConnectionParameters`, `requestConnectionPriority`, `readRemoteRssi` — eagerly resolved by `JPeripheral::from_env_impl()` |
| `Peripheral.java` callbacks | `onDescriptorRead`, `onMtuChanged`, `onReadRemoteRssi`, `onConnectionUpdated` in `Callback`/`CommandCallback` |

`writeDescriptor` signature also changed between versions: 0.11.8 had
`(UUID, UUID, byte[], int)`, 0.12.0 expects `(UUID, UUID, byte[])`.

## How to test

```bash
cd muse_ml
flutter run
# In another terminal:
adb logcat -s btleplug rust_lib_muse_ml RustError
```

Expected logcat output for a successful scan:
```
D/btleplug::droidplug::jni: [btleplug] get_env called
W/btleplug::droidplug::jni: [btleplug] get_env: thread detached, attaching permanently
I/btleplug::droidplug::jni: [btleplug] get_env: attached permanently
D/btleplug::droidplug::adapter: [btleplug] start_scan begin
D/btleplug::droidplug::adapter: [btleplug] start_scan call_method OK
```

## What's NOT changed

- Public API (traits, types) — untouched
- Other platform backends (BlueZ, CoreBluetooth, WinRT)
- Java class structure or package names
- JNI native method registration
