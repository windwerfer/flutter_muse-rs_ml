# Active Task

## Goal
Get a Muse BLE headset discovered and connected on **Android** so the app can
stream EEG/PPG/IMU/telemetry. The Dart UI and Rust FFI surface are in place;
the blocker is the **Android BLE transport layer**.

## Current decision (2026-07-20)
Pivot away from btleplug-on-Android. Plan agreed with the user:

> Fork `muse-rs`, strip out everything btleplug/transport-related, keep only
> the **protocol core** (`parse.rs` / `protocol.rs` / `types.rs`). Do the actual
> BLE with **`flutter_blue_plus`** (Dart). Bridge raw bytes from
> `flutter_blue_plus` into the stripped muse-rs core via `flutter_rust_bridge`,
> which returns `MuseEvent`s back to the UI.

Rationale: the btleplug-on-Android path required a patched fork + JVM-thread
attach hack + bundled Java classes + Kotlin glue (see `lessons-learned.md`).
`flutter_blue_plus` handles Android BLE init natively and is far more
maintainable. See `architecture.md` for the target data flow.

## Status
- ✅ Root cause of the scan failure fully diagnosed (btleplug init + JVM attach).
- ✅ Confirmed muse-rs protocol core is btleplug-free and forkable.
- ✅ Diagnostic harness in place (`debugPrint("[muse] …")` + on-screen
  `scanMessage`). Restored after revert — keep these, they work.
- ⏳ Not yet started: the fork + strip + `flutter_blue_plus` migration.

## Next steps
1. Fork muse-rs into `rust/` as a stripped crate: keep `parse.rs`, `protocol.rs`,
   `types.rs`, thin `lib.rs`; delete `muse_client.rs` + `bin/`.
2. Add Rust bridge: `handle_notification(char_uuid: String, payload: Vec<u8>) -> Vec<MuseEvent>`
   and `encode_command(cmd: &str) -> Vec<u8>`, routing by UUID to the existing
   `parse_*` decoders (mirror what `muse_client.rs` did internally).
3. In `connection_provider.dart`, replace `scan()`/`connect()` (Rust btleplug)
   with `flutter_blue_plus` scan/connect/discover/subscribe; on each
   notification call the frb bridge with the raw bytes.
4. Keep the `subscribe_events` → `MuseEventDto` stream feeding the UI unchanged.

## How to verify (see testing-guide.md)
Run the build/test loop, tap Rescan, and confirm via `adb logcat` that
`[muse] …` lines progress past `starting scan` and that `scanMessage` in the
connect window shows a real result (devices found, or a clear error).
