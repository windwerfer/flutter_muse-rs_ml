# AGENTS.md — Muse ML (Flutter + Rust BLE headset app)

Global orientation for any AI agent or contributor working in this repo.

## Stack
- **Flutter 3.41.7** (stable), Dart (bundled). UI layer.
- **Rust** via `flutter_rust_bridge` **2.11.1** (pinned `=`, both Rust crate and Dart package).
  - Rust lib: `rust/` (crate `rust_lib_muse_ml`).
  - Generated bindings: `rust/src/frb_generated.rs` is **gitignored**; Dart generated files ARE tracked.
- **muse-rs** (`github.com/eugenehp/muse-rs.git` tag `0.1.0`, `default-features = false`) — Muse BLE protocol + transport.
- **btleplug** fork (`github.com/eugenehp/btleplug.git` branch `imrpoved_mac_version`, `0.11.8`) — pulled in transitively by muse-rs. **Do not change this version**; muse-rs depends on the fork's API.
- **Android**: NDK 27/28, Gradle 8.14, `targetSdkVersion = 36`.
- **iOS/macOS**: not the current target; BLE transport uses btleplug's CoreBluetooth path.

## Core rules (do / don't)
- **NEVER** assume a library is available — check `Cargo.toml` / `pubspec.yaml` first.
- **NEVER** commit secrets/keys.
- **NEVER** add code comments unless explicitly asked.
- Do not run `git` commit/push/PR unless explicitly requested.
- When editing Rust under `rust/src/api/`, run `flutter_rust_bridge` codegen if the FFI surface changes, then `cargo check --target aarch64-linux-android` is NOT reliable in this sandbox (see Testing Guide) — rely on `flutter run` for the real compile.
- `flutter analyze lib/src` must stay clean after edits.

## Project layout
```
lib/src/                 # Flutter UI + Riverpod state
  connection_provider.dart  # AppStateNotifier: scan/connect state machine
  app.dart                 # main(), permission request
  connect_window.dart      # device list / rescan UI
  status_bar.dart, views/  # UI
rust/src/api/muse.rs    # FFI bridge: scan/connect/subscribe → MuseEvent stream
rust/src/connection.rs  # in-Rust state (active connection, device cache, sink)
muse-rs (dep)           # transport (btleplug) + protocol (parse/protocol/types)
```

## Where things live (for navigation)
- BLE scan/connect entry: `rust/src/api/muse.rs` (`scan`, `connect`, `subscribe_events`).
- Protocol decoders (pure, no BLE): inside muse-rs `parse.rs` / `protocol.rs` / `types.rs`.
- Permissions: `lib/src/app.dart` `requestBlePermissions()` (uses `permission_handler` + `device_info_plus` for sdk gating).
- Manifest BLE perms: `android/app/src/main/AndroidManifest.xml` (`BLUETOOTH_SCAN` w/ `neverForLocation`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION` capped `maxSdkVersion=30`).

## Known hot spots
- **Android BLE init**: btleplug requires `btleplug::platform::init(&JNIEnv)` from a JNI context BEFORE any scan/connect, or it panics with `"Droidplug has not been initialized"`. This is the central gotcha of this project (see `.ai/lessons-learned.md`).
- **Auto-scan only on saved device**: on fresh launch with no `lastDeviceId`, `_init()` opens the connect window but does NOT scan. Scan only fires on Rescan button or autoconnect to a known device.
