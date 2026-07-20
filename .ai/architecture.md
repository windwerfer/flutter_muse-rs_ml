# Architecture

## Current architecture (as built)
```
Flutter UI (lib/src)
   │  Riverpod: AppStateNotifier (connection_provider.dart)
   ▼
flutter_rust_bridge 2.11.1  ── FFI ──►  Rust crate rust_lib_muse_ml (rust/src/api/muse.rs)
                                            │
                                            ▼
                                       muse-rs 0.1.0 (dep)
                                         ├─ transport: btleplug fork 0.11.8 (Android BLE)
                                         └─ protocol:  parse.rs / protocol.rs / types.rs
                                            (decode raw GATT bytes → MuseEvent)
```
- `scan()` / `connect()` / `subscribe_events()` are the Rust FFI entry points.
- `subscribe_events()` returns a `Stream<MuseEventDto>` that drives all UI.
- Permissions: `requestBlePermissions()` in `app.dart` (permission_handler +
  device_info_plus, SDK-gated).

## Target architecture (decided 2026-07-20)
Replace the btleplug transport with `flutter_blue_plus` (Dart) and keep only
muse-rs's **protocol core** in Rust, fed raw bytes over the FFI bridge.

```
Flutter UI (lib/src)
   │
   ├─ flutter_blue_plus (Dart)  ◄── does scan / connect / discover / subscribe
   │        │  raw List<int> per characteristic notification
   │        ▼  (frb call: handle_notification(uuid, bytes))
   │
   └─ flutter_rust_bridge ──►  stripped muse-rs core (Rust)
                                 parse.rs / protocol.rs / types.rs
                                 handle_notification(uuid, bytes) -> Vec<MuseEvent>
                                 encode_command(cmd) -> Vec<u8>
                                            │
                                            ▼
                                 MuseEvent stream → UI (unchanged)
```

### Why this shape
- `flutter_blue_plus` is mature and handles Android BLE init natively — no
  Kotlin glue, no bundled btleplug Java, no JVM-attach hacks, no patched fork.
- muse-rs's protocol decoders are **pure** (`fn(&[u8]) -> …`), btleplug-free,
  and already implement the Muse framing (EEG 12/24-bit unpacking, PPG, IMU,
  telemetry, control accumulation, Athena payloads). We keep exactly that.
- The only custom Rust is a thin UUID→decoder router mirroring what
  `muse_client.rs` did internally.

## muse-rs module map (for the fork)
| File | Role | Keep in fork? |
|------|------|---------------|
| `parse.rs` | byte decoders (pure) | ✅ keep |
| `protocol.rs` | UUIDs, command encode/decode (pure) | ✅ keep |
| `types.rs` | `MuseEvent`, `Eeg`, `Ppg`, `Imu`, `Telemetry` | ✅ keep |
| `lib.rs` | re-exports | ✅ keep (trim) |
| `muse_client.rs` | btleplug transport (scan/connect/subscribe) | ❌ delete |
| `bin/` | CLI using btleplug | ❌ delete |

## Key data types (crossing the bridge)
- `MuseEventDto` (freezed DTO) variants: `Connected`, `Disconnected`, `Eeg`,
  `Ppg`, `Telemetry`, `Accelerometer`, `Gyroscope`, `Control`.
- `DeviceInfo { name, id }` — produced by scan, consumed by connect.
- `ConnectionStatus`, `TelemetrySnapshot` — UI state.

## Android specifics
- Manifest BLE perms: `BLUETOOTH_SCAN` (neverForLocation), `BLUETOOTH_CONNECT`,
  `ACCESS_FINE_LOCATION` (maxSdkVersion=30).
- `targetSdkVersion = 36`, NDK 27/28, Gradle 8.14.
- `flutter_rust_bridge` generated `rust/src/frb_generated.rs` is gitignored;
  Dart generated files are tracked.
