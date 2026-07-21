# muse_ml

Muse EEG headset companion app — Flutter + Rust via `flutter_rust_bridge`.

## Quick start

```bash
flutter run
```

Scan for nearby Muse headsets by tapping **Rescan**.

**Supported:** Android 10+ (API 29), 64-bit only (`arm64-v8a` / `x86_64`).
Older API levels would theoretically work but are untested.

## Debugging

```bash
# Rust + BLE logs
adb logcat -s btleplug rust_lib_muse_ml RustError

# Everything muse-related
adb logcat | grep -iE "scan_all|btleplug|muse"
```

## Architecture

```
Flutter UI (lib/src/) ←─ FFI ──→ Rust (rust/src/api/muse.rs)
                                    ↕ muse-rs 0.1.0
                                    ↕ btleplug 0.11.8 (patched)
                                    ↕ Android BLE (JNI)
```

BLE transport: btleplug fork at `github.com/windwerfer/btleplug` (tag
`0.12.0-muse-2`). JNI thread-attach patch for tokio worker threads; see
`.ai/btleplug.md` for details.

## Project docs (`.ai/`)

| File | Contents |
|------|----------|
| `btleplug.md` | btleplug fork changes and pitfalls |
| `bugreport.md` | Bug report for upstream btleplug |
| `architecture.md` | Current and target architecture |
| `lessons-learned.md` | Full debug history |
| `testing-guide.md` | Build/test loop |
| `active-task.md` | Current development focus |
