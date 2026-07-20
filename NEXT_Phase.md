# NEXT_Phase.md

> Paste this into a **new thread** as the starting prompt for the next phase.
> It assumes the current repo state (post-btleplug investigation, diagnostics
> restored, decision made to drop btleplug in favor of `flutter_blue_plus` +
> a stripped muse-rs core).

---

## Context (read first)

We are building **Muse ML**, a Flutter app that connects to a Muse BLE
headset and streams EEG/PPG/IMU/telemetry. The repo is at
`/workspaces/flutter_muse_ml`.

**Stack:** Flutter 3.41.7 (stable), Dart, Rust via `flutter_rust_bridge`
2.11.1. Currently `rust/src/api/muse.rs` wraps `muse-rs` 0.1.0, which uses a
forked `btleplug` (e.g. `github.com/eugenehp/btleplug`, branch
`imrpoved_mac_version`, 0.11.8) for the Android BLE transport.

**Decision already made (do NOT reopen the btleplug path):** we are replacing
btleplug's BLE transport with **`flutter_blue_plus`** (Dart). We keep only
muse-rs's **protocol core** in Rust (pure byte→struct decoders, no BLE) and
feed it raw bytes from `flutter_blue_plus` over the `flutter_rust_bridge` FFI.

Why: the btleplug-on-Android path required a patched fork + JVM-thread attach
hack + ~30 bundled Java files + Kotlin glue, and was abandoned. The full
autopsy is in `.ai/lessons-learned.md`. The target architecture is in
`.ai/architecture.md`. The current task status is in `.ai/active-task.md`. The
verified test loop is in `.ai/testing-guide.md`.

A git branch exists with the abandoned btleplug work, in case we ever revisit
it — do not merge it; this phase goes the `flutter_blue_plus` route.

## Phase goal

**Step 1 — Update Flutter (and toolchain) to the most recent stable, and
update the project accordingly.**

- Run `flutter upgrade` (or `flutter channel stable && flutter upgrade`) to get
  the latest **stable** Flutter/Dart. Do NOT use beta/canary.
- After upgrading, make the project build and analyze cleanly:
  - `flutter pub get`
  - `flutter analyze lib/src` must be clean.
  - `flutter_rust_bridge` is pinned at `=2.11.1` (both Rust `Cargo.toml` and
    Dart `pubspec.yaml`). If the Flutter upgrade forces a newer Dart/Flutter
    that is incompatible, bump `flutter_rust_bridge` **together** (Rust crate +
    Dart package) to a compatible stable 2.x and re-run the frb codegen
    (`flutter_rust_bridge` codegen) — generated Dart files are tracked,
    `rust/src/frb_generated.rs` is gitignored.
  - Verify the Android build still configures: NDK 27/28, Gradle 8.14,
    `targetSdkVersion = 36`.
  - Confirm the device is still reachable: `adb devices` shows `HA2A7MWP`.
- Do NOT change app behavior yet — only the toolchain/bindings. Keep the
  existing `[muse]` `debugPrint` diagnostics and the `scanMessage` UI field;
  they are the verification harness (see `.ai/testing-guide.md`).
- Report what version you landed on and any breaking changes you had to fix.

**Step 2 — Fork & strip muse-rs into a new Rust crate holding only the core.**

- Create a new crate (suggested name **`muse_core_rs`** — pure Rust, no
  Flutter/BLE dependency; alternative: `muse_flutter_rs`). Place it under
  `rust/` (e.g. `rust/muse_core_rs/`) or as a workspace member of the existing
  `rust/` crate — your call, but keep it buildable for `aarch64-linux-android`.
- From muse-rs 0.1.0, **keep only the protocol core**:
  - `parse.rs` (pure byte decoders: `decode_eeg_samples`, `parse_telemetry`,
    `parse_accelerometer`, `parse_gyroscope`, `parse_ppg_reading`,
    `parse_athena_notification`, `ControlAccumulator`, etc.)
  - `protocol.rs` (characteristic UUIDs, `encode_command`, `decode_response`)
  - `types.rs` (`MuseEvent`, `Eeg`, `Ppg`, `Imu`, `Telemetry` structs)
  - a thin `lib.rs` re-exporting the above.
- **Delete** `muse_client.rs` and `bin/` (these are the btleplug transport and
  CLI — not needed).
- Verify there are **zero** `btleplug` imports in the kept code (confirm with a
  grep). The decoders are `fn(&[u8]) -> …` / `fn(&[u8], …) -> …` and take no
  BLE types.

**Step 3 — Expose a thin FFI bridge from the core to Dart.**

In `rust/src/api/muse.rs` (or a new api module), replace the old btleplug-based
`scan()`/`connect()` with bridge functions that take raw bytes and return
parsed events, mirroring what `muse_client.rs` used to do internally:
- `handle_notification(char_uuid: String, payload: Vec<u8>) -> Vec<MuseEvent>`
  — route by characteristic UUID to the right `parse_*` decoder and return the
  resulting `MuseEvent`s.
- `encode_command(cmd: String) -> Vec<u8>` — for sending commands back to the
  headset (wraps `protocol::encode_command`).
- Keep `subscribe_events()` / the `MuseEventDto` stream feeding the UI
  unchanged if possible; have the bridge push parsed events into that same
  sink.
- Re-run `flutter_rust_bridge` codegen if the FFI surface changed.

**Step 4 — Replace the BLE transport in Dart with `flutter_blue_plus`.**

- Add `flutter_blue_plus` to `pubspec.yaml`.
- In `connection_provider.dart`, replace the Rust `scan()`/`connect()` calls
  with `flutter_blue_plus`:
  - scan → discover Muse devices (filter by name/manufacturer),
  - connect → `device.connect()`, `discoverServices()`,
  - for each Muse sensor/control characteristic, `setNotifyValue(true)` and on
    `onCharacteristicReceived` call the Rust bridge
    `handle_notification(char.uuid, value)`; forward returned `MuseEvent`s into
    the existing event stream/sink.
  - commands (e.g. start/stop streaming) → `write` the bytes from
    `encode_command(cmd)`.
- Keep `requestBlePermissions()` (app.dart) as-is; `flutter_blue_plus` uses the
  same Android BLE permissions.

## How to verify (critical)
Follow `.ai/testing-guide.md` exactly — the self-contained build/test loop:
clear logcat, launch `flutter run` detached, wait ~110s, kill the flutter
process (NOT adb), then `adb logcat -d | grep muse`. On a fresh install tap
**Rescan** in the connect window (or use the temporary `openConnectWindowAndScan()`
call noted in the guide). Success = `[muse] starting scan` is replaced by
`flutter_blue_plus` scan logs and the connect window's `scanMessage` shows
real devices / a clear error. `flutter analyze lib/src` must stay clean.

## Hard rules (from AGENTS.md)
- Never assume a library is available — check `Cargo.toml` / `pubspec.yaml`
  first.
- Never commit secrets/keys. Never add code comments unless asked.
- Do not run `git` commit/push/PR unless explicitly requested.
- Keep `flutter analyze lib/src` clean after edits.

## Deliverables for this phase
1. Project on latest stable Flutter, building & analyzing clean.
2. New `muse_core_rs` crate with only the protocol core (no btleplug).
3. Rust FFI bridge: `handle_notification` + `encode_command` (+ existing event
   stream).
4. `flutter_blue_plus`-based scan/connect/subscribe in `connection_provider.dart`.
5. A short summary of versions landed, what was deleted, and the verification
   result from the test loop.
